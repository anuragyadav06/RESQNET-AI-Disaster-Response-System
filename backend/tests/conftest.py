"""
Pytest configuration and test isolation fixtures
"""
import pytest
from app.state.world_state import WorldStateManager, world_state
from app.core.config import settings


@pytest.fixture(autouse=True)
def reset_world_state_fixture():
    """Resets global world_state singleton before and after each test."""
    # Reset state to clean initial Metro environment
    world_state.victims.clear()
    world_state.hazards.clear()
    world_state.incidents.clear()
    world_state.missions.clear()
    world_state.road_nodes.clear()
    world_state.road_edges.clear()
    world_state.buildings.clear()
    world_state.facilities.clear()
    world_state.drones.clear()
    world_state._initialize_metro_environment()
    world_state.simulation_time = 0.0
    world_state.state_version = 1
    yield
    world_state.victims.clear()
    world_state.hazards.clear()
    world_state.incidents.clear()
    world_state.missions.clear()
    world_state.road_nodes.clear()
    world_state.road_edges.clear()
    world_state.buildings.clear()
    world_state.facilities.clear()
    world_state.drones.clear()
    world_state._initialize_metro_environment()
