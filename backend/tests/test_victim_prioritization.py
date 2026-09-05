"""
Unit tests for Victim Prioritization & Incident Detection
"""
import pytest
from app.schemas.common import Vector3D
from app.schemas.victim import Victim, VictimPriorityClass
from app.schemas.telemetry import ObservationPacket, ObservationType
from app.intelligence.victims.prioritization_agent import VictimPrioritizationAgent
from app.intelligence.incidents.incident_agent import incident_agent
from app.state.world_state import world_state


def test_victim_prioritization_critical():
    agent = VictimPrioritizationAgent()
    v_crit = Victim(
        id="VIC-TEST-1",
        location=Vector3D(x=10, y=0, z=20),
        people_count=3,
        medical_severity=0.95,
        estimated_survival_urgency=0.90,
        hazard_exposure=0.80,
        accessibility_factor=0.30,
        confidence=0.95,
    )
    breakdown = agent.evaluate_victim(v_crit)
    p_class = agent.determine_class(breakdown.calculated_score)
    
    assert p_class == VictimPriorityClass.CRITICAL
    assert breakdown.calculated_score >= 0.75
    assert len(breakdown.reasons) >= 3
    assert any("Severe medical trauma" in r for r in breakdown.reasons)
    assert any("Multiple individuals" in r for r in breakdown.reasons)


def test_victim_prioritization_low():
    agent = VictimPrioritizationAgent()
    v_low = Victim(
        id="VIC-TEST-2",
        location=Vector3D(x=10, y=0, z=20),
        people_count=1,
        medical_severity=0.10,
        estimated_survival_urgency=0.10,
        hazard_exposure=0.0,
        accessibility_factor=0.90,
        confidence=0.90,
    )
    breakdown = agent.evaluate_victim(v_low)
    p_class = agent.determine_class(breakdown.calculated_score)
    assert p_class == VictimPriorityClass.LOW
    assert breakdown.calculated_score < 0.35


@pytest.mark.asyncio
async def test_incident_agent_observation_handling():
    obs = ObservationPacket(
        observation_id="OBS-001",
        timestamp=10.0,
        source_drone_id="DRONE-S01",
        type=ObservationType.VICTIM_LOCATED,
        location=Vector3D(x=-50.0, y=0.0, z=50.0),
        confidence=0.92,
        raw_reading={"medical_severity": 0.85, "urgency": 0.80, "people_count": 2},
    )
    inc = await incident_agent.process_observation(obs)
    assert inc is not None
    assert inc.type.value == "TRAPPED_VICTIM"
    assert len(world_state.victims) >= 1
