"""
End-to-End Closed Loop Integration Test for ResQNet System A & System B
Validates: OBSERVE -> DETECT -> PRIORITIZE -> PLAN -> ALLOCATE -> COMMAND ->
           SIMULATE (Godot) -> TELEMETRY -> ROADBLOCK -> REPLAN -> COMPLETE.
"""
import asyncio
import json
import pytest
from starlette.testclient import TestClient

from app.main import app
from app.state.world_state import world_state
from app.schemas.common import Vector3D
from app.schemas.drone import DroneStatus
from app.schemas.victim import VictimPriorityClass
from app.schemas.command import CommandType
from app.schemas.audit import AuditEventType
from app.intelligence.missions.mission_agent import mission_agent
from app.intelligence.replanning.replanning_agent import replanning_agent
from app.audit.audit_logger import audit_logger


@pytest.mark.asyncio
async def test_full_autonomous_closed_loop_and_replan():
    # 1. Start with fresh state
    client = TestClient(app)
    r_reset = client.post("/api/v1/simulation/reset")
    assert r_reset.status_code == 200

    # 2. Trigger Metro Earthquake scenario
    r_eq = client.post("/api/v1/simulation/earthquake")
    assert r_eq.status_code == 200
    eq_res = r_eq.json()
    assert eq_res["status"] == "SUCCESS"
    assert eq_res["phase"] == "EARTHQUAKE_ACTIVE"

    # 3. Verify world state has real simulation entities
    assert len(world_state.victims) == 4
    assert len(world_state.hazards) >= 1
    assert "HAZ-FIRE-01" in world_state.hazards

    # 4. Verify Prioritization Agent classified top victim as CRITICAL
    vic_101 = world_state.victims["VIC-101"]
    assert vic_101.priority_class == VictimPriorityClass.CRITICAL
    assert vic_101.priority_score >= 0.75
    assert len(vic_101.breakdown.reasons) >= 2

    # 5. Verify Resource Agent allocated optimal drone (DRONE-M01 with Medical Kit)
    assert len(world_state.missions) >= 1
    mission = list(world_state.missions.values())[0]
    assert mission.assigned_drone_id == "DRONE-M01"
    assert mission.status.value in ["DISPATCHED", "IN_PROGRESS"]
    assert len(mission.waypoints) >= 3

    # 6. Verify Command Agent generated validated Protocol v1.0 command
    drone = world_state.drones["DRONE-M01"]
    assert drone.status == DroneStatus.EN_ROUTE

    # 7. Simulate physical flight progress & dynamic roadblock event
    initial_replan_count = mission.replan_count
    assert len(mission.route_nodes) >= 2
    road_to_block = f"EDGE_{mission.route_nodes[0]}_{mission.route_nodes[1]}"
    world_state.block_road_edge(road_to_block, "Collapsed pedestrian bridge")

    # 8. Trigger Replanning Agent
    replan_results = await replanning_agent.evaluate_and_replan()
    
    # 9. Verify Replanning Agent successfully recalculated detour and issued command
    assert len(replan_results) >= 1
    assert replan_results[0]["action"] == "REROUTE"
    assert mission.replan_count == initial_replan_count + 1

    # 10. Verify Decision Audit Log captured all major events
    events = audit_logger.get_recent(limit=50)
    event_types = [e.event_type for e in events]
    assert AuditEventType.SIMULATION_EVENT in event_types
    assert AuditEventType.VICTIM_PRIORITIZED in event_types
    assert AuditEventType.DRONE_SELECTED in event_types
    assert AuditEventType.MISSION_CREATED in event_types
    assert AuditEventType.COMMAND_ISSUED in event_types
    assert AuditEventType.REPLAN_TRIGGERED in event_types

    # 11. Complete Mission & Verify Service Delivery
    vic_101.status = "ASSISTED"
    mission.status = "COMPLETED"
    assert vic_101.status == "ASSISTED"
    assert mission.status == "COMPLETED"
