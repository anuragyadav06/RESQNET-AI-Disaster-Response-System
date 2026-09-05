"""
ResQNet WebSocket Connection Manager & Real-Time Hub
"""
import asyncio
import json
import logging
import time
from typing import Any, Dict, List, Optional, Set
from fastapi import WebSocket

from app.schemas.command import CommandPayload, CommandAck, CommandResult
from app.schemas.telemetry import DroneTelemetryPacket, ObservationPacket
from app.schemas.audit import AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger

logger = logging.getLogger("resqnet.websocket")


class ConnectionManager:
    def __init__(self):
        # Maps session_id -> WebSocket for System B (Godot / Digital Twin)
        self.simulation_clients: Dict[str, WebSocket] = {}
        # Set of active frontend WebSockets
        self.frontend_clients: Set[WebSocket] = set()
        
        # Pending commands awaiting ACK: command_id -> {sent_time, payload}
        self.pending_commands: Dict[str, Dict[str, Any]] = {}
        
        self._lock = asyncio.Lock()
        self._broadcast_task: Optional[asyncio.Task] = None

    async def connect_simulation(self, session_id: str, websocket: WebSocket):
        await websocket.accept()
        async with self._lock:
            self.simulation_clients[session_id] = websocket
            world_state.system_b_connected = True
            world_state.system_b_session_id = session_id
        
        await audit_logger.log_event(
            event_type=AuditEventType.SIMULATION_EVENT,
            decision=f"System B connected for session {session_id}",
            reason="WebSocket handshake established with Godot Digital Twin",
            output={"session_id": session_id, "status": "CONNECTED"},
        )
        logger.info(f"System B simulation connected: {session_id}")

    async def disconnect_simulation(self, session_id: str):
        async with self._lock:
            if session_id in self.simulation_clients:
                del self.simulation_clients[session_id]
            if not self.simulation_clients:
                world_state.system_b_connected = False
                world_state.system_b_session_id = None
        
        await audit_logger.log_event(
            event_type=AuditEventType.SIMULATION_EVENT,
            decision=f"System B disconnected for session {session_id}",
            reason="WebSocket connection terminated",
            output={"session_id": session_id, "status": "DISCONNECTED"},
        )
        logger.warning(f"System B simulation disconnected: {session_id}")

    async def connect_frontend(self, websocket: WebSocket):
        await websocket.accept()
        async with self._lock:
            self.frontend_clients.add(websocket)
        logger.info(f"Frontend client connected. Total frontend clients: {len(self.frontend_clients)}")
        
        # Immediately push initial state snapshot
        try:
            snapshot = world_state.get_snapshot().model_dump(mode="json")
            snapshot.pop("simulation_frame_base64", None)
            snapshot.pop("simulation_frame_mime_type", None)
            snapshot.pop("simulation_frame_timestamp", None)
            await websocket.send_text(json.dumps({
                "type": "STATE_UPDATE",
                "snapshot": snapshot,
                "timestamp": time.time(),
            }))
        except Exception as e:
            logger.error(f"Error sending initial state to frontend: {e}")

    async def disconnect_frontend(self, websocket: WebSocket):
        async with self._lock:
            self.frontend_clients.discard(websocket)
        logger.info(f"Frontend client disconnected. Remaining: {len(self.frontend_clients)}")

    async def send_command_to_system_b(self, command: CommandPayload) -> bool:
        """Sends a validated machine-readable command to the connected Godot simulation."""
        sent_time = time.time()
        command.issued_at = sent_time
        if command.expires_at <= 0:
            command.expires_at = sent_time + 60.0  # 60 second default timeout
        
        msg = {
            "type": "COMMAND",
            "command": command.model_dump(mode="json"),
        }
        msg_str = json.dumps(msg)
        
        async with self._lock:
            if not self.simulation_clients:
                logger.warning(f"Cannot send command {command.command_id}: No System B simulation connected")
                return False
            
            # Store in pending queue
            self.pending_commands[command.command_id] = {
                "sent_time": sent_time,
                "command": command,
            }
            world_state.last_command_sent_time = sent_time
            
            # Broadcast to all connected simulation clients (usually 1)
            sent = False
            for ws in list(self.simulation_clients.values()):
                try:
                    await ws.send_text(msg_str)
                    sent = True
                except Exception as e:
                    logger.error(f"Failed to transmit command to simulation: {e}")
            return sent

    async def send_simulation_control(self, action: str, parameters: Optional[Dict[str, Any]] = None) -> bool:
        """Send an operator scenario control to the authoritative Godot Digital Twin."""
        message = {"type": "SIMULATION_CONTROL", "action": action, "parameters": parameters or {}}
        async with self._lock:
            if not self.simulation_clients:
                return False
            sent = False
            for ws in list(self.simulation_clients.values()):
                try:
                    await ws.send_text(json.dumps(message))
                    sent = True
                except Exception as exc:
                    logger.error("Simulation control transmission failed: %s", exc)
            return sent

    async def handle_command_ack(self, ack: CommandAck):
        recv_time = time.time()
        command_id = ack.command_id
        latency_ms = 0.0
        
        if command_id in self.pending_commands:
            sent_time = self.pending_commands[command_id]["sent_time"]
            latency_ms = (recv_time - sent_time) * 1000.0
            world_state.command_latency_ms = round(latency_ms, 2)
            del self.pending_commands[command_id]
        
        await audit_logger.log_event(
            event_type=AuditEventType.COMMAND_ACKNOWLEDGED,
            decision=f"Command {command_id} acknowledged by System B: {ack.status}",
            reason=ack.reason or "Simulation acknowledged command acceptance",
            inputs={"command_id": command_id, "drone_id": ack.drone_id},
            output={"status": ack.status, "latency_ms": latency_ms},
            confidence=1.0,
            affected_entities=[ack.drone_id],
        )

    async def broadcast_to_frontend(self, message: Dict[str, Any]):
        """Broadcasts a JSON-serializable message to all connected operator screens."""
        if not self.frontend_clients:
            return
        msg_str = json.dumps(message)
        disconnected = []
        for ws in self.frontend_clients:
            try:
                await ws.send_text(msg_str)
            except Exception:
                disconnected.append(ws)
        
        if disconnected:
            async with self._lock:
                for ws in disconnected:
                    self.frontend_clients.discard(ws)

    async def start_periodic_broadcast(self, interval_s: float = 0.2):
        """Streams state snapshots and diagnostics to frontend at ~5Hz."""
        while True:
            try:
                await asyncio.sleep(interval_s)
                if self.frontend_clients:
                    snapshot = world_state.get_snapshot().model_dump(mode="json")
                    snapshot.pop("simulation_frame_base64", None)
                    snapshot.pop("simulation_frame_mime_type", None)
                    snapshot.pop("simulation_frame_timestamp", None)
                    await self.broadcast_to_frontend({
                        "type": "STATE_UPDATE",
                        "snapshot": snapshot,
                        "timestamp": time.time(),
                    })
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error during state broadcast: {e}")


# Global connection manager singleton
connection_manager = ConnectionManager()
