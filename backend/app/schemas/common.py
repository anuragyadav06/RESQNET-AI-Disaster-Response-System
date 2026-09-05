"""
ResQNet Domain Schemas - Common Types & Enums
"""
from enum import Enum
from pydantic import BaseModel, Field
from typing import Optional


class UncertaintyState(str, Enum):
    CONFIRMED = "CONFIRMED"
    PROBABLE = "PROBABLE"
    UNCERTAIN = "UNCERTAIN"
    STALE = "STALE"
    UNKNOWN = "UNKNOWN"


class SeverityLevel(str, Enum):
    CRITICAL = "CRITICAL"
    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"
    UNKNOWN = "UNKNOWN"


class Vector3D(BaseModel):
    x: float = Field(default=0.0, description="X coordinate in meters (East-West)")
    y: float = Field(default=0.0, description="Y coordinate in meters (Altitude)")
    z: float = Field(default=0.0, description="Z coordinate in meters (North-South)")

    def distance_to(self, other: "Vector3D") -> float:
        return ((self.x - other.x) ** 2 + (self.y - other.y) ** 2 + (self.z - other.z) ** 2) ** 0.5

    def ground_distance_to(self, other: "Vector3D") -> float:
        return ((self.x - other.x) ** 2 + (self.z - other.z) ** 2) ** 0.5


class GeoCoordinate(BaseModel):
    lat: float
    lon: float
    alt: Optional[float] = 0.0
