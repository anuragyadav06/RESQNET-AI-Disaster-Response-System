"""
ResQNet Domain Schemas - Mission Models & Plans
"""
from enum import Enum
from pydantic import BaseModel, Field
from typing import List, Optional
from app.schemas.common import Vector3D


class MissionObjective(str, Enum):
    RESCUE_TRIAGE = "RESCUE_TRIAGE"
    MEDICAL_SUPPLY_DROP = "MEDICAL_SUPPLY_DROP"
    STRUCTURAL_SURVEY = "STRUCTURAL_SURVEY"
    COMMS_RELAY = "COMMS_RELAY"
    PERIMETER_PATROL = "PERIMETER_PATROL"
    RETURN_TO_BASE = "RETURN_TO_BASE"


class MissionStatus(str, Enum):
    PLANNED = "PLANNED"
    APPROVED = "APPROVED"
    DISPATCHED = "DISPATCHED"
    IN_PROGRESS = "IN_PROGRESS"
    REPLANNING = "REPLANNING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    ABORTED = "ABORTED"


class WaypointAction(str, Enum):
    FLY_THROUGH = "FLY_THROUGH"
    HOVER_AND_SURVEY = "HOVER_AND_SURVEY"
    DROP_PAYLOAD = "DROP_PAYLOAD"
    LAND = "LAND"


class Waypoint(BaseModel):
    index: int
    position: Vector3D
    speed_mps: float = 12.0
    action: WaypointAction = WaypointAction.FLY_THROUGH
    action_duration_s: float = 0.0
    completed: bool = False


class RiskAssessment(BaseModel):
    overall_risk: float = Field(default=0.2, ge=0.0, le=1.0)
    category: str = "LOW"  # LOW, MODERATE, HIGH, CRITICAL
    contributors: List[str] = Field(default_factory=list)
    fire_proximity_m: float = 999.0
    battery_margin_percent: float = 50.0
    comms_loss_probability: float = 0.05


class MissionPlan(BaseModel):
    mission_id: str = Field(..., description="e.g. MSN-101")
    objective: MissionObjective
    target_victim_id: Optional[str] = None
    target_incident_id: Optional[str] = None
    assigned_drone_id: str
    priority_score: float = Field(default=0.5, ge=0.0, le=1.0)
    
    route_nodes: List[str] = Field(default_factory=list)
    waypoints: List[Waypoint] = Field(default_factory=list)
    current_waypoint_index: int = 0
    
    estimated_duration_s: float = 60.0
    estimated_battery_drain: float = 15.0
    risk: RiskAssessment = Field(default_factory=RiskAssessment)
    
    fallback_strategy: str = "Return to base upon 20% battery or communication loss"
    explanation: str = "Assigned based on proximity and capability fit"
    status: MissionStatus = MissionStatus.PLANNED
    
    created_at: float = 0.0
    dispatched_at: Optional[float] = None
    completed_at: Optional[float] = None
    failure_reason: Optional[str] = None
    replan_count: int = 0
