"""
Unit tests for Mission Planning, Command Generation, and Dynamic Replanning
"""
import pytest
from app.schemas.common import Vector3D
from app.schemas.victim import Victim, VictimPriorityClass
from app.schemas.drone import DroneStatus
from app.schemas.command import CommandType
from app.state.world_state import world_state
from app.intelligence.missions.mission_agent import mission_agent
from app.intelligence.commands.command_agent import command_agent
from app.intelligence.replanning.replanning_agent import replanning_agent


@pytest.mark.asyncio
async def test_mission_creation_and_command_issuance():
    vic = Victim(
        id="VIC-TEST-100",
        location=Vector3D(x=-50.0, y=0.0, z=50.0),
        people_count=1,
        medical_severity=0.85,
        estimated_survival_urgency=0.80,
    )
    world_state.victims[vic.id] = vic
    
    plan, msg = await mission_agent.create_and_dispatch_mission_for_victim(vic.id)
    assert plan is not None
    assert plan.assigned_drone_id is not None
    assert len(plan.waypoints) >= 2
    assert plan.status.value == "DISPATCHED"
    assert vic.id in world_state.missions[plan.mission_id].target_victim_id


@pytest.mark.asyncio
async def test_replanning_on_roadblock():
    # Setup mission
    vic = Victim(
        id="VIC-TEST-200",
        location=Vector3D(x=50.0, y=0.0, z=50.0),
        medical_severity=0.5,
    )
    world_state.victims[vic.id] = vic
    plan, _ = await mission_agent.create_and_dispatch_mission_for_victim(vic.id)
    assert plan is not None
    
    initial_replan_count = plan.replan_count
    
    # Block a segment of the route
    if len(plan.route_nodes) >= 2:
        edge_id = f"EDGE_{plan.route_nodes[0]}_{plan.route_nodes[1]}"
        world_state.block_road_edge(edge_id, "Secondary earthquake rupture")
        
        # Execute replanner
        results = await replanning_agent.evaluate_and_replan()
        assert len(results) >= 1
        assert results[0]["action"] == "REROUTE"
        assert plan.replan_count == initial_replan_count + 1
        
        # Cleanup
        world_state.unblock_road_edge(edge_id)
