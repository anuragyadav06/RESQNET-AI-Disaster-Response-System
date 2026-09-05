import React, { useEffect, useState } from 'react';
import { Victim } from '../types';
import { api } from '../services/api';
import { HeartPulse, RefreshCw, Send, Camera, MapPin, Radio, ShieldAlert } from 'lucide-react';

interface VictimIntelligenceProps { onRefresh: () => void; }

const imageSrc = (v: Victim) => {
  if (v.evidence?.image_base64) {
    return `data:${v.evidence.image_mime_type || 'image/jpeg'};base64,${v.evidence.image_base64}`;
  }
  if (v.evidence?.image_url) return v.evidence.image_url;
  return '';
};

export const VictimIntelligence: React.FC<VictimIntelligenceProps> = ({ onRefresh }) => {
  const [victims, setVictims] = useState<Victim[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState('');
  const [msg, setMsg] = useState('');

  const fetchVictims = async () => {
    try { setLoading(true); setVictims((await api.listVictims()).sort((a,b) => b.priority_score-a.priority_score)); }
    catch (e) { console.error(e); }
    finally { setLoading(false); }
  };
  useEffect(() => { fetchVictims(); }, []);

  const handleReprioritize = async () => {
    try { setActionLoading('recalc'); setVictims(await api.reprioritizeVictims()); setMsg('Victim intelligence and priority matrix updated.'); onRefresh(); }
    catch (e:any) { setMsg(`Error: ${e.message}`); } finally { setActionLoading(''); }
  };
  const handleDispatch = async (id:string) => {
    try { setActionLoading(id); const r=await api.dispatchDrone('AUTO',id); setMsg(r.message || `Response mission created for ${id}`); await fetchVictims(); onRefresh(); }
    catch (e:any) { setMsg(`Error: ${e.message}`); } finally { setActionLoading(''); }
  };
  const priorityClass = (p:string) => p==='CRITICAL'?'border-red-700/80':p==='HIGH'?'border-amber-700/60':'border-cyan-900/40';

  return <div className="space-y-4">
    <div className="bg-[#0b121e] border border-cyan-900/40 p-4 rounded-xl shadow-lg flex items-center justify-between">
      <div><h2 className="text-base font-bold font-mono text-slate-100 flex items-center gap-2"><HeartPulse className="w-5 h-5 text-red-500"/> VICTIM INTELLIGENCE</h2>
      <p className="text-xs text-slate-400">Every detection carries identity, hazard classification, exact coordinates, visual evidence and the drone that captured it.</p></div>
      <button onClick={handleReprioritize} disabled={!!actionLoading} className="flex items-center gap-1.5 px-3 py-1.5 bg-cyan-700 hover:bg-cyan-600 text-white text-xs font-mono font-bold rounded"><RefreshCw className={`w-4 h-4 ${actionLoading==='recalc'?'animate-spin':''}`}/> RECALCULATE</button>
    </div>
    {msg && <div className="p-2.5 bg-cyan-950/80 border border-cyan-700 text-cyan-300 rounded-lg text-xs font-mono">{msg}</div>}
    {loading ? <div className="text-slate-500 font-mono text-sm">Loading victim intelligence…</div> : <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
      {victims.map(v => { const src=imageSrc(v); return <article key={v.id} className={`bg-[#0b121e] border ${priorityClass(v.priority_class)} rounded-xl overflow-hidden shadow-lg`}>
        <div className="grid grid-cols-[180px_1fr] min-h-[210px]">
          <div className="bg-[#050a10] border-r border-slate-800 relative flex items-center justify-center">
            {src ? <img src={src} alt={`Evidence for ${v.id}`} className="w-full h-full object-cover" onError={(e)=>{(e.currentTarget as HTMLImageElement).style.display='none';}}/> : <div className="text-center text-slate-600"><Camera className="mx-auto w-8 h-8 mb-2"/><span className="text-[10px] font-mono">NO IMAGE</span></div>}
            <span className="absolute top-2 left-2 bg-black/80 border border-cyan-700/60 text-cyan-300 text-[9px] font-mono px-1.5 py-1">{v.evidence?.capture_type || 'DRONE CAMERA'}</span>
          </div>
          <div className="p-4">
            <div className="flex items-center justify-between"><div><div className="text-sm font-mono font-black text-slate-100">{v.id}</div><div className="text-xs text-slate-400 mt-1">{v.name}</div></div><span className="px-2 py-1 rounded bg-red-900/50 border border-red-700/60 text-red-300 text-[10px] font-mono font-bold">{v.priority_class}</span></div>
            <div className="grid grid-cols-2 gap-2 mt-4">
              <Info icon={<ShieldAlert/>} label="HAZARD TYPE" value={v.hazard_type.replace('_',' ')}/>
              <Info icon={<Radio/>} label="CAPTURED BY" value={v.captured_by_drone_id || 'UNKNOWN DRONE'}/>
              <Info icon={<MapPin/>} label="COORDINATES" value={`X ${v.location.x.toFixed(2)} · Y ${v.location.y.toFixed(2)} · Z ${v.location.z.toFixed(2)}`}/>
              <Info icon={<HeartPulse/>} label="PEOPLE / SCORE" value={`${v.people_count} · ${(v.priority_score*100).toFixed(0)}%`}/>
            </div>
            <div className="mt-3 text-[10px] font-mono text-slate-500">Evidence timestamp: {v.evidence?.captured_at ? new Date(v.evidence.captured_at*1000).toLocaleString() : 'simulation time'} </div>
          </div>
        </div>
        <div className="p-3 border-t border-slate-800 flex items-center justify-between"><div className="text-[10px] font-mono text-slate-400">STATUS <b className="text-slate-200">{v.status}</b>{v.assigned_drone_id && <> · RESPONSE {v.assigned_drone_id}</>}</div>{v.status!=='ASSISTED'&&!v.assigned_drone_id?<button onClick={()=>handleDispatch(v.id)} disabled={!!actionLoading} className="flex items-center gap-1.5 px-3 py-1.5 bg-red-600 hover:bg-red-500 text-white text-xs font-mono font-bold rounded"><Send className="w-3.5 h-3.5"/> DISPATCH</button>:<span className="text-xs text-emerald-400 font-mono">RESPONSE ASSIGNED</span>}</div>
      </article>; })}
    </div>}
  </div>;
};

function Info({icon,label,value}:{icon:React.ReactNode,label:string,value:string}) { return <div className="bg-slate-900/80 rounded-lg p-2"><div className="text-[9px] text-slate-500 font-mono flex items-center gap-1">{icon}{label}</div><div className="text-[10px] text-slate-200 font-mono font-bold mt-1 break-words">{value}</div></div>; }
