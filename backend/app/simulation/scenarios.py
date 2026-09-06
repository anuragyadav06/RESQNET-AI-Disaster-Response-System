"""
ResQNet Simulation - Metro Earthquake Disaster Scenario

The scenario provides deterministic victim observations.
Victim severity, operational confidence and priority are calculated
by the backend VictimPrioritizationAgent.
"""

import time
from typing import Dict, Any

from app.schemas.common import Vector3D
from app.schemas.world import BuildingDamageLevel, HazardZone, HazardType
from app.schemas.victim import Victim, VictimStatus
from app.schemas.incident import IncidentEntity, IncidentType, IncidentStatus
from app.schemas.audit import AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger
from app.intelligence.victims.prioritization_agent import prioritization_agent
from app.intelligence.missions.mission_agent import mission_agent
from app.intelligence.replanning.replanning_agent import replanning_agent
from app.simulation.digital_twin_runner import digital_twin_runner
from app.websocket.connection_manager import connection_manager


class ScenarioManager:
    def __init__(self):
        self.current_phase = "IDLE"

    async def reset_to_normal(self) -> Dict[str, Any]:
        """Reset the authoritative Godot Digital Twin when connected."""
        if world_state.system_b_connected:
            sent = await connection_manager.send_simulation_control("RESET")

            if sent:
                world_state.victims.clear()
                world_state.hazards.clear()
                world_state.incidents.clear()
                world_state.missions.clear()
                world_state.increment_version()

                return {
                    "status": "SUCCESS",
                    "phase": "NORMAL_CITY",
                    "message": "RESET command sent to Godot Digital Twin",
                }

        # Reset software simulation state.
        world_state.victims.clear()
        world_state.hazards.clear()
        world_state.incidents.clear()
        world_state.missions.clear()

        # Reset roads.
        for edge in world_state.road_edges.values():
            edge.is_blocked = False
            edge.blockage_reason = None

        # Reset buildings.
        for bld in world_state.buildings.values():
            bld.damage_level = BuildingDamageLevel.INTACT

        # Reset drones.
        for drone in world_state.drones.values():
            drone.position = Vector3D(
                x=0.0,
                y=0.0,
                z=0.0,
            )
            drone.velocity = Vector3D(
                x=0.0,
                y=0.0,
                z=0.0,
            )
            drone.battery_percent = 100.0
            drone.status = "IDLE"
            drone.current_mission_id = None
            drone.target_victim_id = None

        world_state.environment.seismic_activity_richter = 0.0
        world_state.increment_version()

        self.current_phase = "NORMAL_CITY"

        await audit_logger.log_event(
            event_type=AuditEventType.SIMULATION_EVENT,
            decision="Simulation reset to pristine city state",
            reason="Operator scenario reset",
            output={"phase": "NORMAL_CITY"},
        )

        return {
            "status": "SUCCESS",
            "phase": "NORMAL_CITY",
            "message": "City reset to normal state",
        }

    async def trigger_metro_earthquake(self) -> Dict[str, Any]:
        """
        Trigger the earthquake in the authoritative Digital Twin.

        When Godot is connected, live drone observations become the
        source of victim detections.

        When Godot is not connected, the deterministic fallback victims
        below are used.
        """

        if world_state.system_b_connected:
            sent = await connection_manager.send_simulation_control(
                "EARTHQUAKE"
            )

            if sent:
                return {
                    "status": "SUCCESS",
                    "phase": "EARTHQUAKE_ACTIVE",
                    "dispatched_mission": None,
                    "message": (
                        "Earthquake command sent to Godot Digital Twin; "
                        "victim intelligence will populate from live "
                        "drone detections."
                    ),
                }

        now = time.time()
        self.current_phase = "EARTHQUAKE_ACTIVE"

        # ============================================================
        # 1. SEISMIC SHOCK & BUILDING DAMAGE
        # ============================================================

        world_state.environment.seismic_activity_richter = 7.2

        if "BLD-07" in world_state.buildings:
            world_state.buildings[
                "BLD-07"
            ].damage_level = BuildingDamageLevel.COLLAPSED

        if "BLD-03" in world_state.buildings:
            world_state.buildings[
                "BLD-03"
            ].damage_level = BuildingDamageLevel.STRUCTURAL_CRACK

        # ============================================================
        # 2. ROAD BLOCKAGES
        # ============================================================

        world_state.block_road_edge(
            "EDGE_INT_1_1_INT_2_1",
            "Overpass collapse & structural rubble",
        )

        world_state.block_road_edge(
            "EDGE_INT_2_1_INT_2_2",
            "Asphalt fracture & gas line rupture",
        )

        # ============================================================
        # 3. FIRE HAZARD
        # ============================================================

        world_state.hazards["HAZ-FIRE-01"] = HazardZone(
            id="HAZ-FIRE-01",
            type=HazardType.FIRE,
            center=Vector3D(
                x=50.0,
                y=0.0,
                z=110.0,
            ),
            radius_m=35.0,
            intensity=0.88,
        )

        # ============================================================
        # 4. SYSTEM-LEVEL EARTHQUAKE INCIDENT
        #
        # This is NOT the victim assessment confidence.
        # It describes confidence in the overall seismic event.
        # ============================================================

        world_state.incidents["INC-SEISMIC-01"] = IncidentEntity(
            id="INC-SEISMIC-01",
            type=IncidentType.EARTHQUAKE_DAMAGE,
            title="Magnitude 7.2 Urban Seismic Shock",
            location=Vector3D(
                x=0,
                y=0,
                z=0,
            ),
            severity=0.95,
            confidence=0.99,
            timestamp=now,
            evidence=[
                "Accelerometers tripped",
                "Acoustic fracture detected",
                "Structural sensor mesh",
            ],
            status=IncidentStatus.ACTIVE,
        )

        # ============================================================
        # 5. DETERMINISTIC VICTIM OBSERVATIONS
        #
        # IMPORTANT:
        #
        # observation_confidence = raw scout/evidence quality.
        #
        # severity / confidence / priority are NOT manually assigned
        # here. The prioritization agent calculates them from these
        # raw victim conditions.
        #
        # Each victim deliberately has different:
        #   - medical severity
        #   - urgency
        #   - hazard exposure
        #   - accessibility
        #   - observation confidence
        #   - people count
        #   - hazard/state
        #
        # This creates meaningful per-victim variation without random
        # numbers.
        # ============================================================

        vics = [
            # --------------------------------------------------------
            # VIC-101
            # Structural collapse / trapped group.
            # Expected: highest severity and very high priority.
            # --------------------------------------------------------
            Victim(
                id="VIC-101",
                hazard_type="STRUCTURAL_COLLAPSE",
                captured_by_drone_id="DRONE-S01",
                image_url="/victim-evidence/VIC-101.svg",
                name="Trapped Resident Group (Apartment B)",
                location=Vector3D(
                    x=95.0,
                    y=0.0,
                    z=8.0,
                ),
                people_count=3,

                # Raw victim factors.
                medical_severity=0.92,
                estimated_survival_urgency=0.95,
                hazard_exposure=0.75,
                accessibility_factor=0.30,

                # Raw observation quality.
                observation_confidence=0.74,

                status=VictimStatus.DETECTED,
                detected_at=now,
            ),

            # --------------------------------------------------------
            # VIC-102
            # Smoke ingress / medical respiratory risk.
            # Expected: high severity and high priority, but below
            # structural entrapment.
            # --------------------------------------------------------
            Victim(
                id="VIC-102",
                hazard_type="SMOKE",
                captured_by_drone_id="DRONE-S02",
                image_url="/victim-evidence/VIC-102.svg",
                name="Office Worker (Apex Tower Smoke Ingress)",
                location=Vector3D(
                    x=5.0,
                    y=0.0,
                    z=-90.0,
                ),
                people_count=1,

                medical_severity=0.78,
                estimated_survival_urgency=0.84,
                hazard_exposure=0.86,
                accessibility_factor=0.58,

                observation_confidence=0.69,

                status=VictimStatus.DETECTED,
                detected_at=now,
            ),

            # --------------------------------------------------------
            # VIC-103
            # Debris / crush injury.
            # Expected: high severity, but less exposure than smoke
            # and easier access than a collapsed structure.
            # --------------------------------------------------------
            Victim(
                id="VIC-103",
                hazard_type="DEBRIS",
                captured_by_drone_id="DRONE-S03",
                image_url="/victim-evidence/VIC-103.svg",
                name="Pedestrian with Crush Fracture",
                location=Vector3D(
                    x=-60.0,
                    y=0.0,
                    z=40.0,
                ),
                people_count=1,

                medical_severity=0.82,
                estimated_survival_urgency=0.78,
                hazard_exposure=0.62,
                accessibility_factor=0.48,

                observation_confidence=0.77,

                status=VictimStatus.DETECTED,
                detected_at=now,
            ),

            # --------------------------------------------------------
            # VIC-104
            # Exposed survivor.
            # Expected: lower operational severity/priority because
            # accessibility is good and immediate hazard exposure is
            # low.
            # --------------------------------------------------------
            Victim(
                id="VIC-104",
                hazard_type="EXPOSED",
                captured_by_drone_id="DRONE-S04",
                image_url="/victim-evidence/VIC-104.svg",
                name="Disoriented Survivor",
                location=Vector3D(
                    x=-110.0,
                    y=0.0,
                    z=-40.0,
                ),
                people_count=1,

                medical_severity=0.66,
                estimated_survival_urgency=0.67,
                hazard_exposure=0.28,
                accessibility_factor=0.88,

                observation_confidence=0.71,

                status=VictimStatus.DETECTED,
                detected_at=now,
            ),
        ]

        # ============================================================
        # 6. STORE + RUN AUTHORITATIVE ASSESSMENT
        # ============================================================

        for victim in vics:
            world_state.victims[victim.id] = victim

            # This is the ONLY place that should calculate:
            #   severity
            #   operational confidence
            #   priority score
            #   priority class
            #   priority breakdown
            await prioritization_agent.prioritize_and_update(
                victim
            )

        world_state.increment_version()

        # ============================================================
        # 7. AUDIT
        # ============================================================

        await audit_logger.log_event(
            event_type=AuditEventType.SIMULATION_EVENT,
            decision="Metro Earthquake (M 7.2) Triggered",
            reason=(
                "Disaster scenario initialized: "
                "4 victims, 1 active fire, 2 road blockages, "
                "structural collapse"
            ),
            inputs={
                "richter": 7.2,
                "victims": len(vics),
            },
            output={
                "phase": "EARTHQUAKE_ACTIVE",
            },
        )

        # ============================================================
        # 8. AUTONOMOUS RESPONSE
        # ============================================================

        top_mission, msg = (
            await mission_agent.auto_plan_highest_priority()
        )

        # Start Digital Twin simulator to drive physical drone movement.
        digital_twin_runner.start()

        if top_mission and top_mission.assigned_drone_id:
            from app.intelligence.commands.command_agent import command_agent

            if command_agent.command_history:
                await digital_twin_runner.accept_command(
                    command_agent.command_history[-1]
                )

        return {
            "status": "SUCCESS",
            "phase": "EARTHQUAKE_ACTIVE",
            "dispatched_mission": (
                top_mission.mission_id
                if top_mission
                else None
            ),
            "message": (
                f"Earthquake triggered. "
                f"Autonomous mission created: {msg}"
            ),
        }

    async def trigger_aftershock_and_roadblock(
        self,
    ) -> Dict[str, Any]:
        """
        Secondary aftershock blocks the primary avenue,
        forcing dynamic replanning.
        """

        edge_to_block = "EDGE_INT_0_1_INT_1_1"

        world_state.block_road_edge(
            edge_to_block,
            "Aftershock structural debris on Grand Avenue",
        )

        # Trigger dynamic replanning agent.
        replan_results = (
            await replanning_agent.evaluate_and_replan()
        )

        # Forward updated commands to the Digital Twin.
        for rep in replan_results:
            mid = rep.get("mission_id")

            if mid and mid in world_state.missions:
                drone_id = (
                    world_state
                    .missions[mid]
                    .assigned_drone_id
                )

                from app.intelligence.commands.command_agent import command_agent

                if command_agent.command_history:
                    await digital_twin_runner.accept_command(
                        command_agent.command_history[-1]
                    )

        return {
            "status": "SUCCESS",
            "blocked_edge": edge_to_block,
            "replan_results": replan_results,
            "message": (
                f"Aftershock triggered. Blocked {edge_to_block}. "
                f"Replanning performed: "
                f"{len(replan_results)} missions rerouted."
            ),
        }


scenario_manager = ScenarioManager()