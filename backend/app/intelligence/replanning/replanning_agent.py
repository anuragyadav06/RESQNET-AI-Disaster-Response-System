"""
ResQNet Intelligence - Dynamic Mission Replanning Agent
Monitors active missions and autonomously recalculates routes or reallocates drones upon environment changes.
"""
import time
from typing import Any, Dict, List, Optional
from app.schemas.mission import MissionPlan, MissionStatus
from app.schemas.drone import DroneStatus
from app.schemas.command import CommandType
from app.schemas.audit import AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger
from app.intelligence.routing.routing_agent import routing_agent
from app.intelligence.commands.command_agent import command_agent


class ReplanningAgent:
    def __init__(self):
        pass

    async def evaluate_and_replan(self) -> List[Dict[str, Any]]:
        """Evaluates all active missions against dynamic road blockages, expanding fires, and battery changes."""
        replan_results: List[Dict[str, Any]] = []
        
        for mid, mission in list(world_state.missions.items()):
            if mission.status not in [MissionStatus.DISPATCHED, MissionStatus.IN_PROGRESS]:
                continue

            drone_id = mission.assigned_drone_id
            if drone_id not in world_state.drones:
                continue
            drone = world_state.drones[drone_id]

            # 1. Emergency Battery Contingency
            if drone.battery_percent < 15.0:
                mission.status = MissionStatus.REPLANNING
                node_path, rtb_wps, _ = routing_agent.plan_route(drone.position, world_state.facilities["BASE-ALPHA"].location)
                mission.waypoints = rtb_wps
                mission.route_nodes = node_path
                drone.status = DroneStatus.RETURNING
                
                await command_agent.issue_mission_command(mission, CommandType.RETURN_TO_BASE)
                await audit_logger.log_event(
                    event_type=AuditEventType.REPLAN_TRIGGERED,
                    decision=f"Replanning: Emergency RTB triggered for {drone.id}",
                    reason=f"Battery level dropped to {drone.battery_percent:.1f}% (< 15% safety floor)",
                    inputs={"mission_id": mid, "battery": drone.battery_percent},
                    output={"action": "RETURN_TO_BASE"},
                    affected_entities=[drone.id, mid],
                )
                replan_results.append({"mission_id": mid, "action": "RETURN_TO_BASE", "reason": "Low battery"})
                continue

            # 2. Dynamic Route Invalidation Check
            is_valid, bad_entity = routing_agent.is_route_valid(mission.route_nodes)
            if not is_valid:
                # Path severed! Must dynamically recalculate detour around obstacle
                target_pos = None
                if mission.target_victim_id and mission.target_victim_id in world_state.victims:
                    target_pos = world_state.victims[mission.target_victim_id].location
                elif mission.waypoints:
                    target_pos = mission.waypoints[-1].position

                if target_pos:
                    # Plan new detour from current drone position
                    new_nodes, new_wps, new_dist = routing_agent.plan_route(drone.position, target_pos)
                    mission.route_nodes = new_nodes
                    mission.waypoints = new_wps
                    mission.replan_count += 1
                    mission.status = MissionStatus.REPLANNING
                    
                    # Send updated waypoints to System B
                    issued, cmd, msg = await command_agent.issue_mission_command(mission, CommandType.NAVIGATE)
                    mission.status = MissionStatus.IN_PROGRESS
                    world_state.increment_version()

                    reason_msg = f"Flight route invalidated by blockage/hazard on {bad_entity}. Recalculated dynamic detour ({len(new_wps)} waypoints, {new_dist:.0f}m)"
                    await audit_logger.log_event(
                        event_type=AuditEventType.REPLAN_TRIGGERED,
                        decision=f"Replanning: Route recalculated for {drone.id} (Detour around {bad_entity})",
                        reason=reason_msg,
                        inputs={"mission_id": mid, "invalid_segment": bad_entity},
                        output={"new_nodes": new_nodes, "distance_m": new_dist, "replan_count": mission.replan_count},
                        confidence=1.0,
                        affected_entities=[drone.id, mid, bad_entity],
                    )
                    replan_results.append({
                        "mission_id": mid,
                        "action": "REROUTE",
                        "reason": reason_msg,
                        "new_distance_m": new_dist,
                    })

        return replan_results


replanning_agent = ReplanningAgent()
