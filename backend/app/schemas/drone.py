"""
ResQNet Domain Schemas - Drone Fleet Models
"""
from enum import Enum
from pydantic import BaseModel, Field
from typing import List, Optional
from app.schemas.common import Vector3D, UncertaintyState


class DroneCapability(str, Enum):
    SCOUT = "SCOUT"
    MEDICAL = "MEDICAL"
    HEAVY_LIFT = "HEAVY_LIFT"
    RELAY = "RELAY"
    INSPECTION = "INSPECTION"


class DroneStatus(str, Enum):
    IDLE = "IDLE"
    ASSIGNED = "ASSIGNED"
    EN_ROUTE = "EN_ROUTE"
    ON_SITE = "ON_SITE"
    RETURNING = "RETURNING"
    CHARGING = "CHARGING"
    ERROR = "ERROR"
    LOST = "LOST"


class DroneEntity(BaseModel):
    id: str = Field(..., description="Unique drone identifier e.g. DRONE-S01")
    callsign: str = "AeroRescue 1"
    model_name: str = "Matrice 350 RTK / Custom VTOL"
    capabilities: List[DroneCapability] = Field(default_factory=lambda: [DroneCapability.SCOUT])
    
    position: Vector3D = Field(default_factory=Vector3D)
    velocity: Vector3D = Field(default_factory=Vector3D)
    heading: float = Field(default=0.0, description="Heading in degrees 0-360")
    
    battery_percent: float = Field(default=100.0, ge=0.0, le=100.0)
    battery_voltage: float = 24.0
    power_consumption_w: float = 350.0
    
    max_payload_kg: float = 5.0
    current_payload_kg: float = 0.0
    payload_type: Optional[str] = "FIRST_AID_KIT"
    
    communication_quality: float = Field(default=1.0, ge=0.0, le=1.0)
    health: float = Field(default=1.0, ge=0.0, le=1.0)
    status: DroneStatus = DroneStatus.IDLE
    
    current_mission_id: Optional[str] = None
    target_victim_id: Optional[str] = None
    home_facility_id: str = "BASE-ALPHA"
    
    last_telemetry_timestamp: float = 0.0
    telemetry_latency_ms: float = 12.0
    uncertainty_state: UncertaintyState = UncertaintyState.CONFIRMED
