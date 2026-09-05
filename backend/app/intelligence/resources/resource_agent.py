"""
ResQNet Intelligence - Multi-Constrained Drone Fleet Resource Allocation Agent
"""
import time
from typing import Any, Dict, List, Optional, Tuple
from app.schemas.common import Vector3D
from app.schemas.drone import DroneEntity, DroneCapability, DroneStatus
from app.schemas.mission import RiskAssessment
from app.schemas.audit import AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger
from app.intelligence.routing.routing_agent import routing_agent
from app.intelligence.risk.risk_agent import risk_agent


class DroneEvaluation:
    def __init__(self, drone_id: str):
        self.drone_id = drone_id
        self.eligible: bool = False
        self.utility_score: float = 0.0
        self.positive_reasons: List[str] = []
        self.rejection_reasons: List[str] = []
        self.estimated_dist_m: float = 0.0
        self.risk: Optional[RiskAssessment] = None


class ResourceAgent:
    def __init__(self):
        pass

    def evaluate_drone_for_mission(
        self,
        drone: DroneEntity,
        target_pos: Vector3D,
        required_capability: DroneCapability,
        priority_score: float,
    ) -> DroneEvaluation:
        eval_res = DroneEvaluation(drone.id)
        
        # 1. Status Availability Check
        if drone.status in [DroneStatus.CHARGING, DroneStatus.ERROR, DroneStatus.LOST]:
            eval_res.rejection_reasons.append(f"Drone is in unavailable state: {drone.status.value}")
            return eval_res
        
        if drone.status != DroneStatus.IDLE:
            # Check preemption capability if high priority
            if priority_score > 0.85:
                eval_res.rejection_reasons.append(f"Drone currently on active mission; preemption required")
            else:
                eval_res.rejection_reasons.append(f"Drone busy with existing task ({drone.status.value})")
                return eval_res

        # 2. Capability Check
        has_capability = required_capability in drone.capabilities
        if not has_capability:
            eval_res.rejection_reasons.append(
                f"Missing required capability '{required_capability.value}' (Has: {[c.value for c in drone.capabilities]})"
            )
            return eval_res
        else:
            eval_res.positive_reasons.append(f"Equipped with required {required_capability.value} payload/sensors")

        # 3. Route Feasibility & Distance
        node_path, waypoints, total_dist = routing_agent.plan_route(drone.position, target_pos)
        eval_res.estimated_dist_m = total_dist
        
        # 4. Battery Margin & Safety Check
        # Drone consumes ~1% battery per 40m
        round_trip_dist = total_dist * 2.0
        battery_needed = round_trip_dist / 40.0
        battery_margin = drone.battery_percent - battery_needed
        
        if battery_margin < 20.0:
            eval_res.rejection_reasons.append(
                f"Insufficient battery reserve: needs {battery_needed:.1f}%, leaves only {battery_margin:.1f}% (< 20% RTB threshold)"
            )
            return eval_res
        else:
            eval_res.positive_reasons.append(
                f"Sufficient battery margin ({drone.battery_percent:.1f}% current, ~{battery_margin:.1f}% post-mission reserve)"
            )

        # 5. Risk Assessment
        risk = risk_agent.evaluate_route_risk(
            [wp.position for wp in waypoints], drone, total_dist
        )
        eval_res.risk = risk
        
        if risk.category == "CRITICAL" and priority_score < 0.90:
            eval_res.rejection_reasons.append(f"Extreme mission risk ({risk.overall_risk:.2f}): {'; '.join(risk.contributors)}")
            return eval_res
        elif risk.category == "CRITICAL" and priority_score >= 0.90:
            eval_res.positive_reasons.append(f"Elevated risk accepted for critical life-saving intervention ({risk.overall_risk:.2f})")
        else:
            eval_res.positive_reasons.append(f"Acceptable risk corridor ({risk.category}, score {risk.overall_risk:.2f})")

        # 6. Multi-Attribute Utility Score
        # Maximize utility: Capability (1.0), Distance proximity (0-1), Battery level (0-1), Low risk (0-1)
        dist_factor = 1.0 / (1.0 + total_dist / 150.0)
        battery_factor = drone.battery_percent / 100.0
        risk_factor = 1.0 - risk.overall_risk
        
        utility = (
            0.35 * 1.0  # capability matches
            + 0.25 * dist_factor
            + 0.20 * battery_factor
            + 0.20 * risk_factor
        )
        
        eval_res.eligible = True
        eval_res.utility_score = round(utility, 4)
        eval_res.positive_reasons.append(f"Route distance {total_dist:.0f}m (proximity factor: {dist_factor:.2f})")
        return eval_res

    async def allocate_best_drone(
        self,
        target_pos: Vector3D,
        required_capability: DroneCapability = DroneCapability.SCOUT,
        priority_score: float = 0.5,
        target_entity_id: Optional[str] = None,
    ) -> Tuple[Optional[DroneEntity], str, Dict[str, Any]]:
        """Optimizes drone selection subject to constraints and produces explainable decision audit."""
        evaluations: Dict[str, DroneEvaluation] = {}
        for drone_id, drone in world_state.drones.items():
            eval_res = self.evaluate_drone_for_mission(drone, target_pos, required_capability, priority_score)
            evaluations[drone_id] = eval_res

        # Filter eligible candidates
        eligible = [e for e in evaluations.values() if e.eligible]
        if not eligible:
            reasons_summary = "; ".join(
                [f"{eid}: {', '.join(ev.rejection_reasons)}" for eid, ev in evaluations.items()]
            )
            return None, f"No eligible drone found. Rejection details: {reasons_summary}", {}

        # Pick highest utility candidate
        eligible.sort(key=lambda x: x.utility_score, reverse=True)
        winner_eval = eligible[0]
        selected_drone = world_state.drones[winner_eval.drone_id]

        # Build comprehensive explanation
        explanation_lines = [
            f"Selected {selected_drone.id} ({selected_drone.callsign}) with optimal utility score {winner_eval.utility_score:.2f}:",
        ]
        for r in winner_eval.positive_reasons:
            explanation_lines.append(f"  + {r}")

        rejected_alternatives = []
        for e in evaluations.values():
            if e.drone_id != selected_drone.id:
                reasons = e.rejection_reasons if not e.eligible else [f"Lower utility score ({e.utility_score:.2f} vs {winner_eval.utility_score:.2f})"]
                explanation_lines.append(f"Rejected {e.drone_id}: {'; '.join(reasons)}")
                rejected_alternatives.append({"drone_id": e.drone_id, "reasons": reasons})

        full_explanation = "\n".join(explanation_lines)

        await audit_logger.log_event(
            event_type=AuditEventType.DRONE_SELECTED,
            decision=f"Drone {selected_drone.id} allocated for mission to {target_entity_id or 'target'}",
            reason=full_explanation,
            inputs={
                "target_location": target_pos.model_dump(),
                "required_capability": required_capability.value,
                "priority_score": priority_score,
            },
            output={
                "selected_drone_id": selected_drone.id,
                "utility_score": winner_eval.utility_score,
                "estimated_distance_m": winner_eval.estimated_dist_m,
                "rejected_alternatives": rejected_alternatives,
            },
            affected_entities=[selected_drone.id] + ([target_entity_id] if target_entity_id else []),
        )

        return selected_drone, full_explanation, {
            "utility_score": winner_eval.utility_score,
            "estimated_distance_m": winner_eval.estimated_dist_m,
            "risk": winner_eval.risk.model_dump() if winner_eval.risk else None,
            "rejected_alternatives": rejected_alternatives,
        }


resource_agent = ResourceAgent()
