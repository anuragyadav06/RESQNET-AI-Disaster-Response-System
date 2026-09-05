import React, { useMemo, useState } from 'react';
import {
  WorldStateSnapshot,
  DroneEntity,
} from '../types';
import {
  ZoomIn,
  ZoomOut,
  RotateCcw,
  Eye,
  Crosshair,
  Navigation,
} from 'lucide-react';

interface TacticalMapProps {
  snapshot: WorldStateSnapshot | null;
  selectedEntity: any | null;
  onSelectEntity: (entity: any, type: string) => void;
}

/**
 * RESQNET Tactical Radar
 *
 * Design goals:
 * - The entire authoritative -360m..+360m Digital Twin is always visible.
 * - No manual browser resizing is required to understand the map.
 * - 31 drones remain visually distinguishable by role:
 *     SCOUT      = cyan
 *     MEDICAL    = green
 *     HEAVY LIFT = orange
 *     RESCUE     = red
 * - Standby drones are compact symbols without 31 large text labels.
 * - Active response drones get a stronger halo and label.
 * - Completed victims are removed from this operational radar, but remain
 *   in the authoritative snapshot and therefore remain available to the
 *   Victim Intelligence page/history.
 */
export const TacticalMap: React.FC<TacticalMapProps> = ({
  snapshot,
  selectedEntity,
  onSelectEntity,
}) => {
  const [zoom, setZoom] = useState<number>(1);
  const [showDrones, setShowDrones] = useState<boolean>(true);
  const [showVictims, setShowVictims] = useState<boolean>(true);
  const [showHazards, setShowHazards] = useState<boolean>(true);
  const [showRoads, setShowRoads] = useState<boolean>(false);
  const [showBuildings, setShowBuildings] = useState<boolean>(true);
  const [showLegend, setShowLegend] = useState<boolean>(true);

  const mapWidth = 1200;
  const mapHeight = 720;
  const worldMin = -360;
  const worldMax = 360;
  const worldExtent = worldMax - worldMin;

  const toSvgX = (x: number) =>
    ((Math.max(worldMin, Math.min(worldMax, Number(x) || 0)) - worldMin) / worldExtent) * mapWidth;

  const toSvgY = (z: number) =>
    ((Math.max(worldMin, Math.min(worldMax, Number(z) || 0)) - worldMin) / worldExtent) * mapHeight;

  const roadEdges = useMemo(
    () => (snapshot ? Object.values(snapshot.road_edges || {}) : []),
    [snapshot],
  );

  const roadNodes = useMemo(
    () => snapshot?.road_nodes || {},
    [snapshot],
  );

  const drones = useMemo(
    () => (snapshot ? Object.values(snapshot.drones || {}) as DroneEntity[] : []),
    [snapshot],
  );

  const victims = useMemo(
    () => {
      if (!snapshot) return [];
      return Object.values(snapshot.victims || {}).filter((victim: any) => {
        const status = String(victim.status || '').toUpperCase();
        // Operational radar shows only unresolved / actionable victims.
        // Terminal records remain in snapshot and Victim Intelligence.
        return ![
          'RESCUED',
          'ASSISTED',
          'EVACUATED',
          'TREATED',
          'STABILIZED',
          'MEDICALLY_STABILIZED',
          'RESOLVED',
          'SAFE',
        ].includes(status);
      });
    },
    [snapshot],
  );

  const activeVictimCount = victims.length;
  const completedVictimCount = useMemo(() => {
    if (!snapshot) return 0;
    return Object.values(snapshot.victims || {}).filter((victim: any) =>
      [
        'RESCUED',
        'ASSISTED',
        'EVACUATED',
        'TREATED',
        'STABILIZED',
        'MEDICALLY_STABILIZED',
        'RESOLVED',
        'SAFE',
      ].includes(String(victim.status || '').toUpperCase()),
    ).length;
  }, [snapshot]);

  const droneRole = (drone: any): string => {
    // The backend DroneEntity schema exposes capabilities rather than a
    // dedicated drone_type field. Resolve the visual role from every reliable
    // identifier so the radar never paints response drones as scouts.
    const rawType = String(
      drone.drone_type || drone.type || drone.role || drone.drone_role || ''
    ).toUpperCase().replace(/[-_]/g, ' ');

    const capabilities = Array.isArray(drone.capabilities)
      ? drone.capabilities.map((value: unknown) => String(value).toUpperCase().replace(/[-_]/g, ' '))
      : [];

    const callsign = String(drone.callsign || '').toUpperCase();
    const droneId = String(drone.id || '').toUpperCase();
    const modelName = String(drone.model_name || '').toUpperCase();

    // Resolve role deterministically. Fleet prefixes are authoritative here:
    // S = SCOUT, M = MEDICAL, H = HEAVY LIFT, R = RESCUE.
    // This prevents a scout from being misclassified as RESCUE by a loose
    // substring check such as `includes("R ")`.
    const hasCapability = (name: string) =>
      capabilities.some((cap: string) => cap === name || cap.includes(name));

    if (
      hasCapability('HEAVY LIFT') || hasCapability('HEAVYLIFT') ||
      rawType.includes('HEAVY LIFT') || rawType.includes('HEAVYLIFT') ||
      callsign.includes('HEAVY') || droneId.includes('HEAVY') || modelName.includes('HEAVY') ||
      /^DRONE[-_ ]?H(?:\\d|[-_ ])/.test(droneId) || /^H(?:\\d|[-_ ])/.test(callsign)
    ) return 'HEAVY LIFT';

    if (
      hasCapability('MEDICAL') || rawType.includes('MEDICAL') ||
      callsign.includes('MEDICAL') || droneId.includes('MEDICAL') || modelName.includes('MEDICAL') ||
      /^DRONE[-_ ]?M(?:\\d|[-_ ])/.test(droneId) || /^M(?:\\d|[-_ ])/.test(callsign)
    ) return 'MEDICAL';

    if (
      hasCapability('RESCUE') || rawType.includes('RESCUE') ||
      callsign.includes('RESCUE') || droneId.includes('RESCUE') || modelName.includes('RESCUE') ||
      /^DRONE[-_ ]?R(?:\\d|[-_ ])/.test(droneId) || /^R(?:\\d|[-_ ])/.test(callsign)
    ) return 'RESCUE';

    if (
      hasCapability('SCOUT') || rawType.includes('SCOUT') ||
      callsign.includes('SCOUT') || droneId.includes('SCOUT') || modelName.includes('SCOUT') ||
      /^DRONE[-_ ]?S(?:\\d|[-_ ])/.test(droneId) || /^S(?:\\d|[-_ ])/.test(callsign)
    ) return 'SCOUT';

    if (hasCapability('INSPECTION') || rawType.includes('INSPECTION') || rawType.includes('INSPECT')) {
      return 'INSPECTION';
    }

    // Unknown drones remain cyan rather than being incorrectly painted red.
    return 'SCOUT';
  };

  const roleColor = (role: string): string => {
    switch (role) {
      case 'MEDICAL': return '#22c55e';
      case 'HEAVY LIFT': return '#f59e0b';
      case 'RESCUE': return '#ef4444';
      case 'INSPECTION': return '#a78bfa';
      default: return '#22d3ee';
    }
  };

  const isStandby = (drone: any): boolean => {
    const status = String(drone.status || drone.backend_status || '').toUpperCase();
    const mission = String(drone.mission || '').toUpperCase();
    return (
      status === 'STANDBY' ||
      status === 'IDLE' ||
      status === 'AVAILABLE' ||
      mission === 'STANDBY' ||
      mission === 'IDLE'
    );
  };

  const isActiveResponse = (drone: any): boolean => {
    const role = droneRole(drone);
    return role !== 'SCOUT' && !isStandby(drone);
  };

  const resetView = () => setZoom(1);

  return (
    <div
      className="relative w-full h-[620px] bg-[#070c13] rounded-xl border border-cyan-900/40 overflow-hidden shadow-2xl select-none"
      style={{ minHeight: 620 }}
    >
      {/* Compact toolbar */}
      <div className="absolute top-3 left-3 right-3 z-30 flex items-center justify-between gap-3">
        <div className="flex items-center gap-1.5 bg-[#0c1421]/95 backdrop-blur-md px-3 py-2 rounded-lg border border-cyan-800/40 text-xs text-slate-300 shadow-lg">
          <span className="text-cyan-400 font-bold uppercase tracking-wider text-[11px] mr-1 flex items-center gap-1">
            <Crosshair className="w-3.5 h-3.5 animate-pulse" />
            Tactical Radar
          </span>
          <button
            onClick={() => setZoom((v) => Math.min(1.35, +(v + 0.1).toFixed(2)))}
            className="p-1.5 hover:bg-cyan-900/40 rounded transition"
            title="Zoom in"
          >
            <ZoomIn className="w-4 h-4 text-cyan-300" />
          </button>
          <button
            onClick={() => setZoom((v) => Math.max(0.85, +(v - 0.1).toFixed(2)))}
            className="p-1.5 hover:bg-cyan-900/40 rounded transition"
            title="Zoom out"
          >
            <ZoomOut className="w-4 h-4 text-cyan-300" />
          </button>
          <button
            onClick={resetView}
            className="p-1.5 hover:bg-cyan-900/40 rounded transition"
            title="Fit entire map"
          >
            <RotateCcw className="w-4 h-4 text-slate-400" />
          </button>
          <span className="ml-1 text-[10px] text-slate-500 font-mono">
            FIT {(zoom * 100).toFixed(0)}%
          </span>
        </div>

        <div className="flex flex-wrap justify-end items-center gap-1.5 bg-[#0c1421]/95 backdrop-blur-md px-2.5 py-2 rounded-lg border border-cyan-800/40 text-[10px] shadow-lg">
          <span className="text-slate-500 mr-1 flex items-center gap-1">
            <Eye className="w-3.5 h-3.5" /> Layers
          </span>
          <button
            onClick={() => setShowDrones((v) => !v)}
            className={`px-2 py-1 rounded font-mono ${showDrones ? 'bg-cyan-950 text-cyan-300 border border-cyan-700/60' : 'text-slate-500'}`}
          >
            Drones ({drones.length})
          </button>
          <button
            onClick={() => setShowVictims((v) => !v)}
            className={`px-2 py-1 rounded font-mono ${showVictims ? 'bg-red-950 text-red-300 border border-red-700/60' : 'text-slate-500'}`}
          >
            Victims ({activeVictimCount})
          </button>
          <button
            onClick={() => setShowHazards((v) => !v)}
            className={`px-2 py-1 rounded font-mono ${showHazards ? 'bg-orange-950 text-orange-300 border border-orange-700/60' : 'text-slate-500'}`}
          >
            Hazards ({snapshot ? Object.values(snapshot.hazards || {}).length : 0})
          </button>
          <button
            onClick={() => setShowRoads((v) => !v)}
            className={`px-2 py-1 rounded font-mono ${showRoads ? 'bg-slate-800 text-slate-200 border border-slate-600' : 'text-slate-500'}`}
          >
            Roads
          </button>
          <button
            onClick={() => setShowBuildings((v) => !v)}
            className={`px-2 py-1 rounded font-mono ${showBuildings ? 'bg-slate-800 text-slate-200 border border-slate-600' : 'text-slate-500'}`}
          >
            Buildings
          </button>
        </div>
      </div>

      {/* Live Digital Twin frame remains the visual background. */}
      {snapshot?.simulation_frame_base64 && (
        <div className="absolute inset-0 z-0 pointer-events-none bg-black">
          <img
            src={`data:${snapshot.simulation_frame_mime_type || 'image/jpeg'};base64,${snapshot.simulation_frame_base64}`}
            alt="Live Godot Digital Twin simulation"
            className="w-full h-full object-cover opacity-55"
          />
          <div className="absolute inset-0 bg-[#07101b]/35" />
        </div>
      )}

      {/* Responsive tactical canvas. SVG viewBox fits the full world automatically. */}
      <div className="absolute inset-0 overflow-hidden">
        <svg
          viewBox={`0 0 ${mapWidth} ${mapHeight}`}
          preserveAspectRatio="xMidYMid meet"
          className="absolute inset-0 w-full h-full"
          style={{ transform: `scale(${zoom})`, transformOrigin: 'center center', transition: 'transform 160ms ease-out' }}
        >
          <defs>
            <pattern id="rq-grid-clear" width="60" height="60" patternUnits="userSpaceOnUse">
              <path d="M 60 0 L 0 0 0 60" fill="none" stroke="#22364b" strokeWidth="1" opacity="0.32" />
            </pattern>
            <radialGradient id="rq-radar-glow">
              <stop offset="0%" stopColor="#06b6d4" stopOpacity="0.08" />
              <stop offset="100%" stopColor="#06b6d4" stopOpacity="0" />
            </radialGradient>
            <radialGradient id="rq-fire-glow">
              <stop offset="0%" stopColor="#ef4444" stopOpacity="0.42" />
              <stop offset="55%" stopColor="#f97316" stopOpacity="0.16" />
              <stop offset="100%" stopColor="#ef4444" stopOpacity="0" />
            </radialGradient>
          </defs>

          <rect width={mapWidth} height={mapHeight} fill={snapshot?.simulation_frame_base64 ? 'transparent' : '#070c13'} />
          <rect width={mapWidth} height={mapHeight} fill="url(#rq-grid-clear)" />

          {/* Only two range rings: less visual noise than the previous three. */}
          <circle cx={mapWidth / 2} cy={mapHeight / 2} r="155" fill="none" stroke="#17314d" strokeWidth="1" strokeDasharray="4 5" />
          <circle cx={mapWidth / 2} cy={mapHeight / 2} r="300" fill="none" stroke="#17314d" strokeWidth="1" strokeDasharray="5 7" />
          <circle cx={mapWidth / 2} cy={mapHeight / 2} r="300" fill="url(#rq-radar-glow)" />

          <line x1={mapWidth / 2} y1="0" x2={mapWidth / 2} y2={mapHeight} stroke="#17314d" strokeWidth="1" strokeDasharray="3 7" opacity="0.65" />
          <line x1="0" y1={mapHeight / 2} x2={mapWidth} y2={mapHeight / 2} stroke="#17314d" strokeWidth="1" strokeDasharray="3 7" opacity="0.65" />

          {/* Buildings */}
          {showBuildings && snapshot &&
            Object.values(snapshot.buildings || {}).map((b: any) => {
              const bx = toSvgX(Number(b.center?.x || 0) - Number(b.size_x || 0) / 2);
              const by = toSvgY(Number(b.center?.z || 0) - Number(b.size_z || 0) / 2);
              const bw = (Number(b.size_x || 0) / worldExtent) * mapWidth;
              const bh = (Number(b.size_z || 0) / worldExtent) * mapHeight;

              const collapsed = String(b.damage_level || '').toUpperCase() === 'COLLAPSED';
              const cracked = String(b.damage_level || '').toUpperCase() === 'STRUCTURAL_CRACK';

              return (
                <g key={b.id} className="cursor-pointer" onClick={() => onSelectEntity(b, 'BUILDING')}>
                  <rect
                    x={bx}
                    y={by}
                    width={Math.max(3, bw)}
                    height={Math.max(3, bh)}
                    fill={collapsed ? '#35151a' : cracked ? '#332911' : '#111d2b'}
                    stroke={collapsed ? '#ef4444' : cracked ? '#eab308' : '#29435f'}
                    strokeWidth={collapsed ? 1.8 : 1.1}
                    rx="3"
                  />
                  {bw > 35 && bh > 22 && (
                    <text
                      x={bx + bw / 2}
                      y={by + bh / 2 + 3}
                      fill="#647b90"
                      fontSize="9"
                      textAnchor="middle"
                      className="font-mono pointer-events-none"
                    >
                      {String(b.name || b.id || '').split(' ')[0]}
                    </text>
                  )}
                </g>
              );
            })}

          {/* Roads */}
          {showRoads && snapshot &&
            roadEdges.map((edge: any) => {
              const n1: any = roadNodes[edge.from_node];
              const n2: any = roadNodes[edge.to_node];
              if (!n1 || !n2) return null;

              const x1 = toSvgX(n1.position.x);
              const y1 = toSvgY(n1.position.z);
              const x2 = toSvgX(n2.position.x);
              const y2 = toSvgY(n2.position.z);
              const blocked = Boolean(edge.is_blocked);

              return (
                <line
                  key={edge.id}
                  x1={x1}
                  y1={y1}
                  x2={x2}
                  y2={y2}
                  stroke={blocked ? '#ef4444' : '#263d54'}
                  strokeWidth={blocked ? 5 : 2.5}
                  strokeLinecap="round"
                  strokeDasharray={blocked ? '5 4' : 'none'}
                  opacity={0.72}
                />
              );
            })}

          {/* Hazards */}
          {showHazards && snapshot &&
            Object.values(snapshot.hazards || {}).map((hz: any) => {
              if (!hz.active) return null;
              const hx = toSvgX(hz.center.x);
              const hy = toSvgY(hz.center.z);
              const hr = Math.max(8, (Number(hz.radius_m || 0) / worldExtent) * mapWidth);

              return (
                <g key={hz.id} className="cursor-pointer" onClick={() => onSelectEntity(hz, 'HAZARD')}>
                  <circle cx={hx} cy={hy} r={hr} fill="url(#rq-fire-glow)" opacity="0.75" />
                  <circle cx={hx} cy={hy} r={hr} fill="none" stroke="#f97316" strokeWidth="1.2" strokeDasharray="5 4" />
                  <circle cx={hx} cy={hy} r="4" fill="#ef4444" />
                  <text x={hx} y={hy - hr - 5} fill="#fb923c" fontSize="8" textAnchor="middle" className="font-mono font-bold">
                    {String(hz.type || 'HAZARD').replace(/_/g, ' ')}
                  </text>
                </g>
              );
            })}

          {/* Facilities */}
          {snapshot &&
            Object.values(snapshot.facilities || {}).map((fac: any) => {
              const fx = toSvgX(fac.location.x);
              const fy = toSvgY(fac.location.z);
              const isBase = fac.type === 'COMMAND_HQ';

              return (
                <g key={fac.id} className="cursor-pointer" onClick={() => onSelectEntity(fac, 'FACILITY')}>
                  <rect
                    x={fx - 13}
                    y={fy - 13}
                    width="26"
                    height="26"
                    fill={isBase ? '#075985' : '#047857'}
                    stroke="#67e8f9"
                    strokeWidth="1.4"
                    rx="6"
                  />
                  <text x={fx} y={fy + 4} fill="#fff" fontSize="9" textAnchor="middle" className="font-bold">
                    {isBase ? 'HQ' : 'MED'}
                  </text>
                </g>
              );
            })}

          {/* Active victims only. Completed victims deliberately do not render. */}
          {showVictims && snapshot &&
            victims.map((vic: any) => {
              const vx = toSvgX(vic.location.x);
              const vy = toSvgY(vic.location.z);
              const priority = String(vic.priority_class || '').toUpperCase();

              const color =
                priority === 'CRITICAL' ? '#ef4444' :
                priority === 'HIGH' ? '#f59e0b' :
                priority === 'MEDIUM' ? '#06b6d4' :
                '#94a3b8';

              const critical = priority === 'CRITICAL';
              const assigned = String(vic.assigned_drone_id || '').trim();

              return (
                <g key={vic.id} className="cursor-pointer" onClick={() => onSelectEntity(vic, 'VICTIM')}>
                  {critical && (
                    <circle cx={vx} cy={vy} r="13" fill="none" stroke={color} strokeWidth="1.4" opacity="0.55" />
                  )}
                  <circle cx={vx} cy={vy} r="7" fill="#08101d" stroke={color} strokeWidth="2" />
                  <circle cx={vx} cy={vy} r="3" fill={color} />
                  <text x={vx} y={vy - 11} fill={color} fontSize="8.5" textAnchor="middle" className="font-mono font-bold">
                    {vic.id}
                  </text>
                  {assigned && (
                    <text x={vx} y={vy + 16} fill="#7dd3fc" fontSize="6.8" textAnchor="middle" className="font-mono">
                      {assigned}
                    </text>
                  )}
                </g>
              );
            })}

          {/* Drone fleet. Standby units are intentionally compact; active response units are prominent. */}
          {showDrones && drones.map((drone: any) => {
            const dx = toSvgX(drone.position?.x);
            const dy = toSvgY(drone.position?.z);
            const role = droneRole(drone);
            const color = roleColor(role);
            const standby = isStandby(drone);
            const activeResponse = isActiveResponse(drone);
            const selected = selectedEntity && selectedEntity.id === drone.id;

            const size = role === 'SCOUT' ? 5.2 : 6.5;

            return (
              <g
                key={drone.id}
                className="cursor-pointer"
                onClick={() => onSelectEntity(drone, 'DRONE')}
              >
                {selected && (
                  <circle cx={dx} cy={dy} r="17" fill="none" stroke="#ffffff" strokeWidth="1.5" strokeDasharray="4 3" />
                )}

                {activeResponse && (
                  <circle cx={dx} cy={dy} r="13" fill={color} opacity="0.12" stroke={color} strokeWidth="1" />
                )}

                {/* Compact four-arm drone symbol. Role color is the first visual cue. */}
                <g transform={`translate(${dx} ${dy}) rotate(${Number(drone.heading || 0)})`}>
                  <line x1={-size} y1={-size} x2={size} y2={size} stroke={color} strokeWidth={activeResponse ? 2.2 : 1.6} />
                  <line x1={-size} y1={size} x2={size} y2={-size} stroke={color} strokeWidth={activeResponse ? 2.2 : 1.6} />
                  <circle cx={-size} cy={-size} r={2.2} fill={color} />
                  <circle cx={size} cy={size} r={2.2} fill={color} />
                  <circle cx={-size} cy={size} r={2.2} fill={color} />
                  <circle cx={size} cy={-size} r={2.2} fill={color} />
                  <circle cx="0" cy="0" r={activeResponse ? 4.1 : 3.2} fill="#07101a" stroke={color} strokeWidth="1.5" />
                  <polygon points="0,-9 -2.5,-4 2.5,-4" fill={color} />
                </g>

                {/* Labels only when useful. This removes the previous 31-label pile-up. */}
                {(!standby || selected) && (
                  <g transform={`translate(${dx} ${dy - 14})`}>
                    <rect
                      x="-30"
                      y="-7"
                      width="60"
                      height="12"
                      fill="#07101a"
                      stroke={color}
                      strokeWidth="0.9"
                      rx="2"
                    />
                    <text x="0" y="1.5" fill={color} fontSize="7.2" textAnchor="middle" className="font-mono font-bold">
                      {drone.id} · {role}
                    </text>
                  </g>
                )}

                {activeResponse && (
                  <circle cx={dx} cy={dy} r="2" fill="#fff" opacity="0.9" />
                )}
              </g>
            );
          })}
        </svg>
      </div>

      {/* Orientation / counts */}
      <div className="absolute left-3 bottom-3 z-30 flex items-center gap-2 bg-[#0c1421]/95 backdrop-blur-md px-3 py-2 rounded-lg border border-cyan-800/40 text-[9px] font-mono shadow-lg">
        <span className="text-cyan-300">N ↑</span>
        <span className="text-slate-600">|</span>
        <span className="text-slate-400">WORLD ±360m</span>
        <span className="text-slate-600">|</span>
        <span className="text-slate-400">{activeVictimCount} ACTIVE</span>
        {completedVictimCount > 0 && (
          <>
            <span className="text-slate-600">|</span>
            <span className="text-emerald-400">{completedVictimCount} RESOLVED / HISTORY</span>
          </>
        )}
      </div>

      {/* Four-role legend */}
      {showLegend && (
        <div className="absolute right-3 bottom-3 z-30 bg-[#0c1421]/95 backdrop-blur-md px-3 py-2 rounded-lg border border-cyan-800/40 text-[9px] font-mono shadow-lg">
          <div className="flex items-center gap-3">
            <span className="flex items-center gap-1.5">
              <i className="w-2.5 h-2.5 rounded-full" style={{ background: roleColor('SCOUT') }} />
              <span className="text-cyan-300">SCOUT</span>
            </span>
            <span className="flex items-center gap-1.5">
              <i className="w-2.5 h-2.5 rounded-full" style={{ background: roleColor('MEDICAL') }} />
              <span className="text-emerald-300">MEDICAL</span>
            </span>
            <span className="flex items-center gap-1.5">
              <i className="w-2.5 h-2.5 rounded-full" style={{ background: roleColor('HEAVY LIFT') }} />
              <span className="text-amber-300">HEAVY LIFT</span>
            </span>
            <span className="flex items-center gap-1.5">
              <i className="w-2.5 h-2.5 rounded-full" style={{ background: roleColor('RESCUE') }} />
              <span className="text-red-300">RESCUE</span>
            </span>
          </div>
        </div>
      )}

      {/* Small state indicator */}
      {!snapshot && (
        <div className="absolute inset-0 z-40 flex items-center justify-center bg-[#070c13]/80">
          <div className="text-center">
            <Navigation className="mx-auto mb-2 text-cyan-400" size={24} />
            <div className="text-xs font-mono text-slate-400">Waiting for authoritative Digital Twin state…</div>
          </div>
        </div>
      )}
    </div>
  );
};
