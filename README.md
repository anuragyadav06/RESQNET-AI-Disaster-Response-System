# 🚨 RESQNET — AI-Assisted Multi-UAV Disaster Response & Digital Twin Platform

> **An intelligent, explainable and human-supervised disaster-response coordination platform for multi-UAV search, victim prioritization, resource allocation, hazard-aware routing, mission execution and dynamic replanning.**

![Status](https://img.shields.io/badge/Status-Research%20Prototype-blue)
![Python](https://img.shields.io/badge/Python-3.11+-3776AB?logo=python\&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-Backend-009688?logo=fastapi\&logoColor=white)
![React](https://img.shields.io/badge/React-19-61DAFB?logo=react\&logoColor=black)
![TypeScript](https://img.shields.io/badge/TypeScript-5+-3178C6?logo=typescript\&logoColor=white)
![Godot](https://img.shields.io/badge/Godot-4.7+-478CBF?logo=godotengine\&logoColor=white)
![WebSocket](https://img.shields.io/badge/Communication-WebSocket-orange)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 🌐 Overview

**RESQNET** is a disaster-response command and coordination platform designed to assist emergency-response teams in managing **multiple heterogeneous UAVs inside a continuously changing disaster environment**.

Instead of treating drone operations, victim detection, routing, resource allocation and disaster simulation as separate problems, RESQNET connects them into a single closed-loop system:

```text
                    DISASTER EVENT
                          │
                          ▼
                ┌─────────────────────┐
                │   DIGITAL TWIN      │
                │     GODOT 4.7       │
                │                     │
                │ City • Roads • UAVs │
                │ Victims • Hazards   │
                └──────────┬──────────┘
                           │
                     Telemetry /
                     Observations
                           │
                           ▼
                ┌─────────────────────┐
                │   RESQNET CORE      │
                │      FASTAPI        │
                │                     │
                │ World State         │
                │ Victim Intelligence │
                │ Prioritization      │
                │ UAV Allocation      │
                │ Risk Assessment     │
                │ A* Routing          │
                │ Search Planning     │
                │ Mission Orchestration│
                │ Replanning          │
                │ Command Safety      │
                └──────────┬──────────┘
                           │
                    Commands /
                    Live State
                           │
             ┌─────────────┴─────────────┐
             ▼                           ▼
    ┌──────────────────┐       ┌──────────────────┐
    │ COMMAND CENTER   │       │   UAV EXECUTION  │
    │ React + TypeScript│      │  Godot Simulator  │
    │                  │       │                  │
    │ Tactical Map     │       │ Drone Movement   │
    │ Victims          │       │ Battery          │
    │ Fleet            │       │ Mission State    │
    │ Missions         │       │ Telemetry        │
    │ Hazards          │       └─────────┬────────┘
    │ Voice / Text     │                 │
    └──────────────────┘                 │
                                         │
                                         └──────► Feedback
                                                   │
                                                   ▼
                                             REPLANNING
```

The goal is not simply to make drones autonomous.

The goal is to create an **intelligent disaster-response coordination layer** that can continuously answer:

> **Who needs help first? Which UAV should respond? What route should it take? Is the mission safe? What happens if the environment changes?**

---

# 🎯 Problem Statement

During large-scale disasters such as:

* Earthquakes
* Floods
* Urban fires
* Building collapses
* Infrastructure failures
* Large-scale evacuation events

response teams face several simultaneous problems:

* Large affected areas must be searched rapidly.
* Victims have different levels of urgency.
* Different UAVs have different capabilities.
* Roads and airspace conditions can change.
* Battery and mission endurance are limited.
* Hazards can invalidate previously planned routes.
* Multiple drones may duplicate the same search effort.
* Human operators cannot manually optimize every UAV continuously.
* Emergency decisions need to remain explainable and auditable.

Traditional systems often solve only one part of this problem.

RESQNET approaches it as a **closed-loop multi-agent coordination problem**.

---

# 💡 Core Idea

RESQNET combines three major systems:

### System A — Intelligence & Coordination

A Python/FastAPI backend responsible for:

* World-state management
* Victim intelligence
* Victim prioritization
* Multi-UAV resource allocation
* Search planning
* Risk assessment
* Hazard-aware route planning
* Mission orchestration
* Dynamic replanning
* Command validation
* Audit logging

### System B — Disaster Digital Twin

A Godot-based real-time 3D environment that simulates:

* Urban infrastructure
* Roads
* Buildings
* Civilians
* Victims
* Disaster events
* Hazards
* UAV fleet
* UAV movement
* Battery state
* Telemetry
* Mission execution

### System C — Emergency Command Center

A React + TypeScript interface providing:

* Tactical visualization
* Fleet monitoring
* Victim intelligence
* Mission management
* Hazard monitoring
* Route visualization
* Telemetry
* Decision explanations
* Voice/text commands
* Operational controls

---

# 🧠 What Makes RESQNET Different?

RESQNET is not just:

❌ A drone simulator
❌ A map dashboard
❌ A chatbot
❌ A simple victim detector
❌ A pathfinding demo
❌ A single-drone controller

Instead, it connects:

```text
Disaster
   ↓
Situational Awareness
   ↓
Search
   ↓
Victim Intelligence
   ↓
Victim Prioritization
   ↓
Capability Matching
   ↓
UAV Allocation
   ↓
Hazard-Aware Routing
   ↓
Risk Assessment
   ↓
Mission Generation
   ↓
Safety Validation
   ↓
Command Execution
   ↓
Telemetry
   ↓
Environment Change
   ↓
Dynamic Replanning
```

This creates a **closed-loop disaster-response decision system**.

---

# 🚁 Heterogeneous UAV Fleet

The current prototype models a fleet of **31 UAVs** with different operational capabilities.

| UAV Type   | Quantity | Primary Role                 |
| ---------- | -------: | ---------------------------- |
| Scout      |       16 | Reconnaissance & search      |
| Medical    |        5 | Medical response             |
| Heavy-Lift |        5 | Heavy rescue / extrication   |
| Rescue     |        5 | Rescue and extraction        |
| **Total**  |   **31** | **Multi-UAV response fleet** |

The system does not assume that every UAV can perform every task.

Instead, missions are matched to UAV capabilities.

Example:

```text
Victim requires medical assistance
            ↓
Required capability = MEDICAL
            ↓
Search eligible medical UAVs
            ↓
Evaluate:
  • Availability
  • Battery
  • Distance
  • Risk
  • Capability
            ↓
Select best valid UAV
```

---

# 🧍 Victim Intelligence & Prioritization

When a victim observation is received, RESQNET converts it into structured operational intelligence.

A victim record can contain:

* Victim ID
* Location
* Detection evidence
* Detection confidence
* Medical severity
* Survival urgency
* Hazard exposure
* Accessibility
* Number of people
* Detection timestamp
* Capturing UAV
* Priority score
* Priority classification
* Assigned UAV
* Assigned mission

## Priority Model

The current prototype uses an explainable multi-criteria decision model.

```text
Priority Score =
    0.35 × Medical Severity
  + 0.25 × Survival Urgency
  + 0.20 × Hazard Exposure
  + 0.10 × Accessibility
  + 0.10 × Detection Confidence
  + bounded group-size contribution
```

Priority levels are then classified into:

```text
CRITICAL
HIGH
MEDIUM
LOW
```

The objective is not to hide decisions behind a black box.

The system can explain **why a victim received a particular priority**.

---

# 🤖 Explainable UAV Resource Allocation

Selecting the nearest drone is not always the correct decision.

RESQNET evaluates eligible UAVs according to multiple constraints and utility factors.

Current allocation logic considers:

* Mission capability
* UAV availability
* Battery state
* Travel distance
* Route risk
* Operational suitability

Conceptually:

```text
Candidate UAVs
      │
      ├── Capability check
      ├── Availability check
      ├── Battery check
      ├── Distance evaluation
      └── Risk evaluation
              │
              ▼
        Utility scoring
              │
              ▼
      Best eligible UAV
```

The system can retain the reasoning behind the selection, allowing an operator to understand:

> **Why was this UAV selected instead of another one?**

---

# 🗺️ Hazard-Aware Route Planning

RESQNET currently uses **A*** for operational urban graph routing.

The road network is represented as a graph containing:

* Road nodes
* Road edges
* Road types
* Connections
* Blocked roads
* Hazard information

Route costs are not based purely on distance.

Hazard penalties can increase the effective cost of dangerous routes.

```text
Normal route
     +
Hazard penalty
     +
Blocked-road constraints
     ↓
Dynamic route graph
     ↓
A*
     ↓
Safer / lower-cost route
```

This allows the planner to prefer a longer but safer route when necessary.

> **Note:** RRT* is part of the project's continuous-space planning foundation/future extension, while the current urban mission planner primarily uses A* over the road graph.

---

# 🔍 Multi-UAV Search Planning

The scout fleet performs parallel reconnaissance rather than sending one UAV through the entire disaster area.

The current prototype divides the search environment into dedicated search corridors.

For example:

```text
┌──────┬──────┬──────┬──────┐
│ S01  │ S02  │ S03  │ S04  │
├──────┼──────┼──────┼──────┤
│ S05  │ S06  │ S07  │ S08  │
├──────┼──────┼──────┼──────┤
│ S09  │ S10  │ S11  │ S12  │
├──────┼──────┼──────┼──────┤
│ S13  │ S14  │ S15  │ S16  │
└──────┴──────┴──────┴──────┘
```

The objective is to:

* Increase search parallelism
* Reduce duplicate coverage
* Improve area coverage
* Reduce search time
* Maintain predictable operational assignments

The architecture can later be extended to dynamic coverage optimization based on:

* Hazard zones
* Victim probability
* Battery
* Communication quality
* UAV availability
* Terrain
* Search history

---

# 🔄 Dynamic Replanning

Disaster environments are not static.

A route that was safe one minute ago may become unsafe later.

RESQNET therefore treats the environment as dynamic world state.

Example:

```text
Active Mission
      ↓
Road becomes blocked
      ↓
Route invalidated
      ↓
Current UAV position retrieved
      ↓
New route calculated
      ↓
Risk re-evaluated
      ↓
Updated command
      ↓
Mission continues
```

Battery safety can also trigger mission changes:

```text
Battery falls below safe reserve
              ↓
Mission reassessment
              ↓
Return-To-Base / Replanning
```

This transforms RESQNET from a static planner into a **closed-loop response system**.

---

# 🛡️ Safety-Gated Command Architecture

RESQNET does not blindly transmit every generated command.

Before execution, commands pass through validation.

Typical checks include:

* UAV existence
* UAV availability
* Battery safety
* Waypoint validity
* Coordinate bounds
* Altitude constraints
* Mission consistency

Conceptually:

```text
Mission
   ↓
Command Generation
   ↓
Safety Validation
   │
   ├── INVALID → REJECT + AUDIT
   │
   └── VALID
        ↓
     WebSocket
        ↓
      UAV Layer
```

This supports a **human-in-the-loop safety philosophy**.

---

# 👨‍✈️ Human-in-the-Loop Operations

RESQNET is designed as a decision-support and coordination platform rather than an uncontrolled autonomous system.

The intended operational model is:

```text
AI / Algorithms
       ↓
Recommendation
       ↓
Explainability
       ↓
Safety Validation
       ↓
Human Operator
       ↓
Command
       ↓
Execution
```

The operator can inspect the system state and intervene when necessary.

This is especially important for safety-critical disaster-response applications.

---

# 📡 Real-Time Communication

RESQNET uses WebSockets for real-time state synchronization.

### Digital Twin → Backend

Telemetry and observations:

```text
UAV position
UAV status
Battery
Velocity
Heading
Mission state
Victim observations
World-state changes
```

### Backend → Digital Twin

Operational commands:

```text
Navigate
Dispatch
Return-To-Base
Mission control
Search commands
Other validated actions
```

### Backend → Frontend

Live operational state:

```text
Drone state
Victim state
Mission state
Hazards
Telemetry
Events
Decision information
```

REST APIs are used alongside WebSockets for conventional request/response operations.

---

# 🎙️ Voice & Text Command Interface

RESQNET provides a natural command interface for operators.

Example commands can be interpreted into structured intents such as:

```text
GET_STATUS
START_RECON
AUTO_DISPATCH
DISPATCH_RESPONSE
DEPLOY_TO_SECTOR
ABORT_DRONE_MISSION
RETURN_TO_BASE
PRIORITIZE_ROOFTOP
```

The current prototype uses deterministic/rule-based intent interpretation to keep operational commands auditable and predictable.

Voice recognition is handled at the interface layer before commands enter the backend command pipeline.

---

# 🌆 Disaster Digital Twin

The Godot environment provides a real-time simulation of the disaster world.

The Digital Twin can represent:

### Infrastructure

* Buildings
* Roads
* Urban areas
* Infrastructure damage

### Disaster Events

* Earthquake
* Flood
* Fire
* Structural damage
* Dynamic hazards

### Civilians

* Normal civilians
* Victims
* Stranded civilians
* Rooftop victims
* Hazard-exposed civilians

### UAVs

* Multiple UAV classes
* Position
* Movement
* Battery
* Mission
* Telemetry
* Search behavior

The Digital Twin provides a safe and repeatable environment for testing the intelligence layer.

---

# 🌊 Flood Simulation

The flood system models dynamic environmental progression rather than a static water surface.

The simulation can represent:

* Flood-front progression
* Increasing water levels
* Civilian exposure
* Rooftop stranding
* Wall stranding
* Floating civilians
* Debris
* Distress beacons

This allows the response engine to operate against an evolving environment.

---

# 🌐 Three-Layer Architecture

## Layer 1 — Simulation

**Godot 4.7+**

Responsible for:

* Environment
* Disaster physics/logic
* Civilians
* UAV movement
* Sensor simulation
* Telemetry

## Layer 2 — Intelligence

**Python + FastAPI**

Responsible for:

* World state
* Decision-making
* Prioritization
* Resource allocation
* Search planning
* Routing
* Risk
* Mission management
* Replanning
* Safety validation
* Audit logging

## Layer 3 — Command Center

**React + TypeScript**

Responsible for:

* Visualization
* Operator interaction
* Tactical monitoring
* Fleet control
* Victim intelligence
* Mission control
* Voice/text commands
* System diagnostics

---

# 🧩 Technology Stack

## Frontend

* React 19
* TypeScript
* Vite
* Tailwind CSS
* Lucide React
* REST APIs
* WebSockets

## Backend

* Python 3.11+
* FastAPI
* Uvicorn
* Pydantic
* WebSockets
* NetworkX
* NumPy
* SQLite / aiosqlite
* Pytest
* HTTPX

## Digital Twin / Simulation

* Godot 4.7+
* GDScript
* 3D procedural environment
* Disaster simulation
* UAV simulation

## Algorithms

* A* graph search
* Hazard-aware route costing
* Multi-criteria decision scoring
* Utility-based resource allocation
* Multi-UAV search partitioning
* Risk scoring
* Constraint-based command validation
* Dynamic replanning

---

# 🏗️ Repository Structure

```text
RESQNET/
│
├── backend/
│   ├── app/
│   │   ├── agents/
│   │   ├── api/
│   │   ├── core/
│   │   ├── models/
│   │   ├── services/
│   │   ├── routing/
│   │   ├── world/
│   │   └── main.py
│   │
│   ├── tests/
│   ├── requirements.txt
│   └── ...
│
├── frontend/
│   ├── src/
│   │   ├── components/
│   │   ├── pages/
│   │   ├── services/
│   │   ├── hooks/
│   │   └── ...
│   ├── package.json
│   └── ...
│
├── godot/
│   └── RESQNET_ELITE_SIM/
│       ├── scenes/
│       ├── scripts/
│       ├── systems/
│       └── project.godot
│
├── docs/
│
└── README.md
```

---

# 🚀 Getting Started

## Requirements

Install:

* Python 3.11+
* Node.js 18+
* npm
* Godot 4.7+
* Git

---

# ⚙️ 1. Clone the Repository

```bash
git clone https://github.com/anuragyadav06/RESQNET-AI-Disaster-Response-System.git
cd RESQNET
```

---

# 🐍 2. Setup Backend

### Windows PowerShell

```powershell
cd backend

python -m venv .venv

.\.venv\Scripts\Activate.ps1

pip install -r requirements.txt
```

Start the backend:

```powershell
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Backend:

```text
http://localhost:8000
```

FastAPI documentation:

```text
http://localhost:8000/docs
```

---

# ⚛️ 3. Setup Frontend

Open another terminal:

```powershell
cd frontend

npm install

npm run dev
```

The Vite development server will provide the frontend URL shown in the terminal.

---

# 🎮 4. Run the Digital Twin

Open the Godot project:

```text
godot/RESQNET_ELITE_SIM/project.godot
```

Launch the project using **Godot 4.7+**.

Make sure the FastAPI backend is running before connecting the Digital Twin.

---

# 🔌 Communication Flow

Once all three systems are running:

```text
Godot Digital Twin
       │
       │ WebSocket
       ▼
FastAPI Intelligence Core
       │
       │ WebSocket / REST
       ▼
React Command Center
```

The backend acts as the central coordination layer.

---

# 🧪 Example Operational Scenario

A typical RESQNET mission can execute as follows:

### 1. Disaster

```text
Earthquake triggered
```

### 2. Environment Update

The Digital Twin updates:

* Damaged buildings
* Roads
* Hazards
* Civilian locations

### 3. Reconnaissance

Scout UAVs begin parallel search.

### 4. Victim Observation

A scout detects a victim.

### 5. Intelligence

The observation is validated and converted into structured victim intelligence.

### 6. Prioritization

The system calculates the victim's priority.

```text
Priority = CRITICAL
```

### 7. Resource Allocation

The system identifies eligible UAVs.

```text
Required capability → RESCUE
```

### 8. UAV Selection

Candidate UAVs are evaluated using:

* Capability
* Battery
* Distance
* Risk
* Availability

### 9. Route Planning

A* calculates a hazard-aware route.

### 10. Safety Validation

The mission command is checked.

### 11. Execution

The command is transmitted to the Digital Twin.

### 12. Telemetry

UAV state is continuously returned.

### 13. Environmental Change

A road becomes blocked.

### 14. Replanning

The route is recalculated.

### 15. Mission Completion

The victim state and mission state are updated.

---

# 📊 Explainability & Auditability

RESQNET is designed to answer:

### Why was this victim prioritized?

```text
Medical severity
+ Survival urgency
+ Hazard exposure
+ Accessibility
+ Detection confidence
```

### Why was this UAV selected?

```text
Capability match
+ Battery sufficiency
+ Distance
+ Route risk
+ Availability
```

### Why was a command rejected?

```text
Insufficient battery
OR
Invalid waypoint
OR
Unknown UAV
OR
Unsafe command parameters
```

### Why was a mission replanned?

```text
Route invalidation
OR
Hazard change
OR
Battery safety
OR
Operational state change
```

This makes the system significantly more suitable for safety-critical decision support than an unexplained black-box output.

---

# 🔐 Safety Philosophy

RESQNET follows a layered safety architecture:

```text
Perception
    ↓
Decision
    ↓
Risk Assessment
    ↓
Constraint Validation
    ↓
Human Oversight
    ↓
Command
    ↓
Execution
```

Low-level flight safety would ultimately remain under the certified flight controller of the physical UAV.

RESQNET is designed to operate as the **mission-level intelligence and coordination layer**, not as a replacement for certified flight-control systems.

---

# 🧠 AI vs Algorithmic Intelligence

An important design principle of RESQNET is that not every decision needs a neural network.

The current prototype uses explainable computational intelligence where deterministic behavior is desirable:

### Algorithmic / Decision Intelligence

* Victim prioritization
* Resource allocation
* Search partitioning
* A* routing
* Risk scoring
* Constraint validation
* Mission orchestration
* Replanning

### Future Machine Learning

The architecture is designed to support ML-based perception such as:

```text
RGB Camera
    ↓
Object Detection
    ↓
Human Detection
    ↓
Victim Classification
    ↓
Confidence
    ↓
Victim Intelligence
```

Potential future models include:

* YOLO-based human detection
* Thermal-image detection
* Computer vision classification
* Victim pose estimation
* Learned survival/urgency estimation

This separation keeps safety-critical mission logic explainable while allowing learned perception models to improve detection.

---

# 🛰️ Future Real-World Integration

The current system is a simulation/research prototype.

A physical deployment could introduce adapters between RESQNET and real UAV infrastructure.

Potential architecture:

```text
Real UAV
   │
   ├── Camera
   ├── GPS
   ├── IMU
   ├── Battery telemetry
   └── Flight controller
          │
          ▼
   MAVLink / ROS2 / MQTT
          │
          ▼
   RESQNET UAV Gateway
          │
          ▼
   RESQNET Intelligence Core
```

Potential future integrations include:

* PX4
* ArduPilot
* MAVLink
* ROS2
* MQTT
* Real RGB cameras
* Thermal cameras
* GPS
* GIS data
* Weather data
* PostgreSQL
* PostGIS
* Redis
* Edge computing
* Secure field communication networks

---

# 🧪 Current Prototype vs Future Production System

| Capability            | Current Prototype        | Future Production                  |
| --------------------- | ------------------------ | ---------------------------------- |
| Disaster environment  | Simulated                | Real + Digital Twin                |
| UAVs                  | Simulated                | Physical UAVs                      |
| Victim observations   | Simulated                | RGB / Thermal CV                   |
| Victim prioritization | Explainable scoring      | Hybrid scoring + ML                |
| Routing               | Hazard-aware A*          | A* / RRT* / advanced planners      |
| Fleet allocation      | Utility-based            | Dynamic multi-agent optimization   |
| Telemetry             | Simulated                | MAVLink / ROS2 / telemetry gateway |
| Database              | In-memory + SQLite audit | PostgreSQL + PostGIS               |
| Communication         | WebSocket                | Secure field communication         |
| Flight safety         | Simulation validation    | Certified flight controller        |
| Operator              | React Command Center     | Emergency operations center        |
| Digital Twin          | Godot                    | Real-time operational twin         |

---

# 📈 Future Roadmap

## Phase 1 — Current Prototype

* [x] Digital Twin
* [x] Disaster simulation
* [x] Multi-UAV fleet
* [x] Victim intelligence
* [x] Victim prioritization
* [x] Resource allocation
* [x] Search planning
* [x] Hazard-aware routing
* [x] Mission orchestration
* [x] WebSocket communication
* [x] Safety validation
* [x] Dynamic replanning
* [x] React command center
* [x] Voice/text command architecture
* [x] Audit logging

## Phase 2 — Advanced Intelligence

* [ ] Real computer vision
* [ ] YOLO-based victim detection
* [ ] Thermal imaging support
* [ ] Learned victim classification
* [ ] Dynamic search-area optimization
* [ ] Advanced multi-UAV task allocation
* [ ] Improved uncertainty modeling

## Phase 3 — Real UAV Integration

* [ ] PX4 integration
* [ ] ArduPilot integration
* [ ] MAVLink gateway
* [ ] Real telemetry
* [ ] Real GPS
* [ ] Real cameras
* [ ] Hardware-in-the-loop testing

## Phase 4 — Production Infrastructure

* [ ] PostgreSQL/PostGIS
* [ ] Redis/event streaming
* [ ] Secure authentication
* [ ] Distributed deployment
* [ ] Edge computing
* [ ] Fault-tolerant communication
* [ ] Field testing
* [ ] Safety certification
* [ ] Integration with emergency-response agencies

---

# 🏆 Key Engineering Principles

### 1. Human-in-the-Loop

Automation assists emergency personnel rather than replacing human authority.

### 2. Explainability

Critical decisions should have understandable reasoning.

### 3. Safety First

Commands are validated before execution.

### 4. Modular Architecture

Simulation, intelligence and visualization are separated.

### 5. Hardware Independence

The decision layer is designed to communicate through adapters rather than being tied directly to one UAV platform.

### 6. Dynamic Response

The environment is continuously treated as changing world state.

### 7. Auditability

Operational decisions and important state transitions can be recorded and inspected.

### 8. Simulation Before Deployment

High-risk scenarios can be tested repeatedly before physical UAV deployment.

---

# 🎯 Impact

RESQNET is designed to reduce the cognitive and operational burden on disaster-response teams by helping them:

* Search affected regions faster
* Prioritize victims systematically
* Assign appropriate UAV resources
* Avoid unnecessary route risk
* Coordinate heterogeneous UAV fleets
* Detect changing mission conditions
* Replan when the environment changes
* Maintain operator oversight
* Understand why automated recommendations were made

The long-term objective is a scalable disaster-response coordination platform capable of coordinating not only UAVs but potentially:

```text
UAVs
+
Ground Robots
+
Ambulances
+
Rescue Teams
+
Hospitals
+
Supply Depots
+
Communication Relays
```

under a common operational intelligence layer.

---

# ⚠️ Project Status & Disclaimer

RESQNET is currently a **research and demonstration prototype**.

The current system uses a simulated Digital Twin and simulated UAV environment for controlled testing.

It is **not currently certified for real-world autonomous flight or life-critical emergency deployment**.

Physical deployment would require:

* Certified flight-control systems
* Hardware validation
* Communication redundancy
* Regulatory compliance
* Aviation safety procedures
* Real sensor validation
* Cybersecurity controls
* Extensive hardware-in-the-loop testing
* Field testing under controlled conditions

The architecture is intentionally designed so these components can be introduced progressively.

---

# 👥 Project Vision

RESQNET aims to move disaster response from:

```text
Manual Monitoring
       ↓
Manual Decisions
       ↓
Manual Dispatch
       ↓
Reactive Response
```

towards:

```text
Continuous Situational Awareness
             ↓
Explainable Intelligence
             ↓
Optimized Resource Allocation
             ↓
Safety-Gated Automation
             ↓
Dynamic Replanning
             ↓
Human-Supervised Response
```

---

# ⭐ Why RESQNET?

> **Because in a disaster, the challenge isn't only finding people.**
>
> **The challenge is deciding who needs help first, which resource should respond, how it should reach them safely, and how the response should adapt when the situation changes.**

RESQNET is designed around solving that complete coordination problem.

---

## 📜 License

This project is released under the MIT License.

See `LICENSE` for details.

---

## 👨‍💻 Project

**RESQNET — AI-Assisted Multi-UAV Disaster Response & Digital Twin Platform**

Built as a research-oriented disaster-response coordination and simulation system.

**Core technologies:** Python • FastAPI • React • TypeScript • Godot • WebSockets • NetworkX • A* • Explainable Decision Intelligence
