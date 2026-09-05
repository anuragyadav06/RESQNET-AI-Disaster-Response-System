# RESQNET — Elite Metro Disaster Twin + System A Integration

This package merges the user's existing **Godot 4.7 Elite Metro Disaster Twin** with the RESQNET System A backend and operator frontend.

## Architecture

Godot is the authoritative physical Digital Twin.

```text
Godot Elite Metro Twin
  ├─ city / roads
  ├─ earthquake / flood / fire
  ├─ civilians / victims
  └─ 5-drone fleet
          │ WebSocket
          ▼
FastAPI System A
  ├─ live world state
  ├─ drone registry + telemetry
  ├─ victim intelligence
  ├─ prioritization
  ├─ multi-UAV search + RRT*
  ├─ response orchestration
  ├─ mission / command validation
  └─ replanning
          │ WebSocket + REST
          ▼
React Command Center
```

## Godot integration

The bridge is:

`godot/RESQNET_ELITE_SIM/scripts/resqnet_bridge.gd`

The existing city/disaster/drone scripts were preserved. `main.gd` creates the bridge and connects it to `DroneFleet` and `DisasterController`.

### Live data sent from Godot

- Drone ID, type and capabilities
- position / velocity / heading
- battery / altitude / status
- current mission
- disaster state
- fire/flood hazard locations
- victim observations
- simulated camera evidence image
- capturing drone ID

### Victim intelligence

Each detected victim is represented in System A with:

- Victim ID
- hazard type
- X/Y/Z coordinates
- evidence image
- capture timestamp
- capturing drone ID
- people count
- confidence
- medical severity
- urgency
- exposure
- AI priority score/class
- assigned response drone / mission

Victim evidence is intentionally labelled as simulated camera evidence. Replace the bridge's `_evidence_svg()` output with a real camera/thermal frame when connecting an actual sensor.

## Commands from System A to Godot

Supported:

- TAKEOFF
- NAVIGATE
- SURVEY
- DELIVER_SUPPLIES
- RELAY_COMMS
- RETURN_TO_BASE
- HOVER
- ABORT
- LAND

Scenario controls supported:

- EARTHQUAKE
- FLOOD
- FIRE
- SPAWN_VICTIMS
- RESET
- PAUSE
- RESUME

## Run

### 1. Backend

```powershell
cd backend
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

API docs:

`http://localhost:8000/docs`

Health:

`http://localhost:8000/api/v1/health`

### 2. Godot

Open:

`godot/RESQNET_ELITE_SIM/project.godot`

Run the project. It automatically attempts:

`ws://127.0.0.1:8000/ws/simulation/metro_godot_01`

### 3. Frontend

```powershell
cd frontend
npm install
npm run dev
```

Open:

`http://localhost:5173`

## Recommended demo sequence

1. Start backend.
2. Start Godot and wait for `SYSTEM A LINK • CONNECTED`.
3. Start frontend.
4. Trigger earthquake or flood in Godot.
5. Spawn civilians if required.
6. Use **AI Command Center → START RECON**.
7. Scout/inspection drones receive partitioned survey routes.
8. When a drone reaches a distressed civilian, Godot sends victim evidence.
9. System A creates the victim record and calculates priority.
10. Use TRIAGE/DISPATCH or dispatch from Victim Intelligence.
11. System A creates a response mission and sends the selected drone command to Godot.
12. Godot executes the command and returns ACK/result.
13. Telemetry and victim/mission state appear on the dashboard.

## Important

Do not run the legacy backend Digital Twin simulator for the normal demo. The backend simulator is only enabled with:

`RESQNET_INTERNAL_SIMULATOR=1`

Normal operation is:

**Godot = System B / authoritative Digital Twin**

**FastAPI = System A / command + intelligence**

**React = operator command center**
