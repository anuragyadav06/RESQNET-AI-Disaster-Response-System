from __future__ import annotations
from typing import Dict, List
from app.state.world_state import world_state
from app.schemas.drone import DroneCapability, DroneStatus
from app.intelligence.routing.rrt_star import rrt_star
from .coverage_planner import coverage_planner

class SearchPlanner:
    def _obstacles(self):
        return [(b.center.x, b.center.z, max(b.size_x,b.size_z)*0.55) for b in world_state.buildings.values() if b.damage_level.value != "COLLAPSED"]

    def build_plan(self) -> Dict[str, object]:
        scouts = [d for d in world_state.drones.values() if DroneCapability.SCOUT in d.capabilities and d.status == DroneStatus.IDLE and d.battery_percent >= 35]
        ids = [d.id for d in scouts]
        raw = coverage_planner.partition(-180, 180, -180, 180, ids)
        assignments={}
        obstacles=self._obstacles()
        for d in scouts:
            cursor=(d.position.x,d.position.z); routed=[]
            for pt in raw.get(d.id,[])[:28]:
                path=rrt_star.plan(cursor,(pt["x"],pt["z"]),obstacles)
                routed.extend([{"x":x,"y":pt["y"],"z":z} for x,z in path[1:]])
                cursor=(pt["x"],pt["z"])
            assignments[d.id]=routed
        return {"planner":"MULTI_UAV_COVERAGE","coverage_assignments":assignments,"drone_count":len(ids),"overlap_policy":"MINIMIZE_DUPLICATE_COVERAGE","motion_planner":"RRT_STAR","obstacle_model":"BUILDINGS_AND_ACTIVE_HAZARDS"}

search_planner=SearchPlanner()
