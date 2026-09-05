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
import { useSystemWebSocket } from '../websocket/useSystemWebSocket';
import { api } from '../services/api';
import { DroneEntity, Victim } from '../types';
import './ResQNetCommandCenter.css';

const priorityColor = (priority: string) => {
  switch (priority) {
    case 'CRITICAL': return 'critical';
    case 'HIGH': return 'high';
    case 'MEDIUM': return 'medium';
    default: return 'low';
  }
};

const mapX = (x: number) => 50 + (x / 200) * 45;
const mapY = (z: number) => 50 + (z / 200) * 45;

export function ResQNetCommandCenter() {
  const { snapshot, isConnected, latencyMs, refresh } = useSystemWebSocket();
  const [events, setEvents] = useState<any[]>([]);
  const [searchPlan, setSearchPlan] = useState<any>(null);
  const [busy, setBusy] = useState('');
  const [command, setCommand] = useState('');
  const [transcript, setTranscript] = useState('');
  const [response, setResponse] = useState('System ready. Awaiting operator command.');
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
    rec.onerror = () => speak('Voice input failed.');
    rec.onend = () => { recognitionRef.current = null; };
    rec.start();
  };

  const stopVoice = () => {
    recognitionRef.current?.stop();
    recognitionRef.current = null;
  };

  const runCommand = async () => {
    if (!command.trim()) return;
    try {
      const parsed = await api.interpretVoice(command);
      if (parsed.intent === 'GET_STATUS') {
        const status = await api.getResponseStatus();
        speak(`System operational. ${status.available_drones} drones available, ${status.critical_victims} critical victims, and ${status.active_missions} active missions.`);
      } else if (parsed.intent === 'START_RECON') {
        await execute('Recon deployment', api.startRecon, r => `Recon plan created for ${r.drone_count} scout drones.`);
      } else if (parsed.intent === 'AUTO_DISPATCH') {
        await execute('Priority response', api.triageDispatch, r => `Response cycle completed. ${r.dispatched?.length || 0} missions dispatched.`);
      } else if (parsed.intent === 'PRIORITIZE_ROOFTOP') {
        await execute('Victim reprioritization', api.reprioritizeVictims, () => 'Victim priorities updated for operator review.');
      } else {
        speak('Command recognized but it requires a specific manual target.');
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
          <Metric label="Drone fleet" value={`${idleDrones}/${drones.length || 4}`} detail="available" icon={<Navigation />} />
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
                placeholder="Try: “Find trapped civilians” or “Start reconnaissance”"
              />
              <button
                className={`voice-toggle ${recognitionRef.current ? 'recording' : ''}`}
                onClick={recognitionRef.current ? stopVoice : startVoice}
                title={recognitionRef.current ? 'Stop listening' : 'Start voice input'}
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
        <QuickAction label="Start reconnaissance" icon={<Search />} busy={busy === 'Recon deployment'} onClick={() => execute('Recon deployment', api.startRecon, r => `Recon plan created. ${r.drone_count} scout drones assigned.`)} />
        <QuickAction label="Triage & dispatch" icon={<Siren />} busy={busy === 'Priority response'} onClick={() => execute('Priority response', api.triageDispatch, r => `${r.dispatched?.length || 0} priority missions dispatched.`)} />
        <QuickAction label="Reprioritize victims" icon={<Brain />} busy={busy === 'Victim reprioritization'} onClick={() => execute('Victim reprioritization', api.reprioritizeVictims, () => 'Victim priority matrix updated.')} />
        <QuickAction label="Replan missions" icon={<RefreshCw />} busy={busy === 'Dynamic replanning'} onClick={() => execute('Dynamic replanning', api.evaluateReplanning, r => `Replanning evaluation completed. ${Array.isArray(r) ? r.length : 0} changes evaluated.`)} />
      </section>

      <section className="command-grid">
        <article className="rqcc-panel map-panel">
          <PanelHeading title="Live city picture" subtitle="Digital twin" right={snapshot?.session_id || 'metro_session_01'} />
          <div className="tactical-map">
            <div className="map-grid" />
            <div className="map-north">N</div>
            {Object.values(snapshot?.buildings || {}).map((b: any) => (
              <div
                key={b.id}
                className={`building ${b.damage_level && b.damage_level !== 'INTACT' ? 'damaged' : ''}`}
                style={{ left: `${mapX(b.center.x)}%`, top: `${mapY(b.center.z)}%`, width: `${Math.max(2, b.size_x / 18)}%`, height: `${Math.max(2, b.size_z / 18)}%` }}
                title={b.name}
              />
            ))}
            {Object.values(snapshot?.hazards || {}).map((h: any) => h.active && (
              <div
                key={h.id}
                className="hazard-zone"
                style={{ left: `${mapX(h.center.x)}%`, top: `${mapY(h.center.z)}%`, width: `${Math.max(6, h.radius_m / 2.5)}%`, height: `${Math.max(6, h.radius_m / 2.5)}%` }}
                title={h.type}
              />
            ))}
            {victims.map(v => (
              <div
                key={v.id}
                className={`map-victim ${priorityColor(v.priority_class)}`}
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
