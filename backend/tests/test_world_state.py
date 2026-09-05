"""
Test Suite for World State Engine & Schemas
"""
import pytest
from app.state.world_state import WorldStateManager
from app.schemas.telemetry import DroneTelemetryPacket
from app.schemas.common import Vector3D, UncertaintyState
from app.schemas.drone import DroneStatus


def test_initial_world_state():
    ws = WorldStateManager("test_session")
    snapshot = ws.get_snapshot()
    assert snapshot.session_id == "test_session"
    assert len(snapshot.drones) == 4
    assert len(snapshot.road_nodes) == 16
    assert len(snapshot.road_edges) == 48  # 12 horizontal * 2 directions + 12 vertical * 2 directions
    assert "BASE-ALPHA" in snapshot.facilities
    assert "DRONE-S01" in snapshot.drones
    assert snapshot.drones["DRONE-S01"].battery_percent > 90.0


def test_telemetry_update():
    ws = WorldStateManager("test_session")
    initial_ver = ws.state_version
    
    packet = DroneTelemetryPacket(
        drone_id="DRONE-S01",
        timestamp=100.5,
        position=Vector3D(x=50.0, y=15.0, z=25.0),
        velocity=Vector3D(x=5.0, y=0.0, z=2.0),
        heading=45.0,
        battery_percent=88.5,
        status=DroneStatus.EN_ROUTE,
        communication_quality=0.95,
    )
    ws.update_drone_telemetry(packet)
    
    drone = ws.drones["DRONE-S01"]
    assert drone.position.x == 50.0
    assert drone.position.y == 15.0
    assert drone.battery_percent == 88.5
    assert drone.status == DroneStatus.EN_ROUTE
    assert ws.state_version > initial_ver


def test_road_blocking_and_unblocking():
    ws = WorldStateManager("test_session")
    edge_id = list(ws.road_edges.keys())[0]
    
    blocked = ws.block_road_edge(edge_id, "Collapsed overpass")
    assert blocked is True
    assert ws.road_edges[edge_id].is_blocked is True
    assert ws.road_edges[edge_id].blockage_reason == "Collapsed overpass"
    
    unblocked = ws.unblock_road_edge(edge_id)
    assert unblocked is True
    assert ws.road_edges[edge_id].is_blocked is False
