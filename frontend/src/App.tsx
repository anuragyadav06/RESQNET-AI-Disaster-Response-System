import React, { useState } from 'react';
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
  Shield,
  Radio,
  HeartPulse,
  Navigation,
  Network,
  Flame,
  Gauge,
  Brain,
  Cpu,
  RefreshCw,
  Terminal,
  Siren,
} from 'lucide-react';

export function App() {
  const [currentTab, setCurrentTab] = useState<string>('command');
  const { snapshot, isConnected, latencyMs, refresh } = useSystemWebSocket();

  // Navigation tabs definition
  const tabs = [
    { id: 'command', label: 'AI Command Center', icon: Siren },
    { id: 'operations', label: 'Operations Overview', icon: Activity },
    {
      id: 'incidents',
      label: 'Incident Management',
      icon: Shield,
      badge: snapshot ? Object.keys(snapshot.incidents).length : 0,
      badgeColor: 'bg-orange-600',
    },
    {
      id: 'victims',
      label: 'Victim Intelligence',
      icon: HeartPulse,
      badge: snapshot
        ? Object.values(snapshot.victims).filter((v) => v.priority_class === 'CRITICAL').length
        : 0,
      badgeColor: 'bg-red-600 animate-pulse',
    },
    {
      id: 'drones',
      label: 'Drone Fleet',
      icon: Navigation,
      badge: snapshot ? Object.keys(snapshot.drones).length : 4,
      badgeColor: 'bg-cyan-800',
    },
    {
      id: 'missions',
      label: 'Mission Control',
      icon: Radio,
    },
    {
      id: 'routes',
      label: 'Route Planning & Graph',
      icon: Network,
      badge: snapshot ? Object.values(snapshot.road_edges).filter((e) => e.is_blocked).length : 0,
      badgeColor: 'bg-red-800',
    },
    {
      id: 'hazards',
      label: 'Hazard Monitor',
      icon: Flame,
    },
    {
      id: 'telemetry',
      label: 'High-Freq Telemetry',
      icon: Gauge,
    },
    {
      id: 'decisions',
      label: 'Decision Explanations',
      icon: Brain,
    },
    {
      id: 'system',
      label: 'System Diagnostics',
      icon: Cpu,
    },
  ];

  return (
    <div className="min-h-screen w-full bg-[#06090f] text-slate-200 flex flex-col font-sans">
      {/* Top Main Command Header */}
      <header className="h-14 bg-[#090e17] border-b border-cyan-950 px-4 flex items-center justify-between shadow-lg z-40">
        <div className="flex items-center gap-3">
          <div className="relative flex items-center justify-center">
            <div className="w-8 h-8 rounded-lg bg-cyan-950 border border-cyan-600/60 flex items-center justify-center text-cyan-400 font-mono font-black text-sm shadow-[0_0_15px_rgba(6,182,212,0.3)]">
              RQ
            </div>
            <span className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-cyan-400 animate-ping" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-sm font-black tracking-widest uppercase font-mono text-slate-100">
                RESQNET <span className="text-cyan-400 font-bold">SYSTEM A</span>
              </h1>
              <span className="px-1.5 py-0.5 rounded text-[9px] font-mono bg-cyan-950 text-cyan-300 border border-cyan-800">
                COMMAND & INTELLIGENCE
              </span>
            </div>
            <div className="text-[10px] text-slate-400 font-mono flex items-center gap-2">
              <span>SIMULATION: {snapshot?.session_id || 'metro_session_01'}</span>
              <span>•</span>
              <span>T+{snapshot?.simulation_time.toFixed(1) || '0.0'}s</span>
            </div>
          </div>
        </div>

        {/* Live Link & Telemetry Indicators */}
        <div className="flex items-center gap-3 text-xs font-mono">
          <div className="flex items-center gap-2 bg-[#0c1320] px-2.5 py-1 rounded-lg border border-cyan-900/50">
            <span
              className={`w-2 h-2 rounded-full ${
                snapshot?.system_b_connected ? 'bg-emerald-400 shadow-[0_0_8px_#34d399]' : 'bg-amber-400 shadow-[0_0_8px_#fbbf24]'
              } animate-pulse`}
            />
            <span className="text-[11px] text-slate-300 font-bold">
              {snapshot?.system_b_connected ? 'GODOT TWIN LIVE' : 'INTERNAL TWIN SIM'}
            </span>
          </div>

          <div className="hidden md:flex items-center gap-2 bg-[#0c1320] px-2.5 py-1 rounded-lg border border-cyan-900/50 text-[11px] text-slate-400">
            <span>Rate:</span>
            <strong className="text-cyan-300">{snapshot?.telemetry_rate_hz || 10.0} Hz</strong>
            <span className="text-slate-600">|</span>
            <span>Latency:</span>
            <strong className="text-emerald-400">{latencyMs} ms</strong>
          </div>

          <button
            onClick={refresh}
            className="p-1.5 bg-[#0c1320] hover:bg-slate-800 border border-cyan-900/50 rounded-lg text-slate-300 transition"
            title="Refresh State"
          >
            <RefreshCw className="w-3.5 h-3.5" />
          </button>
        </div>
      </header>

      {/* Main Body with Sidebar + Content */}
      <div className="flex-1 flex overflow-hidden">
        {/* Sidebar Navigation */}
        <aside className="w-60 bg-[#070b13] border-r border-cyan-950/80 flex flex-col justify-between p-2">
          <div className="space-y-1">
            <div className="px-3 py-2 text-[10px] font-mono uppercase tracking-wider text-slate-400 font-bold">
              Command Modules
            </div>
            {tabs.map((tab) => {
              const Icon = tab.icon;
              const isActive = currentTab === tab.id;
              return (
                <button
                  key={tab.id}
                  onClick={() => setCurrentTab(tab.id)}
                  className={`w-full flex items-center justify-between px-3 py-2 rounded-lg text-xs font-mono font-medium transition ${
                    isActive
                      ? 'bg-cyan-950/80 text-cyan-300 border border-cyan-700/60 shadow-[0_0_12px_rgba(6,182,212,0.15)] font-bold'
                      : 'text-slate-400 hover:bg-slate-900/80 hover:text-slate-200'
                  }`}
                >
                  <div className="flex items-center gap-2.5">
                    <Icon className={`w-4 h-4 ${isActive ? 'text-cyan-400' : 'text-slate-500'}`} />
                    <span>{tab.label}</span>
                  </div>
                  {tab.badge !== undefined && tab.badge > 0 && (
                    <span
                      className={`px-1.5 py-0.2 rounded text-[10px] font-mono text-white ${
                        tab.badgeColor || 'bg-slate-700'
                      }`}
                    >
                      {tab.badge}
                    </span>
                  )}
                </button>
              );
            })}
          </div>

          {/* Sidebar Footer */}
          <div className="bg-[#0b121e] border border-cyan-950 p-2.5 rounded-lg text-[10px] font-mono text-slate-400 space-y-1">
            <div className="flex justify-between">
              <span>Status Engine:</span>
              <span className="text-emerald-400 font-bold">OPERATIONAL</span>
            </div>
            <div className="flex justify-between">
              <span>State Version:</span>
              <span className="text-cyan-300 font-bold">v{snapshot?.state_version || 1}</span>
            </div>
          </div>
        </aside>

        {/* Dynamic Content Page */}
        <main className="flex-1 overflow-y-auto p-4 bg-[#06090f]">
          {currentTab === 'command' && <ResQNetCommandCenter />}
          {currentTab === 'operations' && (
            <OperationsDashboard
              snapshot={snapshot}
              isConnected={isConnected}
              latencyMs={latencyMs}
              onRefresh={refresh}
            />
          )}
          {currentTab === 'incidents' && <IncidentManagement onRefresh={refresh} />}
          {currentTab === 'victims' && <VictimIntelligence onRefresh={refresh} />}
          {currentTab === 'drones' && <DroneFleetView onRefresh={refresh} />}
          {currentTab === 'missions' && <MissionControlView onRefresh={refresh} />}
          {currentTab === 'routes' && <RoutePlanningView snapshot={snapshot} onRefresh={refresh} />}
          {currentTab === 'hazards' && <HazardMonitorView snapshot={snapshot} />}
          {currentTab === 'telemetry' && <TelemetryView snapshot={snapshot} latencyMs={latencyMs} />}
          {currentTab === 'decisions' && <DecisionExplanationView onRefresh={refresh} />}
          {currentTab === 'system' && <SystemDiagnosticsView snapshot={snapshot} latencyMs={latencyMs} />}
        </main>
      </div>

      {/* Bottom Mission Status Bar */}
      <footer className="h-7 bg-[#070b12] border-t border-cyan-950 px-4 flex items-center justify-between text-[11px] font-mono text-slate-400 z-30">
        <div className="flex items-center gap-4">
          <span className="flex items-center gap-1.5">
            <Terminal className="w-3 h-3 text-cyan-400" /> RESQNET CLOSED-LOOP AUTONOMOUS RESPONSE
          </span>
          <span className="text-slate-600">•</span>
          <span>
            Victims: <strong className="text-red-400">{snapshot ? Object.keys(snapshot.victims).length : 0}</strong>
          </span>
          <span className="text-slate-600">•</span>
          <span>
            Active Incidents: <strong className="text-orange-400">{snapshot ? Object.keys(snapshot.incidents).length : 0}</strong>
          </span>
          <span className="text-slate-600">•</span>
          <span>
            Fleet Available: <strong className="text-cyan-300">{snapshot ? Object.values(snapshot.drones).filter((d) => d.status === 'IDLE').length : 4}</strong>
          </span>
        </div>

        <div className="flex items-center gap-3">
          <span className="text-slate-500">Autonomous A* Dynamic Routing</span>
          <span className="text-slate-600">•</span>
          <span className="text-cyan-400">WebSocket /ws/frontend</span>
        </div>
      </footer>
    </div>
  );
}

export default App;
