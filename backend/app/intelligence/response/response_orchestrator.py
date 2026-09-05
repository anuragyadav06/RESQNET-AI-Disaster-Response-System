"""Closed-loop disaster response coordinator."""
from __future__ import annotations
from typing import Dict, Any
from app.state.world_state import world_state
from app.schemas.drone import DroneStatus, DroneCapability
from app.intelligence.victims.prioritization_agent import prioritization_agent
from app.intelligence.missions.mission_agent import mission_agent
from app.intelligence.search.search_planner import search_planner
from app.events.event_bus import event_bus
from app.schemas.mission import MissionPlan, MissionObjective, MissionStatus
from app.intelligence.commands.command_agent import command_agent
from app.schemas.command import CommandType

class ResponseOrchestrator:
    async def start_recon(self) -> Dict[str, Any]:
        """Activate the authoritative Godot 16-line vertical scout doctrine."""
        from app.websocket.connection_manager import connection_manager
        sent = await connection_manager.send_simulation_control("START_GRID_SEARCH")
        scouts = [d.id for d in world_state.drones.values() if DroneCapability.SCOUT in d.capabilities]
        result = {
            "status": "SUCCESS" if sent else "WAITING_FOR_SYSTEM_B",
            "drone_count": len(scouts),
            "scout_drones": scouts,
            "planner": "AUTHORITATIVE_16_VERTICAL_CORRIDORS",
            "motion_policy": "FIXED_X_Z_AXIS_ONLY_SOUTH_NORTH",
            "overlap_policy": "ZERO_CROSS_CELL_SCOUTING",
            "dispatched": [{"drone_id": d, "mode": "FIXED_VERTICAL_CORRIDOR_SEARCH"} for d in scouts],
            "message": "16 scout drones are assigned one-to-one to fixed vertical X corridors." if sent else "System B Digital Twin is not connected yet."
        }
        await event_bus.publish("RECON_GRID_ACTIVATED", result)
        return result

    async def triage_and_dispatch(self) -> Dict[str, Any]:
        victims = await prioritization_agent.prioritize_all()
        dispatched = []
        for victim in sorted(victims, key=lambda v: v.priority_score, reverse=True):
            if victim.assigned_drone_id:
                continue
            plan, message = await mission_agent.create_and_dispatch_mission_for_victim(victim.id)
            if plan:
                dispatched.append({"mission_id": plan.mission_id, "victim_id": victim.id, "message": message})
                if len(dispatched) >= 3:
                    break
        result = {"prioritized": len(victims), "dispatched": dispatched}
        await event_bus.publish("RESPONSE_CYCLE_EXECUTED", result)
        return result

    async def status(self):
        return {
            "disaster_active": bool(world_state.incidents or world_state.hazards),
            "victims": len(world_state.victims),
            "critical_victims": sum(1 for v in world_state.victims.values() if v.priority_class.value == "CRITICAL"),
            "available_drones": sum(1 for d in world_state.drones.values() if d.status.value == "IDLE"),
            "active_missions": sum(1 for m in world_state.missions.values() if m.status.value in {"DISPATCHED", "IN_PROGRESS", "REPLANNING"}),
            "trapped_victims": sum(1 for v in world_state.victims.values() if v.status.value == "TRAPPED"),
            "rescued_victims": sum(1 for v in world_state.victims.values() if v.status.value == "RESCUED"),
        }

response_orchestrator = ResponseOrchestrator()
