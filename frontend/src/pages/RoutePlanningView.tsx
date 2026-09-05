import React, { useState } from 'react';
import { WorldStateSnapshot, RoadEdge } from '../types';
import { api } from '../services/api';
import { Network, AlertTriangle, CheckCircle, ShieldAlert, Sliders } from 'lucide-react';

interface RoutePlanningViewProps {
  snapshot: WorldStateSnapshot | null;
  onRefresh: () => void;
}

export const RoutePlanningView: React.FC<RoutePlanningViewProps> = ({ snapshot, onRefresh }) => {
  const [filterBlockedOnly, setFilterBlockedOnly] = useState<boolean>(false);
  const [loadingEdge, setLoadingEdge] = useState<string>('');
  const [msg, setMsg] = useState<string>('');

  const edges = snapshot ? Object.values(snapshot.road_edges) : [];
  const filteredEdges = filterBlockedOnly ? edges.filter((e) => e.is_blocked) : edges;

  const handleToggle = async (edge: RoadEdge) => {
    try {
      setLoadingEdge(edge.id);
      if (edge.is_blocked) {
        await api.unblockRoad(edge.id);
        setMsg(`Road ${edge.id} unblocked and re-opened to traffic.`);
      } else {
        await api.blockRoad(edge.id, 'Structural debris / collapse obstruction');
        setMsg(`Road ${edge.id} marked BLOCKED. Dynamic routing graph updated.`);
      }
      onRefresh();
    } catch (e: any) {
      setMsg('Error: ' + e.message);
    } finally {
      setLoadingEdge('');
    }
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-lg flex items-center justify-between">
        <div>
          <h2 className="text-base font-bold font-mono text-slate-100 flex items-center gap-2">
            <Network className="w-5 h-5 text-cyan-400" /> Urban Road Graph & Dynamic Routing Engine
          </h2>
          <p className="text-xs text-slate-400">
            A* graph-based pathfinding with real-time edge invalidation. Toggling any road blockage immediately triggers replanning.
          </p>
        </div>

        <button
          onClick={() => setFilterBlockedOnly(!filterBlockedOnly)}
          className={`px-3 py-1.5 rounded text-xs font-mono font-bold transition border ${
            filterBlockedOnly
              ? 'bg-red-950 text-red-300 border-red-700'
              : 'bg-slate-800 text-slate-300 border-slate-700'
          }`}
        >
          {filterBlockedOnly ? 'Showing Blocked Only' : 'Show All Segments'} ({edges.filter((e) => e.is_blocked).length} blocked)
        </button>
      </div>

      {msg && (
        <div className="p-2.5 bg-cyan-950/80 border border-cyan-700 text-cyan-300 rounded-lg text-xs font-mono">
          {msg}
        </div>
      )}

      {/* Grid of Road Segments */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
        {filteredEdges.map((edge) => (
          <div
            key={edge.id}
            className={`bg-[#0b121e] border p-3.5 rounded-xl shadow transition flex flex-col justify-between ${
              edge.is_blocked ? 'border-red-700/80 bg-red-950/10' : 'border-cyan-900/40'
            }`}
          >
            <div>
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-mono font-bold text-slate-200">{edge.id}</span>
                <span
                  className={`px-2 py-0.5 rounded text-[10px] font-mono font-bold ${
                    edge.is_blocked
                      ? 'bg-red-950 text-red-300 border border-red-700 animate-pulse'
                      : 'bg-emerald-950 text-emerald-300 border border-emerald-700'
                  }`}
                >
                  {edge.is_blocked ? 'BLOCKED' : 'CLEAR'}
                </span>
              </div>

              <div className="text-xs font-mono text-slate-400 mb-2">
                {edge.from_node} ➔ {edge.to_node} ({edge.distance_m}m)
              </div>

              {edge.is_blocked && (
                <div className="text-[11px] text-red-400 font-mono mb-2 bg-red-950/40 p-2 rounded border border-red-900/60">
                  Cause: {edge.blockage_reason || 'Debris obstruction'}
                </div>
              )}
            </div>

            <button
              onClick={() => handleToggle(edge)}
              disabled={loadingEdge === edge.id}
              className={`w-full py-1.5 rounded text-xs font-mono font-bold transition shadow ${
                edge.is_blocked
                  ? 'bg-emerald-700 hover:bg-emerald-600 text-white'
                  : 'bg-red-700 hover:bg-red-600 text-white'
              }`}
            >
              {edge.is_blocked ? 'Clear & Reopen Road' : 'Inject Road Blockage'}
            </button>
          </div>
        ))}
      </div>
    </div>
  );
};
