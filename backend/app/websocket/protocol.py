"""
ResQNet WebSocket Protocol Definition & Message Parsing
"""
from enum import Enum
from pydantic import BaseModel, Field
from typing import Any, Dict, List, Optional
from app.schemas.telemetry import DroneTelemetryPacket, ObservationPacket
from app.schemas.command import CommandPayload, CommandAck, CommandResult


class MessageType(str, Enum):
    # System B -> System A
    REGISTER_SIMULATION = "REGISTER_SIMULATION"
    TELEMETRY_BATCH = "TELEMETRY_BATCH"
    OBSERVATION = "OBSERVATION"
    COMMAND_ACK = "COMMAND_ACK"
    COMMAND_RESULT = "COMMAND_RESULT"
    HEARTBEAT = "HEARTBEAT"
    
    # System A -> System B
    COMMAND = "COMMAND"
    SIMULATION_CONTROL = "SIMULATION_CONTROL"  # PAUSE, RESUME, RESET, INJECT_HAZARD
    HEARTBEAT_ACK = "HEARTBEAT_ACK"
    
    # System A -> Frontend
    STATE_UPDATE = "STATE_UPDATE"
    ALERT = "ALERT"
    AUDIT_EVENT = "AUDIT_EVENT"


class SystemBRegisterMessage(BaseModel):
    type: MessageType = MessageType.REGISTER_SIMULATION
    session_id: str
    client_version: str = "Godot_4.7"
    environment_name: str = "Metro City"
    grid_bounds: Dict[str, float] = Field(default_factory=lambda: {"min_x": -200, "max_x": 200, "min_z": -200, "max_z": 200})


class TelemetryBatchMessage(BaseModel):
    type: MessageType = MessageType.TELEMETRY_BATCH
    session_id: str
    timestamp: float
    packets: List[DroneTelemetryPacket] = Field(default_factory=list)


class ObservationMessage(BaseModel):
    type: MessageType = MessageType.OBSERVATION
    session_id: str
    observation: ObservationPacket


class HeartbeatMessage(BaseModel):
    type: MessageType = MessageType.HEARTBEAT
    client_timestamp: float
    sequence: int = 0
