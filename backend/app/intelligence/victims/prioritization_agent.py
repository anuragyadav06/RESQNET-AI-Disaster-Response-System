"""
ResQNet Intelligence - Explainable Multi-Criteria Victim Assessment

Single source of truth for:
- Overall operational severity
- Operational assessment confidence
- Priority score
- Priority class
- Explainable priority reasons

The assessment is deterministic and derived from:
- victim simulation state
- hazard exposure
- medical condition
- survival urgency
- accessibility
- observation confidence
- people count

IMPORTANT:
- This is NOT YOLO confidence.
- No random values are used.
- Overall severity is stored in victim.severity.
- Medical severity remains victim.medical_severity.
- Operational confidence is stored in victim.confidence.
"""


import time
from typing import List, Tuple

from app.schemas.victim import (
    Victim,
    VictimPriorityClass,
    VictimPriorityBreakdown,
    VictimStatus,
)
from app.schemas.audit import AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger


class VictimPrioritizationAgent:
    # ============================================================
    # PRIORITY WEIGHTS
    # ============================================================

    WEIGHT_MEDICAL = 0.25
    WEIGHT_URGENCY = 0.20
    WEIGHT_EXPOSURE = 0.20
    WEIGHT_STATE_RISK = 0.25
    WEIGHT_ACCESSIBILITY = 0.05
    WEIGHT_CONFIDENCE = 0.05

    # ============================================================
    # OPERATIONAL BOUNDS
    # ============================================================

    MIN_SEVERITY = 0.65
    MAX_SEVERITY = 0.80

    MIN_CONFIDENCE = 0.65
    MAX_CONFIDENCE = 0.80

    # ============================================================
    # HELPERS
    # ============================================================

    @staticmethod
    def _clamp(
        value: float,
        minimum: float,
        maximum: float,
    ) -> float:
        return max(
            minimum,
            min(maximum, float(value)),
        )

    @staticmethod
    def _status_text(victim: Victim) -> str:
        status = victim.status

        if isinstance(status, VictimStatus):
            return status.value.upper()

        return str(status).upper()

    @staticmethod
    def _hazard_text(victim: Victim) -> str:
        """
        Collect hazard information conservatively.

        Supports current schema and older simulation variants.
        """

        values: List[str] = []

        for field_name in (
            "hazard_type",
            "hazard",
            "incident_type",
            "environmental_hazard",
        ):
            value = getattr(victim, field_name, None)

            if value is not None:
                values.append(str(value).upper())

        return " ".join(values)

    # ============================================================
    # STATE RISK
    # ============================================================

    def _state_risk(
        self,
        victim: Victim,
    ) -> Tuple[float, str]:
        """
        Converts the victim's state and hazard into an operational
        risk factor.

        Higher value = greater immediate operational risk.
        """

        status = self._status_text(victim)
        hazard = self._hazard_text(victim)

        combined = f"{status} {hazard}"

        # --------------------------------------------------------
        # 1. Structural entrapment / collapse
        # --------------------------------------------------------

        if any(
            keyword in combined
            for keyword in (
                "TRAPPED",
                "ENTRAPPED",
                "ENTOMBED",
                "COLLAPSE",
                "STRUCTURAL",
                "CRUSH",
            )
        ):
            return (
                1.00,
                "Structural entrapment/collapse risk",
            )

        # --------------------------------------------------------
        # 2. Fire / smoke / gas
        # --------------------------------------------------------

        if any(
            keyword in combined
            for keyword in (
                "FIRE",
                "SMOKE",
                "GAS",
                "BURN",
            )
        ):
            return (
                0.90,
                "Fire/smoke exposure risk",
            )

        # --------------------------------------------------------
        # 3. Flood / water / stranded
        # --------------------------------------------------------

        if any(
            keyword in combined
            for keyword in (
                "FLOOD",
                "WATER",
                "STRANDED",
            )
        ):
            return (
                0.84,
                "Flood/stranding risk",
            )

        # --------------------------------------------------------
        # 4. Debris / rubble / blocked access
        # --------------------------------------------------------

        if any(
            keyword in combined
            for keyword in (
                "DEBRIS",
                "RUBBLE",
                "BLOCKED",
            )
        ):
            return (
                0.82,
                "Debris/crush/access risk",
            )

        # --------------------------------------------------------
        # 5. Detected / triaged / observed
        # --------------------------------------------------------

        if any(
            keyword in status
            for keyword in (
                "DETECTED",
                "TRIAGED",
                "OBSERVED",
            )
        ):
            return (
                0.60,
                "Detected survivor with no confirmed entrapment",
            )

        # --------------------------------------------------------
        # 6. Active response state
        # --------------------------------------------------------

        if any(
            keyword in status
            for keyword in (
                "EN_ROUTE",
                "ASSISTED",
            )
        ):
            return (
                0.55,
                "Victim already involved in response activity",
            )

        # --------------------------------------------------------
        # 7. Terminal / stabilized state
        # --------------------------------------------------------

        if any(
            keyword in status
            for keyword in (
                "RESCUED",
                "EVACUATED",
                "SAFE",
                "RESOLVED",
                "TREATED",
                "STABILIZED",
            )
        ):
            return (
                0.20,
                "Victim is in a terminal/stabilized state",
            )

        # --------------------------------------------------------
        # Default
        # --------------------------------------------------------

        return (
            0.60,
            "General survivor risk",
        )

    # ============================================================
    # SEVERITY
    # ============================================================

    def _calculate_severity(
        self,
        victim: Victim,
        state_risk: float,
    ) -> Tuple[float, List[str]]:
        """
        Calculates overall operational severity.

        Output is always bounded to 65%-80%.

        This is NOT medical severity.

        medical_severity:
            raw medical condition factor

        severity:
            overall operational severity
        """

        med = self._clamp(
            victim.medical_severity,
            0.0,
            1.0,
        )

        urg = self._clamp(
            victim.estimated_survival_urgency,
            0.0,
            1.0,
        )

        exp = self._clamp(
            victim.hazard_exposure,
            0.0,
            1.0,
        )

        # --------------------------------------------------------
        # Weighted severity model
        # --------------------------------------------------------

        raw_severity = (
            0.30 * med
            + 0.25 * urg
            + 0.20 * exp
            + 0.25 * state_risk
        )

        severity = (
            self.MIN_SEVERITY
            + raw_severity
            * (
                self.MAX_SEVERITY
                - self.MIN_SEVERITY
            )
        )

        # --------------------------------------------------------
        # Hazard/state floors
        #
        # Prevent obviously dangerous situations from appearing
        # artificially mild.
        # --------------------------------------------------------

        if state_risk >= 0.95:
            severity = max(
                severity,
                0.79,
            )

        elif state_risk >= 0.88:
            severity = max(
                severity,
                0.75,
            )

        elif state_risk >= 0.82:
            severity = max(
                severity,
                0.72,
            )

        severity = self._clamp(
            severity,
            self.MIN_SEVERITY,
            self.MAX_SEVERITY,
        )

        reasons: List[str] = []

        # --------------------------------------------------------
        # Explainability
        # --------------------------------------------------------

        if state_risk >= 0.95:
            reasons.append(
                "Structural entrapment/collapse significantly "
                "increases severity"
            )

        elif state_risk >= 0.88:
            reasons.append(
                "Fire/smoke exposure significantly increases severity"
            )

        elif state_risk >= 0.82:
            reasons.append(
                "Flood/debris/access hazard increases severity"
            )

        if med >= 0.75:
            reasons.append(
                "High medical severity"
            )

        elif med >= 0.50:
            reasons.append(
                "Moderate medical severity"
            )

        if urg >= 0.70:
            reasons.append(
                "High survival urgency"
            )

        elif urg >= 0.45:
            reasons.append(
                "Moderate survival urgency"
            )

        if exp >= 0.60:
            reasons.append(
                "Significant environmental hazard exposure"
            )

        elif exp >= 0.35:
            reasons.append(
                "Moderate environmental hazard exposure"
            )

        reasons.append(
            "Operational severity bounded to "
            f"{self.MIN_SEVERITY:.0%}-"
            f"{self.MAX_SEVERITY:.0%}"
        )

        return (
            round(severity, 4),
            reasons,
        )

    # ============================================================
    # OBSERVATION CONFIDENCE
    # ============================================================

    def _get_observation_confidence(
        self,
        victim: Victim,
    ) -> float:
        """
        Returns the original observation/evidence confidence.

        If the schema has observation_confidence, use it.

        Otherwise fall back to the current confidence value only
        when it appears to be an externally supplied value.

        The calculated operational confidence itself must NOT be
        recursively fed back into the next calculation.
        """

        observation_confidence = getattr(
            victim,
            "observation_confidence",
            None,
        )

        if observation_confidence is not None:
            return self._clamp(
                observation_confidence,
                0.0,
                1.0,
            )

        # Compatibility fallback.
        #
        # This prevents crashes if observation_confidence has not
        # yet been added to the schema.
        return self._clamp(
            getattr(victim, "confidence", 0.65),
            0.0,
            1.0,
        )

    # ============================================================
    # OPERATIONAL CONFIDENCE
    # ============================================================

    def _calculate_confidence(
        self,
        victim: Victim,
        state_risk: float,
    ) -> Tuple[float, List[str]]:
        """
        Calculates RESQNET operational assessment confidence.

        IMPORTANT:
        This is NOT YOLO confidence.

        It represents confidence in the operational assessment
        based on consistency between:
        - observation/evidence
        - medical information
        - survival urgency
        - hazard exposure
        - accessibility
        - explicit victim state
        """

        med = self._clamp(
            victim.medical_severity,
            0.0,
            1.0,
        )

        urg = self._clamp(
            victim.estimated_survival_urgency,
            0.0,
            1.0,
        )

        exp = self._clamp(
            victim.hazard_exposure,
            0.0,
            1.0,
        )

        acc = self._clamp(
            victim.accessibility_factor,
            0.0,
            1.0,
        )

        observation_confidence = (
            self._get_observation_confidence(victim)
        )

        # --------------------------------------------------------
        # Evidence quality
        # --------------------------------------------------------

        accessibility_quality = (
            1.0 - abs(0.5 - acc)
        )

        evidence_quality = (
            0.30 * observation_confidence
            + 0.20 * med
            + 0.20 * urg
            + 0.15 * exp
            + 0.15 * accessibility_quality
        )

        # --------------------------------------------------------
        # Scale into 65%-80%
        # --------------------------------------------------------

        confidence = (
            self.MIN_CONFIDENCE
            + evidence_quality
            * (
                self.MAX_CONFIDENCE
                - self.MIN_CONFIDENCE
            )
        )

        # Explicit state classifications provide a small amount
        # of additional certainty.
        if state_risk >= 0.95:
            confidence += 0.015

        elif state_risk >= 0.88:
            confidence += 0.010

        confidence = self._clamp(
            confidence,
            self.MIN_CONFIDENCE,
            self.MAX_CONFIDENCE,
        )

        reasons: List[str] = [
            "Assessment confidence uses observation evidence, "
            "medical indicators, urgency, hazard exposure, "
            "accessibility and explicit victim state"
        ]

        if observation_confidence < 0.70:
            reasons.append(
                "Lower observation confidence limits assessment certainty"
            )

        elif observation_confidence >= 0.80:
            reasons.append(
                "Strong observation evidence supports the assessment"
            )

        if acc < 0.40:
            reasons.append(
                "Limited accessibility reduces evidence certainty"
            )

        elif acc >= 0.75:
            reasons.append(
                "Good accessibility improves assessment consistency"
            )

        if state_risk >= 0.88:
            reasons.append(
                "Explicit high-risk state provides strong "
                "operational context"
            )

        reasons.append(
            "Operational confidence bounded to "
            f"{self.MIN_CONFIDENCE:.0%}-"
            f"{self.MAX_CONFIDENCE:.0%}"
        )

        return (
            round(confidence, 4),
            reasons,
        )

    # ============================================================
    # PRIORITY SCORE
    # ============================================================

    def _calculate_priority_score(
        self,
        victim: Victim,
        state_risk: float,
        confidence: float,
    ) -> float:
        """
        Calculates the final deterministic priority score.

        Lower accessibility = higher rescue priority.
        """

        med = self._clamp(
            victim.medical_severity,
            0.0,
            1.0,
        )

        urg = self._clamp(
            victim.estimated_survival_urgency,
            0.0,
            1.0,
        )

        exp = self._clamp(
            victim.hazard_exposure,
            0.0,
            1.0,
        )

        acc = self._clamp(
            victim.accessibility_factor,
            0.0,
            1.0,
        )

        access_risk = 1.0 - acc

        # Small bounded site-level bonus.
        people_bonus = min(
            0.05,
            max(
                0.0,
                (victim.people_count - 1) * 0.02,
            ),
        )

        score = (
            self.WEIGHT_MEDICAL * med
            + self.WEIGHT_URGENCY * urg
            + self.WEIGHT_EXPOSURE * exp
            + self.WEIGHT_STATE_RISK * state_risk
            + self.WEIGHT_ACCESSIBILITY * access_risk
            + self.WEIGHT_CONFIDENCE * confidence
            + people_bonus
        )

        return round(
            self._clamp(
                score,
                0.0,
                1.0,
            ),
            4,
        )

    # ============================================================
    # FULL ASSESSMENT
    # ============================================================

    def assess_victim(
        self,
        victim: Victim,
    ) -> Tuple[
        float,
        float,
        float,
        str,
        List[str],
    ]:
        """
        Returns:

        severity
        operational confidence
        priority score
        state basis
        assessment reasons
        """

        state_risk, state_basis = self._state_risk(
            victim
        )

        severity, severity_reasons = (
            self._calculate_severity(
                victim,
                state_risk,
            )
        )

        confidence, confidence_reasons = (
            self._calculate_confidence(
                victim,
                state_risk,
            )
        )

        priority_score = (
            self._calculate_priority_score(
                victim,
                state_risk,
                confidence,
            )
        )

        reasons: List[str] = []

        reasons.extend(
            severity_reasons
        )

        reasons.extend(
            confidence_reasons
        )

        reasons.append(
            f"State basis: {state_basis}"
        )

        return (
            severity,
            confidence,
            priority_score,
            state_basis,
            reasons,
        )

    # ============================================================
    # PRIORITY BREAKDOWN
    # ============================================================

    def evaluate_victim(
        self,
        victim: Victim,
    ) -> VictimPriorityBreakdown:
        """
        Calculate the complete deterministic priority breakdown.

        IMPORTANT:
        This method uses the SAME values as assess_victim().

        It does not independently invent another assessment.
        """

        state_risk, state_basis = (
            self._state_risk(victim)
        )

        severity, severity_reasons = (
            self._calculate_severity(
                victim,
                state_risk,
            )
        )

        confidence, confidence_reasons = (
            self._calculate_confidence(
                victim,
                state_risk,
            )
        )

        med = self._clamp(
            victim.medical_severity,
            0.0,
            1.0,
        )

        urg = self._clamp(
            victim.estimated_survival_urgency,
            0.0,
            1.0,
        )

        exp = self._clamp(
            victim.hazard_exposure,
            0.0,
            1.0,
        )

        acc = self._clamp(
            victim.accessibility_factor,
            0.0,
            1.0,
        )

        access_risk = 1.0 - acc

        final_score = (
            self._calculate_priority_score(
                victim,
                state_risk,
                confidence,
            )
        )

        reasons: List[str] = []

        reasons.extend(
            severity_reasons
        )

        reasons.extend(
            confidence_reasons
        )

        reasons.append(
            f"State basis: {state_basis}"
        )

        if state_risk >= 0.95:
            reasons.append(
                "State risk is critical because the victim is "
                "structurally trapped/entombed"
            )

        elif state_risk >= 0.88:
            reasons.append(
                "State risk is high because of fire/smoke exposure"
            )

        elif state_risk >= 0.82:
            reasons.append(
                "State risk is high because of flood/debris/access hazard"
            )

        if access_risk >= 0.60:
            reasons.append(
                f"Accessibility risk is high ({access_risk:.2f})"
            )

        elif access_risk <= 0.25:
            reasons.append(
                "Victim is relatively accessible"
            )

        if victim.people_count > 1:
            reasons.append(
                f"Multiple individuals at site "
                f"({victim.people_count}) add a bounded priority bonus"
            )

        reasons.append(
            f"Priority score combines medical({med:.2f}), "
            f"urgency({urg:.2f}), exposure({exp:.2f}), "
            f"state-risk({state_risk:.2f}), "
            f"access-risk({access_risk:.2f}), "
            f"confidence({confidence:.2f})"
        )

        return VictimPriorityBreakdown(
            medical_severity_weight=self.WEIGHT_MEDICAL,
            urgency_weight=self.WEIGHT_URGENCY,
            exposure_weight=self.WEIGHT_EXPOSURE,
            state_risk_weight=self.WEIGHT_STATE_RISK,
            accessibility_weight=self.WEIGHT_ACCESSIBILITY,
            confidence_weight=self.WEIGHT_CONFIDENCE,

            raw_medical_severity=med,
            raw_urgency=urg,
            raw_exposure=exp,
            raw_state_risk=state_risk,
            raw_accessibility=acc,
            raw_confidence=confidence,

            calculated_score=final_score,

            reasons=reasons,
        )

    # ============================================================
    # PRIORITY CLASS
    # ============================================================

    def determine_class(
        self,
        score: float,
    ) -> VictimPriorityClass:
        """
        Priority thresholds:

        CRITICAL >= 0.78
        HIGH     >= 0.65
        MEDIUM   >= 0.50
        LOW      <  0.50
        """

        if score >= 0.78:
            return VictimPriorityClass.CRITICAL

        if score >= 0.65:
            return VictimPriorityClass.HIGH

        if score >= 0.50:
            return VictimPriorityClass.MEDIUM

        return VictimPriorityClass.LOW

    # ============================================================
    # UPDATE VICTIM
    # ============================================================

    async def prioritize_and_update(
        self,
        victim: Victim,
    ) -> Victim:
        """
        Recalculate and persist the complete victim assessment.

        This is the backend single source of truth.

        Frontend, WebSocket and API consumers should use these
        stored values instead of recalculating them independently.
        """

        previous_class = victim.priority_class

        # --------------------------------------------------------
        # Calculate everything from the same source inputs
        # --------------------------------------------------------

        severity, confidence, priority_score, _, _ = (
            self.assess_victim(victim)
        )

        # --------------------------------------------------------
        # Store operational values
        # --------------------------------------------------------

        # IMPORTANT:
        # Do NOT write severity into medical_severity.
        victim.severity = severity

        # confidence is the derived operational assessment
        # confidence.
        victim.confidence = confidence

        victim.priority_score = priority_score

        victim.priority_class = (
            self.determine_class(
                priority_score
            )
        )

        # --------------------------------------------------------
        # Breakdown
        # --------------------------------------------------------

        victim.breakdown = (
            self.evaluate_victim(victim)
        )

        # Keep breakdown score exactly synchronized.
        victim.priority_score = (
            victim.breakdown.calculated_score
        )

        victim.priority_class = (
            self.determine_class(
                victim.priority_score
            )
        )

        victim.last_updated_at = time.time()

        # --------------------------------------------------------
        # Audit trail
        # --------------------------------------------------------

        if previous_class != victim.priority_class:
            await audit_logger.log_event(
                event_type=AuditEventType.VICTIM_PRIORITIZED,

                decision=(
                    f"Victim {victim.id} prioritized as "
                    f"{victim.priority_class.value} "
                    f"(Score: "
                    f"{victim.priority_score:.4f})"
                ),

                reason=(
                    "; ".join(
                        victim.breakdown.reasons
                    )
                    or "Multi-criteria assessment recalculated"
                ),

                inputs={
                    "medical_severity": (
                        victim.medical_severity
                    ),
                    "overall_severity": (
                        victim.severity
                    ),
                    "urgency": (
                        victim.estimated_survival_urgency
                    ),
                    "exposure": (
                        victim.hazard_exposure
                    ),
                    "state_risk": (
                        victim.breakdown.raw_state_risk
                    ),
                    "accessibility": (
                        victim.accessibility_factor
                    ),
                    "observation_confidence": (
                        self._get_observation_confidence(
                            victim
                        )
                    ),
                    "operational_confidence": (
                        victim.confidence
                    ),
                    "people": (
                        victim.people_count
                    ),
                },

                output={
                    "severity": victim.severity,
                    "confidence": victim.confidence,
                    "score": victim.priority_score,
                    "class": victim.priority_class.value,
                },

                confidence=victim.confidence,

                affected_entities=[
                    victim.id
                ],
            )

        # --------------------------------------------------------
        # Persist into world state
        # --------------------------------------------------------

        world_state.victims[
            victim.id
        ] = victim

        world_state.increment_version()

        return victim

    # ============================================================
    # PRIORITIZE ALL
    # ============================================================

    async def prioritize_all(
        self,
    ) -> List[Victim]:
        """
        Reassess every victim using the same deterministic engine.
        """

        updated: List[Victim] = []

        for victim in list(
            world_state.victims.values()
        ):
            updated_victim = (
                await self.prioritize_and_update(
                    victim
                )
            )

            updated.append(
                updated_victim
            )

        updated.sort(
            key=lambda x: x.priority_score,
            reverse=True,
        )

        return updated


# ================================================================
# SINGLETON
# ================================================================

prioritization_agent = VictimPrioritizationAgent()