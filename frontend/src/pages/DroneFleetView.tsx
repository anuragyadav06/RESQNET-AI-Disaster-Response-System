import React, { useState, useEffect } from 'react';
import { DroneEntity, Victim } from '../types';
import { api } from '../services/api';
import { Shield, Battery, Radio, Gauge, Navigation, Send, RotateCcw, Zap } from 'lucide-react';

interface DroneFleetViewProps {
  onRefresh: () => void;
}

export const DroneFleetView: React.FC<DroneFleetViewProps> = ({ onRefresh }) => {
  const [drones, setDrones] = useState<DroneEntity[]>([]);
  const [victims, setVictims] = useState<Victim[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [selectedDrone, setSelectedDrone] = useState<DroneEntity | null>(null);
  const [targetVictimId, setTargetVictimId] = useState<string>('');
  const [msg, setMsg] = useState<string>('');

  const fetchFleet = async () => {
    try {
      setLoading(true);
      const [dData, vData] = await Promise.all([api.listDrones(), api.listVictims()]);
      setDrones(dData);
      setVictims(vData);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchFleet();
  }, []);

  const handleManualDispatch = async (droneId: string) => {
    if (!targetVictimId) {
      alert('Please select a target victim');
      return;
    }
    try {
      const res = await api.dispatchDrone(droneId, targetVictimId);
      setMsg(res.message || `Dispatched ${droneId}`);
      setSelectedDrone(null);
      fetchFleet();
      onRefresh();
    } catch (e: any) {
      setMsg('Dispatch error: ' + e.message);
    }
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-lg flex items-center justify-between">
        <div>
          <h2 className="text-base font-bold font-mono text-slate-100 flex items-center gap-2">
            <Shield className="w-5 h-5 text-cyan-400" /> Autonomous Drone Fleet Management
          </h2>
          <p className="text-xs text-slate-400">
            Real-time physical fleet telemetry, payload status, capability matching, and manual operational dispatch.
          </p>
        </div>
      </div>

      {msg && (
        <div className="p-2.5 bg-cyan-950/80 border border-cyan-700 text-cyan-300 rounded-lg text-xs font-mono">
          {msg}
        </div>
      )}

      {/* Fleet Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {drones.map((drone) => (
          <div
            key={drone.id}
            className="bg-[#0b121e] border border-cyan-900/40 hover:border-cyan-700 p-4 rounded-xl shadow-md flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-mono font-bold text-cyan-400">{drone.id}</span>
                <span
                  className={`px-2 py-0.5 rounded text-[10px] font-mono font-bold ${
                    drone.status === 'IDLE'
                      ? 'bg-emerald-950 text-emerald-300 border border-emerald-700'
                      : drone.status === 'EN_ROUTE'
                      ? 'bg-cyan-950 text-cyan-300 border border-cyan-700 animate-pulse'
                      : 'bg-amber-950 text-amber-300 border border-amber-700'
                  }`}
                >
                  {drone.status}
                </span>
              </div>

              <h3 className="text-sm font-bold text-slate-100 mb-1">{drone.callsign}</h3>
              <div className="text-[10px] text-slate-400 font-mono mb-3">{drone.model_name}</div>

              {/* Battery Meter */}
              <div className="space-y-1 mb-3">
                <div className="flex justify-between text-[11px] font-mono">
                  <span className="text-slate-400 flex items-center gap-1">
                    <Battery className="w-3.5 h-3.5 text-emerald-400" /> Battery:
                  </span>
                  <span
                    className={`font-bold ${
                      drone.battery_percent > 30 ? 'text-emerald-400' : 'text-red-400'
                    }`}
                  >
                    {drone.battery_percent.toFixed(1)}% ({drone.battery_voltage}V)
                  </span>
                </div>
                <div className="w-full h-2 bg-slate-800 rounded-full overflow-hidden">
                  <div
                    className={`h-full transition-all duration-300 ${
                      drone.battery_percent > 30 ? 'bg-emerald-500' : 'bg-red-500'
                    }`}
                    style={{ width: `${drone.battery_percent}%` }}
                  />
                </div>
              </div>

              {/* Live Telemetry Grid */}
              <div className="grid grid-cols-2 gap-2 bg-slate-900/80 p-2.5 rounded-lg text-[11px] font-mono mb-3">
                <div>
                  <span className="text-slate-500 block text-[10px]">ALTITUDE</span>
                  <span className="text-slate-200">{drone.position.y.toFixed(1)} m</span>
                </div>
                <div>
                  <span className="text-slate-500 block text-[10px]">HEADING</span>
                  <span className="text-slate-200">{drone.heading.toFixed(0)}°</span>
                </div>
                <div>
                  <span className="text-slate-500 block text-[10px]">COMMS LINK</span>
                  <span className="text-cyan-400 font-bold">{(drone.communication_quality * 100).toFixed(0)}%</span>
                </div>
                <div>
                  <span className="text-slate-500 block text-[10px]">PAYLOAD</span>
                  <span className="text-slate-200">
                    {drone.current_payload_kg} / {drone.max_payload_kg} kg
                  </span>
                </div>
              </div>

              {/* Capabilities Tags */}
              <div className="flex flex-wrap gap-1 mb-3">
                {drone.capabilities.map((cap, i) => (
                  <span
                    key={i}
                    className="px-1.5 py-0.5 bg-slate-800 text-slate-300 rounded text-[9px] font-mono border border-slate-700"
                  >
                    {cap}
                  </span>
                ))}
              </div>
            </div>

            {/* Actions */}
            <div className="pt-2 border-t border-slate-800">
              {drone.status === 'IDLE' ? (
                <button
                  onClick={() => setSelectedDrone(drone)}
                  className="w-full py-1.5 bg-cyan-700 hover:bg-cyan-600 text-white text-xs font-mono font-bold rounded shadow transition flex items-center justify-center gap-1.5"
                >
                  <Send className="w-3.5 h-3.5" /> Manual Mission Dispatch
                </button>
              ) : (
                <div className="text-[10px] text-slate-400 font-mono text-center">
                  Mission: {drone.current_mission_id || 'Active Flight'}
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      {/* Manual Dispatch Modal */}
      {selectedDrone && (
        <div className="fixed inset-0 z-50 bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#0e1626] border border-cyan-800/60 rounded-xl p-5 w-full max-w-md shadow-2xl">
            <h3 className="text-sm font-bold font-mono text-slate-100 mb-2 flex items-center gap-2">
              <Send className="w-4 h-4 text-cyan-400" /> Dispatch {selectedDrone.id} ({selectedDrone.callsign})
            </h3>
            <p className="text-xs text-slate-400 mb-4 font-mono">
              Equipped capabilities: {selectedDrone.capabilities.join(', ')}
            </p>

            <div className="space-y-3 text-xs">
              <div>
                <label className="block text-slate-400 mb-1">Select Target Victim:</label>
                <select
                  value={targetVictimId}
                  onChange={(e) => setTargetVictimId(e.target.value)}
                  className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-200 font-mono"
                >
                  <option value="">-- Choose Victim --</option>
                  {victims.map((v) => (
                    <option key={v.id} value={v.id}>
                      {v.id} - {v.name} ({v.priority_class}, Sev: {(v.medical_severity * 100).toFixed(0)}%)
                    </option>
                  ))}
                </select>
              </div>

              <div className="flex justify-end gap-2 pt-3">
                <button
                  type="button"
                  onClick={() => setSelectedDrone(null)}
                  className="px-3 py-1.5 bg-slate-800 text-slate-300 rounded font-mono"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  onClick={() => handleManualDispatch(selectedDrone.id)}
                  className="px-3 py-1.5 bg-cyan-600 hover:bg-cyan-500 text-white rounded font-mono font-bold flex items-center gap-1.5"
                >
                  <Send className="w-3.5 h-3.5" /> Confirm Dispatch
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
