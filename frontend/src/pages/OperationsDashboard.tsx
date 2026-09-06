import React, { useState } from 'react';
import { WorldStateSnapshot, DroneEntity, Victim, RoadEdge } from '../types';
import { TacticalMap } from '../components/TacticalMap';
import { api } from '../services/api';
import {
  Activity,
  AlertTriangle,
  Flame,
  Radio,
  Shield,
  Play,
  RotateCcw,
  RefreshCw,
  HeartPulse,
  Send,
  Sliders,
  CheckCircle2,
  XCircle,
  Wrench,
} from 'lucide-react';

interface OperationsDashboardProps {
  snapshot: WorldStateSnapshot | null;
  isConnected: boolean;
  latencyMs: number;
  onRefresh: () => void;
}

export const OperationsDashboard: React.FC<OperationsDashboardProps> = ({
  snapshot,
  isConnected,
  latencyMs,
  onRefresh,
}) => {
  const [selectedEntity, setSelectedEntity] = useState<any | null>(null);
  const [entityType, setEntityType] = useState<string>('');
  const [actionLoading, setActionLoading] = useState<string>('');
  const [actionMessage, setActionMessage] = useState<{ text: string; isError?: boolean } | null>(null);

  const handleSelectEntity = (entity: any, type: string) => {
    setSelectedEntity(entity);
    setEntityType(type);
  };

  const showFeedback = (text: string, isError = false) => {
    setActionMessage({ text, isError });
    setTimeout(() => setActionMessage(null), 4000);
  };

  // Scenario Triggers
  const handleTriggerEarthquake = async () => {
    setActionLoading('earthquake');
    try {
      const res = await api.triggerEarthquake();
      showFeedback(res.message || 'Metro Earthquake scenario triggered!');
      onRefresh();
    } catch (e: any) {
      showFeedback(e.message, true);
    } finally {
      setActionLoading('');
    }
  };

  const handleTriggerAftershock = async () => {
    setActionLoading('aftershock');
    try {
      const res = await api.triggerAftershock();
      showFeedback(res.message || 'Aftershock triggered! Missions dynamically rerouted.');
      onRefresh();
    } catch (e: any) {
      showFeedback(e.message, true);
    } finally {
      setActionLoading('');
    }
  };

  const handleResetCity = async () => {
    setActionLoading('reset');
    try {
      await api.resetSimulation();
      showFeedback('Simulation reset to pristine conditions.');
      setSelectedEntity(null);
      onRefresh();
    } catch (e: any) {
      showFeedback(e.message, true);
    } finally {
      setActionLoading('');
    }
  };

  const handleAutoPlan = async () => {
    setActionLoading('autoplan');
    try {
      const res = await api.autoPlanMission();
      showFeedback(`Mission dispatched: ${res.mission?.mission_id}`);
      onRefresh();
    } catch (e: any) {
      showFeedback(e.message, true);
    } finally {
      setActionLoading('');
    }
  };

  const handleForceReplan = async () => {
    setActionLoading('replan');
    try {
      const res = await api.evaluateReplanning();
      showFeedback(`Replanning executed: ${res.replan_results?.length || 0} missions assessed.`);
      onRefresh();
    } catch (e: any) {
      showFeedback(e.message, true);
    } finally {
      setActionLoading('');
    }
  };

  const handleToggleRoad = async (edge: RoadEdge) => {
    try {
      if (edge.is_blocked) {
        await api.unblockRoad(edge.id);
        showFeedback(`Road ${edge.id} cleared and unblocked.`);
      } else {
        await api.blockRoad(edge.id, 'Manual operator road block');
        showFeedback(`Road ${edge.id} BLOCKED. Rerouting evaluated.`);
      }
      onRefresh();
    } catch (e: any) {
      showFeedback(e.message, true);
    }
  };

  const handleDispatchToVictim = async (
    victimId: string,
    objective: 'RESCUE_EXTRACTION' | 'MEDICAL_SUPPLY_DROP' | 'HEAVY_EXTRICATION'
  ) => {
    setActionLoading(`${victimId}:${objective}`);
    try {
      const res = await api.dispatchDrone('AUTO', victimId, objective);
      showFeedback(res.message || `${objective} dispatched for ${victimId}`);
      onRefresh();
    } catch (e: any) {
      showFeedback(e?.message || 'Dispatch rejected by System A.', true);
    } finally {
      setActionLoading('');
    }
  };

  // KPIs — total detected victims remains the denominator; critical count
  // is calculated from unresolved victims using the explainable assessment.
  const allVictims = snapshot ? Object.values(snapshot.victims) : [];
  const terminalVictimStatuses = new Set([
    'RESCUED', 'ASSISTED', 'EVACUATED', 'TREATED',
    'STABILIZED', 'MEDICALLY_STABILIZED', 'RESOLVED', 'SAFE',
  ]);
  const activeVictims = allVictims.filter(
    (v) => !v.assigned_mission_id && !terminalVictimStatuses.has(String(v.status).toUpperCase())
  );
  const criticalVictims = activeVictims.filter((v) => v.priority_class === 'CRITICAL');
  const criticalCount = criticalVictims.length;
  const totalVictimCount = allVictims.length;
  const activeIncidentsCount = snapshot ? Object.keys(snapshot.incidents).length : 0;
  const idleDronesCount = snapshot
    ? Object.values(snapshot.drones).filter((d) => d.status === 'IDLE').length
    : 0;
  const availableMedical = snapshot ? Object.values(snapshot.drones).filter(d => d.status === 'IDLE' && d.capabilities.includes('MEDICAL')).length : 0;
  const availableRescue = snapshot ? Object.values(snapshot.drones).filter(d => d.status === 'IDLE' && d.capabilities.includes('RESCUE')).length : 0;
  const availableHeavy = snapshot ? Object.values(snapshot.drones).filter(d => d.status === 'IDLE' && d.capabilities.includes('HEAVY_LIFT')).length : 0;

  return (
    <div className="space-y-4">
      {/* 1. Live Operation Status Banner */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        {/* Critical Victims */}
        <div className="bg-[#0b121e] border border-cyan-900/40 p-3 rounded-lg flex items-center gap-3">
          <div className={`p-2 rounded-lg ${criticalCount > 0 ? 'bg-red-950 text-red-400' : 'bg-slate-800 text-slate-400'}`}>
            <AlertTriangle className="w-5 h-5" />
          </div>
          <div>
            <div className="text-[10px] text-slate-400 uppercase font-mono tracking-wider">Critical Victims</div>
            <div className="text-sm font-bold font-mono text-red-400">{criticalCount} <span className="text-xs text-slate-400 font-normal">/ {totalVictimCount}</span></div>
            <div className="text-[10px] text-slate-500 font-mono">State + hazard + medical + accessibility</div>
          </div>
        </div>

        {/* Drone Readiness */}
        <div className="bg-[#0b121e] border border-cyan-900/40 p-3 rounded-lg flex items-center gap-3">
          <div className="p-2 rounded-lg bg-cyan-950 text-cyan-400">
            <Shield className="w-5 h-5" />
          </div>
          <div>
            <div className="text-[10px] text-slate-400 uppercase font-mono tracking-wider">Fleet Ready</div>
            <div className="text-sm font-bold font-mono text-cyan-300">
              {idleDronesCount} <span className="text-xs text-slate-400 font-normal">/ {snapshot ? Object.keys(snapshot.drones).length : 4}</span>
            </div>
            <div className="text-[10px] text-slate-500 font-mono">Base Alpha hangar</div>
          </div>
        </div>

        {/* Active Incidents */}
        <div className="bg-[#0b121e] border border-cyan-900/40 p-3 rounded-lg flex items-center gap-3">
          <div className="p-2 rounded-lg bg-orange-950 text-orange-400">
            <Flame className="w-5 h-5" />
          </div>
          <div>
            <div className="text-[10px] text-slate-400 uppercase font-mono tracking-wider">Active Incidents</div>
            <div className="text-sm font-bold font-mono text-orange-300">{activeIncidentsCount} Declared</div>
            <div className="text-[10px] text-slate-500 font-mono">{snapshot ? Object.keys(snapshot.hazards).length : 0} hazard zones</div>
          </div>
        </div>
      </div>

      {/* 2. Operational Action Toolbar */}
      <div className="bg-[#0e1626] border border-cyan-800/40 p-2.5 rounded-lg flex flex-wrap items-center justify-between gap-2 shadow-lg">
        <div className="flex items-center gap-2">
          <span className="text-xs font-mono font-bold text-slate-300 mr-2 flex items-center gap-1.5">
            <Sliders className="w-4 h-4 text-cyan-400" /> Scenario Commands:
          </span>
          <button
            onClick={handleTriggerEarthquake}
            disabled={actionLoading !== ''}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-red-600 hover:bg-red-500 text-white text-xs font-mono font-bold rounded shadow transition disabled:opacity-50"
          >
            <Activity className="w-3.5 h-3.5" /> Trigger Metro Earthquake (M 7.2)
          </button>
          <button
            onClick={handleTriggerAftershock}
            disabled={actionLoading !== ''}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-amber-600 hover:bg-amber-500 text-white text-xs font-mono font-bold rounded shadow transition disabled:opacity-50"
          >
            <AlertTriangle className="w-3.5 h-3.5" /> Inject Roadblock & Replan
          </button>
          <button
            onClick={handleResetCity}
            disabled={actionLoading !== ''}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-700 hover:bg-slate-600 text-slate-200 text-xs font-mono rounded transition disabled:opacity-50"
          >
            <RotateCcw className="w-3.5 h-3.5" /> Reset City
          </button>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={handleAutoPlan}
            disabled={actionLoading !== ''}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-cyan-600 hover:bg-cyan-500 text-white text-xs font-mono font-bold rounded shadow transition disabled:opacity-50"
          >
            <Send className="w-3.5 h-3.5" /> Auto-Dispatch Top Victim
          </button>
          <button
            onClick={handleForceReplan}
            disabled={actionLoading !== ''}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-indigo-700 hover:bg-indigo-600 text-white text-xs font-mono rounded transition disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${actionLoading === 'replan' ? 'animate-spin' : ''}`} /> Force Replan
          </button>
        </div>
      </div>

      {/* Feedback Notification */}
      {actionMessage && (
        <div
          className={`p-2.5 rounded-lg text-xs font-mono flex items-center gap-2 border ${
            actionMessage.isError
              ? 'bg-red-950/90 text-red-300 border-red-700'
              : 'bg-emerald-950/90 text-emerald-300 border-emerald-700'
          }`}
        >
          {actionMessage.isError ? <XCircle className="w-4 h-4" /> : <CheckCircle2 className="w-4 h-4" />}
          {actionMessage.text}
        </div>
      )}

      {/* 3. Main Center Grid: Tactical Map (Left) + Tactical Entity Inspector (Right) */}
      <div className="grid grid-cols-1 lg:grid-cols-4 gap-4">
        {/* Tactical Map (3 Cols) */}
        <div className="lg:col-span-3">
          <TacticalMap
            snapshot={snapshot}
            selectedEntity={selectedEntity}
            onSelectEntity={handleSelectEntity}
          />
        </div>

        {/* Entity Inspector Drawer (1 Col) */}
        <div className="bg-[#0b121e] border border-cyan-900/40 rounded-xl p-4 flex flex-col justify-between shadow-xl">
          <div>
            <div className="border-b border-cyan-900/40 pb-2 mb-3 flex items-center justify-between">
              <span className="text-xs font-mono uppercase tracking-wider text-cyan-400 font-bold flex items-center gap-1.5">
                <Radio className="w-3.5 h-3.5 text-cyan-400" /> Entity Inspector
              </span>
              <span className="text-[10px] font-mono text-slate-500">
                {entityType || 'NO SELECTION'}
              </span>
            </div>

            {!selectedEntity ? (
              <div className="py-12 text-center text-xs text-slate-500 font-mono">
                Click any drone, victim, road segment, hazard, or building on the tactical radar to inspect live telemetry.
              </div>
            ) : (
              <div className="space-y-3 text-xs">
                {/* Drone Inspector */}
                {entityType === 'DRONE' && (
                  <div className="space-y-2">
                    <div className="text-sm font-bold font-mono text-slate-100">{selectedEntity.id}</div>
                    <div className="text-[11px] text-slate-400">{selectedEntity.callsign}</div>
                    <div className="grid grid-cols-2 gap-2 pt-2">
                      <div className="bg-slate-900 p-2 rounded">
                        <div className="text-[10px] text-slate-500">BATTERY</div>
                        <div className="font-mono text-emerald-400 font-bold">{selectedEntity.battery_percent.toFixed(1)}%</div>
                      </div>
                      <div className="bg-slate-900 p-2 rounded">
                        <div className="text-[10px] text-slate-500">STATUS</div>
                        <div className="font-mono text-cyan-300 font-bold">{selectedEntity.status}</div>
                      </div>
                      <div className="bg-slate-900 p-2 rounded">
                        <div className="text-[10px] text-slate-500">ALTITUDE</div>
                        <div className="font-mono text-slate-300">{selectedEntity.position.y.toFixed(1)} m</div>
                      </div>
                      <div className="bg-slate-900 p-2 rounded">
                        <div className="text-[10px] text-slate-500">PAYLOAD</div>
                        <div className="font-mono text-slate-300">{selectedEntity.current_payload_kg} / {selectedEntity.max_payload_kg} kg</div>
                      </div>
                    </div>
                    <div className="text-[11px] text-slate-400 font-mono pt-1">
                      Capabilities: {selectedEntity.capabilities?.join(', ')}
                    </div>
                  </div>
                )}

                {/* Victim Inspector */}
                {entityType === 'VICTIM' && (
                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-sm font-bold font-mono text-slate-100">{selectedEntity.id}</span>
                      <span className={`px-2 py-0.5 rounded font-mono font-bold text-[10px] ${
                        selectedEntity.priority_class === 'CRITICAL' ? 'bg-red-950 text-red-300 border border-red-700' : 'bg-amber-950 text-amber-300'
                      }`}>
                        {selectedEntity.priority_class}
                      </span>
                    </div>
                    <div className="text-[11px] text-slate-300">{selectedEntity.name}</div>
                    <div className="bg-slate-900 p-2 rounded space-y-1">
                      <div className="flex justify-between text-[11px]">
                        <span className="text-slate-400">Medical Severity:</span>
                        <span className="font-mono text-red-400">{(selectedEntity.medical_severity * 100).toFixed(0)}%</span>
                      </div>
                      <div className="flex justify-between text-[11px]">
                        <span className="text-slate-400">Survival Urgency:</span>
                        <span className="font-mono text-amber-400">{(selectedEntity.estimated_survival_urgency * 100).toFixed(0)}%</span>
                      </div>
                      <div className="flex justify-between text-[11px]">
                        <span className="text-slate-400">People Count:</span>
                        <span className="font-mono text-slate-200">{selectedEntity.people_count} trapped</span>
                      </div>
                      <div className="flex justify-between text-[11px]">
                        <span className="text-slate-400">Priority Score:</span>
                        <span className="font-mono text-cyan-300 font-bold">{selectedEntity.priority_score.toFixed(3)}</span>
                      </div>
                      <div className="flex justify-between text-[11px]">
                        <span className="text-slate-400">Confidence:</span>
                        <span className="font-mono text-emerald-400">{(selectedEntity.confidence * 100).toFixed(0)}%</span>
                      </div>
                      <div className="pt-1 border-t border-slate-800 mt-1 text-[10px]">
                        <span className="text-cyan-400 font-bold">Assessment basis:</span>
                        <span className="text-slate-400"> observed state, hazard exposure, medical severity, survival urgency and accessibility.</span>
                      </div>
                    </div>

                    {/* Compact explainability: keep the most operationally useful reasons visible. */}
                    {selectedEntity.breakdown?.reasons && (
                      <div className="text-[10px] text-slate-400">
                        <div className="font-bold text-slate-300 mb-1">Explainable Reasons</div>
                        <div className="flex flex-wrap gap-x-2 gap-y-0.5">
                          {selectedEntity.breakdown.reasons
                            .filter((r: string) => {
                              const text = String(r).toLowerCase();
                              return (
                                !text.includes('bounded') &&
                                !text.includes('assessment confidence') &&
                                !text.includes('operational confidence') &&
                                !text.includes('priority score combines') &&
                                !text.includes('confidence uses')
                              );
                            })
                            .slice(0, 3)
                            .map((r: string, idx: number) => (
                              <span key={idx} className="font-mono text-slate-400">
                                • {r}
                              </span>
                            ))}
                        </div>
                      </div>
                    )}

                    {selectedEntity.status !== 'EVACUATED' && (
                      <div className="grid grid-cols-1 gap-2 mt-2">
                        <button onClick={() => handleDispatchToVictim(selectedEntity.id, 'MEDICAL_SUPPLY_DROP')} disabled={!!actionLoading || availableMedical === 0} className="w-full py-1.5 bg-emerald-700 hover:bg-emerald-600 disabled:opacity-40 text-white font-mono font-bold rounded shadow transition flex items-center justify-center gap-1.5"><HeartPulse className="w-3.5 h-3.5"/> Dispatch Medical {availableMedical === 0 ? '(NONE READY)' : `(${availableMedical})`}</button>
                        <button onClick={() => handleDispatchToVictim(selectedEntity.id, 'RESCUE_EXTRACTION')} disabled={!!actionLoading || availableRescue === 0} className="w-full py-1.5 bg-red-600 hover:bg-red-500 disabled:opacity-40 text-white font-mono font-bold rounded shadow transition flex items-center justify-center gap-1.5"><Send className="w-3.5 h-3.5"/> Dispatch Rescue {availableRescue === 0 ? '(NONE READY)' : `(${availableRescue})`}</button>
                        <button onClick={() => handleDispatchToVictim(selectedEntity.id, 'HEAVY_EXTRICATION')} disabled={!!actionLoading || availableHeavy === 0} className="w-full py-1.5 bg-amber-700 hover:bg-amber-600 disabled:opacity-40 text-white font-mono font-bold rounded shadow transition flex items-center justify-center gap-1.5"><Wrench className="w-3.5 h-3.5"/> Dispatch Heavy Lift {availableHeavy === 0 ? '(NONE READY)' : `(${availableHeavy})`}</button>
                      </div>
                    )}
                  </div>
                )}

                {/* Road Segment Inspector */}
                {entityType === 'ROAD' && (
                  <div className="space-y-2">
                    <div className="text-sm font-bold font-mono text-slate-100">{selectedEntity.id}</div>
                    <div className="text-slate-400 text-[11px]">Length: {selectedEntity.distance_m}m</div>
                    <div className={`p-2 rounded font-mono ${selectedEntity.is_blocked ? 'bg-red-950 text-red-300 border border-red-700' : 'bg-slate-900 text-emerald-400'}`}>
                      {selectedEntity.is_blocked ? '⛔ ROAD BLOCKED' : '✅ ROAD CLEAR'}
                    </div>
                    {selectedEntity.blockage_reason && (
                      <div className="text-[11px] text-red-400 font-mono">Reason: {selectedEntity.blockage_reason}</div>
                    )}
                    <button
                      onClick={() => handleToggleRoad(selectedEntity)}
                      className={`w-full py-1.5 rounded font-mono font-bold transition ${
                        selectedEntity.is_blocked
                          ? 'bg-emerald-700 hover:bg-emerald-600 text-white'
                          : 'bg-red-700 hover:bg-red-600 text-white'
                      }`}
                    >
                      {selectedEntity.is_blocked ? 'Clear Roadway' : 'Block Roadway'}
                    </button>
                  </div>
                )}

                {/* Hazard Inspector */}
                {entityType === 'HAZARD' && (
                  <div className="space-y-2">
                    <div className="text-sm font-bold font-mono text-orange-400">{selectedEntity.type}</div>
                    <div className="bg-slate-900 p-2 rounded space-y-1">
                      <div className="flex justify-between">
                        <span className="text-slate-400">Radius:</span>
                        <span className="font-mono text-slate-200">{selectedEntity.radius_m}m</span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-slate-400">Intensity:</span>
                        <span className="font-mono text-orange-300">{(selectedEntity.intensity * 100).toFixed(0)}%</span>
                      </div>
                    </div>
                  </div>
                )}

                {/* Building Inspector */}
                {entityType === 'BUILDING' && (
                  <div className="space-y-2">
                    <div className="text-sm font-bold font-mono text-slate-100">{selectedEntity.name}</div>
                    <div className="text-slate-400 text-[11px]">District: {selectedEntity.district}</div>
                    <div className="bg-slate-900 p-2 rounded">
                      <div className="text-[10px] text-slate-500">DAMAGE LEVEL</div>
                      <div className={`font-mono font-bold ${
                        selectedEntity.damage_level === 'COLLAPSED' ? 'text-red-400' : selectedEntity.damage_level === 'STRUCTURAL_CRACK' ? 'text-amber-400' : 'text-emerald-400'
                      }`}>
                        {selectedEntity.damage_level}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>

          <div className="pt-3 border-t border-cyan-900/40 text-[10px] text-slate-500 font-mono flex items-center justify-between">
            <span>Coordinate Space: 400m²</span>
            <span>ResQNet Engine A</span>
          </div>
        </div>
      </div>
    </div>
  );
};
