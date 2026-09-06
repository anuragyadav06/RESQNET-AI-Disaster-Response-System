"""
ResQNet REST API v1 Endpoints
"""
import time
from typing import Any, Dict, List, Optional
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from app.core.config import settings
from app.schemas.common import Vector3D
from app.schemas.drone import DroneStatus
from app.schemas.mission import MissionObjective, MissionStatus
from app.schemas.world import WorldStateSnapshot, HazardZone, HazardType
from app.schemas.victim import Victim, VictimStatus
from app.schemas.incident import IncidentEntity, IncidentType
from app.schemas.audit import AuditRecord, AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger
from app.intelligence.victims.prioritization_agent import prioritization_agent
from app.intelligence.missions.mission_agent import mission_agent
from app.intelligence.routing.routing_agent import routing_agent
from app.intelligence.replanning.replanning_agent import replanning_agent
from app.simulation.scenarios import scenario_manager
from app.intelligence.search.search_planner import search_planner
from app.intelligence.response.response_orchestrator import response_orchestrator
from app.intelligence.voice.command_interpreter import voice_interpreter
from app.events.event_bus import event_bus

api_router = APIRouter()


# 1. Health & Status
@api_router.get("/health")
async def get_health():
    now = time.time()
    stale = world_state.check_stale_telemetry(now)
    return {
        "status": "OPERATIONAL",
        "system_a_version": settings.VERSION,
        "system_b_connected": world_state.system_b_connected,
        "simulation_time": world_state.simulation_time,
        "state_version": world_state.state_version,
        "telemetry_rate_hz": world_state.get_snapshot().telemetry_rate_hz,
        "command_latency_ms": world_state.command_latency_ms,
        "stale_entities": stale,
        "timestamp": now,
    }


# 2. World State Snapshot
@api_router.get("/world", response_model=WorldStateSnapshot)
async def get_world_state():
    return world_state.get_snapshot()


# 3. Simulation Scenarios & Control
@api_router.post("/simulation/earthquake")
async def trigger_earthquake_scenario():
    return await scenario_manager.trigger_metro_earthquake()


@api_router.post("/simulation/aftershock")
async def trigger_aftershock_scenario():
    return await scenario_manager.trigger_aftershock_and_roadblock()


@api_router.post("/simulation/reset")
async def reset_simulation():
    return await scenario_manager.reset_to_normal()


# 4. Incidents
class IncidentCreateRequest(BaseModel):
    type: IncidentType = IncidentType.FIRE
    title: str = "Structural Fire Outbreak"
    location: Vector3D
    severity: float = 0.8
    radius_m: float = 30.0


@api_router.get("/incidents")
async def list_incidents():
    return list(world_state.incidents.values())


@api_router.post("/incidents")
async def create_incident(req: IncidentCreateRequest):
    inc_id = f"INC-MANUAL-{int(time.time()*1000)%100000}"
    incident = IncidentEntity(
        id=inc_id,
        type=req.type,
        title=req.title,
        location=req.location,
        severity=req.severity,
        radius_m=req.radius_m,
        confidence=1.0,
        timestamp=time.time(),
        evidence=["Manual operator injection"],
    )
    world_state.incidents[inc_id] = incident
    if req.type == IncidentType.FIRE:
        world_state.hazards[f"HAZ-{inc_id}"] = HazardZone(
            id=f"HAZ-{inc_id}",
            type=HazardType.FIRE,
            center=req.location,
            radius_m=req.radius_m,
            intensity=req.severity,
        )
    world_state.increment_version()
    return incident


# 5. Victims & Prioritization
@api_router.get("/victims")
async def list_victims():
    return list(world_state.victims.values())


class VictimDetectionRequest(BaseModel):
    """Camera/thermal detection submitted by System B or an operator test client."""
    source_drone_id: str
    location: Vector3D
    confidence: float = 0.85
    hazard_type: str = "UNKNOWN"
    people_count: int = 1
    medical_severity: float = 0.7
    urgency: float = 0.75
    hazard_exposure: float = 0.0
    image_url: Optional[str] = None
    image_base64: Optional[str] = None
    image_mime_type: Optional[str] = None
    notes: Optional[str] = None


@api_router.post("/victims/detect")
async def detect_victim(req: VictimDetectionRequest):
    from app.schemas.telemetry import ObservationPacket, ObservationType
    from app.intelligence.incidents.incident_agent import incident_agent
    obs = ObservationPacket(
        observation_id=f"OBS-VIC-{int(time.time()*1000)}",
        timestamp=time.time(),
        source_drone_id=req.source_drone_id,
        type=ObservationType.VICTIM_LOCATED,
        location=req.location,
        confidence=req.confidence,
        raw_reading={
            "hazard_type": req.hazard_type, "people_count": req.people_count,
            "medical_severity": req.medical_severity, "urgency": req.urgency,
            "hazard_exposure": req.hazard_exposure,
        },
        notes=req.notes, image_url=req.image_url, image_base64=req.image_base64,
        image_mime_type=req.image_mime_type, hazard_type=req.hazard_type,
    )
    incident = await incident_agent.process_observation(obs)
    nearest = min(world_state.victims.values(), key=lambda v: v.location.ground_distance_to(req.location))
    return {"status": "DETECTED", "victim": nearest, "incident": incident}


@api_router.post("/victims/reprioritize")
async def reprioritize_victims():
    updated = await prioritization_agent.prioritize_all()
    return updated


# 6. Drones & Fleet
@api_router.get("/drones")
async def list_drones():
    return list(world_state.drones.values())


class DroneDispatchRequest(BaseModel):
    drone_id: str
    victim_id: str
    objective: Optional[MissionObjective] = None


@api_router.post("/drones/dispatch")
async def dispatch_drone(req: DroneDispatchRequest):
    preferred = None if req.drone_id.upper() == "AUTO" else req.drone_id
    if preferred is not None:
        if preferred not in world_state.drones:
            raise HTTPException(status_code=404, detail=f"Drone {preferred} not found")
        requested = world_state.drones[preferred]
        if requested.status.value != "IDLE":
            raise HTTPException(status_code=409, detail=f"Drone {preferred} is not available ({requested.status.value})")
    plan, msg = await mission_agent.create_and_dispatch_mission_for_victim(req.victim_id, req.objective, preferred_drone_id=preferred)
    if not plan:
        raise HTTPException(status_code=400, detail=msg)
    return {"status": "SUCCESS", "mission": plan, "message": msg}


# 7. Missions
@api_router.get("/missions")
async def list_missions():
    return list(world_state.missions.values())


@api_router.post("/missions/auto-plan")
async def auto_plan_mission():
    plan, msg = await mission_agent.auto_plan_highest_priority()
    if not plan:
        raise HTTPException(status_code=404, detail=msg)
    return {"status": "SUCCESS", "mission": plan, "message": msg}


@api_router.post("/missions/{mission_id}/abort")
async def abort_mission(mission_id: str):
    success = await mission_agent.abort_mission(mission_id)
    if not success:
        raise HTTPException(status_code=404, detail=f"Mission {mission_id} not found")
    return {"status": "SUCCESS", "mission_id": mission_id}


def _resolve_drone_id(drone_id: str) -> str:
    """Voice/operator input may omit dashes or casing (e.g. 'drone3' vs 'DRONE-3')."""
    if drone_id in world_state.drones:
        return drone_id
    normalized = drone_id.upper().replace(" ", "-")
    if normalized in world_state.drones:
        return normalized
    compact = normalized.replace("-", "")
    for known_id in world_state.drones:
        if known_id.replace("-", "") == compact:
            return known_id
    raise HTTPException(status_code=404, detail=f"Drone {drone_id} not found")


@api_router.post("/drones/{drone_id}/abort-mission")
async def abort_drone_mission(drone_id: str):
    """Abort whatever mission the given drone is currently flying."""
    resolved_id = _resolve_drone_id(drone_id)
    drone = world_state.drones[resolved_id]
    if not drone.current_mission_id:
        raise HTTPException(status_code=409, detail=f"Drone {resolved_id} has no active mission")
    mission_id = drone.current_mission_id
    success = await mission_agent.abort_mission(mission_id, reason="Operator voice command: abort")
    if not success:
        raise HTTPException(status_code=404, detail=f"Mission {mission_id} not found")
    return {"status": "SUCCESS", "drone_id": resolved_id, "mission_id": mission_id}


@api_router.post("/drones/{drone_id}/rtb")
async def return_drone_to_base(drone_id: str):
    """Return-to-base: abort any active mission for the drone so it stands down."""
    resolved_id = _resolve_drone_id(drone_id)
    drone = world_state.drones[resolved_id]
    if drone.current_mission_id:
        await mission_agent.abort_mission(drone.current_mission_id, reason="Operator voice command: RTB")
    return {"status": "SUCCESS", "drone_id": resolved_id, "message": f"{resolved_id} recalled to base"}


# 8. Routes & Graph
class RoutePlanRequest(BaseModel):
    start: Vector3D
    target: Vector3D


@api_router.post("/routes/plan")
async def plan_route(req: RoutePlanRequest):
    nodes, wps, dist = routing_agent.plan_route(req.start, req.target)
    return {"nodes": nodes, "waypoints": wps, "distance_m": dist}


class RoadBlockRequest(BaseModel):
    edge_id: str
    reason: str = "Structural collapse blockage"


@api_router.post("/routes/block")
async def block_road(req: RoadBlockRequest):
    success = world_state.block_road_edge(req.edge_id, req.reason)
    if not success:
        raise HTTPException(status_code=404, detail=f"Road edge {req.edge_id} not found")
    replan = await replanning_agent.evaluate_and_replan()
    return {"status": "SUCCESS", "edge_id": req.edge_id, "replan_results": replan}


@api_router.post("/routes/unblock")
async def unblock_road(req: RoadBlockRequest):
    success = world_state.unblock_road_edge(req.edge_id)
    if not success:
        raise HTTPException(status_code=404, detail=f"Road edge {req.edge_id} not found")
    return {"status": "SUCCESS", "edge_id": req.edge_id}


# 9. Hazards
@api_router.get("/hazards")
async def list_hazards():
    return list(world_state.hazards.values())


# 10. Commands
@api_router.get("/commands")
async def list_commands():
    from app.intelligence.commands.command_agent import command_agent
    return command_agent.command_history[-50:]


# 11. Decisions & Explanations
@api_router.get("/decisions")
async def list_decisions(limit: int = 50):
    events = audit_logger.get_recent(limit=limit)
    decision_events = [
        e for e in events
        if e.event_type in [
            AuditEventType.DRONE_SELECTED,
            AuditEventType.VICTIM_PRIORITIZED,
            AuditEventType.MISSION_CREATED,
            AuditEventType.REPLAN_TRIGGERED,
        ]
    ]
    return decision_events


# 12. Audit Events Feed
@api_router.get("/events")
async def list_events(limit: int = 100, event_type: Optional[str] = None):
    et = AuditEventType(event_type) if event_type else None
    return audit_logger.get_recent(limit=limit, event_type=et)


# 13. Replanning manual trigger
@api_router.post("/replanning/evaluate")
async def evaluate_replanning():
    results = await replanning_agent.evaluate_and_replan()
    return {"status": "SUCCESS", "replan_results": results}


# 12-14. Integrated command, search, response and voice control
class VoiceCommandRequest(BaseModel):
    text: str


@api_router.get("/search/plan")
async def get_search_plan():
    return search_planner.build_plan()


@api_router.post("/response/recon")
async def start_recon():
    return await response_orchestrator.start_recon()


@api_router.post("/response/triage-dispatch")
async def triage_dispatch():
    return await response_orchestrator.triage_and_dispatch()


class ResponseDispatchRequest(BaseModel):
    victim_id: str
    objective: MissionObjective
    drone_id: str = "AUTO"


@api_router.post("/response/dispatch")
async def dispatch_response(req: ResponseDispatchRequest):
    """Explicit operator response dispatch; command is transmitted to System B."""
    preferred = None if req.drone_id.upper() == "AUTO" else _resolve_drone_id(req.drone_id)
    plan, msg = await mission_agent.create_and_dispatch_mission_for_victim(
        req.victim_id, req.objective, preferred_drone_id=preferred
    )
    if not plan:
        raise HTTPException(status_code=400, detail=msg)
    return {"status": "SUCCESS", "mission": plan, "message": msg}


@api_router.get("/response/status")
async def response_status():
    return await response_orchestrator.status()


@api_router.post("/voice/interpret")
async def interpret_voice(req: VoiceCommandRequest):
    parsed = voice_interpreter.parse(req.text)
    await event_bus.publish("VOICE_COMMAND_INTERPRETED", {"text": req.text, **parsed}, source="OPERATOR")
    return parsed


@api_router.post("/voice/execute")
async def execute_voice(req: VoiceCommandRequest):
    """Interpret and execute only supported deterministic operator intents."""
    parsed = voice_interpreter.parse(req.text)
    intent = str(parsed.get("intent", "UNKNOWN"))
    params = parsed.get("parameters", {}) or {}

    if intent == "START_RECON":
        result = await response_orchestrator.start_recon()
    elif intent == "AUTO_DISPATCH":
        requested_objective = params.get("objective")
        objective = MissionObjective(str(requested_objective)) if requested_objective else None
        result = await response_orchestrator.triage_and_dispatch(objective=objective)
    elif intent == "DISPATCH_RESPONSE":
        objective = MissionObjective(str(params.get("objective", "RESCUE_EXTRACTION")))
        victim_id = str(params.get("victim_id", ""))
        plan, msg = await mission_agent.create_and_dispatch_mission_for_victim(victim_id, objective)
        if not plan:
            raise HTTPException(status_code=400, detail=msg)
        result = {"status": "SUCCESS", "mission": plan, "message": msg}
    elif intent == "GET_STATUS":
        result = await response_orchestrator.status()
    elif intent == "PRIORITIZE_ROOFTOP":
        updated = await prioritization_agent.prioritize_all()
        result = {"status": "SUCCESS", "victims": updated}
    elif intent == "ABORT_DRONE_MISSION":
        drone_id = _resolve_drone_id(str(params.get("drone_id", "")))
        drone = world_state.drones[drone_id]
        if not drone.current_mission_id:
            raise HTTPException(status_code=409, detail=f"Drone {drone_id} has no active mission")
        ok = await mission_agent.abort_mission(drone.current_mission_id, reason="Operator voice command: abort")
        result = {"status": "SUCCESS" if ok else "FAILED", "drone_id": drone_id}
    elif intent == "RTB":
        drone_id = _resolve_drone_id(str(params.get("drone_id", "")))
        drone = world_state.drones[drone_id]
        if drone.current_mission_id:
            await mission_agent.abort_mission(drone.current_mission_id, reason="Operator voice command: RTB")
        result = {"status": "SUCCESS", "drone_id": drone_id, "message": f"{drone_id} recalled to base"}
    elif intent == "DEPLOY_TO_SECTOR":
        drone_id = _resolve_drone_id(str(params.get("drone_id", "")))
        drone = world_state.drones[drone_id]
        if drone.status.value != "IDLE":
            raise HTTPException(status_code=409, detail=f"Drone {drone_id} is not available ({drone.status.value})")
        result = {"status": "ACCEPTED", "drone_id": drone_id, "sector": str(params.get("sector", "")), "message": "Sector command accepted; System-B will execute the movement."}
    else:
        return {"status": "NOT_EXECUTED", "parsed": parsed, "message": "Command requires a supported structured target/action."}

    await event_bus.publish("VOICE_COMMAND_EXECUTED", {"text": req.text, **parsed, "result": result}, source="OPERATOR")
    return {"status": "EXECUTED", "parsed": parsed, "result": result}


# ============================================================
# SYSTEM-B RESPONSE LIFECYCLE
# ============================================================

def _terminal_status_for_response(action: str, objective: str = "") -> VictimStatus:
    """Map a completed System-B response to a frontend terminal victim status."""
    action_upper = str(action or "").upper()
    objective_upper = str(objective or "").upper()

    if "MEDICAL" in action_upper or "SUPPL" in action_upper or "MEDICAL" in objective_upper:
        return VictimStatus.TREATED

    if (
        "EXTRICATION" in action_upper
        or "HEAVY" in action_upper
        or "EXTRICATION" in objective_upper
    ):
        return VictimStatus.RESCUED

    if (
        "RESCUE" in action_upper
        or "EXTRACTION" in action_upper
        or "RESCUE" in objective_upper
    ):
        return VictimStatus.RESCUED

    if "TRIAGE" in action_upper:
        return VictimStatus.ASSISTED

    # Survey/recon is an intervention acknowledgement rather than
    # a physical extraction, but it is terminal for the current
    # response lifecycle displayed by TacticalMap.
    return VictimStatus.ASSISTED


async def _handle_system_b_response_completed(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process Godot's generic RESPONSE_COMPLETED event.

    Victim assignment fields are deliberately retained here. That lets
    TacticalMap keep the handled victim visible while the handling drone
    is still at the victim, then remove it when the drone physically
    leaves the victim area.
    """
    success = bool(event.get("success", True))
    victim_id = event.get("victim_id")
    mission_id = event.get("mission_id")
    drone_id = event.get("drone_id")
    action = str(event.get("action", ""))
    result = event.get("result", {})

    if not success:
        return {
            "status": "FAILED",
            "victim_id": victim_id,
            "mission_id": mission_id,
            "drone_id": drone_id,
        }

    victim = world_state.victims.get(str(victim_id)) if victim_id else None
    mission = world_state.missions.get(str(mission_id)) if mission_id else None

    if mission is not None:
        mission.status = MissionStatus.COMPLETED
        if hasattr(mission, "failure_reason"):
            mission.failure_reason = None
        if hasattr(mission, "result"):
            mission.result = result

    if victim is not None:
        objective = mission.objective.value if mission is not None else ""
        victim.status = _terminal_status_for_response(action, objective)

        if hasattr(victim, "notes"):
            note = f" System-B response completed successfully ({action or 'response'})."
            victim.notes = (victim.notes or "") + note

    world_state.increment_version()

    await audit_logger.log_event(
        event_type=AuditEventType.MISSION_CREATED,
        decision=(
            f"System-B response completed"
            f"{f' for mission {mission_id}' if mission_id else ''}"
        ),
        reason=(
            f"Response completed for victim {victim_id or 'unknown'} "
            f"using drone {drone_id or 'unknown'}."
        ),
        inputs={
            "victim_id": victim_id,
            "mission_id": mission_id,
            "drone_id": drone_id,
            "action": action,
        },
        output={
            "mission_status": mission.status.value if mission is not None else None,
            "victim_status": victim.status.value if victim is not None else None,
        },
        confidence=1.0,
        affected_entities=[
            x for x in [mission_id, drone_id, victim_id] if x
        ],
    )

    return {
        "status": "COMPLETED",
        "victim_id": victim_id,
        "mission_id": mission_id,
        "drone_id": drone_id,
        "victim_status": victim.status.value if victim is not None else None,
    }


@api_router.post("/simulation/system-b-event")
async def receive_system_b_event(event: Dict[str, Any]):
    """
    REST endpoint for System-B lifecycle events and direct testing.
    """
    event_type = str(
        event.get("event_type")
        or event.get("type")
        or event.get("event")
        or ""
    ).upper()

    if event_type == "RESPONSE_COMPLETED":
        return await _handle_system_b_response_completed(event)

    if event_type == "RESPONSE_FAILED":
        return {
            "status": "FAILED",
            "victim_id": event.get("victim_id"),
            "mission_id": event.get("mission_id"),
            "drone_id": event.get("drone_id"),
        }

    return {"status": "IGNORED", "event_type": event_type}


@api_router.get("/events/live")
async def live_events(limit: int = Query(default=50, ge=1, le=200)):
    return event_bus.recent(limit)
