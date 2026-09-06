"""
ResQNet Intelligence - Mission Planning Agent
Orchestrates victim prioritizations, drone allocations, routes, and risk
into executable mission plans.

UPDATED:
- Supports capability fallback when the preferred drone class is unavailable.
- Allows multiple UAV missions simultaneously.
- Does NOT impose an arbitrary active-drone limit.
- Preserves ResourceAgent safety/risk constraints.
- Converts fallback assignments into capability-compatible mission objectives.
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

    # ============================================================
    # CAPABILITY -> FALLBACK OBJECTIVE
    # ============================================================

    @staticmethod
    def _objective_for_capability(
        capability: DroneCapability,
        requested_objective: MissionObjective,
    ) -> MissionObjective:
        """
        Convert the requested mission into an objective that the
        actually assigned drone is capable of performing.

        This is used only when the ideal drone capability is unavailable.
        """

        if capability == DroneCapability.MEDICAL:
            return MissionObjective.MEDICAL_SUPPLY_DROP

        if capability == DroneCapability.HEAVY_LIFT:
            return MissionObjective.HEAVY_EXTRICATION

        if capability == DroneCapability.RESCUE:
            return requested_objective

        if capability == DroneCapability.SCOUT:
            return MissionObjective.STRUCTURAL_SURVEY

        return requested_objective

    # ============================================================
    # CAPABILITY FALLBACK ORDER
    # ============================================================

    @staticmethod
    def _fallback_capabilities(
        required_capability: DroneCapability,
    ) -> List[DroneCapability]:
        """
        Return capability search order.

        The requested capability is ALWAYS tried first.

        If unavailable, RESQNET progressively considers other
        operational UAV classes.

        This removes the previous hard failure:

            "No eligible RESCUE drone found"

        while still allowing ResourceAgent to reject unsafe drones.
        """

        fallback_order = [
            DroneCapability.RESCUE,
            DroneCapability.MEDICAL,
            DroneCapability.HEAVY_LIFT,
            DroneCapability.SCOUT,
        ]

        ordered: List[DroneCapability] = []

        # Required capability always gets first priority.
        ordered.append(required_capability)

        # Then try all other capabilities.
        for capability in fallback_order:
            if capability not in ordered:
                ordered.append(capability)

        return ordered

    # ============================================================
    # CREATE + DISPATCH
    # ============================================================

    async def create_and_dispatch_mission_for_victim(
        self,
        victim_id: str,
        objective_override: Optional[MissionObjective] = None,
        preferred_drone_id: Optional[str] = None,
    ) -> Tuple[Optional[MissionPlan], str]:

        if victim_id not in world_state.victims:
            return None, f"Victim {victim_id} not found"

        victim = world_state.victims[victim_id]

        # ========================================================
        # 1. DETERMINE IDEAL CAPABILITY + OBJECTIVE
        # ========================================================

        if objective_override:
            requested_objective = objective_override

            required_cap = {
                MissionObjective.MEDICAL_SUPPLY_DROP:
                    DroneCapability.MEDICAL,

                MissionObjective.HEAVY_EXTRICATION:
                    DroneCapability.HEAVY_LIFT,

                MissionObjective.STRUCTURAL_SURVEY:
                    DroneCapability.HEAVY_LIFT,

                MissionObjective.RESCUE_EXTRACTION:
                    DroneCapability.RESCUE,

                MissionObjective.RESCUE_TRIAGE:
                    DroneCapability.RESCUE,
            }.get(
                requested_objective,
                DroneCapability.SCOUT,
            )

        elif victim.medical_severity >= 0.60:
            requested_objective = MissionObjective.MEDICAL_SUPPLY_DROP
            required_cap = DroneCapability.MEDICAL

        elif victim.accessibility_factor < 0.35:
            requested_objective = MissionObjective.HEAVY_EXTRICATION
            required_cap = DroneCapability.HEAVY_LIFT

        else:
            requested_objective = MissionObjective.RESCUE_EXTRACTION
            required_cap = DroneCapability.RESCUE

        objective = requested_objective

        # ========================================================
        # 2. ALLOCATE DRONE
        # ========================================================

        drone = None
        explanation = ""
        meta: Dict = {}
        selected_capability: Optional[DroneCapability] = None

        # --------------------------------------------------------
        # OPERATOR OVERRIDE
        # --------------------------------------------------------

        if preferred_drone_id:

            drone = world_state.drones.get(preferred_drone_id)

            if not drone:
                return None, (
                    f"Requested drone {preferred_drone_id} "
                    f"does not exist"
                )

            if drone.status != DroneStatus.IDLE:
                return None, (
                    f"Requested drone {preferred_drone_id} "
                    f"is unavailable ({drone.status.value})"
                )

            if required_cap not in drone.capabilities:
                return None, (
                    f"Requested drone {preferred_drone_id} "
                    f"lacks capability {required_cap.value}"
                )

            selected_capability = required_cap

            explanation = (
                f"Operator selected {preferred_drone_id}; "
                f"required capability {required_cap.value} "
                f"confirmed"
            )

            meta = {
                "selection_mode": "OPERATOR_OVERRIDE",
                "selected_capability": required_cap.value,
                "fallback_used": False,
            }

        # --------------------------------------------------------
        # AUTOMATIC ALLOCATION + FALLBACK
        # --------------------------------------------------------

        else:

            allocation_attempts: List[str] = []

            for capability in self._fallback_capabilities(required_cap):

                candidate, candidate_explanation, candidate_meta = (
                    await resource_agent.allocate_best_drone(
                        target_pos=victim.location,
                        required_capability=capability,
                        priority_score=victim.priority_score,
                        target_entity_id=victim.id,
                    )
                )

                allocation_attempts.append(
                    f"{capability.value}: {candidate_explanation}"
                )

                if candidate:

                    drone = candidate
                    selected_capability = capability

                    # Ideal capability selected.
                    if capability == required_cap:

                        explanation = (
                            f"{candidate_explanation}; "
                            f"selected required capability "
                            f"{capability.value}"
                        )

                        meta = {
                            **candidate_meta,
                            "selection_mode": "AUTOMATIC",
                            "selected_capability": capability.value,
                            "requested_capability": required_cap.value,
                            "fallback_used": False,
                        }

                    # Fallback capability selected.
                    else:

                        objective = self._objective_for_capability(
                            capability,
                            requested_objective,
                        )

                        explanation = (
                            f"Required {required_cap.value} drone "
                            f"was unavailable. "
                            f"Fallback selected {drone.id} "
                            f"({capability.value}) after safety "
                            f"and availability checks."
                        )

                        meta = {
                            **candidate_meta,
                            "selection_mode": "AUTOMATIC_FALLBACK",
                            "selected_capability": capability.value,
                            "requested_capability": required_cap.value,
                            "fallback_used": True,
                            "fallback_reason": (
                                f"No eligible "
                                f"{required_cap.value} drone"
                            ),
                        }

                    break

            # No drone from ANY capability class.
            if not drone:

                detailed_reason = " | ".join(allocation_attempts)

                return None, (
                    "Resource allocation failed: "
                    "No safe and available UAV could be allocated. "
                    f"Requested capability: {required_cap.value}. "
                    f"Allocation attempts: {detailed_reason}"
                )

        # ========================================================
        # 3. PLAN ROUTE
        # ========================================================

        node_path, waypoints, total_dist = routing_agent.plan_route(
            drone.position,
            victim.location,
            altitude=105.0,
        )

        # ========================================================
        # 4. ASSESS ROUTE RISK
        # ========================================================

        risk = risk_agent.evaluate_route_risk(
            [wp.position for wp in waypoints],
            drone,
            total_dist,
        )

        # ========================================================
        # 5. BUILD MISSION PLAN
        # ========================================================

        now = time.time()

        mission_id = (
            f"MSN-{victim_id}-{uuid.uuid4().hex[:4]}"
        )

        est_duration = round(
            total_dist / 12.0 + 30.0,
            1,
        )

        est_battery_drain = round(
            total_dist / 40.0 * 2.0,
            1,
        )

        fallback_note = ""

        if meta.get("fallback_used"):
            fallback_note = (
                f" Fallback UAV: {drone.id} "
                f"({selected_capability.value})."
            )

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
            fallback_strategy=(
                f"If battery drops below 20% or comms lost, "
                f"abort to {drone.home_facility_id}"
            ),
            explanation=explanation + fallback_note,
            status=MissionStatus.DISPATCHED,
            created_at=now,
            dispatched_at=now,
        )

        # ========================================================
        # 6. UPDATE WORLD STATE
        # ========================================================

        world_state.missions[mission_id] = plan

        drone.status = DroneStatus.EN_ROUTE
        drone.current_mission_id = mission_id
        drone.target_victim_id = victim.id

        victim.assigned_drone_id = drone.id
        victim.assigned_mission_id = mission_id

        world_state.increment_version()

        # ========================================================
        # 7. AUDIT
        # ========================================================

        audit_reason = (
            f"Assigned {drone.id} to victim {victim.id} "
            f"(Priority: {victim.priority_class.value})"
        )

        if meta.get("fallback_used"):
            audit_reason += (
                f". Fallback capability used: "
                f"{selected_capability.value} instead of "
                f"{required_cap.value}"
            )

        await audit_logger.log_event(
            event_type=AuditEventType.MISSION_CREATED,
            decision=(
                f"Mission {mission_id} planned and dispatched "
                f"({objective.value})"
            ),
            reason=audit_reason,
            inputs={
                "victim_id": victim.id,
                "drone_id": drone.id,
                "priority": victim.priority_score,
                "requested_capability": required_cap.value,
                "selected_capability": (
                    selected_capability.value
                    if selected_capability
                    else None
                ),
                "fallback_used": meta.get(
                    "fallback_used",
                    False,
                ),
            },
            output={
                "mission_id": mission_id,
                "estimated_duration_s": est_duration,
                "risk": risk.category,
            },
            confidence=1.0,
            affected_entities=[
                mission_id,
                drone.id,
                victim.id,
            ],
        )

        # ========================================================
        # 8. COMMAND SYSTEM B
        # ========================================================

        if objective == MissionObjective.MEDICAL_SUPPLY_DROP:
            cmd_type = CommandType.DELIVER_SUPPLIES
        else:
            cmd_type = CommandType.NAVIGATE

        issued, cmd_payload, msg = (
            await command_agent.issue_mission_command(
                plan,
                cmd_type,
            )
        )

        # ========================================================
        # 9. ROLLBACK IF SYSTEM B REJECTS COMMAND
        # ========================================================

        if not issued:

            world_state.missions.pop(
                mission_id,
                None,
            )

            drone.status = DroneStatus.IDLE
            drone.current_mission_id = None
            drone.target_victim_id = None

            victim.assigned_drone_id = None
            victim.assigned_mission_id = None

            world_state.increment_version()

            return None, (
                f"Dispatch not executed: {msg}"
            )

        # ========================================================
        # 10. SUCCESS MESSAGE
        # ========================================================

        if meta.get("fallback_used"):

            return plan, (
                f"Mission {mission_id} successfully dispatched "
                f"using fallback UAV {drone.id} "
                f"({selected_capability.value}). "
                f"Original requirement: {required_cap.value}. "
                f"Objective: {objective.value}. "
                f"{msg}"
            )

        return plan, (
            f"Mission {mission_id} successfully created "
            f"and dispatched ({msg})"
        )

    # ============================================================
    # AUTO DISPATCH HIGHEST PRIORITY
    # ============================================================

    async def auto_plan_highest_priority(
        self,
    ) -> Tuple[Optional[MissionPlan], str]:
        """
        Scans all unresolved victims and dispatches the
        highest-priority unserviced victim.
        """

        unassigned_victims = [
            v
            for v in world_state.victims.values()
            if not v.assigned_drone_id
            and v.status.value in [
                "DETECTED",
                "TRIAGED",
            ]
        ]

        if not unassigned_victims:
            return None, (
                "No pending unassigned victims found"
            )

        unassigned_victims.sort(
            key=lambda v: v.priority_score,
            reverse=True,
        )

        top_victim = unassigned_victims[0]

        return await self.create_and_dispatch_mission_for_victim(
            top_victim.id
        )

    # ============================================================
    # ABORT MISSION
    # ============================================================

    async def abort_mission(
        self,
        mission_id: str,
        reason: str = "Operator abort",
    ) -> bool:

        if mission_id not in world_state.missions:
            return False

        mission = world_state.missions[mission_id]

        mission.status = MissionStatus.ABORTED
        mission.failure_reason = reason

        if mission.assigned_drone_id in world_state.drones:

            drone = world_state.drones[
                mission.assigned_drone_id
            ]

            drone.status = DroneStatus.RETURNING

            # Issue RTB command.
            node_path, rtb_wps, _ = (
                routing_agent.plan_route(
                    drone.position,
                    Vector3D(x=0, y=0, z=0),
                )
            )

            mission.waypoints = rtb_wps

            await command_agent.issue_mission_command(
                mission,
                CommandType.RETURN_TO_BASE,
            )

        world_state.increment_version()

        await audit_logger.log_event(
            event_type=AuditEventType.MISSION_FAILED,
            decision=f"Mission {mission_id} ABORTED",
            reason=reason,
            output={
                "status": "ABORTED"
            },
            affected_entities=[
                mission_id,
                mission.assigned_drone_id,
            ],
        )

        return True


mission_agent = MissionAgent()