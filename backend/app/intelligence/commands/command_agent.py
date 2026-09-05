"""
ResQNet Intelligence - Command Generation & Validation Agent
Converts mission plans into machine-readable commands and enforces pre-transmission safety.
"""
import time
import uuid
from typing import Optional, Tuple
from app.schemas.command import CommandPayload, CommandType
from app.schemas.mission import MissionPlan, Waypoint
from app.schemas.drone import DroneEntity
from app.schemas.audit import AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger
from app.websocket.connection_manager import connection_manager


class CommandAgent:
    def __init__(self):
        self.command_history: list = []

    def validate_command(self, command: CommandPayload) -> Tuple[bool, Optional[str]]:
        """Rigorous pre-transmission safety checks. Never sends an unsafe command to System B."""
        # 1. Drone existence
        if command.drone_id not in world_state.drones:
            return False, f"Unknown drone ID '{command.drone_id}'"
        
        drone = world_state.drones[command.drone_id]
        
        # 2. Battery safety
        if drone.battery_percent < 12.0 and command.command not in [CommandType.RETURN_TO_BASE, CommandType.LAND]:
            return False, f"Drone battery critically low ({drone.battery_percent:.1f}%), cannot dispatch non-return command"

        # 3. Waypoints validity
        for wp in command.waypoints:
            if abs(wp.position.x) > 1000.0 or abs(wp.position.z) > 1000.0:
                return False, f"Waypoint coordinates ({wp.position.x}, {wp.position.z}) exceed bounds"
            if wp.position.y < 0.0 or wp.position.y > 200.0:
                return False, f"Waypoint altitude ({wp.position.y}m) outside safe corridor [0, 200m]"

        return True, None

    async def issue_mission_command(
        self,
        mission: MissionPlan,
        command_type: CommandType = CommandType.NAVIGATE,
    ) -> Tuple[bool, Optional[CommandPayload], str]:
        now = time.time()
        cmd_id = f"CMD-{int(now*1000)%1000000}-{uuid.uuid4().hex[:4]}"
        
        payload = CommandPayload(
            protocol_version="1.0",
            command_id=cmd_id,
            drone_id=mission.assigned_drone_id,
            command=command_type,
            waypoints=mission.waypoints,
            priority=mission.priority_score,
            constraints={
                "max_velocity_mps": 15.0,
                "target_altitude_m": 15.0,
                "contingency": mission.fallback_strategy,
                "mission_id": mission.mission_id,
                "planner": "RRT_STAR",
            },
            issued_at=now,
            expires_at=now + 90.0,
        )

        valid, error_msg = self.validate_command(payload)
        if not valid:
            await audit_logger.log_event(
                event_type=AuditEventType.COMMAND_ISSUED,
                decision=f"Command {cmd_id} REJECTED during pre-transmission validation",
                reason=error_msg or "Safety check failed",
                inputs=payload.model_dump(),
                output={"status": "VALIDATION_FAILED", "error": error_msg},
                confidence=1.0,
                affected_entities=[mission.assigned_drone_id, mission.mission_id],
            )
            return False, None, f"Command validation failed: {error_msg}"

        # Transmit via WebSocket to System B
        sent_to_sim = await connection_manager.send_command_to_system_b(payload)

        # Audit log command issuance
        await audit_logger.log_event(
            event_type=AuditEventType.COMMAND_ISSUED,
            decision=f"Command {cmd_id} ({command_type.value}) transmitted to {mission.assigned_drone_id}",
            reason=f"Mission {mission.mission_id} dispatch: {len(mission.waypoints)} waypoints",
            inputs={"mission_id": mission.mission_id, "drone_id": mission.assigned_drone_id},
            output={"command_id": cmd_id, "transmitted_to_sim": sent_to_sim},
            confidence=1.0,
            affected_entities=[mission.assigned_drone_id, mission.mission_id],
        )

        self.command_history.append(payload)
        return True, payload, f"Command {cmd_id} issued successfully (Transmitted to System B: {sent_to_sim})"


command_agent = CommandAgent()
