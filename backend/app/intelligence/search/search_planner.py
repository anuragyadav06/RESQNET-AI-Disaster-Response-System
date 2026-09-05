from __future__ import annotations
from typing import Dict
from app.state.world_state import world_state
from app.schemas.drone import DroneCapability


class SearchPlanner:
    """Authoritative 4x4 scout allocation matching the Godot Digital Twin exactly."""

    def build_plan(self) -> Dict[str, object]:
        scouts = sorted(
            [d for d in world_state.drones.values() if DroneCapability.SCOUT in d.capabilities],
            key=lambda d: d.id,
        )
        assignments = {}
        for index, drone in enumerate(scouts[:16], start=1):
            row = (index - 1) // 4
            col = (index - 1) % 4
            min_x = -360.0 + col * 180.0 + 8.0
            max_x = -360.0 + (col + 1) * 180.0 - 8.0
            min_z = -360.0 + row * 180.0 + 8.0
            max_z = -360.0 + (row + 1) * 180.0 - 8.0
            assignments[drone.id] = {
                "grid_id": f"G{index:02d}",
                "bounds": {"min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z},
                "direction": "NORTH_SOUTH_ONLY",
                "waypoints": [
                    {"x": drone.position.x, "y": 150.0, "z": max_z},
                    {"x": drone.position.x, "y": 150.0, "z": min_z},
                ],
            }
        return {
            "planner": "AUTHORITATIVE_4X4_GRID",
            "motion_planner": "FIXED_NORTH_SOUTH_SWEEP",
            "drone_count": min(16, len(scouts)),
            "grid": {"rows": 4, "cols": 4, "cell_size_m": 180.0, "map_min": -360.0, "map_max": 360.0},
            "coverage_assignments": assignments,
            "overlap_policy": "ONE_SCOUT_PER_CELL",
        }


search_planner = SearchPlanner()
