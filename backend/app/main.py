"""
ResQNet System A - Command & Intelligence Platform
FastAPI Application Entry Point
"""
import asyncio
import json
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.api.v1.routes import api_router
from app.websocket.connection_manager import connection_manager
from app.websocket.protocol import MessageType
from app.schemas.telemetry import DroneTelemetryPacket, ObservationPacket
from app.schemas.command import CommandAck, CommandResult
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger
from app.intelligence.perception.perception_agent import perception_agent
from app.intelligence.incidents.incident_agent import incident_agent
from app.events.event_bus import event_bus
import os
import time

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("resqnet.main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Initializing ResQNet System A Command Platform...")
    await audit_logger.initialize()
    broadcast_task = asyncio.create_task(connection_manager.start_periodic_broadcast(interval_s=0.2))
    # Godot/System B is the authoritative Digital Twin. The legacy backend simulator
    # is opt-in for tests only, never started during normal operation.
    if os.getenv("RESQNET_INTERNAL_SIMULATOR", "0") == "1":
        from app.simulation.digital_twin_runner import digital_twin_runner
        digital_twin_runner.start()
        logger.warning("Legacy internal Digital Twin simulator enabled for test mode.")
    logger.info("ResQNet System A is fully OPERATIONAL.")
    yield
    # Shutdown
    logger.info("Shutting down ResQNet System A...")
    if os.getenv("RESQNET_INTERNAL_SIMULATOR", "0") == "1":
        from app.simulation.digital_twin_runner import digital_twin_runner
        digital_twin_runner.stop()
    broadcast_task.cancel()


app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.API_V1_STR)



async def _reconcile_simulation_event(payload: dict) -> None:
    """Apply authoritative System-B mission/response lifecycle changes to System A."""
    event = str(payload.get("event", payload.get("event_type", ""))).upper()
    mission_id = str(payload.get("mission_id", ""))
    victim_id = str(payload.get("victim_id", ""))
    drone_id = str(payload.get("drone_id", ""))
    success = bool(payload.get("success", False))

    if mission_id and mission_id in world_state.missions:
        mission = world_state.missions[mission_id]
        if event == "RESPONSE_ON_SITE":
            from app.schemas.mission import MissionStatus
            mission.status = MissionStatus.IN_PROGRESS
        elif event == "RESPONSE_COMPLETED":
            from app.schemas.mission import MissionStatus
            mission.status = MissionStatus.COMPLETED if success else MissionStatus.FAILED
            mission.completed_at = time.time()
            if not success:
                mission.failure_reason = str(payload.get("message", "Digital Twin response failed"))

    if drone_id and drone_id in world_state.drones:
        drone = world_state.drones[drone_id]
        if event == "RESPONSE_ON_SITE":
            from app.schemas.drone import DroneStatus
            drone.status = DroneStatus.ON_SITE
        elif event in {"RESPONSE_COMPLETED", "RESPONSE_FAILED"}:
            from app.schemas.drone import DroneStatus
            drone.status = DroneStatus.RETURNING

    if victim_id and victim_id in world_state.victims:
        victim = world_state.victims[victim_id]
        from app.schemas.victim import VictimStatus
        if event in {"VICTIM_TRAPPED", "TRAPPED_VICTIM", "VICTIM_COLLAPSE_TRAPPED"}:
            victim.status = VictimStatus.TRAPPED
            victim.priority_class = victim.priority_class.__class__.CRITICAL
            victim.priority_score = max(victim.priority_score, 0.99)
            victim.notes.append(str(payload.get("message", "Victim trapped by structural collapse.")))
        elif event == "RESPONSE_DISPATCHED":
            victim.status = VictimStatus.EN_ROUTE
            victim.assigned_drone_id = drone_id or victim.assigned_drone_id
        elif event == "RESPONSE_ON_SITE":
            victim.status = VictimStatus.EN_ROUTE
            victim.assigned_drone_id = drone_id or victim.assigned_drone_id
        elif event == "RESPONSE_COMPLETED" and success:
            action = str(payload.get("action", "")).upper()
            if action == "RESCUE_EXTRACTION":
                victim.status = VictimStatus.RESCUED
            elif action == "MEDICAL_SUPPLY_DROP":
                victim.status = VictimStatus.ASSISTED
            elif action in {"HEAVY_EXTRICATION", "STRUCTURAL_SURVEY"}:
                victim.status = VictimStatus.RESCUED
            else:
                victim.status = VictimStatus.TRIAGED
            if action in {"RESCUE_EXTRACTION", "HEAVY_EXTRICATION"}:
                victim.assigned_drone_id = drone_id or victim.assigned_drone_id

    world_state.increment_version()
    await event_bus.publish("DIGITAL_TWIN_RESPONSE", payload, source="SYSTEM_B")
    await connection_manager.broadcast_to_frontend({
        "type": "EVENT",
        "event": {
            "event_type": "DIGITAL_TWIN_RESPONSE",
            "payload": payload,
            "timestamp": time.time(),
            "source": "SYSTEM_B",
        },
    })


# ============================================================================
# WEBSOCKET ENDPOINTS
# ============================================================================

@app.websocket("/ws/frontend")
async def websocket_frontend_endpoint(websocket: WebSocket):
    """Operator Command Center WebSocket stream."""
    await connection_manager.connect_frontend(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            # Frontend can send client heartbeats or query requests
            msg = json.loads(data)
            if msg.get("type") == "PING":
                await websocket.send_text(json.dumps({"type": "PONG", "timestamp": msg.get("timestamp")}))
    except WebSocketDisconnect:
        await connection_manager.disconnect_frontend(websocket)
    except Exception as e:
        logger.error(f"Frontend WS error: {e}")
        await connection_manager.disconnect_frontend(websocket)


@app.websocket("/ws/simulation/{session_id}")
async def websocket_simulation_endpoint(websocket: WebSocket, session_id: str):
    """System B (Godot Digital Twin) Bidirectional WebSocket stream."""
    await connection_manager.connect_simulation(session_id, websocket)
    try:
        while True:
            text = await websocket.receive_text()
            data = json.loads(text)
            msg_type = data.get("type")

            if msg_type == MessageType.REGISTER_SIMULATION.value:
                world_state.system_b_connected = True
                world_state.system_b_session_id = data.get("session_id", session_id)
                # When a real Godot twin registers, its telemetry becomes the
                # authoritative fleet roster; discard demo-only backend drones.
                world_state.drones.clear()
                world_state.increment_version()
                await connection_manager.broadcast_to_frontend({
                    "type": "SYSTEM_EVENT",
                    "event": {"event_type": "SYSTEM_B_REGISTERED", "session_id": session_id, "timestamp": __import__("time").time()}
                })

            elif msg_type == MessageType.TELEMETRY_BATCH.value:
                for pkt_dict in data.get("packets", []):
                    pkt = DroneTelemetryPacket(**pkt_dict)
                    world_state.update_drone_telemetry(pkt)

            elif msg_type == MessageType.OBSERVATION.value:
                obs_dict = data.get("observation", {})
                obs = ObservationPacket(**obs_dict)
                validated_obs = perception_agent.process_observation(obs)
                if validated_obs:
                    await incident_agent.process_observation(validated_obs)
                    await event_bus.publish("OBSERVATION_RECEIVED", validated_obs.model_dump(mode="json"), source="SYSTEM_B", correlation_id=validated_obs.observation_id)
                    await connection_manager.broadcast_to_frontend({"type": "EVENT", "event": event_bus.recent(1)[-1]})

            elif msg_type == MessageType.COMMAND_ACK.value:
                ack = CommandAck(**data.get("ack", {}))
                await connection_manager.handle_command_ack(ack)

            elif msg_type == MessageType.COMMAND_RESULT.value:
                res = CommandResult(**data.get("result", {}))
                # Mark command complete in world state
                logger.info(f"Received command result: {res.command_id} - {res.status}")

            elif msg_type == "SIMULATION_STATE":
                state = data.get("state", {})
                world_state.simulation_time = float(state.get("simulation_time", world_state.simulation_time))
                world_state.environment.seismic_activity_richter = float(state.get("seismic_activity_richter", 0.0))
                # Reconcile active hazard zones from the authoritative Godot twin.
                incoming = {}
                for hz in state.get("hazards", []):
                    try:
                        from app.schemas.world import HazardZone, HazardType
                        htype = HazardType(str(hz.get("type", "FIRE")))
                        center = hz.get("center", {"x":0,"y":0,"z":0})
                        incoming[str(hz.get("id"))] = HazardZone(
                            id=str(hz.get("id")),
                            type=htype,
                            center=center,
                            radius_m=float(hz.get("radius_m", 30.0)),
                            intensity=float(hz.get("intensity", 0.8)),
                        )
                    except Exception:
                        continue
                # Only replace simulation-generated hazard IDs; preserve operator/API hazards.
                for hid in list(world_state.hazards.keys()):
                    if hid.startswith("HAZARD-FROM-GODOT-") or hid.startswith("HAZ-FIRE-") or hid == "HAZ-FLOOD-FRONT":
                        world_state.hazards.pop(hid, None)
                for hid, hz in incoming.items():
                    world_state.hazards[hid] = hz
                world_state.increment_version()
                await connection_manager.broadcast_to_frontend({
                    "type": "SIMULATION_EVENT",
                    "event": {"event_type": "SIMULATION_STATE", "state": state, "timestamp": time.time()}
                })

            elif msg_type == "SIMULATION_FRAME":
                world_state.simulation_frame_base64 = str(data.get("image_base64", ""))
                world_state.simulation_frame_mime_type = str(data.get("image_mime_type", "image/jpeg"))
                world_state.simulation_frame_timestamp = float(data.get("timestamp", time.time()))
                await connection_manager.broadcast_to_frontend({
                    "type": "SIMULATION_FRAME",
                    "image_base64": world_state.simulation_frame_base64,
                    "image_mime_type": world_state.simulation_frame_mime_type,
                    "timestamp": world_state.simulation_frame_timestamp,
                })

            elif msg_type == "EVENT":
                payload = data.get("payload", data.get("event", {}))
                if not isinstance(payload, dict):
                    payload = {}
                await _reconcile_simulation_event(payload)
                await event_bus.publish(
                    str(data.get("event_type", "SIMULATION_EVENT")),
                    payload,
                    source="SYSTEM_B",
                )

            elif msg_type == MessageType.HEARTBEAT.value:
                await websocket.send_text(json.dumps({
                    "type": MessageType.HEARTBEAT_ACK.value,
                    "server_time": world_state.simulation_time,
                }))

    except WebSocketDisconnect:
        await connection_manager.disconnect_simulation(session_id)
    except Exception as e:
        logger.error(f"Simulation WS error for {session_id}: {e}")
        await connection_manager.disconnect_simulation(session_id)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=False)
