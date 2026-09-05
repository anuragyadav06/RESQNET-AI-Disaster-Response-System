"""
ResQNet Domain Schemas - World State & City Environment
"""
from enum import Enum
from pydantic import BaseModel, Field
from typing import Dict, List, Optional
from app.schemas.common import Vector3D, UncertaintyState
from app.schemas.victim import Victim
from app.schemas.drone import DroneEntity
from app.schemas.incident import IncidentEntity


class BuildingDamageLevel(str, Enum):
    INTACT = "INTACT"
    MINOR_DAMAGE = "MINOR_DAMAGE"
    STRUCTURAL_CRACK = "STRUCTURAL_CRACK"
    COLLAPSED = "COLLAPSED"


class Building(BaseModel):
    id: str
    name: str
    district: str
    center: Vector3D
    size_x: float = 30.0
    size_z: float = 30.0
    height: float = 40.0
    damage_level: BuildingDamageLevel = BuildingDamageLevel.INTACT
    occupancy_estimate: int = 20
    is_critical_infrastructure: bool = False


class RoadNode(BaseModel):
    id: str
    position: Vector3D
    is_intersection: bool = True


class RoadEdge(BaseModel):
    id: str
    from_node: str
    to_node: str
    distance_m: float
    is_blocked: bool = False
    blockage_reason: Optional[str] = None
    hazard_cost_multiplier: float = 1.0


class HazardType(str, Enum):
    FIRE = "FIRE"
    SMOKE_PLUME = "SMOKE_PLUME"
    STRUCTURAL_COLLAPSE = "STRUCTURAL_COLLAPSE"
    GAS_LEAK = "GAS_LEAK"
    FLOOD = "FLOOD"


class HazardZone(BaseModel):
    id: str
    type: HazardType
    center: Vector3D
    radius_m: float = 30.0
    intensity: float = Field(default=0.8, ge=0.0, le=1.0)
    spread_rate_m_per_s: float = 0.1
    active: bool = True


class Facility(BaseModel):
    id: str
    name: str
    type: str = "HOSPITAL"  # HOSPITAL, COMMAND_HQ, DRONE_HANGAR, FIRE_STATION
    location: Vector3D
    capacity: int = 100
    current_load: int = 12


class EnvironmentalConditions(BaseModel):
    wind_speed_mps: float = 3.5
    wind_direction_deg: float = 45.0
    visibility_m: float = 8000.0
    rain_rate_mm_hr: float = 0.0
    air_quality_index: float = 45.0
    ambient_temp_c: float = 22.0
    seismic_activity_richter: float = 0.0


class WorldStateSnapshot(BaseModel):
    session_id: str = "resqnet_metro_01"
    simulation_time: float = 0.0
    state_version: int = 1
    system_b_connected: bool = False
    system_b_session_id: Optional[str] = None
    
    drones: Dict[str, DroneEntity] = Field(default_factory=dict)
    victims: Dict[str, Victim] = Field(default_factory=dict)
    hazards: Dict[str, HazardZone] = Field(default_factory=dict)
    incidents: Dict[str, IncidentEntity] = Field(default_factory=dict)
    buildings: Dict[str, Building] = Field(default_factory=dict)
    road_nodes: Dict[str, RoadNode] = Field(default_factory=dict)
    road_edges: Dict[str, RoadEdge] = Field(default_factory=dict)
    facilities: Dict[str, Facility] = Field(default_factory=dict)
    environment: EnvironmentalConditions = Field(default_factory=EnvironmentalConditions)
    
    telemetry_rate_hz: float = 0.0
    command_latency_ms: float = 0.0
    stale_entities_count: int = 0
