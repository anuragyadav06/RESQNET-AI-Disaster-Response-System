"""ResQNet victim intelligence domain models."""

from enum import Enum
from typing import List, Optional

from pydantic import BaseModel, Field

from app.schemas.common import Vector3D, UncertaintyState


class VictimPriorityClass(str, Enum):
    CRITICAL = "CRITICAL"
    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"
    UNKNOWN = "UNKNOWN"


class VictimStatus(str, Enum):
    DETECTED = "DETECTED"
    TRAPPED = "TRAPPED"
    TRIAGED = "TRIAGED"
    EN_ROUTE = "EN_ROUTE"
    ASSISTED = "ASSISTED"
    EVACUATED = "EVACUATED"
    RESCUED = "RESCUED"


class VictimHazardType(str, Enum):
    FIRE = "FIRE"
    SMOKE = "SMOKE"
    FLOOD = "FLOOD"
    COLLAPSE = "STRUCTURAL_COLLAPSE"
    DEBRIS = "DEBRIS"
    EARTHQUAKE = "EARTHQUAKE"
    GAS_LEAK = "GAS_LEAK"
    EXPOSED = "EXPOSED"
    UNKNOWN = "UNKNOWN"


class VictimEvidence(BaseModel):
    """Evidence attached to a victim detection from a drone sensor/camera."""

    image_url: Optional[str] = None
    image_base64: Optional[str] = None
    image_mime_type: Optional[str] = None
    captured_at: Optional[float] = None
    capture_type: str = "SIMULATED_CAMERA"
    caption: Optional[str] = None


class VictimPriorityBreakdown(BaseModel):
    """Explainable factors used to calculate operational priority."""

    medical_severity_weight: float = 0.25
    urgency_weight: float = 0.20
    exposure_weight: float = 0.20
    state_risk_weight: float = 0.25
    accessibility_weight: float = 0.05
    confidence_weight: float = 0.05

    raw_medical_severity: float = Field(ge=0.0, le=1.0)
    raw_urgency: float = Field(ge=0.0, le=1.0)
    raw_exposure: float = Field(ge=0.0, le=1.0)
    raw_state_risk: float = Field(ge=0.0, le=1.0)
    raw_accessibility: float = Field(ge=0.0, le=1.0)
    raw_confidence: float = Field(ge=0.0, le=1.0)

    calculated_score: float = Field(ge=0.0, le=1.0)
    reasons: List[str] = Field(default_factory=list)


class Victim(BaseModel):
    id: str = Field(..., description="Unique victim identifier e.g. VIC-101")
    name: Optional[str] = "Unknown Individual"
    location: Vector3D

    hazard_type: VictimHazardType = VictimHazardType.UNKNOWN

    captured_by_drone_id: Optional[str] = Field(
        default=None,
        description="Drone that produced the detection/evidence",
    )

    evidence: VictimEvidence = Field(default_factory=VictimEvidence)

    people_count: int = Field(default=1, ge=1)

    # ------------------------------------------------------------
    # Raw assessment factors
    # ------------------------------------------------------------

    medical_severity: float = Field(
        default=0.5,
        ge=0.0,
        le=1.0,
        description="Medical condition severity factor.",
    )

    estimated_survival_urgency: float = Field(
        default=0.5,
        ge=0.0,
        le=1.0,
        description="Estimated urgency / golden-hour factor.",
    )

    hazard_exposure: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
        description="Exposure to active environmental hazards.",
    )

    accessibility_factor: float = Field(
        default=0.8,
        ge=0.0,
        le=1.0,
        description="How accessible the victim is to responders; lower means harder to reach.",
    )

    # ------------------------------------------------------------
    # Derived operational assessment
    # ------------------------------------------------------------

    severity: float = Field(
        default=0.65,
        ge=0.65,
        le=0.80,
        description=(
            "Overall operational victim severity, deterministically "
            "derived from state, medical condition, urgency and hazard."
        ),
    )

    confidence: float = Field(
        default=0.65,
        ge=0.65,
        le=0.80,
        description=(
            "RESQNET operational assessment confidence. This is not "
            "a YOLO/model inference confidence."
        ),
    )

    # ------------------------------------------------------------
    # Operational priority
    # ------------------------------------------------------------

    uncertainty_state: UncertaintyState = UncertaintyState.CONFIRMED

    priority_score: float = Field(
        default=0.0,
        ge=0.0,
        le=1.0,
    )

    priority_class: VictimPriorityClass = VictimPriorityClass.UNKNOWN

    status: VictimStatus = VictimStatus.DETECTED

    assigned_drone_id: Optional[str] = None
    assigned_mission_id: Optional[str] = None

    detected_at: float = Field(default=0.0)
    last_updated_at: float = Field(default=0.0)

    breakdown: Optional[VictimPriorityBreakdown] = None

    notes: List[str] = Field(default_factory=list)
