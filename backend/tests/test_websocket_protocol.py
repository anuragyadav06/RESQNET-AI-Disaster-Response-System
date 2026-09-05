"""
Unit tests for WebSocket Protocol & Connection Manager
"""
import asyncio
import pytest
from app.websocket.protocol import (
    MessageType,
    SystemBRegisterMessage,
    TelemetryBatchMessage,
)
from app.schemas.telemetry import DroneTelemetryPacket
from app.schemas.command import CommandPayload, CommandType, CommandAck
from app.websocket.connection_manager import ConnectionManager
from app.schemas.common import Vector3D


def test_protocol_message_serialization():
    reg = SystemBRegisterMessage(session_id="test_sim_01")
    assert reg.type == MessageType.REGISTER_SIMULATION
    assert reg.session_id == "test_sim_01"
    
    dumped = reg.model_dump(mode="json")
    assert dumped["type"] == "REGISTER_SIMULATION"
    assert dumped["grid_bounds"]["min_x"] == -200


def test_telemetry_batch_parsing():
    packet = DroneTelemetryPacket(
        drone_id="DRONE-M01",
        timestamp=12.4,
        position=Vector3D(x=10.0, y=20.0, z=30.0),
        battery_percent=94.0,
    )
    batch = TelemetryBatchMessage(
        session_id="test_sim_01",
        timestamp=12.4,
        packets=[packet],
    )
    dumped = batch.model_dump(mode="json")
    assert len(dumped["packets"]) == 1
    assert dumped["packets"][0]["drone_id"] == "DRONE-M01"


@pytest.mark.asyncio
async def test_command_ack_handling():
    mgr = ConnectionManager()
    mgr.pending_commands["CMD-101"] = {
        "sent_time": 100.0,
        "command": CommandPayload(
            command_id="CMD-101",
            drone_id="DRONE-S01",
            command=CommandType.NAVIGATE,
        ),
    }
    
    ack = CommandAck(
        command_id="CMD-101",
        drone_id="DRONE-S01",
        status="ACCEPTED",
        timestamp=100.02,
    )
    await mgr.handle_command_ack(ack)
    assert "CMD-101" not in mgr.pending_commands
