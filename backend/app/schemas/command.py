"""
ResQNet Domain Schemas - System B Command Protocol v1.0
"""
from enum import Enum
from pydantic import BaseModel, Field
from typing import Any, Dict, List, Optional
from app.schemas.mission import Waypoint


class CommandType(str, Enum):
    TAKEOFF = "TAKEOFF"
    NAVIGATE = "NAVIGATE"
    SURVEY = "SURVEY"
    DELIVER_SUPPLIES = "DELIVER_SUPPLIES"
    RELAY_COMMS = "RELAY_COMMS"
    RETURN_TO_BASE = "RETURN_TO_BASE"
    LAND = "LAND"
    HOVER = "HOVER"
    ABORT = "ABORT"


class CommandPayload(BaseModel):
    protocol_version: str = "1.0"
    command_id: str = Field(..., description="e.g. CMD-001")
    drone_id: str = Field(..., description="e.g. DRONE-S01")
    command: CommandType
    waypoints: List[Waypoint] = Field(default_factory=list)
    priority: float = Field(default=0.5, ge=0.0, le=1.0)
    constraints: Dict[str, Any] = Field(default_factory=dict)
    issued_at: float = 0.0
    expires_at: float = 0.0
    signature: Optional[str] = None


class CommandAck(BaseModel):
    command_id: str
    drone_id: str
    status: str = "ACCEPTED"  # ACCEPTED, REJECTED
    reason: Optional[str] = None
    timestamp: float = 0.0


class CommandResult(BaseModel):
    command_id: str
    drone_id: str
    status: str = "SUCCESS"  # SUCCESS, PARTIAL, FAILED
    details: Optional[str] = None
    timestamp: float = 0.0
