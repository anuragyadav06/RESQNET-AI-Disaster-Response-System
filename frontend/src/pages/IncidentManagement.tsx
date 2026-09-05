import React, { useState, useEffect } from 'react';
import { IncidentEntity } from '../types';
import { api } from '../services/api';
import { Flame, AlertTriangle, ShieldAlert, Plus, CheckCircle, Clock } from 'lucide-react';

interface IncidentManagementProps {
  onRefresh: () => void;
}

export const IncidentManagement: React.FC<IncidentManagementProps> = ({ onRefresh }) => {
  const [incidents, setIncidents] = useState<IncidentEntity[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [showModal, setShowModal] = useState<boolean>(false);

  // Form state for manual incident
  const [newType, setNewType] = useState<string>('FIRE');
  const [newTitle, setNewTitle] = useState<string>('Structural Fire Outbreak');
  const [posX, setPosX] = useState<number>(50);
  const [posZ, setPosZ] = useState<number>(50);
  const [severity, setSeverity] = useState<number>(0.85);

  const fetchIncidents = async () => {
    try {
      setLoading(true);
      const data = await api.listIncidents();
      setIncidents(data);
    } catch (e) {
      console.error('Failed to fetch incidents:', e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchIncidents();
  }, []);

  const handleCreateIncident = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await api.createIncident(newType, newTitle, { x: posX, y: 0, z: posZ }, severity);
      setShowModal(false);
      fetchIncidents();
      onRefresh();
    } catch (err) {
      alert('Failed to inject incident: ' + err);
    }
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-lg">
        <div>
          <h2 className="text-base font-bold font-mono text-slate-100 flex items-center gap-2">
            <ShieldAlert className="w-5 h-5 text-orange-400" /> Incident Detection & Management
          </h2>
          <p className="text-xs text-slate-400">
            Real-time pipeline parsing raw sensor observations from System B into classified emergency events.
          </p>
        </div>
        <button
          onClick={() => setShowModal(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-orange-600 hover:bg-orange-500 text-white text-xs font-mono font-bold rounded shadow transition"
        >
          <Plus className="w-4 h-4" /> Inject New Incident
        </button>
      </div>

      {/* Incident List */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
        {incidents.map((inc) => (
          <div
            key={inc.id}
            className="bg-[#0b121e] border border-cyan-900/40 hover:border-cyan-700/60 transition p-4 rounded-xl shadow-md flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-mono font-bold text-orange-400">{inc.id}</span>
                <span
                  className={`px-2 py-0.5 rounded text-[10px] font-mono font-bold ${
                    inc.status === 'ACTIVE'
                      ? 'bg-red-950 text-red-300 border border-red-700'
                      : 'bg-emerald-950 text-emerald-300 border border-emerald-700'
                  }`}
                >
                  {inc.status}
                </span>
              </div>
              <h3 className="text-sm font-bold text-slate-200 mb-1">{inc.title}</h3>
              <div className="text-[11px] text-slate-400 font-mono mb-3">
                Type: {inc.type} | Radius: {inc.radius_m}m
              </div>

              <div className="space-y-1 bg-slate-900/80 p-2.5 rounded-lg text-xs font-mono mb-3">
                <div className="flex justify-between">
                  <span className="text-slate-400">Severity:</span>
                  <span className="text-red-400 font-bold">{(inc.severity * 100).toFixed(0)}%</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Confidence:</span>
                  <span className="text-emerald-400">{(inc.confidence * 100).toFixed(0)}%</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Coordinates:</span>
                  <span className="text-slate-300">
                    ({inc.location.x.toFixed(0)}, {inc.location.z.toFixed(0)})
                  </span>
                </div>
              </div>

              {inc.evidence && inc.evidence.length > 0 && (
                <div className="text-[11px] text-slate-400">
                  <span className="text-slate-300 font-bold">Sensor Evidence:</span>
                  <ul className="list-disc list-inside mt-0.5 text-slate-400 font-mono text-[10px]">
                    {inc.evidence.map((ev, i) => (
                      <li key={i}>{ev}</li>
                    ))}
                  </ul>
                </div>
              )}
            </div>

            <div className="mt-3 pt-2 border-t border-slate-800 text-[10px] text-cyan-400 font-mono">
              Action: {inc.recommended_action}
            </div>
          </div>
        ))}
      </div>

      {/* Manual Modal */}
      {showModal && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-[#0e1626] border border-cyan-800/60 rounded-xl p-5 w-full max-w-md shadow-2xl">
            <h3 className="text-sm font-bold font-mono text-slate-100 mb-3 flex items-center gap-2">
              <Plus className="w-4 h-4 text-orange-400" /> Inject Disaster Incident
            </h3>
            <form onSubmit={handleCreateIncident} className="space-y-3 text-xs">
              <div>
                <label className="block text-slate-400 mb-1">Incident Type</label>
                <select
                  value={newType}
                  onChange={(e) => setNewType(e.target.value)}
                  className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-200"
                >
                  <option value="FIRE">FIRE</option>
                  <option value="EARTHQUAKE_DAMAGE">EARTHQUAKE_DAMAGE</option>
                  <option value="TRAPPED_VICTIM">TRAPPED_VICTIM</option>
                  <option value="ROAD_BLOCKAGE">ROAD_BLOCKAGE</option>
                  <option value="FLOOD_ZONE">FLOOD_ZONE</option>
                </select>
              </div>
              <div>
                <label className="block text-slate-400 mb-1">Title</label>
                <input
                  type="text"
                  value={newTitle}
                  onChange={(e) => setNewTitle(e.target.value)}
                  className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-200"
                />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="block text-slate-400 mb-1">X Coordinate (-150 to 150)</label>
                  <input
                    type="number"
                    value={posX}
                    onChange={(e) => setPosX(Number(e.target.value))}
                    className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-200 font-mono"
                  />
                </div>
                <div>
                  <label className="block text-slate-400 mb-1">Z Coordinate (-150 to 150)</label>
                  <input
                    type="number"
                    value={posZ}
                    onChange={(e) => setPosZ(Number(e.target.value))}
                    className="w-full bg-slate-900 border border-slate-700 rounded px-2.5 py-1.5 text-slate-200 font-mono"
                  />
                </div>
              </div>
              <div>
                <label className="block text-slate-400 mb-1">Severity: {(severity * 100).toFixed(0)}%</label>
                <input
                  type="range"
                  min="0.1"
                  max="1.0"
                  step="0.05"
                  value={severity}
                  onChange={(e) => setSeverity(Number(e.target.value))}
                  className="w-full"
                />
              </div>
              <div className="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setShowModal(false)}
                  className="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded font-mono"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-3 py-1.5 bg-orange-600 hover:bg-orange-500 text-white rounded font-mono font-bold"
                >
                  Confirm & Inject
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
