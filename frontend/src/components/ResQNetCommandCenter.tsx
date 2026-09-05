import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertTriangle,
  ArrowUpRight,
  Brain,
  CheckCircle2,
  Crosshair,
  MapPin,
  Mic,
  MicOff,
  Navigation,
  Radio,
  RefreshCw,
  Search,
  Send,
  Siren,
  Users,
  Volume2,
  XCircle,
} from 'lucide-react';
import { api } from '../services/api';
import { DroneEntity, Victim, WorldStateSnapshot } from '../types';
import './ResQNetCommandCenter.css';

const priorityColor = (priority: string) => {
  switch (priority) {
    case 'CRITICAL': return 'critical';
    case 'HIGH': return 'high';
    case 'MEDIUM': return 'medium';
    default: return 'low';
  }
};

const mapX = (x: number) => ((x + 360) / 720) * 100;
const mapY = (z: number) => ((z + 360) / 720) * 100;

export function ResQNetCommandCenter({ snapshot, isConnected, latencyMs, refresh }: { snapshot: WorldStateSnapshot | null; isConnected: boolean; latencyMs: number; refresh: () => void }) {
  const [events, setEvents] = useState<any[]>([]);
  const [searchPlan, setSearchPlan] = useState<any>(null);
  const [busy, setBusy] = useState('');
  const [command, setCommand] = useState('');
  const [transcript, setTranscript] = useState('');
  const [response, setResponse] = useState('System ready. Awaiting operator command.');
  const [voiceState, setVoiceState] = useState<'idle'|'listening'|'error'>('idle');
  const recognitionRef = useRef<any>(null);

  const loadEvents = useCallback(async () => {
    try { setEvents(await api.getLiveEvents(40)); } catch { /* live state remains primary */ }
  }, []);

  useEffect(() => {
    loadEvents();
    const id = setInterval(loadEvents, 2000);
    return () => clearInterval(id);
  }, [loadEvents]);

  const drones = useMemo(() => Object.values(snapshot?.drones || {}) as DroneEntity[], [snapshot]);
  const victims = useMemo(() => Object.values(snapshot?.victims || {}) as Victim[], [snapshot]);
  const critical = victims.filter(v => v.priority_class === 'CRITICAL').length;
  const activeMissions = drones.filter(d => d.current_mission_id);
  const idleDrones = drones.filter(d => d.status === 'IDLE').length;
  const blockedRoads = snapshot ? Object.values(snapshot.road_edges).filter(e => e.is_blocked).length : 0;
  const activeHazards = snapshot ? Object.values(snapshot.hazards).filter((h: any) => h.active).length : 0;
  const incidentCount = snapshot ? Object.keys(snapshot.incidents).length : 0;

  const topVictims = [...victims].sort((a, b) => b.priority_score - a.priority_score).slice(0, 7);

  const latestEvents = events.slice(-8).reverse();

  const speak = (text: string) => {
    setResponse(text);
    if ('speechSynthesis' in window) {
      window.speechSynthesis.cancel();
      window.speechSynthesis.speak(new SpeechSynthesisUtterance(text));
    }
  };

  const execute = async (label: string, fn: () => Promise<any>, spoken?: (r: any) => string) => {
    setBusy(label);
    try {
      const result = await fn();
      await refresh();
      await loadEvents();
      speak(spoken ? spoken(result) : `${label} completed successfully.`);
      return result;
    } catch (e: any) {
      speak(`${label} failed. ${e?.message || 'Check system diagnostics.'}`);
    } finally {
      setBusy('');
    }
  };

  const startVoice = () => {
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) {
      speak('Browser speech recognition is unavailable. Use Chrome or enter a command manually.');
      return;
    }

    const rec = new SR();
    recognitionRef.current = rec;
    rec.lang = 'en-IN';
    rec.continuous = false;
    rec.interimResults = true;
    rec.onresult = (e: any) => {
      const text = Array.from(e.results).map((r: any) => r[0].transcript).join('');
      setTranscript(text);
      if (e.results[e.results.length - 1].isFinal) setCommand(text);
    };
    rec.onstart = () => setVoiceState('listening');
    rec.onerror = (e: any) => {
      setVoiceState('error');
      const code = e?.error || 'unknown';
      const messages: Record<string, string> = {
        'no-speech': "No speech detected. Try again and speak clearly.",
        'audio-capture': 'Microphone capture failed. Check the selected microphone.',
        'not-allowed': 'Microphone permission is blocked. Allow microphone access for localhost:5173.',
        'service-not-allowed': 'Browser speech recognition is disabled by the browser.',
        'network': 'The browser speech service is unavailable. Your typed command still works; try Chrome with internet access or use text input.',
        'aborted': 'Voice capture stopped.',
      };
      const msg = messages[code] ?? `Voice input failed (${code}). Type the command to continue.`;
      if (code !== 'aborted') speak(msg);
    };
    rec.onend = () => { recognitionRef.current = null; setVoiceState('idle'); };
    try { rec.start(); } catch (err: any) {
      recognitionRef.current = null;
      setVoiceState('error');
      speak(`Microphone could not start. ${err?.message || 'Use the text command box.'}`);
    }
  };

  const stopVoice = () => {
    recognitionRef.current?.stop();
    recognitionRef.current = null;
  };

  const INTENT_LABELS: Record<string, string> = {
    GET_STATUS: 'get the current status',
    START_RECON: 'start reconnaissance',
    PRIORITIZE_ROOFTOP: 'prioritize rooftop victims',
    AUTO_DISPATCH: 'send the nearest available drone',
  };

  const runCommand = async () => {
    if (!command.trim()) return;
    try {
      const executed = await api.executeOperatorCommand(command);
      const parsed = executed.parsed || {};
      const result = executed.result || {};
      if (executed.status === 'NOT_EXECUTED') {
        const suggestions: string[] = parsed.suggestions || [];
        if (suggestions.length) {
          const asPhrases = suggestions.map(s => `"${INTENT_LABELS[s] || s}"`).join(' or ');
          speak(`I didn't quite catch that. Did you mean ${asPhrases}?`);
        } else {
          speak(parsed.message || 'Command not executed. Try a specific victim or drone action.');
        }
        return;
      }
      if (parsed.intent === 'GET_STATUS') {
        speak(`System operational. ${result.available_drones ?? 0} drones available, ${result.critical_victims ?? 0} critical victims, and ${result.active_missions ?? 0} active missions.`);
      } else if (parsed.intent === 'DISPATCH_RESPONSE') {
        const mission = result.mission;
        speak(`Response mission ${mission?.mission_id || 'created'} dispatched to ${parsed.parameters?.victim_id || 'the victim'}.`);
      } else if (parsed.intent === 'START_RECON') {
        speak(`Reconnaissance activated for ${result.drone_count ?? 16} scout drones.`);
      } else if (parsed.intent === 'AUTO_DISPATCH') {
        speak(`Priority response completed. ${result.dispatched?.length || 0} missions dispatched.`);
      } else if (parsed.intent === 'ABORT_DRONE_MISSION') {
        speak(`${parsed.parameters?.drone_id} mission aborted.`);
      } else if (parsed.intent === 'RTB') {
        speak(`${parsed.parameters?.drone_id} is returning to base.`);
      } else if (parsed.intent === 'DEPLOY_TO_SECTOR') {
        speak(`${parsed.parameters?.drone_id} accepted for ${parsed.parameters?.sector}.`);
      } else {
        speak(result.message || 'Command executed successfully.');
      }
    } catch (e: any) {
      speak(`Command failed. ${e?.message || 'Check system diagnostics.'}`);
    }
  };

  return (
    <div className="rqcc">
      <section className="rqcc-heading">
        <div className="command-center-banner">
          <div>RESQNET / COMMAND</div>
          <h1>Command Center</h1>
          <p>Live incident picture, response resources and autonomous mission control.</p>
        </div>
        <div className="rqcc-heading-state">
          <div className={`rqcc-live-state ${isConnected && snapshot?.system_b_connected ? 'online' : 'degraded'}`}>
            <span className="state-dot" />
            {snapshot?.system_b_connected ? 'Digital twin connected' : 'Simulation mode'}
          </div>
          <span className="rqcc-time">T+{snapshot?.simulation_time?.toFixed(1) || '0.0'}s</span>
        </div>
      </section>

      <section className="overview-grid">
        <article className={`incident-summary ${critical > 0 || activeHazards > 0 ? 'has-alert' : ''}`}>
          <div className="incident-summary-top">
            <div>
              <span className="section-kicker">CURRENT OPERATION</span>
              <h2>{incidentCount > 0 ? 'Active emergency response' : 'Monitoring city state'}</h2>
            </div>
            <span className={`severity-badge ${incidentCount > 0 ? 'critical' : 'normal'}`}>
              <span />{incidentCount > 0 ? 'Active incident' : 'No active incident'}
            </span>
          </div>

          <div className="incident-meta-grid">
            <div><span>Location</span><strong>North Metro</strong></div>
            <div><span>Incident ID</span><strong>{snapshot?.session_id || 'metro_session_01'}</strong></div>
            <div><span>People tracked</span><strong>{victims.length}</strong></div>
            <div><span>Last state update</span><strong>{snapshot ? `T+${snapshot.simulation_time.toFixed(1)}s` : 'Waiting'}</strong></div>
          </div>

          <div className="incident-alert-line">
            <AlertTriangle />
            <div>
              <strong>{critical > 0 ? `${critical} critical victim${critical === 1 ? '' : 's'} require attention` : 'No critical victims currently flagged'}</strong>
              <span>{activeHazards} active hazard zones · {blockedRoads} blocked road segments</span>
            </div>
          </div>
        </article>

        <div className="metric-stack">
          <Metric label="Drone fleet" value={`${idleDrones}/${drones.length || 31}`} detail="available" icon={<Navigation />} />
          <Metric label="Active missions" value={activeMissions.length} detail="live assignments" icon={<Crosshair />} />
          <Metric label="Critical victims" value={critical} detail={`${victims.length} tracked`} icon={<AlertTriangle />} tone="critical" />
          <Metric label="System latency" value={`${latencyMs} ms`} detail={`${snapshot?.telemetry_rate_hz?.toFixed(1) || '0.0'} Hz telemetry`} icon={<Radio />} />
        </div>
      </section>

      <section className="command-panel">
        <div className="command-panel-main">
          <div className="panel-heading">
            <div>
              <span className="section-kicker">OPERATOR COMMAND</span>
              <h3>Voice or text instruction</h3>
            </div>
            <span className="command-flow">Input <b>→</b> Intent <b>→</b> Safety <b>→</b> Execute</span>
          </div>

          <div className="command-input-row">
            <div className="command-input-wrap">
              <Mic className="command-input-icon" />
              <input
                value={command}
                onChange={e => setCommand(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && runCommand()}
                placeholder="Try: “Find trapped civilians” or “Activate 16-drone grid search”"
              />
              <button
                className={`voice-toggle ${voiceState === 'listening' ? 'recording' : ''}`}
                onClick={voiceState === 'listening' ? stopVoice : startVoice}
                title={voiceState === 'listening' ? 'Stop listening' : 'Start voice input'}
              >
                {recognitionRef.current ? <MicOff /> : <Mic />}
              </button>
            </div>
            <button className="primary-command-button" onClick={runCommand}>
              <Send /> Execute
            </button>
          </div>

          <div className="transcript-line">
            <span>Transcript</span>
            <strong>{transcript || 'No active voice transcript'}</strong>
          </div>
        </div>

        <div className="command-response">
          <div className="panel-heading compact">
            <div>
              <span className="section-kicker">SYSTEM RESPONSE</span>
              <h3>Operator feedback</h3>
            </div>
            <Volume2 />
          </div>
          <p>{response}</p>
        </div>
      </section>

      <section className="quick-actions">
        <QuickAction label="Activate 16-drone grid search" icon={<Search />} busy={busy === 'Grid search activation'} onClick={() => execute('Grid search activation', api.startRecon, r => `Recon plan created. ${r.drone_count} scout drones assigned.`)} />
        <QuickAction label="Triage & dispatch" icon={<Siren />} busy={busy === 'Priority response'} onClick={() => execute('Priority response', api.triageDispatch, r => `${r.dispatched?.length || 0} priority missions dispatched.`)} />
        <QuickAction label="Reprioritize victims" icon={<Brain />} busy={busy === 'Victim reprioritization'} onClick={() => execute('Victim reprioritization', api.reprioritizeVictims, () => 'Victim priority matrix updated.')} />
        <QuickAction label="Replan missions" icon={<RefreshCw />} busy={busy === 'Dynamic replanning'} onClick={() => execute('Dynamic replanning', api.evaluateReplanning, r => `Replanning evaluation completed. ${Array.isArray(r) ? r.length : 0} changes evaluated.`)} />
      </section>

      <section className="command-grid">
        <article className="rqcc-panel map-panel">
          <PanelHeading title="Live city picture" subtitle="Digital twin" right={snapshot?.session_id || 'metro_session_01'} />
          <div className="tactical-map">
            {snapshot?.simulation_frame_base64 && (
              <img
                src={`data:${snapshot.simulation_frame_mime_type || 'image/jpeg'};base64,${snapshot.simulation_frame_base64}`}
                alt="Live Godot Digital Twin"
                className="absolute inset-0 w-full h-full object-cover opacity-75 rounded-lg"
              />
            )}
            <div className="map-grid relative z-10" />
            <div className="map-north">N</div>
            {Object.values(snapshot?.buildings || {}).map((b: any) => (
              <div
                key={b.id}
                className={`building ${b.damage_level && b.damage_level !== 'INTACT' ? 'damaged' : ''}`}
                style={{ left: `${mapX(b.center.x)}%`, top: `${mapY(b.center.z)}%`, width: `${Math.max(1.5, b.size_x / 7.2)}%`, height: `${Math.max(1.5, b.size_z / 7.2)}%` }}
                title={b.name}
              />
            ))}
            {Object.values(snapshot?.hazards || {}).map((h: any) => h.active && (
              <div
                key={h.id}
                className="hazard-zone"
                style={{ left: `${mapX(h.center.x)}%`, top: `${mapY(h.center.z)}%`, width: `${Math.max(4, (h.radius_m * 2) / 7.2)}%`, height: `${Math.max(4, (h.radius_m * 2) / 7.2)}%` }}
                title={h.type}
              />
            ))}
            {victims.map(v => (
              <div
                key={v.id}
                className={`map-victim ${v.status === 'EVACUATED' ? 'rescued' : priorityColor(v.priority_class)}`}
                style={{ left: `${mapX(v.location.x)}%`, top: `${mapY(v.location.z)}%` }}
                title={`${v.id} — ${v.priority_class}`}
              />
            ))}
            {drones.map(d => (
              <div
                key={d.id}
                className="map-drone"
                style={{ left: `${mapX(d.position.x)}%`, top: `${mapY(d.position.z)}%` }}
                title={`${d.id} — ${d.status}`}
              >
                <Navigation />
              </div>
            ))}
            <div className="map-caption">Live operational state</div>
            <div className="map-legend">
              <span><i className="legend-dot critical" /> Critical</span>
              <span><i className="legend-dot high" /> High</span>
              <span><i className="legend-drone" /> Drone</span>
              <span><i className="legend-hazard" /> Hazard</span>
            </div>
          </div>
        </article>

        <article className="rqcc-panel fleet-panel">
          <PanelHeading title="Drone fleet" subtitle="Resource readiness" right={`${drones.length} units`} />
          <div className="fleet-list">
            {drones.length === 0 && <EmptyState text="No drone telemetry received." />}
            {drones.map(d => (
              <div className="fleet-item" key={d.id}>
                <div className="fleet-unit-icon"><Navigation /></div>
                <div className="fleet-unit-copy">
                  <strong>{d.id}</strong>
                  <span>{d.callsign}</span>
                </div>
                <div className="fleet-unit-state">
                  <strong>{d.battery_percent.toFixed(0)}%</strong>
                  <span>{d.status}</span>
                </div>
                <div className="fleet-battery"><i style={{ width: `${Math.max(0, Math.min(100, d.battery_percent))}%` }} /></div>
              </div>
            ))}
          </div>
          <div className="panel-footnote"><span>{idleDrones} available</span><span>{activeMissions.length} on mission</span></div>
        </article>
      </section>

      <section className="lower-grid">
        <article className="rqcc-panel">
          <PanelHeading title="Priority queue" subtitle="Victim intelligence" right={`${victims.length} tracked`} />
          <div className="priority-list">
            {topVictims.length === 0 && <EmptyState text="No victims detected." />}
            {topVictims.map(v => (
              <div className="priority-row" key={v.id}>
                <span className={`priority-pill ${priorityColor(v.priority_class)}`}>{v.priority_class}</span>
                <div className="priority-person">
                  <strong>{v.id} · {v.people_count} {v.people_count === 1 ? 'person' : 'people'}</strong>
                  <span>{v.hazard_type?.replaceAll('_', ' ') || 'Unknown hazard'} · {v.status}</span>
                </div>
                <span className="priority-score">{v.priority_score.toFixed(0)}</span>
                <ArrowUpRight className="row-arrow" />
              </div>
            ))}
          </div>
        </article>

        <article className="rqcc-panel">
          <PanelHeading title="Live activity" subtitle="Latest system events" right={`${events.length} events`} />
          <div className="activity-list">
            {latestEvents.length === 0 && <EmptyState text="Waiting for live events." />}
            {latestEvents.map((event: any, index) => (
              <div className="activity-row" key={event.event_id || index}>
                <span className="activity-time">
                  {new Date((event.timestamp || Date.now() / 1000) * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                </span>
                <span className="activity-marker" />
                <div>
                  <strong>{event.event_type || 'System event'}</strong>
                  <span>{event.payload?.message || event.payload?.drone_id || event.payload?.session_id || event.source || 'State update received'}</span>
                </div>
              </div>
            ))}
          </div>
        </article>
      </section>

      <section className="insight-strip">
        <div className="insight-icon"><Brain /></div>
        <div className="insight-copy">
          <span className="section-kicker">DECISION SUPPORT</span>
          <strong>Explainable resource allocation</strong>
          <p>Capability, availability, distance, battery and current risk are evaluated before a mission is recommended.</p>
        </div>
        <button className="secondary-command" onClick={async () => setSearchPlan(await api.getSearchPlan())}>
          Preview coverage plan
          <ArrowUpRight />
        </button>
        {searchPlan && (
          <div className="coverage-summary">
            <strong>{searchPlan.drone_count} scout drones</strong>
            <span>{searchPlan.planner} · {searchPlan.motion_planner}</span>
          </div>
        )}
      </section>
    </div>
  );
}

function Metric({
  label, value, detail, icon, tone,
}: { label: string; value: string | number; detail: string; icon: React.ReactNode; tone?: string }) {
  return (
    <div className={`summary-metric ${tone || ''}`}>
      <div className="summary-metric-icon">{icon}</div>
      <div>
        <span>{label}</span>
        <strong>{value}</strong>
        <small>{detail}</small>
      </div>
    </div>
  );
}

function PanelHeading({ title, subtitle, right }: { title: string; subtitle: string; right?: string }) {
  return (
    <div className="rqcc-panel-heading">
      <div>
        <h3>{title}</h3>
        <span>{subtitle}</span>
      </div>
      {right && <em>{right}</em>}
    </div>
  );
}

function QuickAction({ label, icon, busy, onClick }: { label: string; icon: React.ReactNode; busy: boolean; onClick: () => void }) {
  return (
    <button className="quick-action" onClick={onClick} disabled={busy}>
      {busy ? <RefreshCw className="spin" /> : icon}
      <span>{busy ? 'Working…' : label}</span>
    </button>
  );
}

function EmptyState({ text }: { text: string }) {
  return <div className="empty-state"><Users /><span>{text}</span></div>;
}

export default ResQNetCommandCenter;