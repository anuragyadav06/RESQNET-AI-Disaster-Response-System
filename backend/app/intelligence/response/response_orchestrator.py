"""Closed-loop disaster response coordinator."""
from __future__ import annotations
from typing import Dict, Any
from app.state.world_state import world_state
from app.schemas.drone import DroneStatus
from app.intelligence.victims.prioritization_agent import prioritization_agent
from app.intelligence.missions.mission_agent import mission_agent
from app.intelligence.search.search_planner import search_planner
from app.events.event_bus import event_bus
from app.schemas.mission import MissionPlan, MissionObjective, MissionStatus
from app.intelligence.commands.command_agent import command_agent
from app.schemas.command import CommandType

class ResponseOrchestrator:
    async def start_recon(self) -> Dict[str, Any]:
        plan = search_planner.build_plan()
        dispatched=[]
        for drone_id, points in plan["coverage_assignments"].items():
            if not points: continue
            drone=world_state.drones.get(drone_id)
            if not drone or drone.status != DroneStatus.IDLE: continue
            mission_id=f"RECON-{drone_id}-{int(__import__('time').time()*1000)%100000}"
            waypoints=[]
            for i,p in enumerate(points):
                waypoints.append(__import__('app.schemas.mission',fromlist=['Waypoint']).Waypoint(index=i, position=__import__('app.schemas.common',fromlist=['Vector3D']).Vector3D(**p), action="HOVER_AND_SURVEY" if i%2==0 else "FLY_THROUGH", action_duration_s=2.0 if i%2==0 else 0.0))
            mission=MissionPlan(mission_id=mission_id,objective=MissionObjective.PERIMETER_PATROL,assigned_drone_id=drone_id,priority_score=.8,waypoints=waypoints,estimated_duration_s=max(60,len(waypoints)*2.5),estimated_battery_drain=min(60,len(waypoints)*1.2),status=MissionStatus.DISPATCHED,created_at=__import__('time').time(),dispatched_at=__import__('time').time(),explanation="Multi-drone coverage partition with RRT* motion planning")
            world_state.missions[mission_id]=mission; drone.status=DroneStatus.EN_ROUTE; drone.current_mission_id=mission_id
            ok,cmd,msg=await command_agent.issue_mission_command(mission,CommandType.SURVEY)
            if ok: dispatched.append({"drone_id":drone_id,"mission_id":mission_id,"waypoints":len(waypoints)})
        world_state.increment_version()
        result={**plan,"dispatched":dispatched}
        await event_bus.publish("RECON_PLAN_DISPATCHED",result)
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
        }

response_orchestrator = ResponseOrchestrator()
