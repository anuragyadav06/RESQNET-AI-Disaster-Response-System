"""
ResQNet Simulation - Metro Earthquake Disaster Scenario
"""
import asyncio
import time
from typing import Dict, Any
from app.schemas.common import Vector3D
from app.schemas.world import BuildingDamageLevel, HazardZone, HazardType
from app.schemas.victim import Victim, VictimPriorityClass, VictimStatus
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
        """Reset the authoritative Godot Digital Twin when it is connected."""
        if world_state.system_b_connected:
            sent = await connection_manager.send_simulation_control("RESET")
            if sent:
                world_state.victims.clear()
                world_state.hazards.clear()
                world_state.incidents.clear()
                world_state.missions.clear()
                world_state.increment_version()
                return {"status": "SUCCESS", "phase": "NORMAL_CITY", "message": "RESET command sent to Godot Digital Twin"}
        """Resets the simulation to pristine city conditions."""
        world_state.victims.clear()
        world_state.hazards.clear()
        world_state.incidents.clear()
        world_state.missions.clear()
        
        # Reset roads
        for edge in world_state.road_edges.values():
            edge.is_blocked = False
            edge.blockage_reason = None
            
        # Reset buildings
        for bld in world_state.buildings.values():
            bld.damage_level = BuildingDamageLevel.INTACT
            
        # Reset drones
        for did, drone in world_state.drones.items():
            drone.position = Vector3D(x=0.0, y=0.0, z=0.0)
            drone.velocity = Vector3D(x=0.0, y=0.0, z=0.0)
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
        return {"status": "SUCCESS", "phase": "NORMAL_CITY", "message": "City reset to normal state"}

    async def trigger_metro_earthquake(self) -> Dict[str, Any]:
        """Triggers the earthquake in the authoritative Godot Digital Twin."""
        if world_state.system_b_connected:
            sent = await connection_manager.send_simulation_control("EARTHQUAKE")
            if sent:
                return {"status":"SUCCESS","phase":"EARTHQUAKE_ACTIVE","dispatched_mission":None,
                        "message":"Earthquake command sent to Godot Digital Twin; victim intelligence will populate from live drone detections."}
        now = time.time()
        self.current_phase = "EARTHQUAKE_ACTIVE"
        
        # 1. Seismic Shock & Building Damage
        world_state.environment.seismic_activity_richter = 7.2
        if "BLD-07" in world_state.buildings:
            world_state.buildings["BLD-07"].damage_level = BuildingDamageLevel.COLLAPSED
        if "BLD-03" in world_state.buildings:
            world_state.buildings["BLD-03"].damage_level = BuildingDamageLevel.STRUCTURAL_CRACK

        # 2. Road Blockages
        world_state.block_road_edge("EDGE_INT_1_1_INT_2_1", "Overpass collapse & structural rubble")
        world_state.block_road_edge("EDGE_INT_2_1_INT_2_2", "Asphalt fracture & gas line rupture")

        # 3. Fire Hazard in District 3
        world_state.hazards["HAZ-FIRE-01"] = HazardZone(
            id="HAZ-FIRE-01",
            type=HazardType.FIRE,
            center=Vector3D(x=50.0, y=0.0, z=110.0),
            radius_m=35.0,
            intensity=0.88,
        )

        # 4. Declare Initial Incidents
        world_state.incidents["INC-SEISMIC-01"] = IncidentEntity(
            id="INC-SEISMIC-01",
            type=IncidentType.EARTHQUAKE_DAMAGE,
            title="Magnitude 7.2 Urban Seismic Shock",
            location=Vector3D(x=0, y=0, z=0),
            severity=0.95,
            confidence=0.99,
            timestamp=now,
            evidence=["Accelerometers tripped", "Acoustic fracture detected", "Structural sensor mesh"],
            status=IncidentStatus.ACTIVE,
        )

        # 5. Victims detected across city
        vics = [
            Victim(
                id="VIC-101",
                hazard_type="STRUCTURAL_COLLAPSE", captured_by_drone_id="DRONE-S01", image_url="/victim-evidence/VIC-101.svg",
                name="Trapped Resident Group (Apartment B)",
                location=Vector3D(x=95.0, y=0.0, z=8.0),
                people_count=3,
                medical_severity=0.92,
                estimated_survival_urgency=0.95,
                hazard_exposure=0.75,
                accessibility_factor=0.30,
                confidence=0.96,
                detected_at=now,
            ),
            Victim(
                id="VIC-102",
                hazard_type="SMOKE", captured_by_drone_id="DRONE-S01", image_url="/victim-evidence/VIC-102.svg",
                name="Office Worker (Apex Tower Smoke Ingress)",
                location=Vector3D(x=5.0, y=0.0, z=-90.0),
                people_count=1,
                medical_severity=0.72,
                estimated_survival_urgency=0.70,
                hazard_exposure=0.60,
                accessibility_factor=0.85,
                confidence=0.90,
                detected_at=now,
            ),
            Victim(
                id="VIC-103",
                hazard_type="DEBRIS", captured_by_drone_id="DRONE-S01", image_url="/victim-evidence/VIC-103.svg",
                name="Pedestrian with Crush Fracture",
                location=Vector3D(x=-60.0, y=0.0, z=40.0),
                people_count=1,
                medical_severity=0.50,
                estimated_survival_urgency=0.55,
                hazard_exposure=0.20,
                accessibility_factor=0.95,
                confidence=0.94,
                detected_at=now,
            ),
            Victim(
                id="VIC-104",
                hazard_type="EXPOSED", captured_by_drone_id="DRONE-S01", image_url="/victim-evidence/VIC-104.svg",
                name="Disoriented Survivor",
                location=Vector3D(x=-110.0, y=0.0, z=-40.0),
                people_count=1,
                medical_severity=0.25,
                estimated_survival_urgency=0.30,
                hazard_exposure=0.05,
                accessibility_factor=1.0,
                confidence=0.88,
                detected_at=now,
            ),
        ]

        for v in vics:
            world_state.victims[v.id] = v
            await prioritization_agent.prioritize_and_update(v)

        world_state.increment_version()

        await audit_logger.log_event(
            event_type=AuditEventType.SIMULATION_EVENT,
            decision="Metro Earthquake (M 7.2) Triggered",
            reason="Disaster scenario initialized: 4 victims, 1 active fire, 2 road blockages, structural collapse",
            inputs={"richter": 7.2, "victims": len(vics)},
            output={"phase": "EARTHQUAKE_ACTIVE"},
        )

        # Autonomous closed loop: automatically plan and dispatch mission to the CRITICAL victim
        top_mission, msg = await mission_agent.auto_plan_highest_priority()
        
        # Start digital twin simulator to drive physical drone movement
        digital_twin_runner.start()
        if top_mission and top_mission.assigned_drone_id:
            # Tell digital twin runner to execute this drone command
            from app.intelligence.commands.command_agent import command_agent
            if command_agent.command_history:
                await digital_twin_runner.accept_command(command_agent.command_history[-1])

        return {
            "status": "SUCCESS",
            "phase": "EARTHQUAKE_ACTIVE",
            "dispatched_mission": top_mission.mission_id if top_mission else None,
            "message": f"Earthquake triggered. Autonomous mission created: {msg}",
        }

    async def trigger_aftershock_and_roadblock(self) -> Dict[str, Any]:
        """Secondary aftershock blocks the primary avenue, forcing dynamic replanning."""
        now = time.time()
        edge_to_block = "EDGE_INT_0_1_INT_1_1"
        world_state.block_road_edge(edge_to_block, "Aftershock structural debris on Grand Avenue")
        
        # Trigger dynamic replanning agent
        replan_results = await replanning_agent.evaluate_and_replan()
        
        # If active command was updated, forward to digital twin runner
        for rep in replan_results:
            mid = rep.get("mission_id")
            if mid and mid in world_state.missions:
                drone_id = world_state.missions[mid].assigned_drone_id
                from app.intelligence.commands.command_agent import command_agent
                if command_agent.command_history:
                    await digital_twin_runner.accept_command(command_agent.command_history[-1])

        return {
            "status": "SUCCESS",
            "blocked_edge": edge_to_block,
            "replan_results": replan_results,
            "message": f"Aftershock triggered. Blocked {edge_to_block}. Replanning performed: {len(replan_results)} missions rerouted.",
        }


scenario_manager = ScenarioManager()
