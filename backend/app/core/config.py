"""
ResQNet Core Configuration
"""
import os
from pydantic import BaseModel, Field
from typing import List


class Settings(BaseModel):
    PROJECT_NAME: str = "ResQNet System A Command & Intelligence Platform"
    VERSION: str = "1.0.0"
    API_V1_STR: str = "/api/v1"
    
    # WebSocket & Session settings
    DEFAULT_SESSION_ID: str = "metro_session_01"
    TELEMETRY_STALE_TIMEOUT_S: float = 3.0
    COMMAND_TIMEOUT_S: float = 10.0
    HEARTBEAT_INTERVAL_S: float = 2.0
    
    # Safety thresholds
    DRONE_MIN_BATTERY_RETURN: float = 20.0  # percentage
    DRONE_CRITICAL_BATTERY: float = 12.0
    FIRE_SAFETY_BUFFER_M: float = 35.0
    
    # Audit persistence
    DB_PATH: str = "resqnet_audit.db"
    CORS_ORIGINS: List[str] = Field(default_factory=lambda: ["*"])


settings = Settings()
