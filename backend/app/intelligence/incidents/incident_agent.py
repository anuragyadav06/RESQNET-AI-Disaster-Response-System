"""
ResQNet Intelligence - Incident Detection & Hazard Management Agent
"""
import time
import uuid
from typing import Dict, List, Optional
from app.schemas.common import Vector3D, UncertaintyState
from app.schemas.incident import IncidentEntity, IncidentType, IncidentStatus
from app.schemas.world import HazardZone, HazardType, BuildingDamageLevel
from app.schemas.telemetry import ObservationPacket, ObservationType
from app.schemas.victim import Victim, VictimStatus, VictimHazardType, VictimEvidence
from app.schemas.audit import AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger
from app.intelligence.victims.prioritization_agent import prioritization_agent


class IncidentAgent:
    def __init__(self):
        pass

    async def process_observation(self, obs: ObservationPacket) -> Optional[IncidentEntity]:
        """Translates validated raw sensor observations into structured incidents and world entities."""
        now = time.time()
        
        if obs.type == ObservationType.VICTIM_LOCATED:
            # Check if victim already exists near location
            existing_vic = None
            for v in world_state.victims.values():
                if v.location.ground_distance_to(obs.location) < 10.0:
                    existing_vic = v
                    break
            
            if existing_vic:
                existing_vic.confidence = max(existing_vic.confidence, obs.confidence)
                existing_vic.captured_by_drone_id = obs.source_drone_id
                if obs.image_url or obs.image_base64:
                    existing_vic.evidence.image_url = obs.image_url or existing_vic.evidence.image_url
                    existing_vic.evidence.image_base64 = obs.image_base64 or existing_vic.evidence.image_base64
                    existing_vic.evidence.image_mime_type = obs.image_mime_type or existing_vic.evidence.image_mime_type
                    existing_vic.evidence.captured_at = obs.timestamp
                await prioritization_agent.prioritize_and_update(existing_vic)
                return None
            
            # Create new victim
            vic_id = f"VIC-{len(world_state.victims) + 101}"
            med_sev = obs.raw_reading.get("medical_severity", 0.7)
            urgency = obs.raw_reading.get("urgency", 0.75)
            people = obs.raw_reading.get("people_count", 1)
            hazard_raw = str(obs.raw_reading.get("hazard_type", "UNKNOWN")).upper()
            hazard_aliases = {"COLLAPSE": "STRUCTURAL_COLLAPSE", "STRUCTURAL COLLAPSE": "STRUCTURAL_COLLAPSE"}
            hazard_raw = hazard_aliases.get(hazard_raw, hazard_raw)
            try:
                hazard_type = VictimHazardType(hazard_raw)
            except ValueError:
                hazard_type = VictimHazardType.UNKNOWN
            image_url = obs.image_url or obs.raw_reading.get("image_url")
            image_base64 = obs.image_base64 or obs.raw_reading.get("image_base64")
            image_mime = obs.image_mime_type or obs.raw_reading.get("image_mime_type")
            new_vic = Victim(
                id=vic_id,
                name=f"Trapped Survivor ({vic_id})",
                location=obs.location,
                hazard_type=hazard_type,
                captured_by_drone_id=obs.source_drone_id,
                evidence=VictimEvidence(
                    image_url=image_url, image_base64=image_base64, image_mime_type=image_mime,
                    captured_at=obs.timestamp, capture_type="DRONE_CAMERA",
                    caption=f"Victim evidence captured by {obs.source_drone_id}"
                ),
                people_count=people,
                medical_severity=med_sev,
                estimated_survival_urgency=urgency,
                hazard_exposure=float(obs.raw_reading.get("hazard_exposure", 0.0)),
                confidence=obs.confidence,
                detected_at=now,
                notes=[f"Detected by {obs.source_drone_id}", f"Hazard: {hazard_type.value}"],
            )
            await prioritization_agent.prioritize_and_update(new_vic)
            
            # Create corresponding incident
            inc_id = f"INC-VIC-{vic_id}"
            incident = IncidentEntity(
                id=inc_id,
                type=IncidentType.TRAPPED_VICTIM,
                title=f"Trapped Victim: {vic_id}",
                location=obs.location,
                radius_m=10.0,
                severity=med_sev,
                confidence=obs.confidence,
                timestamp=now,
                evidence=[f"Thermal detection by {obs.source_drone_id}", f"Confidence {obs.confidence:.2f}"],
                affected_entities=[vic_id],
                status=IncidentStatus.ACTIVE,
                recommended_action=f"Dispatch medical or triage drone to {vic_id}",
            )
            world_state.incidents[inc_id] = incident
            world_state.increment_version()
            
            await audit_logger.log_event(
                event_type=AuditEventType.INCIDENT_DETECTED,
                decision=f"Incident {inc_id} detected: Trapped Victim",
                reason=f"High thermal signature confirmed by {obs.source_drone_id}",
                inputs={"location": obs.location.model_dump(), "confidence": obs.confidence},
                output={"incident_id": inc_id, "victim_id": vic_id, "severity": med_sev},
                confidence=obs.confidence,
                affected_entities=[inc_id, vic_id],
            )
            return incident

        elif obs.type == ObservationType.FIRE_DETECTED:
            hz_id = f"HAZ-FIRE-{uuid.uuid4().hex[:4]}"
            world_state.hazards[hz_id] = HazardZone(
                id=hz_id,
                type=HazardType.FIRE,
                center=obs.location,
                radius_m=obs.raw_reading.get("radius_m", 35.0),
                intensity=obs.raw_reading.get("intensity", 0.85),
            )
            
            inc_id = f"INC-FIRE-{uuid.uuid4().hex[:4]}"
            incident = IncidentEntity(
                id=inc_id,
                type=IncidentType.FIRE,
                title=f"Active Structural Fire ({obs.location.x:.0f}, {obs.location.z:.0f})",
                location=obs.location,
                radius_m=35.0,
                severity=0.85,
                confidence=obs.confidence,
                timestamp=now,
                evidence=[f"Smoke & thermal spike reported by {obs.source_drone_id}"],
                affected_entities=[hz_id],
                status=IncidentStatus.ACTIVE,
                recommended_action="Establish drone flight perimeter exclusion zone",
            )
            world_state.incidents[inc_id] = incident
            world_state.increment_version()
            
            await audit_logger.log_event(
                event_type=AuditEventType.HAZARD_SPAWNED,
                decision=f"Hazard {hz_id} (Fire) spawned and Incident {inc_id} declared",
                reason=f"Intense infrared radiation detected by {obs.source_drone_id}",
                output={"hazard_id": hz_id, "incident_id": inc_id},
                affected_entities=[hz_id, inc_id],
            )
            return incident

        elif obs.type == ObservationType.ROAD_IMPASSABLE:
            # Find closest road edge
            closest_edge_id = None
            min_dist = float("inf")
            for eid, edge in world_state.road_edges.items():
                n1 = world_state.road_nodes[edge.from_node]
                n2 = world_state.road_nodes[edge.to_node]
                mid_x = (n1.position.x + n2.position.x) / 2
                mid_z = (n1.position.z + n2.position.z) / 2
                mid = Vector3D(x=mid_x, y=0.0, z=mid_z)
                d = obs.location.ground_distance_to(mid)
                if d < min_dist:
                    min_dist = d
                    closest_edge_id = eid
            
            if closest_edge_id and min_dist < 60.0:
                world_state.block_road_edge(closest_edge_id, reason="Structural rubble blockage")
                inc_id = f"INC-BLOCK-{closest_edge_id}"
                incident = IncidentEntity(
                    id=inc_id,
                    type=IncidentType.ROAD_BLOCKAGE,
                    title=f"Road Impassable: {closest_edge_id}",
                    location=obs.location,
                    radius_m=20.0,
                    severity=0.75,
                    confidence=obs.confidence,
                    timestamp=now,
                    evidence=[f"Debris blockage identified by {obs.source_drone_id}"],
                    affected_entities=[closest_edge_id],
                    status=IncidentStatus.ACTIVE,
                    recommended_action="Reroute all surface operations and low-altitude ingress paths",
                )
                world_state.incidents[inc_id] = incident
                world_state.increment_version()
                
                await audit_logger.log_event(
                    event_type=AuditEventType.ROAD_BLOCKED,
                    decision=f"Road segment {closest_edge_id} marked BLOCKED",
                    reason="Structural debris impassable observation",
                    output={"edge_id": closest_edge_id, "incident_id": inc_id},
                    affected_entities=[closest_edge_id, inc_id],
                )
                return incident

        return None


incident_agent = IncidentAgent()
