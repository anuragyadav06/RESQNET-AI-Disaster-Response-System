import React, { useState, useRef, useMemo } from 'react';
import {
  WorldStateSnapshot,
  DroneEntity,
  Victim,
  HazardZone,
  Building,
  RoadEdge,
  RoadNode,
} from '../types';
import {
  Navigation,
  AlertTriangle,
  Flame,
  Shield,
  Hospital,
  ZoomIn,
  ZoomOut,
  RotateCcw,
  Eye,
  Crosshair,
  Radio,
  Zap,
} from 'lucide-react';
import { api } from '../services/api';

interface TacticalMapProps {
  snapshot: WorldStateSnapshot | null;
  selectedEntity: any | null;
  onSelectEntity: (entity: any, type: string) => void;
}

export const TacticalMap: React.FC<TacticalMapProps> = ({
  snapshot,
  selectedEntity,
  onSelectEntity,
}) => {
  // Pan and Zoom state
  const [zoom, setZoom] = useState<number>(1.35);
  const [pan, setPan] = useState<{ x: number; y: number }>({ x: 0, y: 0 });
  const [isDragging, setIsDragging] = useState<boolean>(false);
  const [dragStart, setDragStart] = useState<{ x: number; y: number }>({ x: 0, y: 0 });

  // Filter toggles
  const [showDrones, setShowDrones] = useState<boolean>(true);
  const [showVictims, setShowVictims] = useState<boolean>(true);
  const [showHazards, setShowHazards] = useState<boolean>(true);
  const [showRoads, setShowRoads] = useState<boolean>(true);
  const [showBuildings, setShowBuildings] = useState<boolean>(true);
  const [showPaths, setShowPaths] = useState<boolean>(true);

  const containerRef = useRef<HTMLDivElement | null>(null);

  // Map coordinate transformation (-180m to +180m world coords -> SVG viewport 800x800)
  const mapWidth = 800;
  const mapHeight = 800;
  const worldExtent = 380; // Total world range meters

  const toSvgX = (x: number) => {
    const norm = (x + worldExtent / 2) / worldExtent;
    return norm * mapWidth;
  };

  const toSvgY = (z: number) => {
    // Z in world space is North-South, map Y is inverted (top is North)
    const norm = (z + worldExtent / 2) / worldExtent;
    return norm * mapHeight;
  };

  // Mouse drag handling
  const handleMouseDown = (e: React.MouseEvent) => {
    if (e.button === 0) {
      setIsDragging(true);
      setDragStart({ x: e.clientX - pan.x, y: e.clientY - pan.y });
    }
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    if (isDragging) {
      setPan({
        x: e.clientX - dragStart.x,
        y: e.clientY - dragStart.y,
      });
    }
  };

  const handleMouseUp = () => setIsDragging(false);

  const handleZoom = (delta: number) => {
    setZoom((prev) => Math.max(0.6, Math.min(3.5, prev + delta)));
  };

  const resetView = () => {
    setZoom(1.35);
    setPan({ x: 0, y: 0 });
  };

  // Road edges map
  const roadEdges = useMemo(() => {
    if (!snapshot) return [];
    return Object.values(snapshot.road_edges);
  }, [snapshot]);

  // Road nodes map
  const roadNodes = useMemo(() => {
    if (!snapshot) return {};
    return snapshot.road_nodes;
  }, [snapshot]);

  return (
    <div className="relative w-full h-[620px] bg-[#090d14] rounded-xl border border-cyan-900/40 overflow-hidden shadow-2xl select-none">
      {/* Map Control Toolbar */}
      <div className="absolute top-3 left-3 z-30 flex items-center gap-1.5 bg-[#0e1626]/90 backdrop-blur-md px-3 py-1.5 rounded-lg border border-cyan-800/40 text-xs text-slate-300">
        <span className="text-cyan-400 font-bold uppercase tracking-wider text-[11px] mr-2 flex items-center gap-1">
          <Crosshair className="w-3.5 h-3.5 text-cyan-400 animate-pulse" /> Tactical Radar
        </span>
        <button
          onClick={() => handleZoom(0.2)}
          className="p-1.5 hover:bg-cyan-900/40 rounded transition"
          title="Zoom In"
        >
          <ZoomIn className="w-4 h-4 text-cyan-300" />
        </button>
        <button
          onClick={() => handleZoom(-0.2)}
          className="p-1.5 hover:bg-cyan-900/40 rounded transition"
          title="Zoom Out"
        >
          <ZoomOut className="w-4 h-4 text-cyan-300" />
        </button>
        <button
          onClick={resetView}
          className="p-1.5 hover:bg-cyan-900/40 rounded transition"
          title="Reset View"
        >
          <RotateCcw className="w-4 h-4 text-slate-400" />
        </button>
        <div className="h-4 w-px bg-slate-700 mx-1" />
        <span className="text-[11px] text-slate-400">Scale: {(zoom * 100).toFixed(0)}%</span>
      </div>

      {/* Layer Filter Toggles */}
      <div className="absolute top-3 right-3 z-30 flex items-center gap-2 bg-[#0e1626]/90 backdrop-blur-md px-3 py-1.5 rounded-lg border border-cyan-800/40 text-[11px] text-slate-300">
        <span className="text-slate-400 mr-1 flex items-center gap-1">
          <Eye className="w-3.5 h-3.5 text-slate-400" /> Layers:
        </span>
        <button
          onClick={() => setShowDrones(!showDrones)}
          className={`px-2 py-0.5 rounded font-mono ${
            showDrones ? 'bg-cyan-950 text-cyan-300 border border-cyan-700/60' : 'text-slate-500 hover:text-slate-400'
          }`}
        >
          Drones ({snapshot ? Object.keys(snapshot.drones).length : 0})
        </button>
        <button
          onClick={() => setShowVictims(!showVictims)}
          className={`px-2 py-0.5 rounded font-mono ${
            showVictims ? 'bg-red-950 text-red-300 border border-red-700/60' : 'text-slate-500 hover:text-slate-400'
          }`}
        >
          Victims ({snapshot ? Object.keys(snapshot.victims).length : 0})
        </button>
        <button
          onClick={() => setShowHazards(!showHazards)}
          className={`px-2 py-0.5 rounded font-mono ${
            showHazards ? 'bg-orange-950 text-orange-300 border border-orange-700/60' : 'text-slate-500 hover:text-slate-400'
          }`}
        >
          Hazards ({snapshot ? Object.keys(snapshot.hazards).length : 0})
        </button>
        <button
          onClick={() => setShowRoads(!showRoads)}
          className={`px-2 py-0.5 rounded font-mono ${
            showRoads ? 'bg-slate-800 text-slate-200 border border-slate-600' : 'text-slate-500 hover:text-slate-400'
          }`}
        >
          Roads
        </button>
        <button
          onClick={() => setShowBuildings(!showBuildings)}
          className={`px-2 py-0.5 rounded font-mono ${
            showBuildings ? 'bg-slate-800 text-slate-200 border border-slate-600' : 'text-slate-500 hover:text-slate-400'
          }`}
        >
          Buildings
        </button>
      </div>

      {/* Main Tactical SVG Canvas */}
      <div
        ref={containerRef}
        className="w-full h-full cursor-grab active:cursor-grabbing overflow-hidden flex items-center justify-center"
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUp}
        onMouseLeave={handleMouseUp}
      >
        <svg
          viewBox={`0 0 ${mapWidth} ${mapHeight}`}
          className="w-full h-full pointer-events-auto"
          style={{
            transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
            transformOrigin: 'center center',
            transition: isDragging ? 'none' : 'transform 0.15s ease-out',
          }}
        >
          <defs>
            {/* Grid background pattern */}
            <pattern id="grid-pattern" width="40" height="40" patternUnits="userSpaceOnUse">
              <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#132338" strokeWidth="0.8" />
            </pattern>
            {/* Blocked road crosshatch pattern */}
            <pattern id="hazard-crosshatch" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
              <rect width="4" height="8" fill="#ef4444" opacity="0.75" />
            </pattern>
            {/* Radial glow filters */}
            <radialGradient id="fire-glow" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="#f97316" stopOpacity="0.85" />
              <stop offset="60%" stopColor="#ef4444" stopOpacity="0.45" />
              <stop offset="100%" stopColor="#ef4444" stopOpacity="0" />
            </radialGradient>
            <radialGradient id="radar-sweep" cx="50%" cy="50%" r="50%">
              <stop offset="0%" stopColor="#06b6d4" stopOpacity="0.08" />
              <stop offset="100%" stopColor="#06b6d4" stopOpacity="0.0" />
            </radialGradient>
          </defs>

          {/* 1. Radar Grid Background */}
          <rect width={mapWidth} height={mapHeight} fill="#0a0e17" />
          <rect width={mapWidth} height={mapHeight} fill="url(#grid-pattern)" />

          {/* Radar Circles */}
          <circle cx={mapWidth / 2} cy={mapHeight / 2} r="120" fill="none" stroke="#17314d" strokeWidth="1" strokeDasharray="3 3" />
          <circle cx={mapWidth / 2} cy={mapHeight / 2} r="240" fill="none" stroke="#17314d" strokeWidth="1" strokeDasharray="4 4" />
          <circle cx={mapWidth / 2} cy={mapHeight / 2} r="360" fill="none" stroke="#17314d" strokeWidth="1" strokeDasharray="6 6" />
          <circle cx={mapWidth / 2} cy={mapHeight / 2} r="360" fill="url(#radar-sweep)" />

          {/* Crosshair Axes */}
          <line x1={mapWidth / 2} y1="0" x2={mapWidth / 2} y2={mapHeight} stroke="#17314d" strokeWidth="1" strokeDasharray="2 4" />
          <line x1="0" y1={mapHeight / 2} x2={mapWidth} y2={mapHeight / 2} stroke="#17314d" strokeWidth="1" strokeDasharray="2 4" />

          {/* 2. District Buildings Layer */}
          {showBuildings && snapshot &&
            Object.values(snapshot.buildings).map((b) => {
              const bx = toSvgX(b.center.x - b.size_x / 2);
              const by = toSvgY(b.center.z - b.size_z / 2);
              const bw = (b.size_x / worldExtent) * mapWidth;
              const bh = (b.size_z / worldExtent) * mapHeight;

              let fillColor = '#131e2e';
              let strokeColor = '#1e3857';
              if (b.damage_level === 'COLLAPSED') {
                fillColor = '#3b1212';
                strokeColor = '#ef4444';
              } else if (b.damage_level === 'STRUCTURAL_CRACK') {
                fillColor = '#3b2f12';
                strokeColor = '#eab308';
              }

              return (
                <g key={b.id} className="cursor-pointer" onClick={() => onSelectEntity(b, 'BUILDING')}>
                  <rect
                    x={bx}
                    y={by}
                    width={bw}
                    height={bh}
                    fill={fillColor}
                    stroke={strokeColor}
                    strokeWidth="1.5"
                    rx="3"
                    className="hover:opacity-80 transition"
                  />
                  <text
                    x={bx + bw / 2}
                    y={by + bh / 2 + 3}
                    fill="#94a3b8"
                    fontSize="7.5"
                    textAnchor="middle"
                    className="font-mono font-bold pointer-events-none"
                  >
                    {b.name.split(' ')[0]}
                  </text>
                  {b.damage_level !== 'INTACT' && (
                    <circle cx={bx + bw - 4} cy={by + 4} r="3" fill={strokeColor} />
                  )}
                </g>
              );
            })}

          {/* 3. Road Network Layer */}
          {showRoads && snapshot &&
            roadEdges.map((edge) => {
              const n1 = roadNodes[edge.from_node];
              const n2 = roadNodes[edge.to_node];
              if (!n1 || !n2) return null;

              const x1 = toSvgX(n1.position.x);
              const y1 = toSvgY(n1.position.z);
              const x2 = toSvgX(n2.position.x);
              const y2 = toSvgY(n2.position.z);

              return (
                <g key={edge.id} className="cursor-pointer" onClick={() => onSelectEntity(edge, 'ROAD')}>
                  {/* Road Base */}
                  <line
                    x1={x1}
                    y1={y1}
                    x2={x2}
                    y2={y2}
                    stroke={edge.is_blocked ? '#ef4444' : '#1e324a'}
                    strokeWidth={edge.is_blocked ? 6 : 4}
                    strokeLinecap="round"
                    strokeDasharray={edge.is_blocked ? '4 3' : 'none'}
                    className="hover:stroke-cyan-500 transition"
                  />
                  {edge.is_blocked && (
                    <line
                      x1={x1}
                      y1={y1}
                      x2={x2}
                      y2={y2}
                      stroke="url(#hazard-crosshatch)"
                      strokeWidth="6"
                    />
                  )}
                </g>
              );
            })}

          {/* Road Intersections */}
          {showRoads && snapshot &&
            Object.values(roadNodes).map((node) => (
              <circle
                key={node.id}
                cx={toSvgX(node.position.x)}
                cy={toSvgY(node.position.z)}
                r="3"
                fill="#0f1b2b"
                stroke="#334155"
                strokeWidth="1"
              />
            ))}

          {/* 4. Active Hazard Zones (Fires, Gas, Collapse) */}
          {showHazards && snapshot &&
            Object.values(snapshot.hazards).map((hz) => {
              if (!hz.active) return null;
              const hx = toSvgX(hz.center.x);
              const hy = toSvgY(hz.center.z);
              const hr = (hz.radius_m / worldExtent) * mapWidth;

              return (
                <g key={hz.id} className="cursor-pointer" onClick={() => onSelectEntity(hz, 'HAZARD')}>
                  <circle
                    cx={hx}
                    cy={hy}
                    r={hr}
                    fill="url(#fire-glow)"
                    className="animate-pulse"
                  />
                  <circle
                    cx={hx}
                    cy={hy}
                    r={hr}
                    fill="none"
                    stroke="#f97316"
                    strokeWidth="1.5"
                    strokeDasharray="4 3"
                  />
                  <circle cx={hx} cy={hy} r="4" fill="#ef4444" />
                  <text
                    x={hx}
                    y={hy - hr - 4}
                    fill="#f97316"
                    fontSize="9"
                    textAnchor="middle"
                    className="font-bold uppercase tracking-wider font-mono"
                  >
                    🔥 {hz.type} ({hz.radius_m}m)
                  </text>
                </g>
              );
            })}

          {/* 5. Emergency Facilities */}
          {snapshot &&
            Object.values(snapshot.facilities).map((fac) => {
              const fx = toSvgX(fac.location.x);
              const fy = toSvgY(fac.location.z);
              const isBase = fac.type === 'COMMAND_HQ';

              return (
                <g key={fac.id} className="cursor-pointer" onClick={() => onSelectEntity(fac, 'FACILITY')}>
                  <rect
                    x={fx - 14}
                    y={fy - 14}
                    width="28"
                    height="28"
                    fill={isBase ? '#0369a1' : '#047857'}
                    stroke="#38bdf8"
                    strokeWidth="1.5"
                    rx="6"
                  />
                  <text
                    x={fx}
                    y={fy + 4}
                    fill="#ffffff"
                    fontSize="10"
                    textAnchor="middle"
                    className="font-bold pointer-events-none"
                  >
                    {isBase ? 'HQ' : 'MED'}
                  </text>
                  <text
                    x={fx}
                    y={fy + 24}
                    fill="#38bdf8"
                    fontSize="8"
                    textAnchor="middle"
                    className="font-mono font-bold"
                  >
                    {fac.id}
                  </text>
                </g>
              );
            })}

          {/* 6. Active Mission Flight Paths */}
          {showPaths && snapshot &&
            Object.values(snapshot.drones).map((drone) => {
              const missionId = drone.current_mission_id;
              if (!missionId) return null;
              // Find waypoints
              const mission = snapshot.drones[drone.id];
              return null;
            })}

          {/* 7. Victims Layer */}
          {showVictims && snapshot &&
            Object.values(snapshot.victims).map((vic) => {
              const vx = toSvgX(vic.location.x);
              const vy = toSvgY(vic.location.z);

              let color = '#94a3b8';
              let pulseClass = '';
              if (vic.priority_class === 'CRITICAL') {
                color = '#ef4444';
                pulseClass = 'animate-ping';
              } else if (vic.priority_class === 'HIGH') {
                color = '#f59e0b';
                pulseClass = 'animate-pulse';
              } else if (vic.priority_class === 'MEDIUM') {
                color = '#06b6d4';
              }

              if (vic.status === 'ASSISTED') {
                color = '#10b981';
                pulseClass = '';
              }

              return (
                <g key={vic.id} className="cursor-pointer" onClick={() => onSelectEntity(vic, 'VICTIM')}>
                  {/* Ping Ring for Critical */}
                  {vic.priority_class === 'CRITICAL' && vic.status !== 'ASSISTED' && (
                    <circle cx={vx} cy={vy} r="16" fill="none" stroke="#ef4444" strokeWidth="1.5" opacity="0.6" className="animate-ping" />
                  )}
                  {/* Outer Beacon */}
                  <circle cx={vx} cy={vy} r="9" fill="#0b111e" stroke={color} strokeWidth="2" />
                  <circle cx={vx} cy={vy} r="4" fill={color} />
                  {/* Label */}
                  <text
                    x={vx}
                    y={vy - 12}
                    fill={color}
                    fontSize="8.5"
                    textAnchor="middle"
                    className="font-mono font-bold"
                  >
                    {vic.id} {vic.priority_class === 'CRITICAL' ? '⚠️' : ''}
                  </text>
                  {vic.assigned_drone_id && (
                    <text
                      x={vx}
                      y={vy + 18}
                      fill="#38bdf8"
                      fontSize="7"
                      textAnchor="middle"
                      className="font-mono"
                    >
                      ← {vic.assigned_drone_id}
                    </text>
                  )}
                </g>
              );
            })}

          {/* 8. Drone Fleet Layer */}
          {showDrones && snapshot &&
            Object.values(snapshot.drones).map((drone) => {
              const dx = toSvgX(drone.position.x);
              const dy = toSvgY(drone.position.z);
              const isSelected = selectedEntity && selectedEntity.id === drone.id;

              return (
                <g
                  key={drone.id}
                  className="cursor-pointer"
                  onClick={() => onSelectEntity(drone, 'DRONE')}
                >
                  {/* Selection Ring */}
                  {isSelected && (
                    <circle cx={dx} cy={dy} r="22" fill="none" stroke="#38bdf8" strokeWidth="2" strokeDasharray="3 3" className="animate-spin" />
                  )}

                  {/* Heading & Drone Symbol */}
                  <g transform={`translate(${dx}, ${dy}) rotate(${drone.heading})`}>
                    {/* Propulsion Field Glow */}
                    <circle cx="0" cy="0" r="14" fill="#0284c7" opacity="0.25" />
                    {/* Drone Quad Wings */}
                    <line x1="-9" y1="-9" x2="9" y2="9" stroke="#38bdf8" strokeWidth="1.5" />
                    <line x1="-9" y1="9" x2="9" y2="-9" stroke="#38bdf8" strokeWidth="1.5" />
                    {/* Rotor Heads */}
                    <circle cx="-9" cy="-9" r="2.5" fill="#38bdf8" />
                    <circle cx="9" cy="9" r="2.5" fill="#38bdf8" />
                    <circle cx="-9" cy="9" r="2.5" fill="#38bdf8" />
                    <circle cx="9" cy="-9" r="2.5" fill="#38bdf8" />
                    {/* Core Pod */}
                    <circle cx="0" cy="0" r="5" fill="#0c4a6e" stroke="#7dd3fc" strokeWidth="1.5" />
                    {/* Forward Heading Pointer */}
                    <polygon points="0,-12 -3,-5 3,-5" fill="#38bdf8" />
                  </g>

                  {/* Drone Callout Tag */}
                  <g transform={`translate(${dx}, ${dy - 18})`}>
                    <rect x="-24" y="-8" width="48" height="13" fill="#08101d" stroke="#0284c7" strokeWidth="0.8" rx="2" />
                    <text x="0" y="1" fill="#7dd3fc" fontSize="7.5" textAnchor="middle" className="font-mono font-bold">
                      {drone.id}
                    </text>
                  </g>

                  {/* Battery Gauge Bar */}
                  <g transform={`translate(${dx - 12}, ${dy + 15})`}>
                    <rect width="24" height="3" fill="#1e293b" rx="1" />
                    <rect
                      width={Math.max(2, (drone.battery_percent / 100) * 24)}
                      height="3"
                      fill={drone.battery_percent > 30 ? '#10b981' : '#ef4444'}
                      rx="1"
                    />
                  </g>
                </g>
              );
            })}
        </svg>
      </div>

      {/* Map Legend */}
      <div className="absolute bottom-3 left-3 z-30 flex items-center gap-3 bg-[#0e1626]/90 backdrop-blur-md px-3 py-1.5 rounded-lg border border-cyan-800/40 text-[10px] text-slate-400 font-mono">
        <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-red-500 animate-ping"></span> Critical Victim</span>
        <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-amber-500"></span> High Victim</span>
        <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-cyan-400"></span> Drone</span>
        <span className="flex items-center gap-1"><span className="w-2 h-2 rounded bg-orange-500"></span> Hazard Zone</span>
        <span className="flex items-center gap-1"><span className="w-2 h-1 bg-red-500"></span> Blocked Road</span>
      </div>
    </div>
  );
};
