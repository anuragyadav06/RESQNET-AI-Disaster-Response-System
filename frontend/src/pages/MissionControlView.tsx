import React, { useState, useEffect } from 'react';
import { MissionPlan } from '../types';
import { api } from '../services/api';
import { Navigation, AlertTriangle, ShieldCheck, XOctagon, Clock, Battery, Send } from 'lucide-react';

interface MissionControlViewProps {
  onRefresh: () => void;
}

export const MissionControlView: React.FC<MissionControlViewProps> = ({ onRefresh }) => {
  const [missions, setMissions] = useState<MissionPlan[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [msg, setMsg] = useState<string>('');

  const fetchMissions = async () => {
    try {
      setLoading(true);
      const data = await api.listMissions();
      setMissions(data);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchMissions();
  }, []);

  const handleAbort = async (mId: string) => {
    if (!confirm(`Are you sure you want to abort mission ${mId}?`)) return;
    try {
      await api.abortMission(mId);
      setMsg(`Mission ${mId} aborted. Drone returning to base.`);
      fetchMissions();
      onRefresh();
    } catch (e: any) {
      setMsg('Error: ' + e.message);
    }
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-lg flex items-center justify-between">
        <div>
          <h2 className="text-base font-bold font-mono text-slate-100 flex items-center gap-2">
            <Navigation className="w-5 h-5 text-cyan-400" /> Mission Planning & Active Execution
          </h2>
          <p className="text-xs text-slate-400">
            Lifecycle monitoring of autonomous rescue missions, waypoint flight progress, and emergency aborts.
          </p>
        </div>
      </div>

      {msg && (
        <div className="p-2.5 bg-cyan-950/80 border border-cyan-700 text-cyan-300 rounded-lg text-xs font-mono">
          {msg}
        </div>
      )}

      {/* Missions Grid */}
      <div className="space-y-3">
        {missions.map((mission) => (
          <div
            key={mission.mission_id}
            className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-md space-y-3"
          >
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-800 pb-2">
              <div className="flex items-center gap-3">
                <span className="text-sm font-mono font-bold text-cyan-400">{mission.mission_id}</span>
                <span className="text-xs font-bold font-mono text-slate-200 uppercase tracking-wider">
                  {mission.objective}
                </span>
                <span className="text-xs font-mono text-slate-400">
                  Drone: <strong className="text-cyan-300">{mission.assigned_drone_id}</strong>
                </span>
                {mission.target_victim_id && (
                  <span className="text-xs font-mono text-slate-400">
                    Target: <strong className="text-red-400">{mission.target_victim_id}</strong>
                  </span>
                )}
              </div>

              <div className="flex items-center gap-2">
                {mission.replan_count > 0 && (
                  <span className="px-2 py-0.5 bg-amber-950 text-amber-300 border border-amber-700 rounded text-[10px] font-mono font-bold">
                    Rerouted ({mission.replan_count}x)
                  </span>
                )}
                <span
                  className={`px-2.5 py-0.5 rounded text-xs font-mono font-bold ${
                    mission.status === 'COMPLETED'
                      ? 'bg-emerald-950 text-emerald-300 border border-emerald-700'
                      : mission.status === 'ABORTED' || mission.status === 'FAILED'
                      ? 'bg-red-950 text-red-300 border border-red-700'
                      : 'bg-cyan-950 text-cyan-300 border border-cyan-700 animate-pulse'
                  }`}
                >
                  {mission.status}
                </span>
                {['PLANNED', 'DISPATCHED', 'IN_PROGRESS', 'REPLANNING'].includes(mission.status) && (
                  <button
                    onClick={() => handleAbort(mission.mission_id)}
                    className="px-2.5 py-1 bg-red-700 hover:bg-red-600 text-white text-[11px] font-mono rounded shadow flex items-center gap-1"
                  >
                    <XOctagon className="w-3.5 h-3.5" /> Abort
                  </button>
                )}
              </div>
            </div>

            {/* Metrics */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-2 bg-slate-900/80 p-2.5 rounded-lg text-xs font-mono">
              <div>
                <span className="text-slate-500 block text-[10px]">EST. DURATION</span>
                <span className="text-slate-200">{mission.estimated_duration_s} seconds</span>
              </div>
              <div>
                <span className="text-slate-500 block text-[10px]">BATTERY DRAIN</span>
                <span className="text-slate-200">~{mission.estimated_battery_drain.toFixed(1)}%</span>
              </div>
              <div>
                <span className="text-slate-500 block text-[10px]">MISSION RISK</span>
                <span
                  className={`font-bold ${
                    mission.risk?.category === 'CRITICAL'
                      ? 'text-red-400'
                      : mission.risk?.category === 'HIGH'
                      ? 'text-amber-400'
                      : 'text-emerald-400'
                  }`}
                >
                  {mission.risk?.category} ({(mission.risk?.overall_risk * 100 || 0).toFixed(0)}%)
                </span>
              </div>
              <div>
                <span className="text-slate-500 block text-[10px]">PRIORITY SCORE</span>
                <span className="text-cyan-300 font-bold">{mission.priority_score.toFixed(3)}</span>
              </div>
            </div>

            {/* Waypoints Sequence Bar */}
            <div>
              <div className="text-[10px] uppercase font-mono font-bold text-slate-400 mb-1">
                Flight Waypoints ({mission.waypoints.length} nodes):
              </div>
              <div className="flex flex-wrap items-center gap-1.5 font-mono text-[10px]">
                {mission.waypoints.map((wp, idx) => (
                  <div
                    key={idx}
                    className={`px-2 py-1 rounded border flex items-center gap-1 ${
                      idx === mission.current_waypoint_index
                        ? 'bg-cyan-900 text-cyan-200 border-cyan-500 animate-pulse font-bold'
                        : idx < mission.current_waypoint_index
                        ? 'bg-slate-900 text-slate-500 border-slate-800'
                        : 'bg-slate-800 text-slate-300 border-slate-700'
                    }`}
                  >
                    <span>WP{wp.index}:</span>
                    <span>
                      ({wp.position.x.toFixed(0)}, {wp.position.z.toFixed(0)})
                    </span>
                    {wp.action !== 'FLY_THROUGH' && <span className="text-amber-400">[{wp.action}]</span>}
                  </div>
                ))}
              </div>
            </div>

            {/* Explanation & Fallback */}
            <div className="text-[11px] text-slate-400 space-y-1 pt-1 border-t border-slate-800/80">
              <div>
                <strong className="text-slate-300">Allocation Rationale:</strong> {mission.explanation}
              </div>
              <div>
                <strong className="text-slate-300">Contingency Fallback:</strong> {mission.fallback_strategy}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
