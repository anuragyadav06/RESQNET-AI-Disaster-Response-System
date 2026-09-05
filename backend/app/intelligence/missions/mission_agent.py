"""
ResQNet Intelligence - Mission Planning Agent
Orchestrates victim prioritizations, drone allocations, routes, and risk into executable mission plans.
"""
import time
import uuid
from typing import Dict, List, Optional, Tuple
from app.schemas.common import Vector3D
from app.schemas.victim import Victim, VictimPriorityClass
from app.schemas.drone import DroneCapability, DroneStatus
from app.schemas.mission import (
    MissionPlan,
    MissionObjective,
    MissionStatus,
    RiskAssessment,
)
from app.schemas.command import CommandType
from app.schemas.audit import AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger
from app.intelligence.routing.routing_agent import routing_agent
from app.intelligence.risk.risk_agent import risk_agent
from app.intelligence.resources.resource_agent import resource_agent
from app.intelligence.commands.command_agent import command_agent


class MissionAgent:
    def __init__(self):
        pass

    async def create_and_dispatch_mission_for_victim(
        self,
        victim_id: str,
        objective_override: Optional[MissionObjective] = None,
        preferred_drone_id: Optional[str] = None,
    ) -> Tuple[Optional[MissionPlan], str]:
        if victim_id not in world_state.victims:
            return None, f"Victim {victim_id} not found"
        
        victim = world_state.victims[victim_id]
        
        # 1. Determine capability requirement & objective
        if objective_override:
            objective = objective_override
            required_cap = DroneCapability.SCOUT
            if objective == MissionObjective.MEDICAL_SUPPLY_DROP:
                required_cap = DroneCapability.MEDICAL
        elif victim.medical_severity >= 0.60:
            objective = MissionObjective.MEDICAL_SUPPLY_DROP
            required_cap = DroneCapability.MEDICAL
        elif victim.accessibility_factor < 0.35:
            objective = MissionObjective.STRUCTURAL_SURVEY
            required_cap = DroneCapability.HEAVY_LIFT
        else:
            objective = MissionObjective.RESCUE_TRIAGE
            required_cap = DroneCapability.SCOUT

        # 2. Allocate optimal drone, or honor an explicit operator selection
        if preferred_drone_id:
            drone = world_state.drones.get(preferred_drone_id)
            if not drone or drone.status != DroneStatus.IDLE:
                return None, f"Requested drone {preferred_drone_id} is unavailable"
            if required_cap not in drone.capabilities:
                return None, f"Requested drone {preferred_drone_id} lacks capability {required_cap.value}"
            explanation = f"Operator selected {preferred_drone_id}; safety and capability checks passed"
            meta = {"selection_mode": "OPERATOR_OVERRIDE"}
        else:
            drone, explanation, meta = await resource_agent.allocate_best_drone(
                target_pos=victim.location,
                required_capability=required_cap,
                priority_score=victim.priority_score,
                target_entity_id=victim.id,
            )
        
        if not drone:
            return None, f"Resource allocation failed: {explanation}"

        # 3. Plan optimal route
        node_path, waypoints, total_dist = routing_agent.plan_route(drone.position, victim.location)
        
        # 4. Assess risk
        risk = risk_agent.evaluate_route_risk(
            [wp.position for wp in waypoints], drone, total_dist
        )

        # 5. Build Mission Plan
        now = time.time()
        mission_id = f"MSN-{victim_id}-{uuid.uuid4().hex[:4]}"
        est_duration = round(total_dist / 12.0 + 30.0, 1)  # ~12 m/s flight + 30s survey/drop
        est_battery_drain = round(total_dist / 40.0 * 2.0, 1)  # round trip drain

        plan = MissionPlan(
            mission_id=mission_id,
            objective=objective,
            target_victim_id=victim.id,
            assigned_drone_id=drone.id,
            priority_score=victim.priority_score,
            route_nodes=node_path,
            waypoints=waypoints,
            estimated_duration_s=est_duration,
            estimated_battery_drain=est_battery_drain,
            risk=risk,
            fallback_strategy=f"If battery drops below 20% or comms lost, abort to {drone.home_facility_id}",
            explanation=explanation,
            status=MissionStatus.DISPATCHED,
            created_at=now,
            dispatched_at=now,
        )

        # Update entities
        world_state.missions[mission_id] = plan
        drone.status = DroneStatus.EN_ROUTE
        drone.current_mission_id = mission_id
        drone.target_victim_id = victim.id
        victim.assigned_drone_id = drone.id
        victim.assigned_mission_id = mission_id
        world_state.increment_version()

        await audit_logger.log_event(
            event_type=AuditEventType.MISSION_CREATED,
            decision=f"Mission {mission_id} planned and dispatched ({objective.value})",
            reason=f"Assigned {drone.id} to victim {victim.id} (Priority: {victim.priority_class.value})",
            inputs={"victim_id": victim.id, "drone_id": drone.id, "priority": victim.priority_score},
            output={"mission_id": mission_id, "estimated_duration_s": est_duration, "risk": risk.category},
            confidence=1.0,
            affected_entities=[mission_id, drone.id, victim.id],
        )

        # 6. Generate and send Command Protocol v1.0 packet to System B
        cmd_type = CommandType.DELIVER_SUPPLIES if objective == MissionObjective.MEDICAL_SUPPLY_DROP else CommandType.NAVIGATE
        issued, cmd_payload, msg = await command_agent.issue_mission_command(plan, cmd_type)

        return plan, f"Mission {mission_id} successfully created and dispatched ({msg})"

    async def auto_plan_highest_priority(self) -> Tuple[Optional[MissionPlan], str]:
        """Scans all unresolved victims, picks the highest unserviced victim, and plans mission."""
        unassigned_victims = [
            v for v in world_state.victims.values()
            if not v.assigned_drone_id and v.status.value in ["DETECTED", "TRIAGED"]
        ]
        if not unassigned_victims:
            return None, "No pending unassigned victims found"

        # Sort by priority score descending
        unassigned_victims.sort(key=lambda v: v.priority_score, reverse=True)
        top_victim = unassigned_victims[0]
        return await self.create_and_dispatch_mission_for_victim(top_victim.id)

    async def abort_mission(self, mission_id: str, reason: str = "Operator abort") -> bool:
        if mission_id not in world_state.missions:
            return False
        
        mission = world_state.missions[mission_id]
        mission.status = MissionStatus.ABORTED
        mission.failure_reason = reason
        
        if mission.assigned_drone_id in world_state.drones:
            drone = world_state.drones[mission.assigned_drone_id]
            drone.status = DroneStatus.RETURNING
            # Issue RTB command
            node_path, rtb_wps, _ = routing_agent.plan_route(drone.position, Vector3D(x=0, y=0, z=0))
            mission.waypoints = rtb_wps
            await command_agent.issue_mission_command(mission, CommandType.RETURN_TO_BASE)

        world_state.increment_version()
        await audit_logger.log_event(
            event_type=AuditEventType.MISSION_FAILED,
            decision=f"Mission {mission_id} ABORTED",
            reason=reason,
            output={"status": "ABORTED"},
            affected_entities=[mission_id, mission.assigned_drone_id],
        )
        return True


mission_agent = MissionAgent()
