// ResQNet Frontend Domain TypeScript Definitions

export type UncertaintyState = 'CONFIRMED' | 'PROBABLE' | 'UNCERTAIN' | 'STALE' | 'UNKNOWN';

export type SeverityLevel = 'CRITICAL' | 'HIGH' | 'MEDIUM' | 'LOW' | 'UNKNOWN';

export interface Vector3D {
  x: number;
  y: number;
  z: number;
}

export interface DroneEntity {
  id: string;
  callsign: string;
  model_name: string;
  capabilities: ('SCOUT' | 'MEDICAL' | 'HEAVY_LIFT' | 'RELAY' | 'INSPECTION')[];
  position: Vector3D;
  velocity: Vector3D;
  heading: number;
  battery_percent: number;
  battery_voltage: number;
  power_consumption_w: number;
  max_payload_kg: number;
  current_payload_kg: number;
  payload_type?: string;
  communication_quality: number;
  health: number;
  status: 'IDLE' | 'ASSIGNED' | 'EN_ROUTE' | 'ON_SITE' | 'RETURNING' | 'CHARGING' | 'ERROR' | 'LOST';
  current_mission_id?: string;
  target_victim_id?: string;
  home_facility_id: string;
  last_telemetry_timestamp: number;
  telemetry_latency_ms: number;
  uncertainty_state: UncertaintyState;
}

export interface VictimPriorityBreakdown {
  medical_severity_weight: number;
  urgency_weight: number;
  exposure_weight: number;
  accessibility_weight: number;
  confidence_weight: number;
  raw_medical_severity: number;
  raw_urgency: number;
  raw_exposure: number;
  raw_accessibility: number;
  raw_confidence: number;
  calculated_score: number;
  reasons: string[];
}

export interface VictimEvidence {
  image_url?: string;
  image_base64?: string;
  image_mime_type?: string;
  captured_at?: number;
  capture_type?: string;
  caption?: string;
}

export interface Victim {
  id: string;
  name: string;
  location: Vector3D;
  hazard_type: 'FIRE' | 'SMOKE' | 'FLOOD' | 'STRUCTURAL_COLLAPSE' | 'DEBRIS' | 'EARTHQUAKE' | 'GAS_LEAK' | 'EXPOSED' | 'UNKNOWN';
  captured_by_drone_id?: string;
  evidence: VictimEvidence;
  people_count: number;
  medical_severity: number;
  estimated_survival_urgency: number;
  hazard_exposure: number;
  accessibility_factor: number;
  confidence: number;
  uncertainty_state: UncertaintyState;
  priority_score: number;
  priority_class: SeverityLevel;
  status: 'DETECTED' | 'TRIAGED' | 'EN_ROUTE' | 'ASSISTED' | 'EVACUATED';
  assigned_drone_id?: string;
  assigned_mission_id?: string;
  detected_at: number;
  last_updated_at: number;
  breakdown?: VictimPriorityBreakdown;
  notes: string[];
}

export interface IncidentEntity {
  id: string;
  type: 'EARTHQUAKE_DAMAGE' | 'FIRE' | 'TRAPPED_VICTIM' | 'ROAD_BLOCKAGE' | 'DRONE_FAILURE' | 'COMMUNICATION_DEGRADATION' | 'FLOOD_ZONE';
  title: string;
  location: Vector3D;
  radius_m: number;
  severity: number;
  confidence: number;
  timestamp: number;
  evidence: string[];
  affected_entities: string[];
  status: 'ACTIVE' | 'CONTAINED' | 'RESOLVED';
  recommended_action: string;
  uncertainty_state: UncertaintyState;
}

export interface HazardZone {
  id: string;
  type: 'FIRE' | 'SMOKE_PLUME' | 'STRUCTURAL_COLLAPSE' | 'GAS_LEAK' | 'FLOOD';
  center: Vector3D;
  radius_m: number;
  intensity: number;
  spread_rate_m_per_s: number;
  active: boolean;
}

export interface Building {
  id: string;
  name: string;
  district: string;
  center: Vector3D;
  size_x: number;
  size_z: number;
  height: number;
  damage_level: 'INTACT' | 'MINOR_DAMAGE' | 'STRUCTURAL_CRACK' | 'COLLAPSED';
  occupancy_estimate: number;
  is_critical_infrastructure: boolean;
}

export interface RoadNode {
  id: string;
  position: Vector3D;
  is_intersection: boolean;
}

export interface RoadEdge {
  id: string;
  from_node: string;
  to_node: string;
  distance_m: number;
  is_blocked: boolean;
  blockage_reason?: string;
  hazard_cost_multiplier: number;
}

export interface Facility {
  id: string;
  name: string;
  type: string;
  location: Vector3D;
  capacity: number;
  current_load: number;
}

export interface EnvironmentalConditions {
  wind_speed_mps: number;
  wind_direction_deg: number;
  visibility_m: number;
  rain_rate_mm_hr: number;
  air_quality_index: number;
  ambient_temp_c: number;
  seismic_activity_richter: number;
}

export interface Waypoint {
  index: number;
  position: Vector3D;
  speed_mps: number;
  action: 'FLY_THROUGH' | 'HOVER_AND_SURVEY' | 'DROP_PAYLOAD' | 'LAND';
  action_duration_s: number;
  completed: boolean;
}

export interface RiskAssessment {
  overall_risk: number;
  category: string;
  contributors: string[];
  fire_proximity_m: number;
  battery_margin_percent: number;
  comms_loss_probability: number;
}

export interface MissionPlan {
  mission_id: string;
  objective: 'RESCUE_TRIAGE' | 'MEDICAL_SUPPLY_DROP' | 'STRUCTURAL_SURVEY' | 'COMMS_RELAY' | 'PERIMETER_PATROL' | 'RETURN_TO_BASE';
  target_victim_id?: string;
  target_incident_id?: string;
  assigned_drone_id: string;
  priority_score: number;
  route_nodes: string[];
  waypoints: Waypoint[];
  current_waypoint_index: number;
  estimated_duration_s: number;
  estimated_battery_drain: number;
  risk: RiskAssessment;
  fallback_strategy: string;
  explanation: string;
  status: 'PLANNED' | 'APPROVED' | 'DISPATCHED' | 'IN_PROGRESS' | 'REPLANNING' | 'COMPLETED' | 'FAILED' | 'ABORTED';
  created_at: number;
  dispatched_at?: number;
  completed_at?: number;
  failure_reason?: string;
  replan_count: number;
}

export interface AuditRecord {
  event_id: string;
  timestamp: number;
  event_type: string;
  decision: string;
  inputs: Record<string, any>;
  output: Record<string, any>;
  reason: string;
  confidence: number;
  affected_entities: string[];
}

export interface WorldStateSnapshot {
  session_id: string;
  simulation_time: number;
  state_version: number;
  system_b_connected: boolean;
  system_b_session_id?: string;
  drones: Record<string, DroneEntity>;
  victims: Record<string, Victim>;
  hazards: Record<string, HazardZone>;
  incidents: Record<string, IncidentEntity>;
  buildings: Record<string, Building>;
  road_nodes: Record<string, RoadNode>;
  road_edges: Record<string, RoadEdge>;
  facilities: Record<string, Facility>;
  environment: EnvironmentalConditions;
  telemetry_rate_hz: number;
  command_latency_ms: number;
  stale_entities_count: number;
}

export interface HealthStatus {
  status: string;
  system_a_version: string;
  system_b_connected: boolean;
  simulation_time: number;
  state_version: number;
  telemetry_rate_hz: number;
  command_latency_ms: number;
  stale_entities: number;
  timestamp: number;
}

export interface OperationalEvent {
  protocol?: string;
  event_id?: string;
  timestamp: number;
  event_type: string;
  source?: string;
  correlation_id?: string;
  payload: Record<string, any>;
}
