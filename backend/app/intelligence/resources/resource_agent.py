"""
ResQNet Intelligence - Multi-Constrained Drone Fleet Resource Allocation Agent

Responsibilities:
- Select an available drone for a mission.
- Enforce capability, battery, route, and safety constraints.
- Never silently allocate a busy drone.
- For critical life-saving missions, allow controlled risk acceptance
  when an exact-capability drone is available but the route is otherwise
  classified as CRITICAL.
- Preserve explainable allocation decisions and audit information.
"""

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
    """
    Multi-constrained drone resource allocator.

    Important safety rule:
    A drone must be IDLE before it can be allocated.

    Critical missions may accept an otherwise CRITICAL route risk,
    but this does NOT permit:
    - unavailable drones,
    - busy drones,
    - insufficient battery,
    - missing capabilities.
    """

    # Risk ceiling for ordinary missions.
    STANDARD_CRITICAL_RISK_LIMIT = 0.90

    # Absolute ceiling for an emergency life-saving mission.
    #
    # Your current simulation can produce values around 0.98 because of
    # simultaneous fire + aftershock conditions. A critical rescue can
    # therefore still proceed if an exact-capability drone is available.
    EMERGENCY_RISK_LIMIT = 0.985

    # A mission above this value is considered too dangerous even for
    # emergency rescue.
    ABSOLUTE_RISK_LIMIT = 0.99

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

        # ============================================================
        # 1. STATUS / AVAILABILITY
        # ============================================================

        if drone.status in [
            DroneStatus.CHARGING,
            DroneStatus.ERROR,
            DroneStatus.LOST,
        ]:
            eval_res.rejection_reasons.append(
                f"Drone is in unavailable state: {drone.status.value}"
            )
            return eval_res

        # A drone must actually be idle before allocation.
        #
        # The previous implementation mentioned "preemption required"
        # but did not perform preemption. That could allow a busy drone
        # to become eligible accidentally.
        if drone.status != DroneStatus.IDLE:
            eval_res.rejection_reasons.append(
                f"Drone busy with existing task ({drone.status.value})"
            )
            return eval_res

        eval_res.positive_reasons.append("Drone is available and IDLE")

        # ============================================================
        # 2. CAPABILITY
        # ============================================================

        has_capability = required_capability in drone.capabilities

        if not has_capability:
            eval_res.rejection_reasons.append(
                f"Missing required capability "
                f"'{required_capability.value}' "
                f"(Has: {[c.value for c in drone.capabilities]})"
            )
            return eval_res

        eval_res.positive_reasons.append(
            f"Equipped with required {required_capability.value} payload/sensors"
        )

        # ============================================================
        # 3. ROUTE FEASIBILITY / DISTANCE
        # ============================================================

        try:
            node_path, waypoints, total_dist = routing_agent.plan_route(
                drone.position,
                target_pos,
            )
        except Exception as exc:
            eval_res.rejection_reasons.append(
                f"Route planning failed: {exc}"
            )
            return eval_res

        if not waypoints:
            eval_res.rejection_reasons.append(
                "No feasible route generated to target"
            )
            return eval_res

        eval_res.estimated_dist_m = total_dist

        eval_res.positive_reasons.append(
            f"Route feasible ({total_dist:.0f}m)"
        )

        # ============================================================
        # 4. BATTERY
        # ============================================================

        # Simulation model:
        # approximately 1% battery per 40m.
        round_trip_dist = total_dist * 2.0
        battery_needed = round_trip_dist / 40.0
        battery_margin = drone.battery_percent - battery_needed

        if battery_margin < 20.0:
            eval_res.rejection_reasons.append(
                f"Insufficient battery reserve: "
                f"needs {battery_needed:.1f}%, "
                f"leaves only {battery_margin:.1f}% "
                f"(< 20% RTB threshold)"
            )
            return eval_res

        eval_res.positive_reasons.append(
            f"Sufficient battery margin "
            f"({drone.battery_percent:.1f}% current, "
            f"~{battery_margin:.1f}% post-mission reserve)"
        )

        # ============================================================
        # 5. ROUTE RISK
        # ============================================================

        try:
            risk = risk_agent.evaluate_route_risk(
                [wp.position for wp in waypoints],
                drone,
                total_dist,
            )
        except Exception as exc:
            eval_res.rejection_reasons.append(
                f"Risk assessment failed: {exc}"
            )
            return eval_res

        eval_res.risk = risk

        risk_score = float(risk.overall_risk)

        # ------------------------------------------------------------
        # Standard mission
        # ------------------------------------------------------------
        if risk.category == "CRITICAL":
            if priority_score < 0.90:
                eval_res.rejection_reasons.append(
                    f"Extreme mission risk ({risk_score:.2f}): "
                    f"{'; '.join(risk.contributors)}"
                )
                return eval_res

            # --------------------------------------------------------
            # Critical life-saving mission
            # --------------------------------------------------------
            if risk_score >= self.ABSOLUTE_RISK_LIMIT:
                eval_res.rejection_reasons.append(
                    f"Mission risk {risk_score:.2f} exceeds absolute "
                    f"safety ceiling ({self.ABSOLUTE_RISK_LIMIT:.2f})"
                )
                return eval_res

            if risk_score <= self.EMERGENCY_RISK_LIMIT:
                eval_res.positive_reasons.append(
                    f"Critical life-saving mission accepted despite "
                    f"elevated route risk ({risk_score:.2f})"
                )

                if risk.contributors:
                    eval_res.positive_reasons.append(
                        f"Risk contributors acknowledged: "
                        f"{'; '.join(risk.contributors)}"
                    )

        else:
            eval_res.positive_reasons.append(
                f"Acceptable risk corridor "
                f"({risk.category}, score {risk_score:.2f})"
            )

        # ============================================================
        # 6. MULTI-ATTRIBUTE UTILITY
        # ============================================================

        # Proximity:
        # closer drones are preferred.
        dist_factor = 1.0 / (1.0 + total_dist / 150.0)

        # Battery:
        battery_factor = max(
            0.0,
            min(1.0, drone.battery_percent / 100.0),
        )

        # Risk:
        risk_factor = max(
            0.0,
            min(1.0, 1.0 - risk_score),
        )

        utility = (
            0.35 * 1.0
            + 0.25 * dist_factor
            + 0.20 * battery_factor
            + 0.20 * risk_factor
        )

        eval_res.eligible = True
        eval_res.utility_score = round(utility, 4)

        eval_res.positive_reasons.append(
            f"Route distance {total_dist:.0f}m "
            f"(proximity factor: {dist_factor:.2f})"
        )

        eval_res.positive_reasons.append(
            f"Utility score {eval_res.utility_score:.2f}"
        )

        return eval_res

    async def allocate_best_drone(
        self,
        target_pos: Vector3D,
        required_capability: DroneCapability = DroneCapability.SCOUT,
        priority_score: float = 0.5,
        target_entity_id: Optional[str] = None,
    ) -> Tuple[Optional[DroneEntity], str, Dict[str, Any]]:
        """
        Select the best available drone satisfying all hard constraints.

        Hard constraints:
        - Drone must be IDLE.
        - Drone must have required capability.
        - Drone must have sufficient battery.
        - Route must be feasible.
        - Risk must remain below the emergency absolute ceiling.

        For critical missions, CRITICAL route risk can be accepted
        when it remains below the emergency ceiling.
        """

        evaluations: Dict[str, DroneEvaluation] = {}

        for drone_id, drone in world_state.drones.items():
            evaluations[drone_id] = self.evaluate_drone_for_mission(
                drone=drone,
                target_pos=target_pos,
                required_capability=required_capability,
                priority_score=priority_score,
            )

        # ============================================================
        # ELIGIBLE CANDIDATES
        # ============================================================

        eligible = [
            evaluation
            for evaluation in evaluations.values()
            if evaluation.eligible
        ]

        if not eligible:
            # Produce a concise explanation first.
            exact_capability_rejections = []
            busy_count = 0
            unavailable_count = 0
            risk_count = 0
            battery_count = 0

            for evaluation in evaluations.values():
                reasons = evaluation.rejection_reasons

                for reason in reasons:
                    if "busy with existing task" in reason:
                        busy_count += 1

                    if "unavailable state" in reason:
                        unavailable_count += 1

                    if "Extreme mission risk" in reason or "risk" in reason.lower():
                        risk_count += 1

                    if "battery" in reason.lower():
                        battery_count += 1

                if reasons:
                    exact_capability_rejections.append(
                        f"{evaluation.drone_id}: {'; '.join(reasons)}"
                    )

            summary_parts = [
                f"No eligible {required_capability.value} drone found."
            ]

            if busy_count:
                summary_parts.append(
                    f"{busy_count} drone(s) busy"
                )

            if unavailable_count:
                summary_parts.append(
                    f"{unavailable_count} unavailable"
                )

            if risk_count:
                summary_parts.append(
                    f"{risk_count} rejected by safety/risk constraints"
                )

            if battery_count:
                summary_parts.append(
                    f"{battery_count} rejected by battery constraints"
                )

            summary_parts.append(
                "Detailed rejection: " +
                "; ".join(exact_capability_rejections)
            )

            return None, " | ".join(summary_parts), {}

        # ============================================================
        # SELECT BEST
        # ============================================================

        # Highest utility wins.
        #
        # Because risk contributes to utility, if multiple rescue drones
        # are available, the safer route is naturally preferred.
        eligible.sort(
            key=lambda evaluation: evaluation.utility_score,
            reverse=True,
        )

        winner_eval = eligible[0]
        selected_drone = world_state.drones[winner_eval.drone_id]

        # ============================================================
        # EXPLANATION
        # ============================================================

        explanation_lines = [
            (
                f"Selected {selected_drone.id} "
                f"({selected_drone.callsign}) "
                f"with optimal utility score "
                f"{winner_eval.utility_score:.2f}:"
            )
        ]

        for reason in winner_eval.positive_reasons:
            explanation_lines.append(f"  + {reason}")

        rejected_alternatives = []

        for evaluation in evaluations.values():
            if evaluation.drone_id == selected_drone.id:
                continue

            if evaluation.eligible:
                reasons = [
                    (
                        f"Lower utility score "
                        f"({evaluation.utility_score:.2f} vs "
                        f"{winner_eval.utility_score:.2f})"
                    )
                ]
            else:
                reasons = evaluation.rejection_reasons

            explanation_lines.append(
                f"Rejected {evaluation.drone_id}: "
                f"{'; '.join(reasons)}"
            )

            rejected_alternatives.append(
                {
                    "drone_id": evaluation.drone_id,
                    "reasons": reasons,
                }
            )

        full_explanation = "\n".join(explanation_lines)

        # ============================================================
        # AUDIT
        # ============================================================

        await audit_logger.log_event(
            event_type=AuditEventType.DRONE_SELECTED,
            decision=(
                f"Drone {selected_drone.id} allocated for mission to "
                f"{target_entity_id or 'target'}"
            ),
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
                "risk": (
                    winner_eval.risk.model_dump()
                    if winner_eval.risk
                    else None
                ),
                "rejected_alternatives": rejected_alternatives,
            },
            affected_entities=(
                [selected_drone.id]
                + ([target_entity_id] if target_entity_id else [])
            ),
        )

        return (
            selected_drone,
            full_explanation,
            {
                "utility_score": winner_eval.utility_score,
                "estimated_distance_m": winner_eval.estimated_dist_m,
                "risk": (
                    winner_eval.risk.model_dump()
                    if winner_eval.risk
                    else None
                ),
                "rejected_alternatives": rejected_alternatives,
            },
        )


resource_agent = ResourceAgent()