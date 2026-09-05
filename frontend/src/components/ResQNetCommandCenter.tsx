import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AlertTriangle, Brain, Crosshair, Mic, MicOff, Navigation, Radio, RefreshCw, Search, Send, ShieldCheck, Siren, Square, Volume2, Zap } from 'lucide-react';
import { useSystemWebSocket } from '../websocket/useSystemWebSocket';
import { api } from '../services/api';
import { DroneEntity, Victim, WorldStateSnapshot } from '../types';
import './ResQNetCommandCenter.css';

const colorForPriority = (p: string) => p === 'CRITICAL' ? '#ff3b3b' : p === 'HIGH' ? '#ff9f43' : p === 'MEDIUM' ? '#ffd166' : '#5eead4';
const mapX = (x: number) => 50 + (x / 200) * 45;
const mapY = (z: number) => 50 + (z / 200) * 45;

export function ResQNetCommandCenter() {
  const { snapshot, isConnected, latencyMs, refresh } = useSystemWebSocket();
  const [events, setEvents] = useState<any[]>([]);
  const [searchPlan, setSearchPlan] = useState<any>(null);
  const [busy, setBusy] = useState('');
  const [command, setCommand] = useState('');
  const [transcript, setTranscript] = useState('');
  const [response, setResponse] = useState('RESQNET ready. Awaiting operator command.');
  const recognitionRef = useRef<any>(null);

  const loadEvents = useCallback(async () => {
    try { setEvents(await api.getLiveEvents(40)); } catch { /* websocket remains primary */ }
  }, []);
  useEffect(() => { loadEvents(); const id = setInterval(loadEvents, 2000); return () => clearInterval(id); }, [loadEvents]);

  const drones = useMemo(() => Object.values(snapshot?.drones || {}) as DroneEntity[], [snapshot]);
  const victims = useMemo(() => Object.values(snapshot?.victims || {}) as Victim[], [snapshot]);
  const activeMissions = useMemo(() => Object.values(snapshot?.drones || {}).filter((d: any) => d.current_mission_id), [snapshot]);
  const critical = victims.filter(v => v.priority_class === 'CRITICAL').length;

  const speak = (text: string) => {
    setResponse(text);
    if ('speechSynthesis' in window) { window.speechSynthesis.cancel(); window.speechSynthesis.speak(new SpeechSynthesisUtterance(text)); }
  };

  const execute = async (label: string, fn: () => Promise<any>, spoken?: (r: any) => string) => {
    setBusy(label);
    try { const r = await fn(); await refresh(); await loadEvents(); speak(spoken ? spoken(r) : `${label} completed successfully.`); return r; }
    catch (e: any) { speak(`${label} failed. ${e?.message || 'Check system diagnostics.'}`); }
    finally { setBusy(''); }
  };

  const startVoice = () => {
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) { speak('Browser speech recognition is unavailable. Use Chrome or enter a command manually.'); return; }
    const rec = new SR(); recognitionRef.current = rec; rec.lang = 'en-IN'; rec.continuous = false; rec.interimResults = true;
    rec.onresult = (e: any) => { const text = Array.from(e.results).map((r: any) => r[0].transcript).join(''); setTranscript(text); if (e.results[e.results.length - 1].isFinal) setCommand(text); };
    rec.onerror = () => speak('Voice input failed.'); rec.onend = () => recognitionRef.current = null; rec.start();
  };
  const stopVoice = () => { recognitionRef.current?.stop(); recognitionRef.current = null; };

  const runCommand = async () => {
    if (!command.trim()) return;
    const parsed = await api.interpretVoice(command);
    if (parsed.intent === 'GET_STATUS') {
      const s = await api.getResponseStatus();
      speak(`System operational. ${s.available_drones} drones available, ${s.critical_victims} critical victims, and ${s.active_missions} active missions.`);
    } else if (parsed.intent === 'START_RECON') {
      await execute('Recon deployment', api.startRecon, r => `Recon plan created for ${r.drone_count} scout drones. Coverage lanes assigned.`);
    } else if (parsed.intent === 'AUTO_DISPATCH') {
      await execute('Priority response', api.triageDispatch, r => `Response cycle completed. ${r.dispatched?.length || 0} missions dispatched.`);
    } else if (parsed.intent === 'PRIORITIZE_ROOFTOP') {
      await execute('Victim reprioritization', api.reprioritizeVictims, () => 'Victims reprioritized. Rooftop and exposed victims are ready for operator review.');
    } else {
      speak('Command recognized as unknown or requiring a manual target.');
    }
  };

  return <div className="rqcc">
    <section className="rqcc-hero">
      <div><div className="eyebrow">RESQNET / SYSTEM A</div><h2>AI DISASTER COMMAND CENTER</h2><p>Closed-loop control of the Godot Digital Twin, multi-UAV missions and victim response.</p></div>
      <div className="hero-status"><span className={isConnected && snapshot?.system_b_connected ? 'live-dot' : 'warn-dot'} />{isConnected && snapshot?.system_b_connected ? 'SYSTEM B LIVE' : 'WAITING FOR GODOT'}<span className="mono">{latencyMs} ms</span></div>
    </section>

    <section className="metric-grid">
      <Metric label="DRONES ONLINE" value={drones.length} sub={`${drones.filter(d => d.status === 'IDLE').length} available`} icon={<Navigation />} />
      <Metric label="CRITICAL VICTIMS" value={critical} sub={`${victims.length} detected`} icon={<AlertTriangle />} danger />
      <Metric label="ACTIVE MISSIONS" value={activeMissions.length} sub="live assignments" icon={<Crosshair />} />
      <Metric label="TELEMETRY" value={`${snapshot?.telemetry_rate_hz?.toFixed(1) || '0.0'} Hz`} sub="Godot → System A" icon={<Radio />} />
    </section>

    <section className="command-strip">
      <div className="voice-box">
        <div className="voice-head"><span><Mic /> VOICE COMMAND</span><span className="mono">STT → INTENT → SAFETY → EXECUTION</span></div>
        <div className="voice-row"><input value={command} onChange={e => setCommand(e.target.value)} onKeyDown={e => e.key === 'Enter' && runCommand()} placeholder="e.g. Find trapped civilians" /><button onClick={recognitionRef.current ? stopVoice : startVoice} className="icon-btn">{recognitionRef.current ? <MicOff /> : <Mic />}</button><button onClick={runCommand} className="execute-btn"><Send /> EXECUTE</button></div>
        <div className="transcript">{transcript || 'No active transcript'}</div>
      </div>
      <div className="response-box"><div className="voice-head"><span><Volume2 /> SYSTEM RESPONSE</span></div><div className="response-text">{response}</div></div>
    </section>

    <section className="action-row">
      <Action label="START RECON" icon={<Search />} busy={busy==='Recon deployment'} onClick={() => execute('Recon deployment', api.startRecon, r => `Recon plan created. ${r.drone_count} scout drones assigned non-overlapping coverage sectors.`)} />
      <Action label="TRIAGE + DISPATCH" icon={<Siren />} busy={busy==='Priority response'} onClick={() => execute('Priority response', api.triageDispatch, r => `${r.dispatched?.length || 0} priority missions dispatched.`)} />
      <Action label="REPRIORITIZE" icon={<Brain />} busy={busy==='Victim reprioritization'} onClick={() => execute('Victim reprioritization', api.reprioritizeVictims, () => 'Victim priority matrix updated.')} />
      <Action label="REPLAN" icon={<RefreshCw />} busy={busy==='Dynamic replanning'} onClick={() => execute('Dynamic replanning', api.evaluateReplanning, r => `Replanning evaluation completed. ${Array.isArray(r) ? r.length : 0} changes evaluated.`)} />
    </section>

    <section className="main-grid">
      <div className="panel map-panel"><PanelTitle icon={<ShieldCheck />} title="TACTICAL DIGITAL TWIN" right={snapshot?.session_id || 'metro_session_01'} /><div className="tactical-map">
        <div className="map-grid" />
        {Object.values(snapshot?.buildings || {}).map((b: any) => <div key={b.id} className="building" style={{left:`${mapX(b.center.x)}%`,top:`${mapY(b.center.z)}%`,width:`${Math.max(2,b.size_x/18)}%`,height:`${Math.max(2,b.size_z/18)}%`}} title={b.name} />)}
        {Object.values(snapshot?.hazards || {}).map((h: any) => <div key={h.id} className="hazard" style={{left:`${mapX(h.center.x)}%`,top:`${mapY(h.center.z)}%`,width:`${Math.max(5,h.radius_m/2.5)}%`,height:`${Math.max(5,h.radius_m/2.5)}%`}} />)}
        {victims.map(v => <div key={v.id} className="victim-dot" style={{left:`${mapX(v.location.x)}%`,top:`${mapY(v.location.z)}%`,background:colorForPriority(v.priority_class)}} title={`${v.id} ${v.priority_class}`} />)}
        {drones.map(d => <div key={d.id} className="drone-dot" style={{left:`${mapX(d.position.x)}%`,top:`${mapY(d.position.z)}%`}} title={`${d.id} ${d.status}`}><Navigation /></div>)}
        <div className="map-label tl">NORTH / METRO DIGITAL TWIN</div><div className="map-label br">RRT* / COVERAGE / LIVE STATE</div>
      </div></div>

      <div className="panel"><PanelTitle icon={<Navigation />} title="DRONE FLEET" right="LIVE TELEMETRY" /><div className="list">{drones.map(d => <div className="fleet-row" key={d.id}><div className="fleet-icon"><Navigation /></div><div className="grow"><b>{d.id}</b><span>{d.callsign}</span></div><div className="fleet-stat"><b>{d.battery_percent.toFixed(0)}%</b><span>{d.status}</span></div><div className="battery"><i style={{width:`${d.battery_percent}%`}} /></div></div>)}</div></div>
    </section>

    <section className="lower-grid">
      <div className="panel"><PanelTitle icon={<AlertTriangle />} title="VICTIM INTELLIGENCE" right={`${victims.length} TRACKS`} /><div className="victim-list">{victims.sort((a,b)=>b.priority_score-a.priority_score).slice(0,8).map(v => <div className="victim-row" key={v.id}><span className="priority" style={{background:colorForPriority(v.priority_class)}}>{v.priority_class}</span><div className="grow"><b>{v.id} · {v.people_count} PERSON{v.people_count>1?'S':''}</b><span>{v.hazard_type?.replace('_',' ') || 'UNKNOWN HAZARD'} · {v.captured_by_drone_id || 'NO DRONE'} · ({v.location.x.toFixed(0)}, {v.location.y.toFixed(0)}, {v.location.z.toFixed(0)})</span></div><span className="mono">{v.status}</span></div>)}</div></div>
      <div className="panel"><PanelTitle icon={<Crosshair />} title="SEARCH / MISSION INTELLIGENCE" right="AI PLANNER" /><div className="intel"><button className="secondary" onClick={async()=>setSearchPlan(await api.getSearchPlan())}>PREVIEW COVERAGE PLAN</button>{searchPlan && <div className="plan-summary"><b>{searchPlan.drone_count} scout drones</b><span>Planner: {searchPlan.planner}</span><span>Motion: {searchPlan.motion_planner}</span><span>Overlap: {searchPlan.overlap_policy}</span></div>}<div className="decision"><Brain /><div><b>Explainable allocation</b><span>Capability + availability + distance + battery + risk are evaluated before dispatch.</span></div></div></div></div>
    </section>

    <section className="panel event-panel"><PanelTitle icon={<Zap />} title="LIVE EVENT STREAM" right={`${events.length} EVENTS`} /><div className="events">{events.slice(-12).reverse().map((e:any,i)=><div className="event" key={e.event_id || i}><span className="event-time">{new Date((e.timestamp||Date.now()/1000)*1000).toLocaleTimeString()}</span><b>{e.event_type}</b><span>{e.payload?.message || e.payload?.drone_id || e.payload?.session_id || e.source || 'System event'}</span></div>)}</div></section>
  </div>;
}

function Metric({label,value,sub,icon,danger}:{label:string,value:any,sub:string,icon:React.ReactNode,danger?:boolean}) { return <div className="metric"><div className="metric-icon">{icon}</div><div><span>{label}</span><strong className={danger?'danger':''}>{value}</strong><small>{sub}</small></div></div> }
function PanelTitle({icon,title,right}:{icon:React.ReactNode,title:string,right:string}) { return <div className="panel-title"><span>{icon}{title}</span><em>{right}</em></div> }
function Action({label,icon,busy,onClick}:{label:string,icon:React.ReactNode,busy:boolean,onClick:()=>void}) { return <button className="action" onClick={onClick} disabled={busy}>{busy?<RefreshCw className="spin"/>:icon}<span>{busy?'WORKING…':label}</span></button> }
