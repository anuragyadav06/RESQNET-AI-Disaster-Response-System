"""
ResQNet World State Engine - Versioned Thread-Safe In-Memory State
"""
import time
from typing import Dict, List, Optional, Tuple
from app.core.config import settings
from app.schemas.common import Vector3D, UncertaintyState, SeverityLevel
from app.schemas.drone import DroneEntity, DroneCapability, DroneStatus
from app.schemas.victim import Victim, VictimPriorityClass, VictimStatus
from app.schemas.incident import IncidentEntity, IncidentType, IncidentStatus
from app.schemas.world import (
    Building,
    BuildingDamageLevel,
    RoadNode,
    RoadEdge,
    HazardZone,
    HazardType,
    Facility,
    EnvironmentalConditions,
    WorldStateSnapshot,
)
from app.schemas.mission import MissionPlan, MissionStatus
from app.schemas.telemetry import DroneTelemetryPacket
from app.schemas.audit import AuditEventType
from app.audit.audit_logger import audit_logger


class WorldStateManager:
    def __init__(self, session_id: str = settings.DEFAULT_SESSION_ID):
        self.session_id = session_id
        self.simulation_time: float = 0.0
        self.state_version: int = 1
        
        self.system_b_connected: bool = False
        self.system_b_session_id: Optional[str] = None
        
        self.drones: Dict[str, DroneEntity] = {}
        self.victims: Dict[str, Victim] = {}
        self.hazards: Dict[str, HazardZone] = {}
        self.incidents: Dict[str, IncidentEntity] = {}
        self.missions: Dict[str, MissionPlan] = {}
        self.buildings: Dict[str, Building] = {}
        self.road_nodes: Dict[str, RoadNode] = {}
        self.road_edges: Dict[str, RoadEdge] = {}
        self.facilities: Dict[str, Facility] = {}
        self.environment: EnvironmentalConditions = EnvironmentalConditions()
        
        self.telemetry_packet_count: int = 0
        self.telemetry_start_time: float = time.time()
        self.last_command_sent_time: float = 0.0
        self.last_command_ack_time: float = 0.0
        self.command_latency_ms: float = 14.5
        
        self._initialize_metro_environment()

    def _initialize_metro_environment(self):
        """Builds a realistic 4x4 urban grid (Metro City) with facilities, buildings, and initial drone fleet."""
        # 1. Facilities
        self.facilities["BASE-ALPHA"] = Facility(
            id="BASE-ALPHA",
            name="ResQNet Command & Drone Hangar Alpha",
            type="COMMAND_HQ",
            location=Vector3D(x=0.0, y=0.0, z=0.0),
            capacity=10,
            current_load=4,
        )
        self.facilities["HOSPITAL-CENTRAL"] = Facility(
            id="HOSPITAL-CENTRAL",
            name="Metro General Hospital & Trauma Center",
            type="HOSPITAL",
            location=Vector3D(x=300.0, y=0.0, z=100.0),
            capacity=250,
            current_load=180,
        )

        # 2. Road Network (4x4 Grid, 100m spacing from -150m to +150m in X and Z)
        grid_coords = [-150.0, -50.0, 50.0, 150.0]
        node_map = {}
        for i, x in enumerate(grid_coords):
            for j, z in enumerate(grid_coords):
                node_id = f"INT_{i}_{j}"
                node_map[(i, j)] = node_id
                self.road_nodes[node_id] = RoadNode(
                    id=node_id,
                    position=Vector3D(x=x, y=0.0, z=z),
                    is_intersection=True,
                )

        # Road Edges (Bidirectional)
        edge_idx = 0
        for i in range(4):
            for j in range(4):
                curr = node_map[(i, j)]
                # Connect to East neighbor (i+1, j)
                if i < 3:
                    nbr = node_map[(i + 1, j)]
                    e1 = f"EDGE_{curr}_{nbr}"
                    e2 = f"EDGE_{nbr}_{curr}"
                    dist = 100.0
                    self.road_edges[e1] = RoadEdge(id=e1, from_node=curr, to_node=nbr, distance_m=dist)
                    self.road_edges[e2] = RoadEdge(id=e2, from_node=nbr, to_node=curr, distance_m=dist)
                # Connect to North neighbor (i, j+1)
                if j < 3:
                    nbr = node_map[(i, j + 1)]
                    e1 = f"EDGE_{curr}_{nbr}"
                    e2 = f"EDGE_{nbr}_{curr}"
                    dist = 100.0
                    self.road_edges[e1] = RoadEdge(id=e1, from_node=curr, to_node=nbr, distance_m=dist)
                    self.road_edges[e2] = RoadEdge(id=e2, from_node=nbr, to_node=curr, distance_m=dist)

        # 3. Major Buildings / Districts
        districts = [
            ("BLD-01", "Civic Center Grand Hall", "Civic Center", Vector3D(x=-100.0, y=25.0, z=-100.0), 40, 50),
            ("BLD-02", "City Municipal Archive", "Civic Center", Vector3D(x=-100.0, y=15.0, z=0.0), 30, 30),
            ("BLD-03", "Apex Financial Tower", "Financial District", Vector3D(x=0.0, y=60.0, z=-100.0), 35, 120),
            ("BLD-04", "Metro Bank Plaza", "Financial District", Vector3D(x=0.0, y=45.0, z=0.0), 35, 90),
            ("BLD-05", "Grand Metro Hotel", "Hospitality Hub", Vector3D(x=0.0, y=30.0, z=100.0), 40, 60),
            ("BLD-06", "Metro Central Station", "Transit Corridor", Vector3D(x=100.0, y=18.0, z=-100.0), 50, 35),
            ("BLD-07", "North Residential Block A", "Residential North", Vector3D(x=100.0, y=20.0, z=0.0), 35, 40),
            ("BLD-08", "North Residential Block B", "Residential North", Vector3D(x=100.0, y=20.0, z=100.0), 35, 40),
            ("BLD-09", "Metro High School", "Education Zone", Vector3D(x=-100.0, y=12.0, z=100.0), 60, 25),
        ]
        for bid, bname, dist, pos, sz, h in districts:
            self.buildings[bid] = Building(
                id=bid,
                name=bname,
                district=dist,
                center=pos,
                size_x=sz,
                size_z=sz,
                height=h,
                damage_level=BuildingDamageLevel.INTACT,
                occupancy_estimate=60,
            )

        # 4. Initial Drone Fleet (Ready at Base Alpha)
        self.drones["DRONE-S01"] = DroneEntity(
            id="DRONE-S01",
            callsign="Scout One (Fast Recon)",
            model_name="SkyRanger R70",
            capabilities=[DroneCapability.SCOUT, DroneCapability.INSPECTION],
            position=Vector3D(x=-10.0, y=0.0, z=-5.0),
            battery_percent=98.5,
            max_payload_kg=2.0,
            status=DroneStatus.IDLE,
            home_facility_id="BASE-ALPHA",
            last_telemetry_timestamp=time.time(),
        )
        self.drones["DRONE-M01"] = DroneEntity(
            id="DRONE-M01",
            callsign="MedEvac MedKit Carrier",
            model_name="Matrice 350 RTK - MedDrop",
            capabilities=[DroneCapability.MEDICAL, DroneCapability.SCOUT],
            position=Vector3D(x=0.0, y=0.0, z=-5.0),
            battery_percent=95.0,
            max_payload_kg=7.0,
            current_payload_kg=3.5,
            payload_type="EMERGENCY_TRAUMA_KIT",
            status=DroneStatus.IDLE,
            home_facility_id="BASE-ALPHA",
            last_telemetry_timestamp=time.time(),
        )
        self.drones["DRONE-H01"] = DroneEntity(
            id="DRONE-H01",
            callsign="Titan Heavy Lifter",
            model_name="Freefly Alta X",
            capabilities=[DroneCapability.HEAVY_LIFT, DroneCapability.RELAY],
            position=Vector3D(x=10.0, y=0.0, z=-5.0),
            battery_percent=92.0,
            max_payload_kg=15.0,
            current_payload_kg=0.0,
            payload_type="EXTRICATION_EQUIPMENT",
            status=DroneStatus.IDLE,
            home_facility_id="BASE-ALPHA",
            last_telemetry_timestamp=time.time(),
        )
        self.drones["DRONE-S02"] = DroneEntity(
            id="DRONE-S02",
            callsign="Inspector Secondary",
            model_name="Autel EVO II Dual 640T",
            capabilities=[DroneCapability.SCOUT, DroneCapability.INSPECTION],
            position=Vector3D(x=20.0, y=0.0, z=-5.0),
            battery_percent=100.0,
            max_payload_kg=1.5,
            status=DroneStatus.IDLE,
            home_facility_id="BASE-ALPHA",
            last_telemetry_timestamp=time.time(),
        )

    def increment_version(self):
        self.state_version += 1

    def update_drone_telemetry(self, packet: DroneTelemetryPacket):
        """Ingests live telemetry from Godot or Digital Twin simulation."""
        now = time.time()
        self.telemetry_packet_count += 1
        
        if packet.drone_id in self.drones:
            drone = self.drones[packet.drone_id]
            if packet.capabilities:
                drone.capabilities = packet.capabilities
            if packet.drone_type:
                drone.model_name = f"Godot {packet.drone_type}"
            drone.position = packet.position
            drone.velocity = packet.velocity
            drone.heading = packet.heading
            drone.battery_percent = max(0.0, min(100.0, packet.battery_percent))
            drone.battery_voltage = packet.battery_voltage
            drone.status = packet.status
            drone.current_mission_id = packet.mission_id
            drone.communication_quality = packet.communication_quality
            drone.last_telemetry_timestamp = now
            drone.uncertainty_state = UncertaintyState.CONFIRMED

            # Update mission progress if en route
            if drone.current_mission_id and drone.current_mission_id in self.missions:
                mission = self.missions[drone.current_mission_id]
                mission.current_waypoint_index = packet.current_waypoint_index
        else:
            # New drone registration
            self.drones[packet.drone_id] = DroneEntity(
                id=packet.drone_id,
                position=packet.position,
                capabilities=packet.capabilities or [DroneCapability.SCOUT],
                model_name=f"Godot {packet.drone_type}" if packet.drone_type else "Godot Digital Twin Drone",
                velocity=packet.velocity,
                heading=packet.heading,
                battery_percent=packet.battery_percent,
                status=packet.status,
                communication_quality=packet.communication_quality,
                last_telemetry_timestamp=now,
            )
        self.increment_version()

    def check_stale_telemetry(self, now: Optional[float] = None) -> int:
        """Flags drones as STALE if no telemetry received within timeout window."""
        if now is None:
            now = time.time()
        stale_count = 0
        timeout = settings.TELEMETRY_STALE_TIMEOUT_S
        
        for drone in self.drones.values():
            if drone.status != DroneStatus.IDLE and (now - drone.last_telemetry_timestamp) > timeout:
                if drone.uncertainty_state != UncertaintyState.STALE:
                    drone.uncertainty_state = UncertaintyState.STALE
                    drone.communication_quality = max(0.0, drone.communication_quality - 0.5)
                    stale_count += 1
                    self.increment_version()
        return stale_count

    def block_road_edge(self, edge_id: str, reason: str = "Debris from structural collapse") -> bool:
        if edge_id in self.road_edges:
            self.road_edges[edge_id].is_blocked = True
            self.road_edges[edge_id].blockage_reason = reason
            self.increment_version()
            return True
        return False

    def unblock_road_edge(self, edge_id: str) -> bool:
        if edge_id in self.road_edges:
            self.road_edges[edge_id].is_blocked = False
            self.road_edges[edge_id].blockage_reason = None
            self.increment_version()
            return True
        return False

    def get_snapshot(self) -> WorldStateSnapshot:
        now = time.time()
        stale_count = self.check_stale_telemetry(now)
        
        elapsed = max(0.1, now - self.telemetry_start_time)
        hz = round(self.telemetry_packet_count / elapsed, 1)
        if elapsed > 10.0:
            # Reset counters periodically for smooth rolling rate
            self.telemetry_packet_count = int(hz * 2)
            self.telemetry_start_time = now - 2.0

        return WorldStateSnapshot(
            session_id=self.session_id,
            simulation_time=self.simulation_time,
            state_version=self.state_version,
            system_b_connected=self.system_b_connected,
            system_b_session_id=self.system_b_session_id,
            drones=self.drones,
            victims=self.victims,
            hazards=self.hazards,
            incidents=self.incidents,
            buildings=self.buildings,
            road_nodes=self.road_nodes,
            road_edges=self.road_edges,
            facilities=self.facilities,
            environment=self.environment,
            telemetry_rate_hz=hz if self.system_b_connected else 0.0,
            command_latency_ms=self.command_latency_ms,
            stale_entities_count=stale_count,
        )


# Global singleton
world_state = WorldStateManager()
