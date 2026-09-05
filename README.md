# 🚨 RESQNET — AI-Powered Disaster Response & Digital Twin

<p align="center">

**An intelligent disaster-response command system that connects AI-driven decision making with a real-time 3D disaster simulation.**

[![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python)](https://www.python.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-Backend-009688?logo=fastapi)](https://fastapi.tiangolo.com/)
[![React](https://img.shields.io/badge/React-Frontend-61DAFB?logo=react)](https://react.dev/)
[![Godot](https://img.shields.io/badge/Godot-4.x-478CBF?logo=godot-engine)](https://godotengine.org/)
[![WebSocket](https://img.shields.io/badge/Communication-WebSocket-orange)](#architecture)
[![Status](https://img.shields.io/badge/Status-Prototype-yellow)](#project-status)

</p>

---

## 🌐 Overview

**RESQNET** is an AI-assisted disaster-response system designed to simulate how intelligent autonomous systems could coordinate emergency operations during large-scale disasters.

The platform combines:

* 🧠 **AI-driven response intelligence**
* 🌆 **3D Digital Twin simulation**
* 🚁 **Multi-drone coordination**
* 🗺️ **Dynamic navigation and route planning**
* 🆘 **Victim detection and prioritization**
* 📡 **Real-time telemetry**
* 🎯 **Mission planning and dispatch**
* 🎙️ **Voice-based operator interaction**
* 📊 **Live emergency command center**

Instead of treating a disaster as a static dataset, RESQNET creates a **living simulated environment** where disasters evolve, drones operate inside the environment, observations are generated, and the response system continuously updates its decisions.

---

# 🧩 Core Architecture

RESQNET is divided into three major systems.

```text
                  RESQNET
                     │
        ┌────────────┴────────────┐
        │                         │
     SYSTEM B                  SYSTEM A
   DIGITAL TWIN              AI RESPONSE CORE
        │                         │
        │                         │
        ▼                         ▼
┌─────────────────┐       ┌─────────────────────┐
│     GODOT       │◄─────►│      FASTAPI        │
│                 │ WS    │                     │
│ • 3D City       │       │ • World State       │
│ • Roads         │       │ • Drone Registry     │
│ • Disasters     │       │ • Victim Intelligence│
│ • Civilians     │       │ • Prioritization     │
│ • Drones        │       │ • Mission Planning   │
│ • Simulation    │       │ • RRT* Routing       │
└─────────────────┘       │ • Replanning         │
                          │ • Command Validation │
                          └──────────┬──────────┘
                                     │
                                  REST/WS
                                     │
                                     ▼
                          ┌─────────────────────┐
                          │   REACT COMMAND     │
                          │       CENTER        │
                          │                     │
                          │ • Tactical Map      │
                          │ • Fleet Monitoring   │
                          │ • Victim Intelligence│
                          │ • Missions           │
                          │ • Events             │
                          │ • Response Controls  │
                          │ • Voice Interface    │
                          └─────────────────────┘
```

### System B — Digital Twin

**Godot** acts as the authoritative physical simulation.

It represents:

* City environment
* Road network
* Disaster events
* Fire and flood hazards
* Civilians/victims
* Drone fleet
* Drone movement
* Environmental state
* Simulated sensor/camera observations

The Godot simulation communicates its state to System A through WebSockets.

### System A — AI Response & Command Layer

The **FastAPI backend** acts as the intelligence and coordination layer.

It handles:

* Live world-state ingestion
* Drone registration
* Telemetry
* Victim intelligence
* Victim prioritization
* Multi-UAV search
* RRT* route planning
* Response orchestration
* Mission creation
* Command validation
* Dynamic replanning
* Communication between the simulation and command center

### Operator Command Center

The **React frontend** provides the emergency operator with a centralized tactical interface.

It provides:

* Live tactical map
* Drone fleet monitoring
* Victim intelligence
* Mission monitoring
* Event stream
* Coverage visualization
* Response actions
* Diagnostics
* Voice interaction
* Browser text-to-speech

---

# 🚁 Multi-Drone Response

RESQNET is designed around coordinated multi-UAV operations rather than treating each drone as an isolated entity.

Different missions can be assigned based on:

* Drone capabilities
* Location
* Battery
* Mission state
* Victim priority
* Disaster conditions
* Route feasibility

Supported command types include:

```text
TAKEOFF
NAVIGATE
SURVEY
DELIVER_SUPPLIES
RELAY_COMMS
RETURN_TO_BASE
HOVER
ABORT
LAND
```

---

# 🆘 Victim Intelligence

When the Digital Twin generates a victim observation, System A creates a structured intelligence record.

A victim record can contain:

```text
Victim ID
Hazard Type
Location
Evidence
Timestamp
Capturing Drone
People Count
Confidence
Medical Severity
Urgency
Exposure
AI Priority Score
Priority Class
Assigned Drone
Assigned Mission
```

This allows the system to move from:

```text
Observation
     ↓
Victim Detection
     ↓
Intelligence Extraction
     ↓
Priority Calculation
     ↓
Mission Creation
     ↓
Drone Dispatch
     ↓
Mission Execution
     ↓
Telemetry / Result
```

---

# 🗺️ Intelligent Routing

RESQNET contains a foundation for autonomous multi-drone navigation.

The backend includes **RRT*** based routing for planning paths through the simulated environment.

The system can combine:

* Current drone position
* Destination
* Environment
* Mission requirements
* Routing constraints
* Dynamic replanning

This provides the foundation for future obstacle-aware and disaster-aware navigation.

---

# 🎯 Disaster Scenarios

The simulation supports scenario controls including:

* 🌎 Earthquake
* 🌊 Flood
* 🔥 Fire
* 🧍 Victim spawning
* ⏸️ Pause
* ▶️ Resume
* 🔄 Reset

The goal is to demonstrate how the response system reacts to a changing environment rather than simply replaying a predefined video.

---

# 🎙️ Voice Interaction

The Command Center supports browser-based voice interaction where supported.

The architecture includes:

```text
Operator Voice
      ↓
Speech Recognition
      ↓
Intent Interpretation
      ↓
Safety Validation
      ↓
System Command
      ↓
FastAPI
      ↓
Godot Digital Twin
```

The system also provides browser-based text-to-speech for voice output.

> Voice interaction is currently a prototype capability and should not be considered a certified aviation or emergency-command interface.

---

# 🔄 End-to-End Response Flow

A typical RESQNET disaster-response cycle looks like this:

```text
1. Disaster occurs
        ↓
2. Godot updates the Digital Twin
        ↓
3. World state is streamed to System A
        ↓
4. AI Command Center receives live state
        ↓
5. Recon mission is initiated
        ↓
6. Multiple drones receive survey routes
        ↓
7. Drones explore affected areas
        ↓
8. Victim observation is generated
        ↓
9. Victim intelligence is created
        ↓
10. Priority is calculated
        ↓
11. Response mission is generated
        ↓
12. Appropriate drone is selected
        ↓
13. Command is sent to Godot
        ↓
14. Godot executes the command
        ↓
15. ACK / telemetry is returned
        ↓
16. Command Center updates in real time
```

---

# 🏗️ Repository Structure

```text
RESQNET-AI-Disaster-Response-System/
│
├── backend/
│   └── app/
│       ├── intelligence/
│       │   ├── routing/
│       │   ├── search/
│       │   └── response/
│       │
│       ├── protocol/
│       └── ...
│
├── frontend/
│   └── ...
│
├── godot/
│   └── RESQNET_ELITE_SIM/
│       ├── scripts/
│       ├── scenes/
│       └── project.godot
│
├── FULL_INTEGRATION_STATUS.md
├── README_ELITE_INTEGRATION.md
│
├── run_all.bat
├── run_backend.bat
├── run_frontend.bat
└── run_godot.bat
```

The repository currently contains separate backend, frontend, and Godot components along with integration documentation and Windows startup scripts.

---

# ⚙️ Technology Stack

| Layer                    | Technology                 |
| ------------------------ | -------------------------- |
| Digital Twin             | Godot 4.x                  |
| Backend                  | Python + FastAPI           |
| API                      | REST                       |
| Real-time Communication  | WebSocket                  |
| Frontend                 | React                      |
| Routing                  | RRT*                       |
| Voice Input              | Browser Speech Recognition |
| Voice Output             | Browser Text-to-Speech     |
| Simulation Communication | WebSocket                  |
| Development              | Python / Node.js / Godot   |

---

# 🚀 Installation

## 1. Clone the repository

```bash
git clone https://github.com/anuragyadav06/RESQNET-AI-Disaster-Response-System.git
cd RESQNET-AI-Disaster-Response-System
```

---

## 2. Start the Backend

```powershell
cd backend

python -m venv .venv

.\.venv\Scripts\Activate.ps1

python -m pip install -r requirements.txt

python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Backend:

```text
http://localhost:8000
```

API documentation:

```text
http://localhost:8000/docs
```

Health endpoint:

```text
http://localhost:8000/api/v1/health
```

---

## 3. Start the Frontend

Open another terminal:

```powershell
cd frontend

npm install

npm run dev
```

Then open:

```text
http://localhost:5173
```

---

## 4. Start the Digital Twin

Open:

```text
godot/RESQNET_ELITE_SIM/project.godot
```

using **Godot 4.x** and run the project.

The simulation attempts to connect to:

```text
ws://127.0.0.1:8000/ws/simulation/metro_godot_01
```

---

# ⚡ Quick Start — Windows

The repository includes startup scripts:

```text
run_backend.bat
run_frontend.bat
run_godot.bat
run_all.bat
```

For the normal demonstration, the recommended order is:

```text
Backend
   ↓
Godot
   ↓
Frontend
```

Wait for the Godot/System A connection to establish before starting the response workflow.

---

# 🎬 Recommended Demonstration

For a complete RESQNET demonstration:

### Step 1 — Start Backend

Launch FastAPI on port `8000`.

### Step 2 — Start Godot

Launch the Digital Twin and wait for:

```text
SYSTEM A LINK • CONNECTED
```

### Step 3 — Start Frontend

Open the Command Center at:

```text
http://localhost:5173
```

### Step 4 — Trigger Disaster

Start an earthquake or flood scenario.

### Step 5 — Deploy Reconnaissance

Use:

```text
AI COMMAND CENTER → START RECON
```

### Step 6 — Detect Victims

As drones explore the environment, simulated victim observations are sent to System A.

### Step 7 — Triage

Review detected victims and their calculated priorities.

### Step 8 — Dispatch

Create a response mission for a selected victim.

### Step 9 — Execute

System A sends the validated command to Godot.

### Step 10 — Monitor

Observe:

* Drone telemetry
* Mission status
* Victim state
* Events
* World state
* Response progress

---

# 🔌 Communication Architecture

RESQNET uses WebSockets for real-time communication.

```text
Godot
  │
  │ World State
  │ Telemetry
  │ Victim Observations
  ▼
FastAPI
  │
  │ Commands
  │ Mission Updates
  │ Response Decisions
  ▼
Godot
```

The frontend communicates with the backend through REST and WebSocket interfaces.

---

# 🧠 Important Architecture Principle

The authoritative Digital Twin in normal operation is:

> **Godot = System B**

The intelligence and command layer is:

> **FastAPI = System A**

The operator interface is:

> **React = Command Center**

The legacy backend simulator is **not enabled by default**. It is available only through:

```text
RESQNET_INTERNAL_SIMULATOR=1
```

This prevents the legacy simulator from competing with the Godot Digital Twin during normal operation.

---

# 📡 Current Integration Capabilities

The current integrated prototype includes:

* [x] System A ↔ System B WebSocket communication
* [x] Live world-state streaming
* [x] Drone registry
* [x] Drone telemetry
* [x] Mission telemetry
* [x] Multi-drone routing foundation
* [x] Multi-UAV search/coverage
* [x] Victim observation pipeline
* [x] Victim prioritization
* [x] Response orchestration
* [x] Mission/command validation
* [x] Dynamic replanning interface
* [x] Tactical Command Center
* [x] Voice output
* [x] Browser voice-command prototype
* [x] Godot command execution bridge

These capabilities correspond to the current integration build documented in the repository.

---

# ⚠️ Project Status & Limitations

RESQNET is currently an **advanced research/academic prototype**, not a certified emergency-response or autonomous aviation system.

The current implementation uses a simulated environment and simulated sensor evidence.

In particular:

* Physical UAV control is not implemented as certified flight control.
* Real-world drone hardware requires an appropriate flight-controller adapter.
* Real camera/thermal feeds require actual sensor integration.
* Production-grade speech-to-text/text-to-speech providers can be integrated later.
* The current victim evidence pipeline can use simulated camera evidence.
* The richer city/disaster simulation can continue evolving while preserving the System A integration boundary.

The architecture is intentionally designed so simulated components can later be replaced with real providers and hardware adapters.

---

# 🔮 Future Roadmap

## Phase 1 — Core Integration

* [x] Digital Twin
* [x] Backend intelligence layer
* [x] Command Center
* [x] WebSocket communication
* [x] Drone telemetry
* [x] Mission system

## Phase 2 — Intelligence

* [x] Victim prioritization
* [x] Multi-UAV search
* [x] RRT* routing
* [x] Dynamic replanning
* [ ] Advanced disaster prediction
* [ ] More sophisticated resource optimization

## Phase 3 — Real Sensor Integration

* [ ] Live drone camera feeds
* [ ] Thermal imaging
* [ ] Computer vision victim detection
* [ ] Real-time geospatial feeds
* [ ] Environmental sensors

## Phase 4 — Hardware Integration

* [ ] PX4 / ArduPilot integration
* [ ] Real UAV telemetry
* [ ] Mission upload
* [ ] Hardware-in-the-loop simulation
* [ ] Secure command channel

## Phase 5 — Large-Scale Digital Twin

* [ ] Large metropolitan environments
* [ ] Real road-network data
* [ ] Population simulation
* [ ] Infrastructure damage modeling
* [ ] Weather integration
* [ ] Emergency-service coordination

---

# 🎓 Academic & Research Applications

RESQNET can serve as a research platform for:

* Artificial Intelligence
* Multi-Agent Systems
* Autonomous Robotics
* Disaster Management
* Digital Twins
* Path Planning
* Computer Vision
* Reinforcement Learning
* Human-AI Interaction
* Emergency Response Optimization
* UAV Swarm Coordination

---

# 👨‍💻 Project

**RESQNET — AI Disaster Response System**

An integrated prototype combining:

**Artificial Intelligence + Digital Twin + Autonomous UAV Coordination + Emergency Command Center**

Built for experimentation, simulation, research, and demonstration of intelligent disaster-response architectures.

---

# 📄 Documentation

Additional technical documentation is available in:

```text
FULL_INTEGRATION_STATUS.md
README_ELITE_INTEGRATION.md
```

---

# ⚖️ Disclaimer

RESQNET is a research and simulation prototype.

It must not be used as a substitute for certified emergency-management systems, professional disaster-response organizations, certified UAV flight controllers, or real-world safety procedures.

---

<p align="center">

### 🚨 RESQNET

**Simulate. Detect. Decide. Respond.**

</p>
