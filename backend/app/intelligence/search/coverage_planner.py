"""Multi-UAV search coverage planner. Coverage decides WHERE; RRT* decides HOW."""
from __future__ import annotations
from typing import Dict, List

class CoveragePlanner:
    def partition(self, min_x: float, max_x: float, min_z: float, max_z: float, drone_ids: List[str], altitude: float = 20.0, lane_spacing: float = 28.0) -> Dict[str, List[dict]]:
        if not drone_ids:
            return {}
        width = (max_x - min_x) / len(drone_ids)
        result: Dict[str, List[dict]] = {}
        for i, drone_id in enumerate(drone_ids):
            x0, x1 = min_x + i * width, min_x + (i + 1) * width
            points = []
            z = min_z
            lane = 0
            while z <= max_z + 0.01:
                xa, xb = x0 + 4, x1 - 4
                if lane % 2 == 0:
                    points += [{"x": xa, "y": altitude, "z": z}, {"x": xb, "y": altitude, "z": z}]
                else:
                    points += [{"x": xb, "y": altitude, "z": z}, {"x": xa, "y": altitude, "z": z}]
                z += lane_spacing
                lane += 1
            result[drone_id] = points
        return result

coverage_planner = CoveragePlanner()
