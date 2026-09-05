# RESQNET Full Integration Build

This build is an integrated end-to-end prototype built on the supplied ResQNet2 baseline.

## Implemented / wired in this build

1. Protocol contracts: `backend/app/protocol/`
2. System A ↔ System B WebSocket: existing connection retained and registration/state events added
3. Live world-state stream: frontend WebSocket + HTTP fallback
4. Drone registry + telemetry: existing world-state ingestion retained; mission telemetry now includes mission_id
5. System A → Godot commands: command validation + execution adapter expanded for TAKEOFF/NAVIGATE/SURVEY/DELIVER/RELAY/RTB/HOVER/ABORT/LAND
6. Multi-drone navigation foundation: `backend/app/intelligence/routing/rrt_star.py`
7. Multi-UAV search/coverage: `backend/app/intelligence/search/`
8. Observation/victim pipeline: existing perception/prioritization retained and observation events are streamed
9. Response orchestrator: `backend/app/intelligence/response/response_orchestrator.py`
10. Medical/supply/relay mission model: existing mission objectives and command types wired through the same command path
11. Dynamic replanning: existing replanning agent remains exposed through API and dashboard action
12. Dashboard integration: new **AI Command Center** with live tactical map, fleet, victims, missions, event stream, coverage preview, response actions and diagnostics
13. Voice output: browser TTS in the Command Center
14. Voice command interaction: browser STT when supported + deterministic safety-oriented intent interpreter API

## Important architecture rule

Godot/System B is the authoritative Digital Twin in normal operation. The legacy backend Digital Twin simulator is now **opt-in only** via:

`RESQNET_INTERNAL_SIMULATOR=1`

It is not started by default.

## Running

Backend:

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Frontend:

```powershell
cd frontend
npm install
npm run dev
```

Godot: open `godot/project.godot` in Godot 4.x and run the project.

Dashboard: `http://localhost:5173`
API docs: `http://localhost:8000/docs`
Health: `http://localhost:8000/api/v1/health`

## Reality check

The supplied ResQNet2 archive contains a compact Godot scene with four drone controllers rather than the larger city/disaster scene described in the project conversation. This build does not delete or replace that supplied simulation. The integration boundary is ready for the richer Godot scene to connect to the same System A protocol.

Physical UAVs, production STT/TTS providers, and real sensor/CV feeds remain adapter/provider dependent; the prototype does not pretend that a browser or Godot mock is a certified flight controller.
