import React, { useState, useEffect } from 'react';
import { AuditRecord } from '../types';
import { api } from '../services/api';
import { Brain, FileText, CheckCircle2, AlertCircle, RefreshCw, Layers } from 'lucide-react';

interface DecisionExplanationViewProps {
  onRefresh: () => void;
}

export const DecisionExplanationView: React.FC<DecisionExplanationViewProps> = ({ onRefresh }) => {
  const [decisions, setDecisions] = useState<AuditRecord[]>([]);
  const [loading, setLoading] = useState<boolean>(true);

  const fetchDecisions = async () => {
    try {
      setLoading(true);
      const data = await api.listDecisions(60);
      setDecisions(data);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchDecisions();
  }, []);

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-lg flex items-center justify-between">
        <div>
          <h2 className="text-base font-bold font-mono text-slate-100 flex items-center gap-2">
            <Brain className="w-5 h-5 text-indigo-400" /> Explainable AI Decision Audit Trail
          </h2>
          <p className="text-xs text-slate-400">
            Transparent, fully auditable algorithmic reasoning traces explaining why resources were allocated, victims triaged, and routes adapted.
          </p>
        </div>
        <button
          onClick={fetchDecisions}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-indigo-700 hover:bg-indigo-600 text-white text-xs font-mono font-bold rounded shadow transition"
        >
          <RefreshCw className="w-4 h-4" /> Refresh Audit Trail
        </button>
      </div>

      {/* Decisions List */}
      <div className="space-y-3">
        {decisions.length === 0 ? (
          <div className="bg-[#0b121e] border border-cyan-900/40 p-8 rounded-xl text-center text-xs font-mono text-slate-500">
            No decisions logged yet. Trigger the Metro Earthquake scenario to generate autonomous AI decisions.
          </div>
        ) : (
          decisions.map((record) => (
            <div
              key={record.event_id}
              className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-md space-y-2.5"
            >
              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-800 pb-2">
                <div className="flex items-center gap-2">
                  <span className="text-xs font-mono text-slate-500">
                    {new Date(record.timestamp * 1000).toLocaleTimeString()}
                  </span>
                  <span className="px-2 py-0.5 rounded text-[10px] font-mono font-bold bg-indigo-950 text-indigo-300 border border-indigo-700">
                    {record.event_type}
                  </span>
                  <span className="text-xs font-mono font-bold text-slate-200">{record.decision}</span>
                </div>
                <span className="text-[11px] font-mono text-emerald-400">
                  Confidence: {(record.confidence * 100).toFixed(0)}%
                </span>
              </div>

              {/* Rationale Text */}
              <div className="bg-slate-900/90 p-3 rounded-lg border border-slate-800 text-xs font-mono text-slate-300 leading-relaxed whitespace-pre-line">
                {record.reason}
              </div>

              {/* Inputs and Outputs */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-[11px] font-mono">
                {record.inputs && Object.keys(record.inputs).length > 0 && (
                  <div className="bg-slate-950 p-2 rounded border border-slate-900">
                    <span className="text-slate-500 block text-[10px] uppercase font-bold">Input Context:</span>
                    <pre className="text-slate-400 overflow-x-auto text-[10px] mt-1">
                      {JSON.stringify(record.inputs, null, 2)}
                    </pre>
                  </div>
                )}
                {record.output && Object.keys(record.output).length > 0 && (
                  <div className="bg-slate-950 p-2 rounded border border-slate-900">
                    <span className="text-slate-500 block text-[10px] uppercase font-bold">Decision Output:</span>
                    <pre className="text-cyan-300 overflow-x-auto text-[10px] mt-1">
                      {JSON.stringify(record.output, null, 2)}
                    </pre>
                  </div>
                )}
              </div>

              {/* Affected Entities */}
              {record.affected_entities && record.affected_entities.length > 0 && (
                <div className="flex items-center gap-1.5 text-[10px] font-mono text-slate-500 pt-1">
                  <span>Affected Entities:</span>
                  {record.affected_entities.map((ent, i) => (
                    <span key={i} className="px-1.5 py-0.2 bg-slate-800 text-slate-300 rounded">
                      {ent}
                    </span>
                  ))}
                </div>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
};
