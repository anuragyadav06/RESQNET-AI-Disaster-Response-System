"""
ResQNet Intelligence - Dynamic Graph Routing Agent with Real-Time Invalidation
"""
import math
from typing import Dict, List, Optional, Set, Tuple
import networkx as nx

from app.schemas.common import Vector3D
from app.schemas.mission import Waypoint, WaypointAction
from app.state.world_state import world_state


class RoutingAgent:
    def __init__(self, cruise_altitude_m: float = 15.0, default_speed_mps: float = 12.0):
        self.cruise_altitude_m = cruise_altitude_m
        self.default_speed_mps = default_speed_mps

    def build_network_graph(self) -> nx.DiGraph:
        """Constructs a dynamic NetworkX DiGraph reflecting live road blockages and hazard costs."""
        G = nx.DiGraph()
        
        # Add nodes with coordinates
        for nid, node in world_state.road_nodes.items():
            G.add_node(nid, pos=(node.position.x, node.position.z), vec=node.position)
        
        # Add edges with live dynamic weights
        for eid, edge in world_state.road_edges.items():
            # If road is physically blocked by rubble or collapsed structure, omit or weight infinity
            if edge.is_blocked:
                continue
            
            if edge.from_node not in world_state.road_nodes or edge.to_node not in world_state.road_nodes:
                continue

            n_from = world_state.road_nodes[edge.from_node]
            n_to = world_state.road_nodes[edge.to_node]
            
            # Base length
            base_dist = n_from.position.ground_distance_to(n_to.position)
            mid_x = (n_from.position.x + n_to.position.x) / 2.0
            mid_z = (n_from.position.z + n_to.position.z) / 2.0
            mid_pos = Vector3D(x=mid_x, y=0.0, z=mid_z)
            
            # Hazard proximity penalty
            hazard_mult = 1.0
            for hid, hz in world_state.hazards.items():
                if not hz.active:
                    continue
                d = mid_pos.ground_distance_to(hz.center)
                if d < hz.radius_m:
                    hazard_mult += 20.0 * hz.intensity
                elif d < (hz.radius_m + 30.0):
                    hazard_mult += 5.0 * hz.intensity
            
            dynamic_weight = base_dist * hazard_mult * edge.hazard_cost_multiplier
            G.add_edge(edge.from_node, edge.to_node, id=eid, weight=dynamic_weight, distance=base_dist)

        return G

    def find_nearest_node(self, pos: Vector3D) -> Optional[str]:
        """Finds the nearest road intersection node to a given coordinate."""
        best_nid = None
        min_dist = float("inf")
        for nid, node in world_state.road_nodes.items():
            d = pos.ground_distance_to(node.position)
            if d < min_dist:
                min_dist = d
                best_nid = nid
        return best_nid

    def plan_route(
        self,
        start_pos: Vector3D,
        target_pos: Vector3D,
        altitude: Optional[float] = None,
    ) -> Tuple[List[str], List[Waypoint], float]:
        """Plans optimal 3D waypoints using A* pathfinding on the urban graph."""
        alt = altitude or self.cruise_altitude_m
        G = self.build_network_graph()
        
        start_node = self.find_nearest_node(start_pos)
        target_node = self.find_nearest_node(target_pos)

        if not start_node or not target_node:
            # Fallback to direct aerial line if road nodes unavailable
            wps = [
                Waypoint(index=0, position=Vector3D(x=start_pos.x, y=alt, z=start_pos.z), action=WaypointAction.FLY_THROUGH),
                Waypoint(index=1, position=Vector3D(x=target_pos.x, y=alt, z=target_pos.z), action=WaypointAction.HOVER_AND_SURVEY),
            ]
            return [], wps, start_pos.ground_distance_to(target_pos)

        # Heuristic for A* (Euclidean ground distance)
        def heuristic(u, v):
            p1 = G.nodes[u]["pos"]
            p2 = G.nodes[v]["pos"]
            return math.hypot(p1[0] - p2[0], p1[1] - p2[1])

        try:
            node_path = nx.astar_path(G, start_node, target_node, heuristic=heuristic, weight="weight")
        except (nx.NetworkXNoPath, nx.NodeNotFound):
            # No road graph path available due to severe road blockages; fallback to high-altitude aerial direct path
            wps = [
                Waypoint(index=0, position=Vector3D(x=start_pos.x, y=alt + 15.0, z=start_pos.z), action=WaypointAction.FLY_THROUGH),
                Waypoint(index=1, position=Vector3D(x=target_pos.x, y=alt + 15.0, z=target_pos.z), action=WaypointAction.HOVER_AND_SURVEY),
            ]
            return [], wps, start_pos.ground_distance_to(target_pos)

        # Convert node sequence to Waypoint array
        waypoints: List[Waypoint] = []
        # Takeoff waypoint
        waypoints.append(
            Waypoint(index=0, position=Vector3D(x=start_pos.x, y=alt, z=start_pos.z), action=WaypointAction.FLY_THROUGH)
        )
        
        total_dist = start_pos.ground_distance_to(world_state.road_nodes[node_path[0]].position)
        for i, nid in enumerate(node_path):
            npos = world_state.road_nodes[nid].position
            waypoints.append(
                Waypoint(
                    index=len(waypoints),
                    position=Vector3D(x=npos.x, y=alt, z=npos.z),
                    speed_mps=self.default_speed_mps,
                    action=WaypointAction.FLY_THROUGH,
                )
            )
            if i > 0:
                prev_nid = node_path[i - 1]
                total_dist += world_state.road_nodes[prev_nid].position.ground_distance_to(npos)

        # Target arrival waypoint
        waypoints.append(
            Waypoint(
                index=len(waypoints),
                position=Vector3D(x=target_pos.x, y=alt, z=target_pos.z),
                action=WaypointAction.HOVER_AND_SURVEY,
                action_duration_s=10.0,
            )
        )
        total_dist += world_state.road_nodes[node_path[-1]].position.ground_distance_to(target_pos)

        return node_path, waypoints, round(total_dist, 1)

    def is_route_valid(self, node_path: List[str]) -> Tuple[bool, Optional[str]]:
        """Validates if an existing route is still traversable or has become blocked."""
        if len(node_path) < 2:
            return True, None

        for i in range(len(node_path) - 1):
            u = node_path[i]
            v = node_path[i + 1]
            # Check edge status
            edge_id = f"EDGE_{u}_{v}"
            if edge_id in world_state.road_edges:
                if world_state.road_edges[edge_id].is_blocked:
                    return False, edge_id
            
            # Check if any hazard has expanded into this segment
            n1 = world_state.road_nodes[u]
            n2 = world_state.road_nodes[v]
            mid = Vector3D(x=(n1.position.x + n2.position.x) / 2, y=0.0, z=(n1.position.z + n2.position.z) / 2)
            for hid, hz in world_state.hazards.items():
                if hz.active and mid.ground_distance_to(hz.center) < (hz.radius_m * 0.8):
                    return False, f"HAZARD_{hid}"

        return True, None


routing_agent = RoutingAgent()
