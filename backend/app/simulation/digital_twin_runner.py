"""
ResQNet Simulation - High-Fidelity Digital Twin Runner
Simulates realistic drone kinematics, battery discharge, sensor observations, and waypoint execution.
"""
import asyncio
import logging
import math
import time
from typing import Dict, List, Optional
from app.schemas.common import Vector3D
from app.schemas.drone import DroneStatus
from app.schemas.mission import MissionStatus, WaypointAction
from app.schemas.telemetry import DroneTelemetryPacket, ObservationPacket, ObservationType
from app.schemas.command import CommandPayload, CommandAck, CommandResult, CommandType
from app.state.world_state import world_state
from app.websocket.connection_manager import connection_manager
from app.intelligence.perception.perception_agent import perception_agent
from app.intelligence.incidents.incident_agent import incident_agent
from app.audit.audit_logger import audit_logger

logger = logging.getLogger("resqnet.simulation")


class DigitalTwinRunner:
    def __init__(self, update_rate_hz: float = 10.0):
        self.update_rate_hz = update_rate_hz
        self.dt = 1.0 / update_rate_hz
        self.is_running = False
        self._task: Optional[asyncio.Task] = None
        self.active_commands: Dict[str, CommandPayload] = {}

    def start(self):
        if not self.is_running:
            self.is_running = True
            self._task = asyncio.create_task(self._simulation_loop())
            logger.info("Digital Twin Simulator started at 10Hz")

    def stop(self):
        self.is_running = False
        if self._task:
            self._task.cancel()

    async def accept_command(self, command: CommandPayload):
        """Called when a command is issued by CommandAgent."""
        self.active_commands[command.drone_id] = command
        # Send immediate ACK
        ack = CommandAck(
            command_id=command.command_id,
            drone_id=command.drone_id,
            status="ACCEPTED",
            timestamp=time.time(),
        )
        await connection_manager.handle_command_ack(ack)

    async def _simulation_loop(self):
        while self.is_running:
            try:
                loop_start = time.time()
                world_state.simulation_time += self.dt

                # Simulate each drone in the world
                for drone_id, drone in list(world_state.drones.items()):
                    if drone.status in [DroneStatus.EN_ROUTE, DroneStatus.RETURNING]:
                        self._update_drone_kinematics(drone)

                # Broadcast live state update to frontends periodically
                await asyncio.sleep(self.dt)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in simulation loop: {e}")
                await asyncio.sleep(self.dt)

    def _update_drone_kinematics(self, drone):
        if drone.id not in self.active_commands:
            return

        cmd = self.active_commands[drone.id]
        if not cmd.waypoints:
            return

        mission_id = drone.current_mission_id
        mission = world_state.missions.get(mission_id) if mission_id else None
        curr_wp_idx = mission.current_waypoint_index if mission else 0

        if curr_wp_idx >= len(cmd.waypoints):
            # Mission waypoints finished
            drone.status = DroneStatus.ON_SITE if drone.status != DroneStatus.RETURNING else DroneStatus.IDLE
            if mission:
                mission.status = MissionStatus.COMPLETED
                mission.completed_at = time.time()
                if mission.target_victim_id and mission.target_victim_id in world_state.victims:
                    world_state.victims[mission.target_victim_id].status = "ASSISTED"
            del self.active_commands[drone.id]
            return

        target_wp = cmd.waypoints[curr_wp_idx]
        pos = drone.position
        target_pos = target_wp.position

        # Direction vector
        dx = target_pos.x - pos.x
        dy = target_pos.y - pos.y
        dz = target_pos.z - pos.z
        dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        speed = target_wp.speed_mps
        step_dist = speed * self.dt

        if dist <= step_dist or dist < 1.0:
            # Arrived at waypoint
            drone.position = Vector3D(x=target_pos.x, y=target_pos.y, z=target_pos.z)
            if mission:
                mission.current_waypoint_index += 1

            # Check waypoint action
            if target_wp.action == WaypointAction.DROP_PAYLOAD:
                drone.current_payload_kg = 0.0
                if mission and mission.target_victim_id:
                    vic = world_state.victims.get(mission.target_victim_id)
                    if vic:
                        vic.status = "ASSISTED"
                        vic.medical_severity = max(0.1, vic.medical_severity - 0.4)
            return

        # Move along direction
        ratio = step_dist / dist
        new_x = pos.x + dx * ratio
        new_y = pos.y + dy * ratio
        new_z = pos.z + dz * ratio

        drone.position = Vector3D(x=new_x, y=new_y, z=new_z)
        drone.velocity = Vector3D(x=dx * speed / dist, y=dy * speed / dist, z=dz * speed / dist)
        drone.heading = (math.atan2(dx, dz) * 180.0 / math.pi) % 360.0

        # Realistic battery consumption: ~0.05% per second at cruise speed
        power_drain = (drone.power_consumption_w * self.dt) / (600.0 * 3600.0) * 100.0
        drone.battery_percent = max(0.0, drone.battery_percent - power_drain)

        # Telemetry ingestion packet
        packet = DroneTelemetryPacket(
            drone_id=drone.id,
            timestamp=world_state.simulation_time,
            position=drone.position,
            velocity=drone.velocity,
            heading=drone.heading,
            battery_percent=round(drone.battery_percent, 2),
            status=drone.status,
            communication_quality=drone.communication_quality,
            current_waypoint_index=curr_wp_idx,
            mission_id=mission_id,
        )
        world_state.update_drone_telemetry(packet)


digital_twin_runner = DigitalTwinRunner()
