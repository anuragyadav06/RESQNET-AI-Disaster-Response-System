"""
ResQNet Intelligence - Incident Detection & Hazard Management Agent

Responsible for translating validated observations into:
- Incidents
- Hazards
- Victims
- Victim evidence

Victim severity, operational confidence and priority are NOT
calculated here.

Those values are calculated by VictimPrioritizationAgent,
which remains the single source of truth.
"""

import time
import uuid
from typing import Optional

from app.schemas.common import Vector3D
from app.schemas.incident import (
    IncidentEntity,
    IncidentType,
    IncidentStatus,
)
from app.schemas.world import (
    HazardZone,
    HazardType,
)
from app.schemas.telemetry import (
    ObservationPacket,
    ObservationType,
)
from app.schemas.victim import (
    Victim,
    VictimStatus,
    VictimHazardType,
    VictimEvidence,
)
from app.schemas.audit import AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger
from app.intelligence.victims.prioritization_agent import (
    prioritization_agent,
)


class IncidentAgent:
    def __init__(self):
        pass

    # ============================================================
    # SAFE NUMERIC HELPER
    # ============================================================

    @staticmethod
    def _safe_float(
        value,
        default: float,
        minimum: float = 0.0,
        maximum: float = 1.0,
    ) -> float:
        """
        Safely convert observation values into bounded floats.
        """

        try:
            result = float(value)
        except (TypeError, ValueError):
            result = default

        return max(
            minimum,
            min(maximum, result),
        )

    @staticmethod
    def _safe_int(
        value,
        default: int,
        minimum: int = 1,
    ) -> int:
        """
        Safely convert people_count into an integer.
        """

        try:
            result = int(value)
        except (TypeError, ValueError):
            result = default

        return max(
            minimum,
            result,
        )

    # ============================================================
    # HAZARD NORMALIZATION
    # ============================================================

    @staticmethod
    def _parse_victim_hazard(
        raw_hazard,
    ) -> VictimHazardType:
        """
        Normalize simulation/observation hazard names into the
        VictimHazardType enum.
        """

        hazard_raw = str(
            raw_hazard or "UNKNOWN"
        ).strip().upper()

        hazard_aliases = {
            "COLLAPSE": "STRUCTURAL_COLLAPSE",
            "STRUCTURAL COLLAPSE": "STRUCTURAL_COLLAPSE",
            "STRUCTURAL": "STRUCTURAL_COLLAPSE",
            "RUBBLE": "DEBRIS",
            "WATER": "FLOOD",
            "BURN": "FIRE",
            "GAS": "GAS_LEAK",
        }

        hazard_raw = hazard_aliases.get(
            hazard_raw,
            hazard_raw,
        )

        try:
            return VictimHazardType(
                hazard_raw
            )
        except ValueError:
            return VictimHazardType.UNKNOWN

    # ============================================================
    # VICTIM LOCATED
    # ============================================================

    async def _process_victim_observation(
        self,
        obs: ObservationPacket,
        now: float,
    ) -> Optional[IncidentEntity]:
        """
        Process a victim-location observation.

        Creates or updates a victim and then sends it through the
        centralized VictimPrioritizationAgent.
        """

        # --------------------------------------------------------
        # Find an existing victim near this observation
        # --------------------------------------------------------

        existing_vic = None

        for victim in world_state.victims.values():
            if (
                victim.location.ground_distance_to(
                    obs.location
                )
                < 10.0
            ):
                existing_vic = victim
                break

        # --------------------------------------------------------
        # Extract observation inputs
        # --------------------------------------------------------

        raw_reading = obs.raw_reading or {}

        observation_confidence = self._safe_float(
            obs.confidence,
            default=0.70,
            minimum=0.0,
            maximum=1.0,
        )

        medical_severity = self._safe_float(
            raw_reading.get(
                "medical_severity",
                0.70,
            ),
            default=0.70,
        )

        urgency = self._safe_float(
            raw_reading.get(
                "urgency",
                raw_reading.get(
                    "estimated_survival_urgency",
                    0.75,
                ),
            ),
            default=0.75,
        )

        hazard_exposure = self._safe_float(
            raw_reading.get(
                "hazard_exposure",
                0.60,
            ),
            default=0.60,
        )

        accessibility = self._safe_float(
            raw_reading.get(
                "accessibility_factor",
                raw_reading.get(
                    "accessibility",
                    0.50,
                ),
            ),
            default=0.50,
        )

        people_count = self._safe_int(
            raw_reading.get(
                "people_count",
                1,
            ),
            default=1,
        )

        hazard_type = self._parse_victim_hazard(
            raw_reading.get(
                "hazard_type",
                "UNKNOWN",
            )
        )

        # --------------------------------------------------------
        # Evidence
        # --------------------------------------------------------

        image_url = (
            obs.image_url
            or raw_reading.get("image_url")
        )

        image_base64 = (
            obs.image_base64
            or raw_reading.get("image_base64")
        )

        image_mime = (
            obs.image_mime_type
            or raw_reading.get("image_mime_type")
        )

        # ========================================================
        # UPDATE EXISTING VICTIM
        # ========================================================

        if existing_vic:

            # Preserve the original observation confidence if the
            # schema supports it. New observations can improve it.
            if hasattr(
                existing_vic,
                "observation_confidence",
            ):
                previous_observation_confidence = (
                    getattr(
                        existing_vic,
                        "observation_confidence",
                        0.0,
                    )
                )

                existing_vic.observation_confidence = max(
                    previous_observation_confidence,
                    observation_confidence,
                )

            # Update stable raw assessment inputs from the newest
            # validated observation.
            existing_vic.medical_severity = (
                medical_severity
            )

            existing_vic.estimated_survival_urgency = (
                urgency
            )

            existing_vic.hazard_exposure = (
                hazard_exposure
            )

            existing_vic.accessibility_factor = (
                accessibility
            )

            existing_vic.people_count = (
                people_count
            )

            # Only update hazard when a useful value was supplied.
            if hazard_type != VictimHazardType.UNKNOWN:
                existing_vic.hazard_type = (
                    hazard_type
                )

            existing_vic.captured_by_drone_id = (
                obs.source_drone_id
            )

            # ----------------------------------------------------
            # Evidence update
            # ----------------------------------------------------

            if (
                image_url
                or image_base64
                or image_mime
            ):
                existing_vic.evidence.image_url = (
                    image_url
                    or existing_vic.evidence.image_url
                )

                existing_vic.evidence.image_base64 = (
                    image_base64
                    or existing_vic.evidence.image_base64
                )

                existing_vic.evidence.image_mime_type = (
                    image_mime
                    or existing_vic.evidence.image_mime_type
                )

                existing_vic.evidence.captured_at = (
                    obs.timestamp
                )

            existing_vic.last_updated_at = now

            # ----------------------------------------------------
            # Recalculate EVERYTHING from the same source inputs.
            # ----------------------------------------------------

            await prioritization_agent.prioritize_and_update(
                existing_vic
            )

            return None

        # ========================================================
        # CREATE NEW VICTIM
        # ========================================================

        victim_id = str(
            raw_reading.get("victim_id")
            or f"VIC-{len(world_state.victims) + 101}"
        )

        # --------------------------------------------------------
        # Create victim
        # --------------------------------------------------------

        victim_kwargs = dict(
            id=victim_id,
            name=f"Trapped Survivor ({victim_id})",
            location=obs.location,
            hazard_type=hazard_type,
            captured_by_drone_id=obs.source_drone_id,

            evidence=VictimEvidence(
                image_url=image_url,
                image_base64=image_base64,
                image_mime_type=image_mime,
                captured_at=obs.timestamp,
                capture_type="DRONE_CAMERA",
                caption=(
                    f"Victim evidence captured by "
                    f"{obs.source_drone_id}"
                ),
            ),

            people_count=people_count,

            # RAW medical factor.
            medical_severity=medical_severity,

            # RAW urgency factor.
            estimated_survival_urgency=urgency,

            # RAW environmental exposure factor.
            hazard_exposure=hazard_exposure,

            # RAW accessibility factor.
            #
            # Higher accessibility = easier to reach.
            # The prioritization engine inverts this for priority.
            accessibility_factor=accessibility,

            detected_at=now,
            last_updated_at=now,

            status=VictimStatus.DETECTED,

            notes=[
                f"Detected by {obs.source_drone_id}",
                f"Hazard: {hazard_type.value}",
            ],
        )

        # --------------------------------------------------------
        # IMPORTANT:
        #
        # New schema should have observation_confidence.
        # It stores the ORIGINAL observation confidence.
        #
        # Operational victim.confidence is calculated later by
        # VictimPrioritizationAgent and remains 65%-80%.
        # --------------------------------------------------------

        if hasattr(
            Victim,
            "model_fields",
        ) and "observation_confidence" in Victim.model_fields:
            victim_kwargs[
                "observation_confidence"
            ] = observation_confidence

        new_victim = Victim(
            **victim_kwargs
        )

        # ========================================================
        # SINGLE SOURCE OF TRUTH
        # ========================================================

        await prioritization_agent.prioritize_and_update(
            new_victim
        )

        # ========================================================
        # CREATE CORRESPONDING INCIDENT
        # ========================================================

        incident_id = (
            f"INC-VIC-{victim_id}"
        )

        incident = IncidentEntity(
            id=incident_id,
            type=IncidentType.TRAPPED_VICTIM,
            title=f"Trapped Victim: {victim_id}",
            location=obs.location,
            radius_m=10.0,

            # Incident keeps the raw medical severity as its
            # incident-level medical indicator.
            severity=new_victim.severity,

            confidence=new_victim.confidence,

            timestamp=now,

            evidence=[
                (
                    f"Thermal detection by "
                    f"{obs.source_drone_id}"
                ),
                (
                    f"Observation confidence "
                    f"{observation_confidence:.2f}"
                ),
            ],

            affected_entities=[
                victim_id
            ],

            status=IncidentStatus.ACTIVE,

            recommended_action=(
                f"Dispatch medical or triage drone "
                f"to {victim_id}"
            ),
        )

        world_state.incidents[
            incident_id
        ] = incident

        world_state.increment_version()

        # ========================================================
        # AUDIT
        # ========================================================

        await audit_logger.log_event(
            event_type=AuditEventType.INCIDENT_DETECTED,

            decision=(
                f"Incident {incident_id} detected: "
                f"Trapped Victim"
            ),

            reason=(
                f"High thermal signature confirmed by "
                f"{obs.source_drone_id}"
            ),

            inputs={
                "location": (
                    obs.location.model_dump()
                ),
                "observation_confidence": (
                    observation_confidence
                ),
                "medical_severity": (
                    medical_severity
                ),
                "urgency": (
                    urgency
                ),
                "hazard_exposure": (
                    hazard_exposure
                ),
                "accessibility": (
                    accessibility
                ),
                "people_count": (
                    people_count
                ),
                "hazard_type": (
                    hazard_type.value
                ),
            },

            output={
                "incident_id": incident_id,
                "victim_id": victim_id,

                # These are the FINAL backend values after
                # prioritization.
                "severity": new_victim.severity,
                "confidence": new_victim.confidence,
                "priority_score": (
                    new_victim.priority_score
                ),
                "priority_class": (
                    new_victim.priority_class.value
                ),
            },

            confidence=observation_confidence,

            affected_entities=[
                incident_id,
                victim_id,
            ],
        )

        return incident

    # ============================================================
    # MAIN OBSERVATION PROCESSOR
    # ============================================================

    async def process_observation(
        self,
        obs: ObservationPacket,
    ) -> Optional[IncidentEntity]:
        """
        Translates validated raw sensor observations into
        structured incidents and world entities.
        """

        now = time.time()

        # ========================================================
        # VICTIM
        # ========================================================

        if obs.type == ObservationType.VICTIM_LOCATED:
            return await self._process_victim_observation(
                obs,
                now,
            )

        # ========================================================
        # FIRE
        # ========================================================

        elif obs.type == ObservationType.FIRE_DETECTED:

            hazard_id = (
                f"HAZ-FIRE-"
                f"{uuid.uuid4().hex[:4]}"
            )

            world_state.hazards[
                hazard_id
            ] = HazardZone(
                id=hazard_id,
                type=HazardType.FIRE,
                center=obs.location,
                radius_m=self._safe_float(
                    obs.raw_reading.get(
                        "radius_m",
                        35.0,
                    ),
                    default=35.0,
                    minimum=1.0,
                    maximum=500.0,
                ),
                intensity=self._safe_float(
                    obs.raw_reading.get(
                        "intensity",
                        0.85,
                    ),
                    default=0.85,
                ),
            )

            incident_id = (
                f"INC-FIRE-"
                f"{uuid.uuid4().hex[:4]}"
            )

            incident = IncidentEntity(
                id=incident_id,
                type=IncidentType.FIRE,

                title=(
                    f"Active Structural Fire "
                    f"({obs.location.x:.0f}, "
                    f"{obs.location.z:.0f})"
                ),

                location=obs.location,
                radius_m=35.0,
                severity=0.85,
                confidence=obs.confidence,
                timestamp=now,

                evidence=[
                    (
                        f"Smoke & thermal spike reported by "
                        f"{obs.source_drone_id}"
                    )
                ],

                affected_entities=[
                    hazard_id
                ],

                status=IncidentStatus.ACTIVE,

                recommended_action=(
                    "Establish drone flight perimeter "
                    "exclusion zone"
                ),
            )

            world_state.incidents[
                incident_id
            ] = incident

            world_state.increment_version()

            await audit_logger.log_event(
                event_type=AuditEventType.HAZARD_SPAWNED,

                decision=(
                    f"Hazard {hazard_id} (Fire) spawned "
                    f"and Incident {incident_id} declared"
                ),

                reason=(
                    f"Intense infrared radiation detected by "
                    f"{obs.source_drone_id}"
                ),

                output={
                    "hazard_id": hazard_id,
                    "incident_id": incident_id,
                },

                affected_entities=[
                    hazard_id,
                    incident_id,
                ],
            )

            return incident

        # ========================================================
        # ROAD IMPASSABLE
        # ========================================================

        elif obs.type == ObservationType.ROAD_IMPASSABLE:

            closest_edge_id = None
            min_dist = float("inf")

            for edge_id, edge in (
                world_state.road_edges.items()
            ):

                node_a = world_state.road_nodes[
                    edge.from_node
                ]

                node_b = world_state.road_nodes[
                    edge.to_node
                ]

                mid_x = (
                    node_a.position.x
                    + node_b.position.x
                ) / 2

                mid_z = (
                    node_a.position.z
                    + node_b.position.z
                ) / 2

                midpoint = Vector3D(
                    x=mid_x,
                    y=0.0,
                    z=mid_z,
                )

                distance = (
                    obs.location.ground_distance_to(
                        midpoint
                    )
                )

                if distance < min_dist:
                    min_dist = distance
                    closest_edge_id = edge_id

            if (
                closest_edge_id
                and min_dist < 60.0
            ):

                world_state.block_road_edge(
                    closest_edge_id,
                    reason=(
                        "Structural rubble blockage"
                    ),
                )

                incident_id = (
                    f"INC-BLOCK-{closest_edge_id}"
                )

                incident = IncidentEntity(
                    id=incident_id,
                    type=IncidentType.ROAD_BLOCKAGE,

                    title=(
                        f"Road Impassable: "
                        f"{closest_edge_id}"
                    ),

                    location=obs.location,
                    radius_m=20.0,
                    severity=0.75,
                    confidence=obs.confidence,
                    timestamp=now,

                    evidence=[
                        (
                            f"Debris blockage identified by "
                            f"{obs.source_drone_id}"
                        )
                    ],

                    affected_entities=[
                        closest_edge_id
                    ],

                    status=IncidentStatus.ACTIVE,

                    recommended_action=(
                        "Reroute all surface operations and "
                        "low-altitude ingress paths"
                    ),
                )

                world_state.incidents[
                    incident_id
                ] = incident

                world_state.increment_version()

                await audit_logger.log_event(
                    event_type=AuditEventType.ROAD_BLOCKED,

                    decision=(
                        f"Road segment "
                        f"{closest_edge_id} marked BLOCKED"
                    ),

                    reason=(
                        "Structural debris impassable "
                        "observation"
                    ),

                    output={
                        "edge_id": closest_edge_id,
                        "incident_id": incident_id,
                    },

                    affected_entities=[
                        closest_edge_id,
                        incident_id,
                    ],
                )

                return incident

        return None


# ================================================================
# SINGLETON
# ================================================================

incident_agent = IncidentAgent()