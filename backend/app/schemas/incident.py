"""
ResQNet Domain Schemas - Incident Models
"""
from enum import Enum
from pydantic import BaseModel, Field
from typing import List, Optional
from app.schemas.common import Vector3D, UncertaintyState


class IncidentType(str, Enum):
    EARTHQUAKE_DAMAGE = "EARTHQUAKE_DAMAGE"
    FIRE = "FIRE"
    TRAPPED_VICTIM = "TRAPPED_VICTIM"
    ROAD_BLOCKAGE = "ROAD_BLOCKAGE"
    DRONE_FAILURE = "DRONE_FAILURE"
    COMMUNICATION_DEGRADATION = "COMMUNICATION_DEGRADATION"
    FLOOD_ZONE = "FLOOD_ZONE"


class IncidentStatus(str, Enum):
    ACTIVE = "ACTIVE"
    CONTAINED = "CONTAINED"
    RESOLVED = "RESOLVED"


class IncidentEntity(BaseModel):
    id: str = Field(..., description="e.g. INC-001")
    type: IncidentType
    title: str
    location: Vector3D
    radius_m: float = Field(default=25.0, ge=0.0)
    severity: float = Field(default=0.7, ge=0.0, le=1.0)
    confidence: float = Field(default=0.9, ge=0.0, le=1.0)
    timestamp: float = Field(default=0.0, description="Simulation timestamp")
    evidence: List[str] = Field(default_factory=list)
    affected_entities: List[str] = Field(default_factory=list)
    status: IncidentStatus = IncidentStatus.ACTIVE
    recommended_action: str = "Dispatch reconnaissance drone"
    uncertainty_state: UncertaintyState = UncertaintyState.CONFIRMED
