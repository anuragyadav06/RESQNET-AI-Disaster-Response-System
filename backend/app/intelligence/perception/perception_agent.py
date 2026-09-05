"""
ResQNet Intelligence - Perception Agent
Responsible for sensor fusion, deduplication, and observation confidence assessment.
"""
import time
from typing import Dict, List, Optional
from app.schemas.common import Vector3D, UncertaintyState
from app.schemas.telemetry import ObservationPacket, ObservationType
from app.state.world_state import world_state


class PerceptionAgent:
    def __init__(self, deduplication_radius_m: float = 8.0):
        self.deduplication_radius_m = deduplication_radius_m
        self.observed_history: List[ObservationPacket] = []

    def process_observation(self, obs: ObservationPacket) -> Optional[ObservationPacket]:
        """Validates, calibrates confidence, and filters redundant observations."""
        # Validate coordinates
        if abs(obs.location.x) > 1000 or abs(obs.location.z) > 1000:
            return None  # Out of city bounds
        
        # Check for near-duplicate observation of same type recently
        now = obs.timestamp or time.time()
        for past in reversed(self.observed_history[-50:]):
            if past.type == obs.type and (now - past.timestamp) < 30.0:
                dist = obs.location.ground_distance_to(past.location)
                if dist < self.deduplication_radius_m:
                    # Merge / refine confidence rather than duplicating
                    past.confidence = min(1.0, (past.confidence + obs.confidence) / 1.8)
                    return None
        
        self.observed_history.append(obs)
        return obs


perception_agent = PerceptionAgent()
