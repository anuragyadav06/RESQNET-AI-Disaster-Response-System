import React from 'react';
import { WorldStateSnapshot } from '../types';
import { Flame, Wind, Eye, Compass, Activity, ShieldAlert } from 'lucide-react';

interface HazardMonitorViewProps {
  snapshot: WorldStateSnapshot | null;
}

export const HazardMonitorView: React.FC<HazardMonitorViewProps> = ({ snapshot }) => {
  const hazards = snapshot ? Object.values(snapshot.hazards) : [];
  const env = snapshot?.environment;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-lg">
        <h2 className="text-base font-bold font-mono text-slate-100 flex items-center gap-2">
          <Flame className="w-5 h-5 text-orange-400" /> Hazard Surveillance & Environmental Telemetry
        </h2>
        <p className="text-xs text-slate-400">
          Continuous tracking of fire plumes, thermal intensity, structural collapses, and atmospheric conditions affecting drone flight corridors.
        </p>
      </div>

      {/* Environmental Metrics */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div className="bg-[#0b121e] border border-cyan-900/40 p-3.5 rounded-xl shadow flex items-center gap-3">
          <div className="p-2.5 bg-cyan-950 text-cyan-400 rounded-lg">
            <Wind className="w-5 h-5" />
          </div>
          <div>
            <span className="text-[10px] text-slate-400 uppercase font-mono block">Wind Velocity</span>
            <span className="text-sm font-mono font-bold text-slate-200">
              {env?.wind_speed_mps || 3.5} m/s @ {env?.wind_direction_deg || 45}°
            </span>
          </div>
        </div>

        <div className="bg-[#0b121e] border border-cyan-900/40 p-3.5 rounded-xl shadow flex items-center gap-3">
          <div className="p-2.5 bg-slate-800 text-slate-300 rounded-lg">
            <Eye className="w-5 h-5" />
          </div>
          <div>
            <span className="text-[10px] text-slate-400 uppercase font-mono block">Visibility</span>
            <span className="text-sm font-mono font-bold text-slate-200">
              {(env?.visibility_m ? env.visibility_m / 1000 : 8.0).toFixed(1)} km
            </span>
          </div>
        </div>

        <div className="bg-[#0b121e] border border-cyan-900/40 p-3.5 rounded-xl shadow flex items-center gap-3">
          <div className={`p-2.5 rounded-lg ${env?.seismic_activity_richter ? 'bg-red-950 text-red-400 animate-bounce' : 'bg-slate-800 text-slate-400'}`}>
            <Activity className="w-5 h-5" />
          </div>
          <div>
            <span className="text-[10px] text-slate-400 uppercase font-mono block">Seismic Activity</span>
            <span className="text-sm font-mono font-bold text-slate-200">
              {env?.seismic_activity_richter ? `${env.seismic_activity_richter} Richter` : '0.0 Richter'}
            </span>
          </div>
        </div>

        <div className="bg-[#0b121e] border border-cyan-900/40 p-3.5 rounded-xl shadow flex items-center gap-3">
          <div className="p-2.5 bg-orange-950 text-orange-400 rounded-lg">
            <ShieldAlert className="w-5 h-5" />
          </div>
          <div>
            <span className="text-[10px] text-slate-400 uppercase font-mono block">Air Quality Index</span>
            <span className="text-sm font-mono font-bold text-orange-300">
              {env?.air_quality_index || 45} AQI
            </span>
          </div>
        </div>
      </div>

      {/* Hazards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
        {hazards.map((hz) => (
          <div
            key={hz.id}
            className="bg-[#0b121e] border border-orange-800/50 p-4 rounded-xl shadow-md space-y-3"
          >
            <div className="flex items-center justify-between">
              <span className="text-xs font-mono font-bold text-orange-400">{hz.id}</span>
              <span className="px-2 py-0.5 bg-orange-950 text-orange-300 border border-orange-700 rounded text-[10px] font-mono font-bold">
                {hz.type}
              </span>
            </div>

            <div className="grid grid-cols-2 gap-2 bg-slate-900/80 p-2.5 rounded-lg text-xs font-mono">
              <div>
                <span className="text-slate-500 block text-[10px]">CENTER</span>
                <span className="text-slate-200">
                  ({hz.center.x.toFixed(0)}, {hz.center.z.toFixed(0)})
                </span>
              </div>
              <div>
                <span className="text-slate-500 block text-[10px]">RADIUS</span>
                <span className="text-slate-200">{hz.radius_m} meters</span>
              </div>
              <div>
                <span className="text-slate-500 block text-[10px]">INTENSITY</span>
                <span className="text-orange-400 font-bold">{(hz.intensity * 100).toFixed(0)}%</span>
              </div>
              <div>
                <span className="text-slate-500 block text-[10px]">SPREAD RATE</span>
                <span className="text-slate-200">{hz.spread_rate_m_per_s} m/s</span>
              </div>
            </div>

            <div className="text-[11px] text-slate-400 font-mono">
              Flight exclusion zone enforced within {hz.radius_m + 30}m buffer.
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
