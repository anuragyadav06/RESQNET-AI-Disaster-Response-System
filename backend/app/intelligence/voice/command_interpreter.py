"""Deterministic voice-command interpreter; no LLM required for safety-critical intents."""
import re
from typing import Any, Dict

class VoiceCommandInterpreter:
    def parse(self, text: str) -> Dict[str, Any]:
        t = text.strip().lower()
        if "current disaster status" in t or t in {"status", "system status"}:
            return {"intent": "GET_STATUS", "parameters": {}}
        if "find trapped civilians" in t or "start reconnaissance" in t or "search for victims" in t:
            return {"intent": "START_RECON", "parameters": {}}
        if "prioritize rooftop victims" in t:
            return {"intent": "PRIORITIZE_ROOFTOP", "parameters": {}}
        if "send nearest available drone" in t:
            return {"intent": "AUTO_DISPATCH", "parameters": {}}
        m = re.search(r"deploy\s+(drone[- ]?[a-z0-9]+)\s+to\s+(sector\s+[a-z0-9-]+)", t)
        if m:
            return {"intent": "DEPLOY_TO_SECTOR", "parameters": {"drone_id": m.group(1).upper().replace(" ", "-"), "sector": m.group(2).upper()}}
        m = re.search(r"abort\s+(drone[- ]?[a-z0-9]+).*mission", t)
        if m:
            return {"intent": "ABORT_DRONE_MISSION", "parameters": {"drone_id": m.group(1).upper().replace(" ", "-")}}
        m = re.search(r"drone\s+([a-z0-9-]+)\s+return to base", t)
        if m:
            return {"intent": "RTB", "parameters": {"drone_id": m.group(1).upper()}}
        return {"intent": "UNKNOWN", "parameters": {}, "reason": "Command not recognized"}

voice_interpreter = VoiceCommandInterpreter()
