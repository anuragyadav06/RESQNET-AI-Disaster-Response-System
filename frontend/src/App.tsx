import React, { useState } from 'react';
import './App.css';
import { useSystemWebSocket } from './websocket/useSystemWebSocket';
import { OperationsDashboard } from './pages/OperationsDashboard';
import { IncidentManagement } from './pages/IncidentManagement';
import { VictimIntelligence } from './pages/VictimIntelligence';
import { DroneFleetView } from './pages/DroneFleetView';
import { MissionControlView } from './pages/MissionControlView';
import { RoutePlanningView } from './pages/RoutePlanningView';
import { HazardMonitorView } from './pages/HazardMonitorView';
import { TelemetryView } from './pages/TelemetryView';
import { DecisionExplanationView } from './pages/DecisionExplanationView';
import { SystemDiagnosticsView } from './pages/SystemDiagnosticsView';
import { ResQNetCommandCenter } from './components/ResQNetCommandCenter';
import {
  Activity,
  AlertTriangle,
  Brain,
  Cpu,
  Gauge,
  HeartPulse,
  LayoutDashboard,
  Map,
  Radio,
  RefreshCw,
  Route,
  Settings,
  Shield,
  Siren,
  TriangleAlert,
  Users,
  Navigation,
} from 'lucide-react';

export function App() {
  const [currentTab, setCurrentTab] = useState('command');
  const { snapshot, isConnected, latencyMs, refresh } = useSystemWebSocket();

  const tabs = [
    { id: 'command', label: 'Command Center', icon: LayoutDashboard },
    { id: 'operations', label: 'Operations', icon: Activity },
    {
      id: 'incidents',
      label: 'Incidents',
      icon: Shield,
      badge: snapshot ? Object.keys(snapshot.incidents).length : 0,
      tone: 'warning',
    },
    {
      id: 'victims',
      label: 'Victims',
      icon: HeartPulse,
      badge: snapshot ? Object.values(snapshot.victims).filter(v => v.priority_class === 'CRITICAL').length : 0,
      tone: 'critical',
    },
    {
      id: 'drones',
      label: 'Drone Fleet',
      icon: Navigation,
      badge: snapshot ? Object.keys(snapshot.drones).length : 4,
      tone: 'info',
    },
    { id: 'missions', label: 'Mission Control', icon: Radio },
    {
      id: 'routes',
      label: 'Route Planning',
      icon: Route,
      badge: snapshot ? Object.values(snapshot.road_edges).filter(e => e.is_blocked).length : 0,
      tone: 'critical',
    },
    { id: 'hazards', label: 'Hazards', icon: TriangleAlert },
    { id: 'telemetry', label: 'Telemetry', icon: Gauge },
    { id: 'decisions', label: 'Decisions', icon: Brain },
    { id: 'system', label: 'System Health', icon: Cpu },
  ];

  const commandTabs = tabs.slice(0, 7);
  const analysisTabs = tabs.slice(7);

  const renderTab = (tab: typeof tabs[number]) => {
    const Icon = tab.icon;
    const active = currentTab === tab.id;

    return (
      <button
        key={tab.id}
        onClick={() => setCurrentTab(tab.id)}
        className={`app-nav-item ${active ? 'is-active' : ''}`}
      >
        <span className="app-nav-left">
          <Icon />
          <span>{tab.label}</span>
        </span>
        {tab.badge !== undefined && tab.badge > 0 && (
          <span className={`app-nav-badge ${tab.tone || ''}`}>{tab.badge}</span>
        )}
      </button>
    );
  };

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="app-brand">
          <div className="app-logo" aria-hidden="true">RQ</div>
          <div className="app-brand-copy">
            <div className="app-brand-name">RESQNET</div>
            <div className="app-brand-meta">Emergency Response Platform</div>
          </div>
        </div>

        <div className="app-header-center">
          <span className="app-context-label">Metro Response</span>
          <span className="app-context-separator">/</span>
          <span>{snapshot?.session_id || 'metro_session_01'}</span>
          <span className="app-context-separator">/</span>
          <span>T+{snapshot?.simulation_time?.toFixed(1) || '0.0'}s</span>
        </div>

        <div className="app-header-actions">
          <div className={`connection-status ${isConnected && snapshot?.system_b_connected ? 'online' : 'degraded'}`}>
            <span className="status-dot" />
            <span>{snapshot?.system_b_connected ? 'Twin connected' : 'Simulation mode'}</span>
          </div>
          <div className="header-metric">
            <span>Latency</span>
            <strong>{latencyMs} ms</strong>
          </div>
          <button className="header-icon-button" onClick={refresh} title="Refresh system state">
            <RefreshCw />
          </button>
          <div className="operator">
            <div className="operator-avatar">OP</div>
            <div className="operator-copy">
              <strong>Operator</strong>
              <span>Command desk</span>
            </div>
          </div>
        </div>
      </header>

      <div className="app-body">
        <aside className="app-sidebar">
          <div className="app-nav">
            <div className="app-nav-section">
              <div className="app-nav-heading">Command</div>
              {commandTabs.map(renderTab)}
            </div>

            <div className="app-nav-section">
              <div className="app-nav-heading">Analysis & System</div>
              {analysisTabs.map(renderTab)}
            </div>
          </div>

          <div className="app-sidebar-footer">
            <div className="system-health">
              <div className="system-health-top">
                <span className="health-dot" />
                <strong>All systems operational</strong>
              </div>
              <div className="system-health-meta">
                <span>State v{snapshot?.state_version || 1}</span>
                <span>Synced just now</span>
              </div>
            </div>
            <button className="sidebar-settings" onClick={() => setCurrentTab('system')}>
              <Settings />
              <span>System settings</span>
            </button>
          </div>
        </aside>

        <main className="app-main">
          {snapshot?.simulation_frame_base64 && (
            <div className="mb-3 bg-[#07111d] border border-cyan-900/50 rounded-xl overflow-hidden shadow-lg">
              <div className="px-3 py-1.5 flex items-center justify-between text-[10px] font-mono">
                <span className="text-cyan-300">LIVE DIGITAL TWIN / SYSTEM B VIEW</span>
                <span className="text-slate-500">Authoritative simulation · T+{snapshot.simulation_time.toFixed(1)}s</span>
              </div>
              <img className="w-full max-h-52 object-cover" src={`data:${snapshot.simulation_frame_mime_type || 'image/jpeg'};base64,${snapshot.simulation_frame_base64}`} alt="Live Godot Digital Twin" />
            </div>
          )}
          <div className="mobile-nav">
            <button className={currentTab === 'command' ? 'active' : ''} onClick={() => setCurrentTab('command')}><LayoutDashboard />Command</button>
            <button className={currentTab === 'incidents' ? 'active' : ''} onClick={() => setCurrentTab('incidents')}><Shield />Incidents</button>
            <button className={currentTab === 'victims' ? 'active' : ''} onClick={() => setCurrentTab('victims')}><HeartPulse />Victims</button>
            <button className={currentTab === 'missions' ? 'active' : ''} onClick={() => setCurrentTab('missions')}><Radio />Missions</button>
          </div>

          {currentTab === 'command' && <ResQNetCommandCenter snapshot={snapshot} isConnected={isConnected} latencyMs={latencyMs} refresh={refresh} />}
          {currentTab === 'operations' && (
            <OperationsDashboard snapshot={snapshot} isConnected={isConnected} latencyMs={latencyMs} onRefresh={refresh} />
          )}
          {currentTab === 'incidents' && <IncidentManagement onRefresh={refresh} snapshot={snapshot} />}
          {currentTab === 'victims' && <VictimIntelligence onRefresh={refresh} snapshot={snapshot} />}
          {currentTab === 'drones' && <DroneFleetView onRefresh={refresh} snapshot={snapshot} />}
          {currentTab === 'missions' && <MissionControlView onRefresh={refresh} snapshot={snapshot} />}
          {currentTab === 'routes' && <RoutePlanningView snapshot={snapshot} onRefresh={refresh} />}
          {currentTab === 'hazards' && <HazardMonitorView snapshot={snapshot} />}
          {currentTab === 'telemetry' && <TelemetryView snapshot={snapshot} latencyMs={latencyMs} />}
          {currentTab === 'decisions' && <DecisionExplanationView onRefresh={refresh} />}
          {currentTab === 'system' && <SystemDiagnosticsView snapshot={snapshot} latencyMs={latencyMs} />}
        </main>
      </div>

      <footer className="app-footer">
        <div>
          <span className="footer-live"><span className="status-dot" />Live system state</span>
          <span>WebSocket /ws/frontend</span>
          <span>•</span>
          <span>{snapshot ? Object.keys(snapshot.victims).length : 0} people tracked</span>
          <span>•</span>
          <span>{snapshot ? Object.keys(snapshot.drones).length : 0} drones</span>
        </div>
        <div className="footer-right">
          <span>RESQNET System A</span>
          <span>Response intelligence</span>
        </div>
      </footer>
    </div>
  );
}

export default App;
