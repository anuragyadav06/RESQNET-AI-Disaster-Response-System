"""
ResQNet Intelligence - Explainable Multi-Criteria Victim Prioritization Agent
"""
import time
from typing import Dict, List, Optional, Tuple
from app.schemas.victim import Victim, VictimPriorityClass, VictimPriorityBreakdown, VictimStatus
from app.schemas.audit import AuditEventType
from app.state.world_state import world_state
from app.audit.audit_logger import audit_logger


class VictimPrioritizationAgent:
    WEIGHT_MEDICAL = 0.35
    WEIGHT_URGENCY = 0.25
    WEIGHT_EXPOSURE = 0.20
    WEIGHT_ACCESSIBILITY = 0.10
    WEIGHT_CONFIDENCE = 0.10

    def evaluate_victim(self, victim: Victim) -> VictimPriorityBreakdown:
        """Calculates deterministic explainable priority score and reason trace."""
        # 1. Base linear combination
        med = max(0.0, min(1.0, victim.medical_severity))
        urg = max(0.0, min(1.0, victim.estimated_survival_urgency))
        exp = max(0.0, min(1.0, victim.hazard_exposure))
        acc = max(0.0, min(1.0, victim.accessibility_factor))
        conf = max(0.0, min(1.0, victim.confidence))

        base_score = (
            self.WEIGHT_MEDICAL * med
            + self.WEIGHT_URGENCY * urg
            + self.WEIGHT_EXPOSURE * exp
            + self.WEIGHT_ACCESSIBILITY * (1.0 - (1.0 - acc) * 0.5)
            + self.WEIGHT_CONFIDENCE * conf
        )

        # People count boost (+2% per additional person, max +10%)
        people_bonus = min(0.10, max(0.0, (victim.people_count - 1) * 0.02))
        final_score = max(0.0, min(1.0, base_score + people_bonus))

        # Compile explainable factor reasons
        reasons: List[str] = []
        if med >= 0.75:
            reasons.append(f"Severe medical trauma requiring immediate life support ({med:.2f})")
        elif med >= 0.5:
            reasons.append(f"Moderate injuries requiring field stabilization ({med:.2f})")
        
        if urg >= 0.70:
            reasons.append(f"High survival urgency; rapid golden-hour window ({urg:.2f})")
        
        if exp >= 0.60:
            reasons.append(f"Imminent hazard exposure from fire/collapse plume ({exp:.2f})")
        elif exp >= 0.30:
            reasons.append(f"Moderate environmental hazard proximity ({exp:.2f})")
            
        if acc < 0.40:
            reasons.append(f"Severely trapped/entombed; heavy extrication payload required ({acc:.2f})")
        
        if victim.people_count > 1:
            reasons.append(f"Multiple individuals trapped at site ({victim.people_count} people)")

        if conf < 0.70:
            reasons.append(f"Observation confidence degraded; sensor uncertainty ({conf:.2f})")

        return VictimPriorityBreakdown(
            medical_severity_weight=self.WEIGHT_MEDICAL,
            urgency_weight=self.WEIGHT_URGENCY,
            exposure_weight=self.WEIGHT_EXPOSURE,
            accessibility_weight=self.WEIGHT_ACCESSIBILITY,
            confidence_weight=self.WEIGHT_CONFIDENCE,
            raw_medical_severity=med,
            raw_urgency=urg,
            raw_exposure=exp,
            raw_accessibility=acc,
            raw_confidence=conf,
            calculated_score=round(final_score, 4),
            reasons=reasons,
        )

    def determine_class(self, score: float) -> VictimPriorityClass:
        if score >= 0.75:
            return VictimPriorityClass.CRITICAL
        elif score >= 0.55:
            return VictimPriorityClass.HIGH
        elif score >= 0.35:
            return VictimPriorityClass.MEDIUM
        else:
            return VictimPriorityClass.LOW

    async def prioritize_and_update(self, victim: Victim) -> Victim:
        breakdown = self.evaluate_victim(victim)
        prev_class = victim.priority_class
        
        victim.breakdown = breakdown
        victim.priority_score = breakdown.calculated_score
        victim.priority_class = self.determine_class(victim.priority_score)
        victim.last_updated_at = time.time()
        
        # Log audit if priority escalated or changed
        if prev_class != victim.priority_class:
            await audit_logger.log_event(
                event_type=AuditEventType.VICTIM_PRIORITIZED,
                decision=f"Victim {victim.id} prioritized as {victim.priority_class.value} (Score: {victim.priority_score})",
                reason="; ".join(breakdown.reasons) or "Multi-criteria score recalculated",
                inputs={
                    "medical": victim.medical_severity,
                    "urgency": victim.estimated_survival_urgency,
                    "exposure": victim.hazard_exposure,
                    "people": victim.people_count,
                },
                output={"score": victim.priority_score, "class": victim.priority_class.value},
                confidence=victim.confidence,
                affected_entities=[victim.id],
            )
        
        world_state.victims[victim.id] = victim
        world_state.increment_version()
        return victim

    async def prioritize_all(self) -> List[Victim]:
        updated = []
        for v in list(world_state.victims.values()):
            u = await self.prioritize_and_update(v)
            updated.append(u)
        # Sort descending by priority score
        updated.sort(key=lambda x: x.priority_score, reverse=True)
        return updated


prioritization_agent = VictimPrioritizationAgent()
