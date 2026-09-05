"""
ResQNet Domain Schemas - Decision Audit Logging
"""
from enum import Enum
from pydantic import BaseModel, Field
from typing import Any, Dict, List, Optional


class AuditEventType(str, Enum):
    INCIDENT_DETECTED = "INCIDENT_DETECTED"
    VICTIM_PRIORITIZED = "VICTIM_PRIORITIZED"
    DRONE_SELECTED = "DRONE_SELECTED"
    MISSION_CREATED = "MISSION_CREATED"
    ROUTE_CREATED = "ROUTE_CREATED"
    COMMAND_ISSUED = "COMMAND_ISSUED"
    COMMAND_ACKNOWLEDGED = "COMMAND_ACKNOWLEDGED"
    MISSION_STARTED = "MISSION_STARTED"
    MISSION_FAILED = "MISSION_FAILED"
    MISSION_COMPLETED = "MISSION_COMPLETED"
    REPLAN_TRIGGERED = "REPLAN_TRIGGERED"
    ROAD_BLOCKED = "ROAD_BLOCKED"
    ROAD_UNBLOCKED = "ROAD_UNBLOCKED"
    HAZARD_SPAWNED = "HAZARD_SPAWNED"
    SIMULATION_EVENT = "SIMULATION_EVENT"


class AuditRecord(BaseModel):
    event_id: str
    timestamp: float
    event_type: AuditEventType
    decision: str
    inputs: Dict[str, Any] = Field(default_factory=dict)
    output: Dict[str, Any] = Field(default_factory=dict)
    reason: str
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)
    affected_entities: List[str] = Field(default_factory=list)
