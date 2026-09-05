"""
Unit tests for Routing, Invalidation, Risk, and Resource Allocation
"""
import pytest
from app.schemas.common import Vector3D
from app.schemas.drone import DroneCapability, DroneStatus
from app.schemas.world import HazardZone, HazardType
from app.intelligence.routing.routing_agent import RoutingAgent
from app.intelligence.risk.risk_agent import RiskAgent
from app.intelligence.resources.resource_agent import ResourceAgent
from app.state.world_state import WorldStateManager, world_state


def test_routing_shortest_path():
    agent = RoutingAgent()
    start = Vector3D(x=-150.0, y=0.0, z=-150.0)
    target = Vector3D(x=150.0, y=0.0, z=150.0)
    
    node_path, waypoints, total_dist = agent.plan_route(start, target)
    assert len(node_path) >= 4
    assert len(waypoints) >= 4
    assert total_dist > 0.0


def test_routing_invalidation_on_blockage():
    agent = RoutingAgent()
    start = Vector3D(x=-150.0, y=0.0, z=-150.0)
    target = Vector3D(x=-50.0, y=0.0, z=-150.0)
    
    node_path, _, _ = agent.plan_route(start, target)
    assert len(node_path) >= 2
    
    # Route is initially valid
    valid, edge = agent.is_route_valid(node_path)
    assert valid is True
    
    # Block the edge between the first two nodes
    e_id = f"EDGE_{node_path[0]}_{node_path[1]}"
    world_state.block_road_edge(e_id, "Fallen utility pole")
    
    # Now route must be invalid!
    valid_after, bad_edge = agent.is_route_valid(node_path)
    assert valid_after is False
    assert bad_edge == e_id
    
    # Replan must find alternative path avoiding the blocked edge
    new_path, new_wps, _ = agent.plan_route(start, target)
    new_valid, _ = agent.is_route_valid(new_path)
    assert new_valid is True
    
    # Cleanup
    world_state.unblock_road_edge(e_id)


def test_risk_evaluation_near_fire():
    risk_ag = RiskAgent()
    # Spawn a fire hazard
    world_state.hazards["HAZ_TEST_FIRE"] = HazardZone(
        id="HAZ_TEST_FIRE",
        type=HazardType.FIRE,
        center=Vector3D(x=50.0, y=0.0, z=50.0),
        radius_m=30.0,
        intensity=0.9,
    )
    
    drone = world_state.drones["DRONE-S01"]
    # Path passing directly into the fire
    wps = [Vector3D(x=48.0, y=10.0, z=48.0)]
    risk_assessment = risk_ag.evaluate_route_risk(wps, drone, 100.0)
    
    assert risk_assessment.overall_risk >= 0.5
    assert any("FIRE" in c for c in risk_assessment.contributors)
    
    # Cleanup
    del world_state.hazards["HAZ_TEST_FIRE"]


@pytest.mark.asyncio
async def test_resource_allocation_capability_matching():
    res_ag = ResourceAgent()
    target_pos = Vector3D(x=0.0, y=0.0, z=50.0)
    
    # Medical mission: should pick DRONE-M01 (which has MEDICAL capability) over DRONE-S01
    drone, explanation, meta = await res_ag.allocate_best_drone(
        target_pos=target_pos,
        required_capability=DroneCapability.MEDICAL,
        priority_score=0.90,
    )
    assert drone is not None
    assert drone.id == "DRONE-M01"
    assert DroneCapability.MEDICAL in drone.capabilities
    assert "DRONE-S01" in explanation  # Must mention why S01 was rejected!
