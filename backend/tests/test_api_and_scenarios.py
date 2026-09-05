"""
Integration tests for REST API Endpoints and Disaster Scenarios
"""
import pytest
from starlette.testclient import TestClient
from app.main import app


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def test_api_health(client):
    res = client.get("/api/v1/health")
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "OPERATIONAL"
    assert "state_version" in data


def test_api_world_state(client):
    res = client.get("/api/v1/world")
    assert res.status_code == 200
    data = res.json()
    assert len(data["drones"]) >= 4
    assert len(data["road_nodes"]) == 16


def test_scenario_metro_earthquake_and_replan(client):
    # 1. Reset
    r_reset = client.post("/api/v1/simulation/reset")
    assert r_reset.status_code == 200
    
    # 2. Trigger Earthquake
    r_eq = client.post("/api/v1/simulation/earthquake")
    assert r_eq.status_code == 200
    eq_data = r_eq.json()
    assert eq_data["status"] == "SUCCESS"
    assert eq_data["phase"] == "EARTHQUAKE_ACTIVE"
    
    # 3. Verify victims and incidents populated
    r_vics = client.get("/api/v1/victims")
    assert r_vics.status_code == 200
    victims = r_vics.json()
    assert len(victims) >= 4
    # Check that at least one is CRITICAL
    crit_vics = [v for v in victims if v["priority_class"] == "CRITICAL"]
    assert len(crit_vics) >= 1
    
    # 4. Verify autonomous mission dispatched
    r_missions = client.get("/api/v1/missions")
    assert r_missions.status_code == 200
    missions = r_missions.json()
    assert len(missions) >= 1
    assert missions[0]["status"] in ["DISPATCHED", "IN_PROGRESS"]
    
    # 5. Trigger aftershock to force replanning
    r_aftershock = client.post("/api/v1/simulation/aftershock")
    assert r_aftershock.status_code == 200
    af_data = r_aftershock.json()
    assert af_data["status"] == "SUCCESS"
    
    # 6. Verify decisions log contains audit entries
    r_dec = client.get("/api/v1/decisions")
    assert r_dec.status_code == 200
    decisions = r_dec.json()
    assert len(decisions) >= 2
