import React, { useMemo, useState } from 'react';
import { WorldStateSnapshot, Victim } from '../types';
import { api } from '../services/api';
import { HeartPulse, RefreshCw, Send, Camera, MapPin, Radio, ShieldAlert, Truck, Crosshair, Wrench, CheckCircle2 } from 'lucide-react';

interface VictimIntelligenceProps { onRefresh: () => void; snapshot: WorldStateSnapshot | null; }

const imageSrc = (v: Victim) => v.evidence?.image_base64
  ? `data:${v.evidence.image_mime_type || 'image/jpeg'};base64,${v.evidence.image_base64}`
  : v.evidence?.image_url || '';

export const VictimIntelligence: React.FC<VictimIntelligenceProps> = ({ onRefresh, snapshot }) => {
  const [actionLoading, setActionLoading] = useState('');
  const [msg, setMsg] = useState('');
  const victims = useMemo(
    () => Object.values(snapshot?.victims || {})
      .filter((v) => !v.assigned_mission_id && !['EVACUATED', 'RESCUED', 'ASSISTED', 'TREATED', 'STABILIZED', 'MEDICALLY_STABILIZED', 'RESOLVED', 'SAFE'].includes(v.status))
      .sort((a,b) => b.priority_score-a.priority_score),
    [snapshot]
  );
  const drones = useMemo(() => Object.values(snapshot?.drones || {}), [snapshot]);
  const available = (cap: string) => drones.filter(d => d.status === 'IDLE' && d.capabilities.includes(cap as any)).length;

  const dispatch = async (victim: Victim, objective: 'RESCUE_EXTRACTION'|'MEDICAL_SUPPLY_DROP'|'HEAVY_EXTRICATION') => {
    const key = `${victim.id}:${objective}`;
    setActionLoading(key);
    try {
      const r = await api.dispatchDrone('AUTO', victim.id, objective);
      setMsg(r.message || `${objective.replaceAll('_',' ')} dispatched for ${victim.id}.`);
      onRefresh();
    } catch (e:any) {
      setMsg(`Dispatch failed: ${e?.message || 'System rejected the mission.'}`);
    } finally { setActionLoading(''); }
  };

  const priorityClass = (p:string) => p==='CRITICAL'?'border-red-700/80':p==='HIGH'?'border-amber-700/60':'border-cyan-900/40';

  return <div className="space-y-4">
    <div className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-lg flex items-center justify-between">
      <div><h2 className="text-base font-bold font-mono text-slate-100 flex items-center gap-2"><HeartPulse className="w-5 h-5 text-red-500"/> VICTIM INTELLIGENCE</h2>
      <p className="text-xs text-slate-400">Authoritative System-B detections, exact coordinates, exact Digital-Twin camera evidence and live response status.</p></div>
      <div className="text-[10px] font-mono text-slate-400">MED {available('MEDICAL')} · HEAVY {available('HEAVY_LIFT')} · RESCUE {available('RESCUE')}</div>
    </div>
    {msg && <div className="p-2.5 bg-cyan-950/80 border border-cyan-700 text-cyan-300 rounded-lg text-xs font-mono">{msg}</div>}
    {victims.length === 0 ? <div className="text-slate-500 font-mono text-sm">No victims detected by the 16-scout search grid yet.</div> : <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
      {victims.map(v => { const src=imageSrc(v); const resolved=v.status==='EVACUATED' || v.status==='RESCUED';
        const trapped=v.status==='TRAPPED'; return <article key={v.id} className={`bg-[#0b121e] border ${priorityClass(v.priority_class)} rounded-xl overflow-hidden shadow-lg`}>
        <div className="grid grid-cols-[220px_1fr] min-h-[235px]">
          <div className="bg-[#050a10] border-r border-slate-800 relative flex items-center justify-center overflow-hidden">
            {src ? <img src={src} alt={`Exact Digital Twin evidence for ${v.id}`} className="w-full h-full object-cover"/> : <div className="text-center text-slate-600"><Camera className="mx-auto w-8 h-8 mb-2"/><span className="text-[10px] font-mono">WAITING FOR DRONE FRAME</span></div>}
            <span className="absolute top-2 left-2 bg-black/85 border border-cyan-700/60 text-cyan-300 text-[9px] font-mono px-1.5 py-1">{v.evidence?.capture_type || 'DRONE CAMERA'}</span>
            {trapped && <span className="absolute bottom-2 left-2 bg-red-950/95 border border-red-500 text-red-300 text-[10px] font-mono font-bold px-2 py-1 flex items-center gap-1"><ShieldAlert className="w-3 h-3"/> TRAPPED UNDER STRUCTURAL DEBRIS</span>}
            {resolved && <span className="absolute bottom-2 left-2 bg-emerald-950/95 border border-emerald-500 text-emerald-300 text-[10px] font-mono font-bold px-2 py-1 flex items-center gap-1"><CheckCircle2 className="w-3 h-3"/> RESCUED</span>}
          </div>
          <div className="p-4">
            <div className="flex items-center justify-between"><div><div className="text-sm font-mono font-black text-slate-100">{v.id}</div><div className="text-xs text-slate-400 mt-1">{v.name}</div></div><span className="px-2 py-1 rounded bg-red-900/50 border border-red-700/60 text-red-300 text-[10px] font-mono font-bold">{v.priority_class}</span></div>
            <div className="grid grid-cols-2 gap-2 mt-4">
              <Info icon={<ShieldAlert/>} label="HAZARD" value={v.hazard_type.replaceAll('_',' ')}/>
              <Info icon={<Radio/>} label="SCOUT" value={v.captured_by_drone_id || 'UNKNOWN'}/>
              <Info icon={<MapPin/>} label="LOCATION" value={`X ${v.location.x.toFixed(1)} · Z ${v.location.z.toFixed(1)}`}/>
              <Info icon={<HeartPulse/>} label="MEDICAL / STATUS" value={`${(v.medical_severity*100).toFixed(0)}% · ${v.status}`}/>
            </div>
            <div className="mt-3 text-[10px] font-mono text-slate-500">Evidence: {v.evidence?.captured_at ? new Date(v.evidence.captured_at*1000).toLocaleString() : 'pending'} · Confidence {(v.confidence*100).toFixed(0)}%</div>
          </div>
        </div>
        <div className="p-3 border-t border-slate-800">
          <div className="text-[10px] font-mono text-slate-400 mb-2">RESPONSE OPTIONS — only available System-B response aircraft are dispatchable</div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
            <ResponseButton icon={<Truck/>} label="MEDICAL" disabled={resolved || available('MEDICAL')===0 || !!actionLoading} busy={actionLoading===`${v.id}:MEDICAL_SUPPLY_DROP`} onClick={()=>dispatch(v,'MEDICAL_SUPPLY_DROP')} />
            <ResponseButton icon={<Send/>} label="RESCUE" disabled={resolved || available('RESCUE')===0 || !!actionLoading} busy={actionLoading===`${v.id}:RESCUE_EXTRACTION`} onClick={()=>dispatch(v,'RESCUE_EXTRACTION')} />
            <ResponseButton icon={<Wrench/>} label="HEAVY LIFT" disabled={resolved || available('HEAVY_LIFT')===0 || !!actionLoading} busy={actionLoading===`${v.id}:HEAVY_EXTRICATION`} onClick={()=>dispatch(v,'HEAVY_EXTRICATION')} />
          </div>
          <div className="mt-2 text-[10px] font-mono text-slate-500">{v.assigned_drone_id ? `ASSIGNED RESPONSE: ${v.assigned_drone_id}` : 'No response aircraft assigned'}{v.assigned_mission_id ? ` · MISSION ${v.assigned_mission_id}` : ''}</div>
        </div>
      </article>; })}
    </div>}
  </div>;
};

function Info({icon,label,value}:{icon:React.ReactNode,label:string,value:string}) { return <div className="bg-slate-900/80 rounded-lg p-2"><div className="text-[9px] text-slate-500 font-mono flex items-center gap-1">{icon}{label}</div><div className="text-[10px] text-slate-200 font-mono font-bold mt-1 break-words">{value}</div></div>; }
function ResponseButton({icon,label,onClick,disabled,busy}:{icon:React.ReactNode,label:string,onClick:()=>void,disabled:boolean,busy:boolean}) { return <button onClick={onClick} disabled={disabled} className="flex items-center justify-center gap-1.5 py-2 rounded bg-cyan-800 hover:bg-cyan-700 disabled:opacity-35 disabled:cursor-not-allowed text-white text-[10px] font-mono font-bold border border-cyan-700">{busy?<RefreshCw className="w-3.5 h-3.5 animate-spin"/>:icon}<span>{busy?'DISPATCHING…':label}</span></button>; }
