"""
ResQNet Domain Schemas - Telemetry and Observations
"""
from enum import Enum
from pydantic import BaseModel, Field
from typing import Any, Dict, List, Optional
from app.schemas.common import Vector3D
from app.schemas.drone import DroneStatus, DroneCapability


class ObservationType(str, Enum):
    VICTIM_LOCATED = "VICTIM_LOCATED"
    FIRE_DETECTED = "FIRE_DETECTED"
    ROAD_IMPASSABLE = "ROAD_IMPASSABLE"
    STRUCTURAL_FRACTURE = "STRUCTURAL_FRACTURE"
    DEBRIS_DETECTED = "DEBRIS_DETECTED"


class ObservationPacket(BaseModel):
    observation_id: str
    timestamp: float
    source_drone_id: str
    type: ObservationType
    location: Vector3D
    confidence: float = Field(default=0.85, ge=0.0, le=1.0)
    raw_reading: Dict[str, Any] = Field(default_factory=dict)
    notes: Optional[str] = None
    # Optional camera/thermal evidence attached to the observation.
    image_url: Optional[str] = None
    image_base64: Optional[str] = None
    image_mime_type: Optional[str] = None
    hazard_type: Optional[str] = None


class DroneTelemetryPacket(BaseModel):
    drone_id: str
    drone_type: Optional[str] = None
    capabilities: List[DroneCapability] = Field(default_factory=list)
    timestamp: float
    position: Vector3D
    velocity: Vector3D = Field(default_factory=Vector3D)
    heading: float = 0.0
    battery_percent: float = Field(default=100.0, ge=0.0, le=100.0)
    battery_voltage: float = 24.0
    current_draw_a: float = 14.5
    altitude_agl_m: float = 0.0
    communication_quality: float = Field(default=1.0, ge=0.0, le=1.0)
    status: DroneStatus = DroneStatus.IDLE
    current_waypoint_index: int = 0
    mission_id: Optional[str] = None


class TelemetryBatch(BaseModel):
    session_id: str
    timestamp: float
    packets: List[DroneTelemetryPacket] = Field(default_factory=list)
    observations: List[ObservationPacket] = Field(default_factory=list)
