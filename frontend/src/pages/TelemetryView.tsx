import React from 'react';
import { WorldStateSnapshot } from '../types';
import { Gauge, Radio, Battery, Zap, Compass, Activity } from 'lucide-react';

interface TelemetryViewProps {
  snapshot: WorldStateSnapshot | null;
  latencyMs: number;
}

export const TelemetryView: React.FC<TelemetryViewProps> = ({ snapshot, latencyMs }) => {
  const drones = snapshot ? Object.values(snapshot.drones) : [];

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-lg flex items-center justify-between">
        <div>
          <h2 className="text-base font-bold font-mono text-slate-100 flex items-center gap-2">
            <Gauge className="w-5 h-5 text-cyan-400" /> High-Frequency Telemetry Ingestion
          </h2>
          <p className="text-xs text-slate-400">
            Real-time physical kinematics stream direct from System B Godot Digital Twin at 10Hz.
          </p>
        </div>
        <div className="flex items-center gap-3 text-xs font-mono">
          <span className="text-slate-400">Rate: <strong className="text-cyan-300">{snapshot?.telemetry_rate_hz || 10.0} Hz</strong></span>
          <span className="text-slate-400">Command Latency: <strong className="text-emerald-400">{latencyMs} ms</strong></span>
        </div>
      </div>

      {/* Drones Telemetry Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {drones.map((drone) => (
          <div
            key={drone.id}
            className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-md space-y-3"
          >
            <div className="flex items-center justify-between border-b border-slate-800 pb-2">
              <div>
                <span className="text-xs font-mono font-bold text-cyan-400 mr-2">{drone.id}</span>
                <span className="text-xs font-bold text-slate-200">{drone.callsign}</span>
              </div>
              <span className="text-[10px] font-mono text-emerald-400 bg-emerald-950 px-2 py-0.5 rounded border border-emerald-800">
                LINK: {(drone.communication_quality * 100).toFixed(0)}%
              </span>
            </div>

            {/* Gauges Grid */}
            <div className="grid grid-cols-3 gap-2 text-xs font-mono">
              <div className="bg-slate-900/80 p-2.5 rounded-lg">
                <span className="text-slate-500 block text-[10px]">POSITION (X, Y, Z)</span>
                <span className="text-slate-200">
                  {drone.position.x.toFixed(1)}, {drone.position.y.toFixed(1)}, {drone.position.z.toFixed(1)}
                </span>
              </div>
              <div className="bg-slate-900/80 p-2.5 rounded-lg">
                <span className="text-slate-500 block text-[10px]">VELOCITY</span>
                <span className="text-slate-200">
                  {Math.hypot(drone.velocity.x, drone.velocity.z).toFixed(1)} m/s
                </span>
              </div>
              <div className="bg-slate-900/80 p-2.5 rounded-lg">
                <span className="text-slate-500 block text-[10px]">HEADING</span>
                <span className="text-slate-200">{drone.heading.toFixed(0)}°</span>
              </div>

              <div className="bg-slate-900/80 p-2.5 rounded-lg">
                <span className="text-slate-500 block text-[10px]">BATTERY VOLTAGE</span>
                <span className="text-emerald-400 font-bold">{drone.battery_voltage} V</span>
              </div>
              <div className="bg-slate-900/80 p-2.5 rounded-lg">
                <span className="text-slate-500 block text-[10px]">POWER CONSUMPTION</span>
                <span className="text-amber-400 font-bold">{drone.power_consumption_w} W</span>
              </div>
              <div className="bg-slate-900/80 p-2.5 rounded-lg">
                <span className="text-slate-500 block text-[10px]">CURRENT DRAW</span>
                <span className="text-slate-200">~15.2 A</span>
              </div>
            </div>

            {/* Battery bar */}
            <div className="space-y-1">
              <div className="flex justify-between text-[11px] font-mono">
                <span className="text-slate-400">State of Charge:</span>
                <span className="font-bold text-emerald-400">{drone.battery_percent.toFixed(1)}%</span>
              </div>
              <div className="w-full h-2 bg-slate-800 rounded-full overflow-hidden">
                <div
                  className="h-full bg-emerald-500 transition-all duration-300"
                  style={{ width: `${drone.battery_percent}%` }}
                />
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
