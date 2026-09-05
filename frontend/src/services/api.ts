// ResQNet REST API Client

import {
  HealthStatus,
  WorldStateSnapshot,
  Victim,
  DroneEntity,
  MissionPlan,
  IncidentEntity,
  AuditRecord,
  Vector3D,
} from '../types';

const API_BASE = 'http://localhost:8000/api/v1';

async function handleResponse<T>(res: Response): Promise<T> {
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`API Error ${res.status}: ${errText}`);
  }
  return res.json();
}

export const api = {
  async getHealth(): Promise<HealthStatus> {
    const res = await fetch(`${API_BASE}/health`);
    return handleResponse<HealthStatus>(res);
  },

  async getWorldState(): Promise<WorldStateSnapshot> {
    const res = await fetch(`${API_BASE}/world`);
    return handleResponse<WorldStateSnapshot>(res);
  },

  async triggerEarthquake(): Promise<any> {
    const res = await fetch(`${API_BASE}/simulation/earthquake`, { method: 'POST' });
    return handleResponse<any>(res);
  },

  async triggerAftershock(): Promise<any> {
    const res = await fetch(`${API_BASE}/simulation/aftershock`, { method: 'POST' });
    return handleResponse<any>(res);
  },

  async resetSimulation(): Promise<any> {
    const res = await fetch(`${API_BASE}/simulation/reset`, { method: 'POST' });
    return handleResponse<any>(res);
  },

  async listVictims(): Promise<Victim[]> {
    const res = await fetch(`${API_BASE}/victims`);
    return handleResponse<Victim[]>(res);
  },

  async reprioritizeVictims(): Promise<Victim[]> {
    const res = await fetch(`${API_BASE}/victims/reprioritize`, { method: 'POST' });
    return handleResponse<Victim[]>(res);
  },

  async listDrones(): Promise<DroneEntity[]> {
    const res = await fetch(`${API_BASE}/drones`);
    return handleResponse<DroneEntity[]>(res);
  },

  async dispatchDrone(drone_id: string, victim_id: string, objective?: string): Promise<any> {
    const res = await fetch(`${API_BASE}/drones/dispatch`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ drone_id, victim_id, objective }),
    });
    return handleResponse<any>(res);
  },
  async executeOperatorCommand(text: string): Promise<any> {
    const res = await fetch(`${API_BASE}/voice/execute`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text }),
    });
    return handleResponse<any>(res);
  },

  // Backward-compatible alias for existing screens.
  async executeVoiceCommand(text: string): Promise<any> {
    return this.executeOperatorCommand(text);
  },

  async listMissions(): Promise<MissionPlan[]> {
    const res = await fetch(`${API_BASE}/missions`);
    return handleResponse<MissionPlan[]>(res);
  },

  async autoPlanMission(): Promise<any> {
    const res = await fetch(`${API_BASE}/missions/auto-plan`, { method: 'POST' });
    return handleResponse<any>(res);
  },

  async abortMission(mission_id: string): Promise<any> {
    const res = await fetch(`${API_BASE}/missions/${mission_id}/abort`, { method: 'POST' });
    return handleResponse<any>(res);
  },

  async abortDroneMission(drone_id: string): Promise<any> {
    const res = await fetch(`${API_BASE}/drones/${drone_id}/abort-mission`, { method: 'POST' });
    return handleResponse<any>(res);
  },

  async rtbDrone(drone_id: string): Promise<any> {
    const res = await fetch(`${API_BASE}/drones/${drone_id}/rtb`, { method: 'POST' });
    return handleResponse<any>(res);
  },

  async listIncidents(): Promise<IncidentEntity[]> {
    const res = await fetch(`${API_BASE}/incidents`);
    return handleResponse<IncidentEntity[]>(res);
  },

  async createIncident(type: string, title: string, location: Vector3D, severity: number): Promise<IncidentEntity> {
    const res = await fetch(`${API_BASE}/incidents`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type, title, location, severity }),
    });
    return handleResponse<IncidentEntity>(res);
  },

  async blockRoad(edge_id: string, reason: string = 'Manual road blockage'): Promise<any> {
    const res = await fetch(`${API_BASE}/routes/block`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ edge_id, reason }),
    });
    return handleResponse<any>(res);
  },

  async unblockRoad(edge_id: string): Promise<any> {
    const res = await fetch(`${API_BASE}/routes/unblock`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ edge_id }),
    });
    return handleResponse<any>(res);
  },

  async listDecisions(limit: number = 50): Promise<AuditRecord[]> {
    const res = await fetch(`${API_BASE}/decisions?limit=${limit}`);
    return handleResponse<AuditRecord[]>(res);
  },

  async listEvents(limit: number = 100, event_type?: string): Promise<AuditRecord[]> {
    const url = event_type ? `${API_BASE}/events?limit=${limit}&event_type=${event_type}` : `${API_BASE}/events?limit=${limit}`;
    const res = await fetch(url);
    return handleResponse<AuditRecord[]>(res);
  },

  async evaluateReplanning(): Promise<any> {
    const res = await fetch(`${API_BASE}/replanning/evaluate`, { method: 'POST' });
    return handleResponse<any>(res);
  },

  async getSearchPlan(): Promise<any> {
    const res = await fetch(`${API_BASE}/search/plan`);
    return handleResponse<any>(res);
  },

  async startRecon(): Promise<any> {
    const res = await fetch(`${API_BASE}/response/recon`, { method: 'POST' });
    return handleResponse<any>(res);
  },

  async triageDispatch(): Promise<any> {
    const res = await fetch(`${API_BASE}/response/triage-dispatch`, { method: 'POST' });
    return handleResponse<any>(res);
  },

  async getResponseStatus(): Promise<any> {
    const res = await fetch(`${API_BASE}/response/status`);
    return handleResponse<any>(res);
  },

  async interpretVoice(text: string): Promise<any> {
    const res = await fetch(`${API_BASE}/voice/interpret`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text }),
    });
    return handleResponse<any>(res);
  },

  async getLiveEvents(limit = 50): Promise<any[]> {
    const res = await fetch(`${API_BASE}/events/live?limit=${limit}`);
    return handleResponse<any[]>(res);
  },
};