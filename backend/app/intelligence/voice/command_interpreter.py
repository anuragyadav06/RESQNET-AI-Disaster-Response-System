"""
Voice-command interpreter.

Design:
  1. FAST PATH - exact/regex matches for the canonical safety-critical phrasings.
     Deterministic, offline, zero-latency, fully auditable. Used first so that a
     known-good command is never delayed or reinterpreted.
  2. FUZZY PATH - if nothing in the fast path matches, we fall back to keyword /
     synonym scoring so operators who don't know the "magic words" can still be
     understood (e.g. "any survivors out there?" -> START_RECON).
  3. If neither path is confident enough, we return UNKNOWN together with our
     best guesses so the UI can show "Did you mean...?" instead of a dead end.

This keeps safety-critical intents deterministic while making the system
tolerant of ordinary English. For a production system, the fuzzy path is the
natural place to plug in an LLM-based classifier as a further fallback - the
interface (return a dict with "intent"/"parameters"/"confidence") would stay
the same.
"""
import re
from difflib import SequenceMatcher
from typing import Any, Dict, List, Optional, Tuple

# Words that should not affect matching either way.
_STOPWORDS = {
    "the", "a", "an", "please", "can", "you", "could", "would", "to", "for",
    "me", "of", "on", "at", "is", "are", "there", "any", "now", "just", "go",
    "do", "we", "our", "i", "want", "need", "let's", "lets",
}

# Zero-parameter intents: matched by fuzzy keyword/synonym overlap against the
# operator's utterance when the exact fast-path phrases don't hit.
_INTENT_KEYWORDS: Dict[str, List[str]] = {
    "GET_STATUS": [
        "status", "situation", "sitrep", "report", "update", "overview",
        "how", "things", "looking", "state", "condition", "brief", "summary",
    ],
    "START_RECON": [
        "find", "search", "recon", "reconnaissance", "scout", "survivors",
        "civilians", "trapped", "victims", "people", "locate", "look", "detect",
        "canvass", "sweep",
    ],
    "PRIORITIZE_ROOFTOP": [
        "prioritize", "rooftop", "roof", "roofs", "priority", "reorder",
        "reprioritize", "rank", "triage",
    ],
    "AUTO_DISPATCH": [
        "send", "dispatch", "deploy", "nearest", "available", "auto",
        "automatic", "closest", "free", "any", "drone", "unit",
    ],
}

# Minimum fuzzy confidence before we'll act on a zero-parameter intent.
_FUZZY_THRESHOLD = 0.34


def _normalize(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"[^a-z0-9\s-]", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def _tokens(text: str) -> List[str]:
    return [w for w in _normalize(text).split() if w not in _STOPWORDS]


def _keyword_score(query_tokens: List[str], keywords: List[str]) -> float:
    if not query_tokens:
        return 0.0
    hits = 0.0
    for qt in query_tokens:
        token_best = max((SequenceMatcher(None, qt, kw).ratio() for kw in keywords), default=0.0)
        if token_best > 0.8:
            hits += 1.0
        elif token_best > 0.6:
            hits += 0.5
    return hits / max(len(query_tokens), 1)


def _fuzzy_best_intent(t: str) -> Tuple[Optional[str], float]:
    """Score the utterance against each zero-parameter intent's keyword set.

    Combines exact token overlap with a fuzzy (typo/ASR-error tolerant)
    similarity check on each word pair, so near-miss transcriptions like
    "reconasance" or "prioritise" still land correctly.
    """
    query_tokens = _tokens(t)
    if not query_tokens:
        return None, 0.0

    best_intent, best_score = None, 0.0
    for intent, keywords in _INTENT_KEYWORDS.items():
        score = _keyword_score(query_tokens, keywords)
        if score > best_score:
            best_intent, best_score = intent, score
    return best_intent, best_score


class VoiceCommandInterpreter:
    """Deterministic, auditable natural-language command parser.

    The parser intentionally accepts normal operator English rather than forcing
    one magic phrase. Safety-critical execution still requires a concrete target
    for response missions.
    """

    _VICTIM_ID = r"(?:VIC[- ]?\d+)"

    def _victim_id(self, text: str) -> Optional[str]:
        m = re.search(self._VICTIM_ID, text, re.IGNORECASE)
        return m.group(0).upper().replace(" ", "-") if m else None

    def parse(self, text: str) -> Dict[str, Any]:
        raw = text or ""
        t = _normalize(raw)
        if not t:
            return {"intent": "UNKNOWN", "parameters": {}, "reason": "Empty command", "confidence": 0.0}

        # Status / reconnaissance / prioritisation.
        if re.search(r"\b(?:current|overall|system|disaster)?\s*(?:status|situation|sitrep|report|update|overview)\b", t):
            return {"intent": "GET_STATUS", "parameters": {}, "confidence": 0.99, "matched_via": "semantic"}
        if re.search(r"\b(?:find|search|locate|detect|scan|look for|sweep|canvass)\b.*\b(?:victims?|survivors?|civilians?|people|trapped)\b", t) or re.search(r"\b(?:start|begin|activate)\b.*\b(?:recon|reconnaissance|scout|search)\b", t):
            return {"intent": "START_RECON", "parameters": {}, "confidence": 0.99, "matched_via": "semantic"}
        if re.search(r"\b(?:prioritize|prioritise|rank|reorder|reprioritize|reprioritise)\b.*\b(?:rooftop|roof|victim|survivor)s?\b", t):
            return {"intent": "PRIORITIZE_ROOFTOP", "parameters": {}, "confidence": 0.98, "matched_via": "semantic"}

        victim_id = self._victim_id(t)

        # Explicit response type + victim ID. Supports both:
        # "send rescue to VIC-103" and "send rescue to victim VIC-103".
        if victim_id:
            action_patterns = [
                ("RESCUE_EXTRACTION", r"\b(?:rescue|extract|extraction|evacuate|evacuation|save)\b"),
                ("MEDICAL_SUPPLY_DROP", r"\b(?:medical|medic|doctor|medical\s+support|stabilize|stabilise)\b"),
                ("HEAVY_EXTRICATION", r"\b(?:heavy\s*lift|heavy|extrication|extricate|rubble|debris|clear\s+(?:the\s+)?rubble|lift\s+(?:the\s+)?debris)\b"),
            ]
            for objective, pattern in action_patterns:
                if re.search(pattern, t):
                    if re.search(r"\b(?:send|dispatch|deploy|route|move|bring|get|assign|activate|launch)\b", t):
                        return {"intent": "DISPATCH_RESPONSE", "parameters": {"victim_id": victim_id, "objective": objective}, "confidence": 0.99, "matched_via": "victim-action"}

            # "Send the appropriate team to VIC-103" defaults to rescue extraction.
            if re.search(r"\b(?:send|dispatch|deploy|route|move|bring|assign|activate|launch)\b", t):
                return {"intent": "DISPATCH_RESPONSE", "parameters": {"victim_id": victim_id, "objective": "RESCUE_EXTRACTION", "auto_select": True}, "confidence": 0.91, "matched_via": "victim-target"}

        # Explicit fleet/capability dispatch WITHOUT a concrete victim.
        # This MUST run before generic AUTO_DISPATCH so that words such as
        # "rescue", "medical", and "heavy lift" are not discarded and the
        # mission planner cannot fall back to victim medical severity.
        if re.search(r"\b(?:send|dispatch|deploy|launch|activate)\b.*\b(?:rescue|rescuer|extraction|extract|evacuation|evacuate)\b.*\b(?:drones?|units?|teams?)\b", t) or re.search(r"\b(?:rescue|rescuer|extraction|extract|evacuation|evacuate)\b.*\b(?:drones?|units?|teams?)\b", t):
            return {"intent": "AUTO_DISPATCH", "parameters": {"objective": "RESCUE_EXTRACTION"}, "confidence": 0.99, "matched_via": "explicit-capability"}

        if re.search(r"\b(?:send|dispatch|deploy|launch|activate)\b.*\b(?:medical|medic|doctor|medical\s+support)\b.*\b(?:drones?|units?|teams?)\b", t) or re.search(r"\b(?:medical|medic|doctor|medical\s+support)\b.*\b(?:drones?|units?|teams?)\b", t):
            return {"intent": "AUTO_DISPATCH", "parameters": {"objective": "MEDICAL_SUPPLY_DROP"}, "confidence": 0.99, "matched_via": "explicit-capability"}

        if re.search(r"\b(?:send|dispatch|deploy|launch|activate)\b.*\b(?:heavy\s*lift|heavy\s+rescue|extrication|extricate|rubble|debris)\b.*\b(?:drones?|units?|teams?)\b", t) or re.search(r"\b(?:heavy\s*lift|heavy\s+rescue|extrication|extricate|rubble|debris)\b.*\b(?:drones?|units?|teams?)\b", t):
            return {"intent": "AUTO_DISPATCH", "parameters": {"objective": "HEAVY_EXTRICATION"}, "confidence": 0.99, "matched_via": "explicit-capability"}

        # Automatic priority dispatch without a concrete victim.
        if re.search(r"\b(?:send|dispatch|deploy|launch|activate)\b.*\b(?:nearest|closest|available|appropriate|suitable|any)\b.*\b(?:drone|unit|team)\b", t) or re.search(r"\b(?:auto|automatic|automatically)\b.*\bdispatch\b", t):
            return {"intent": "AUTO_DISPATCH", "parameters": {}, "confidence": 0.96, "matched_via": "semantic"}

        # Specific drone to sector.
        m = re.search(
            r"(?:deploy|send|dispatch|route|move)\s+(drone[- ]?[a-z0-9]+)\s+(?:to|toward|towards|into)\s+(sector\s+[a-z0-9-]+)", t,
        )
        if m:
            return {"intent": "DEPLOY_TO_SECTOR", "parameters": {"drone_id": m.group(1).upper().replace(" ", "-"), "sector": m.group(2).upper()}, "confidence": 0.98, "matched_via": "exact"}

        m = re.search(r"(?:abort|cancel|stop)\s+(drone[- ]?[a-z0-9]+)(?:'s)?\s*(?:mission|task|operation)?", t)
        if m:
            return {"intent": "ABORT_DRONE_MISSION", "parameters": {"drone_id": m.group(1).upper().replace(" ", "-")}, "confidence": 0.99, "matched_via": "exact"}

        m = re.search(r"(drone[- ]?[a-z0-9]+).*?(?:return to base|return home|come back|head back|rtb)", t)
        if m:
            return {"intent": "RTB", "parameters": {"drone_id": m.group(1).upper().replace(" ", "-")}, "confidence": 0.99, "matched_via": "exact"}

        intent, score = _fuzzy_best_intent(t)
        if intent and score >= _FUZZY_THRESHOLD:
            return {"intent": intent, "parameters": {}, "confidence": round(score, 2), "matched_via": "fuzzy"}

        query_tokens = _tokens(t)
        ranked = sorted(((i, _keyword_score(query_tokens, kws)) for i, kws in _INTENT_KEYWORDS.items()), key=lambda p: p[1], reverse=True)
        suggestions = [i for i, s in ranked if s > 0.15][:2]
        return {"intent": "UNKNOWN", "parameters": {}, "reason": "Command not recognized", "confidence": round(score, 2), "suggestions": suggestions}


voice_interpreter = VoiceCommandInterpreter()