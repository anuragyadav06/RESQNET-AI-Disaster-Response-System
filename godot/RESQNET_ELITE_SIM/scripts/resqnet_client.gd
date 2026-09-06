class_name ResQNetClient
extends Node

# ============================================================
# RESQNET SYSTEM B <-> SYSTEM A
# Godot 4.7.x
#
# BACKWARD-COMPATIBLE INTEGRATION CLIENT
#
# IMPORTANT:
#   DroneFleet owns physical drone behaviour.
#   DisasterController owns physical disaster behaviour.
#   ResQNetClient owns communication/state transport.
#
# GODOT / SYSTEM B
#       |
#       | telemetry
#       | simulation state
#       | victim observations
#       | evidence
#       | response events
#       v
# FASTAPI / SYSTEM A
#       |
#       | commands
#       | simulation controls
#       v
# GODOT / SYSTEM B
#
# Existing communication contracts are intentionally preserved.
# New RESQNET state is additive rather than destructive.
# ============================================================


signal connection_changed(connected: bool)
signal backend_event(text: String)
signal victim_detected(data: Dictionary)
signal victim_evidence_captured(data: Dictionary)
signal response_event(data: Dictionary)
signal simulation_state_changed(data: Dictionary)


# ============================================================
# CONFIG
# ============================================================

const BACKEND_URL: String = \
	"ws://127.0.0.1:8000/ws/simulation/metro_godot_01"

const SESSION_ID: String = \
	"metro_godot_01"

const CLIENT_VERSION: String = \
	"Godot_4.7.2"

const ENVIRONMENT_NAME: String = \
	"RESQNET Elite Metro Disaster Twin"


# Existing communication cadence.
const TELEMETRY_INTERVAL: float = 0.25
const STATE_INTERVAL: float = 0.50
const HEARTBEAT_INTERVAL: float = 5.0
const RECONNECT_INTERVAL: float = 3.0
const VICTIM_SCAN_INTERVAL: float = 0.50

# New live Digital Twin / fleet state cadence.
const FLEET_STATE_INTERVAL: float = 0.50
const EVIDENCE_RETRY_INTERVAL: float = 1.50


# ============================================================
# AUTHORITATIVE MAP
# ============================================================

# These values are the operational simulation boundary.
#
# IMPORTANT:
#   Everything physical must remain inside these bounds.
#
const MAP_MIN_X: float = -360.0
const MAP_MAX_X: float = 360.0
const MAP_MIN_Z: float = -360.0
const MAP_MAX_Z: float = 360.0

const MAP_MIN_Y: float = 55.0
const MAP_MAX_Y: float = 240.0


# ============================================================
# SEARCH GRID
# ============================================================

const GRID_ROWS: int = 1
const GRID_COLUMNS: int = 16
const GRID_CELL_COUNT: int = 16

const SCOUT_COUNT: int = 16
const MEDICAL_COUNT: int = 5
const HEAVY_LIFT_COUNT: int = 5
const RESCUE_COUNT: int = 5

const TOTAL_DRONE_COUNT: int = \
	SCOUT_COUNT \
	+ MEDICAL_COUNT \
	+ HEAVY_LIFT_COUNT \
	+ RESCUE_COUNT


# ============================================================
# SOCKET
# ============================================================

var socket: WebSocketPeer = WebSocketPeer.new()

var connected: bool = false
var connection_attempted: bool = false


# ============================================================
# REFERENCES
# ============================================================

var main_controller: Node = null
var fleet: Node = null
var disaster: Node = null


# ============================================================
# TIMERS
# ============================================================

var telemetry_timer: float = 0.0
var state_timer: float = 0.0
var heartbeat_timer: float = 0.0
var reconnect_timer: float = 0.0
var victim_scan_timer: float = 0.0
var fleet_state_timer: float = 0.0
var evidence_retry_timer: float = 0.0


# ============================================================
# VICTIM CACHE
# ============================================================

var detected_victims: Dictionary = {}

var victim_counter: int = 100

# Victim evidence waiting for successful transmission.
var pending_evidence: Dictionary = {}

# Victim operational state.
var victim_states: Dictionary = {}


# ============================================================
# RESPONSE STATE
# ============================================================

var active_response_missions: Dictionary = {}

var completed_response_missions: Dictionary = {}


# ============================================================
# SETUP
# ============================================================

func setup(
	p_main: Node,
	p_fleet: Node,
	p_disaster: Node
) -> void:

	main_controller = p_main
	fleet = p_fleet
	disaster = p_disaster

	# DroneFleet is the authoritative source for physical victim detection.
	# Connect once so the client never invents a second search model.
	if fleet != null and fleet.has_signal("victim_detected"):
		fleet.connect("victim_detected", Callable(self, "_on_fleet_victim_detected"), CONNECT_DEFERRED)
	if fleet != null and fleet.has_signal("response_event"):
		fleet.connect("response_event", Callable(self, "_on_fleet_response_event"), CONNECT_DEFERRED)

	backend_event.emit(
		"SYSTEM B  |  RESQNET CLIENT INITIALIZED"
	)

	backend_event.emit(
		"FLEET  |  %d SCOUT | %d MEDICAL | %d HEAVY LIFT | %d RESCUE"
		% [
			SCOUT_COUNT,
			MEDICAL_COUNT,
			HEAVY_LIFT_COUNT,
			RESCUE_COUNT
		]
	)


# ============================================================
# CONNECT
# ============================================================

func connect_to_backend() -> void:

	if connection_attempted:
		return

	if socket.get_ready_state() == \
		WebSocketPeer.STATE_OPEN:

		return

	connection_attempted = true
	reconnect_timer = 0.0

	backend_event.emit(
		"SYSTEM A  |  CONNECTING TO COMMAND PLATFORM..."
	)

	var error: Error = socket.connect_to_url(
		BACKEND_URL
	)

	if error != OK:

		connection_attempted = false

		backend_event.emit(
			"SYSTEM A  |  CONNECTION FAILED | ERROR %s"
			% error
		)


# ============================================================
# PROCESS
# ============================================================

func _process(delta: float) -> void:

	socket.poll()

	var socket_state: WebSocketPeer.State = \
		socket.get_ready_state()


	if socket_state == \
		WebSocketPeer.STATE_OPEN:

		if not connected:

			_on_connected()

		_read_messages()

		telemetry_timer += delta
		state_timer += delta
		heartbeat_timer += delta
		victim_scan_timer += delta
		fleet_state_timer += delta
		evidence_retry_timer += delta


		if telemetry_timer >= \
			TELEMETRY_INTERVAL:

			telemetry_timer = 0.0

			_send_telemetry()


		if state_timer >= \
			STATE_INTERVAL:

			state_timer = 0.0

			_send_simulation_state()


		if heartbeat_timer >= \
			HEARTBEAT_INTERVAL:

			heartbeat_timer = 0.0

			_send_heartbeat()


		if victim_scan_timer >= \
			VICTIM_SCAN_INTERVAL:

			victim_scan_timer = 0.0

			_scan_for_victims()


		if fleet_state_timer >= \
			FLEET_STATE_INTERVAL:

			fleet_state_timer = 0.0

			_send_fleet_state()


		if evidence_retry_timer >= \
			EVIDENCE_RETRY_INTERVAL:

			evidence_retry_timer = 0.0

			_retry_pending_evidence()


	elif socket_state == \
		WebSocketPeer.STATE_CLOSED:

		if connected:

			connected = false

			connection_changed.emit(false)

			backend_event.emit(
				"SYSTEM A  |  COMMAND PLATFORM DISCONNECTED"
			)


		connection_attempted = false

		reconnect_timer += delta


		if reconnect_timer >= \
			RECONNECT_INTERVAL:

			reconnect_timer = 0.0

			socket = WebSocketPeer.new()

			connect_to_backend()


# ============================================================
# CONNECTED
# ============================================================

func _on_connected() -> void:

	connected = true
	connection_attempted = false

	telemetry_timer = 0.0
	state_timer = 0.0
	heartbeat_timer = 0.0
	victim_scan_timer = 0.0
	fleet_state_timer = 0.0
	evidence_retry_timer = 0.0

	connection_changed.emit(true)

	backend_event.emit(
		"SYSTEM A  |  COMMAND CHANNEL ONLINE"
	)


	# --------------------------------------------------------
	# PRESERVE ORIGINAL REGISTRATION CONTRACT
	# --------------------------------------------------------

	_send_json({

		"type":
			"REGISTER_SIMULATION",

		"session_id":
			SESSION_ID,

		"client_version":
			CLIENT_VERSION,

		"environment_name":
			ENVIRONMENT_NAME,

		"grid_bounds": {

			"min_x":
				MAP_MIN_X,

			"max_x":
				MAP_MAX_X,

			"min_z":
				MAP_MIN_Z,

			"max_z":
				MAP_MAX_Z
		},

		# Additive capability information.
		"capabilities": {

			"authoritative_digital_twin":
				true,

			"scout_drones":
				SCOUT_COUNT,

			"medical_drones":
				MEDICAL_COUNT,

			"heavy_lift_drones":
				HEAVY_LIFT_COUNT,

			"rescue_drones":
				RESCUE_COUNT,

			"total_drones":
				TOTAL_DRONE_COUNT,

			"grid_search":
				true,

			"grid_rows":
				GRID_ROWS,

			"grid_columns":
				GRID_COLUMNS,

			"north_south_only_scout_search":
				true,

			"victim_camera_evidence":
				true,

			"live_simulation_state":
				true
		}
	})


	backend_event.emit(
		"SYSTEM A  |  SIMULATION REGISTERED | %s"
		% SESSION_ID
	)


# ============================================================
# READ MESSAGES
# ============================================================

func _read_messages() -> void:

	while socket.get_available_packet_count() > 0:

		var packet: PackedByteArray = \
			socket.get_packet()

		var text: String = \
			packet.get_string_from_utf8()


		if text.is_empty():
			continue


		var parsed: Variant = \
			JSON.parse_string(text)


		if parsed == null:

			backend_event.emit(
				"SYSTEM A  |  INVALID JSON RECEIVED"
			)

			continue


		if not (
			parsed is Dictionary
		):

			backend_event.emit(
				"SYSTEM A  |  INVALID MESSAGE FORMAT"
			)

			continue


		_handle_message(
			parsed as Dictionary
		)


# ============================================================
# MESSAGE ROUTER
# ============================================================

func _handle_message(
	message: Dictionary
) -> void:

	var message_type: String = str(
		message.get(
			"type",
			""
		)
	).to_upper()


	match message_type:

		"COMMAND":

			var command_value: Variant = \
				message.get(
					"command",
					{}
				)


			if command_value is Dictionary:

				_handle_command(
					command_value as Dictionary
				)


		"SIMULATION_CONTROL":

			_handle_simulation_control(
				message
			)


		"HEARTBEAT_ACK":

			backend_event.emit(
				"SYSTEM A  |  HEARTBEAT ACK"
			)


		"COMMAND_ACK":

			backend_event.emit(
				"SYSTEM A  |  COMMAND ACK"
			)


		"COMMAND_RESULT":

			_handle_command_result(
				message
			)


		"RESPONSE_MISSION":

			_handle_response_mission(
				message
			)


		"RESPONSE_COMMAND":

			_handle_response_command(
				message
			)


		"MISSION_COMMAND":

			_handle_response_command(
				message
			)


		"RESCUE_COMPLETE":

			_handle_rescue_complete(
				message
			)


		"VICTIM_STATUS":

			_handle_victim_status(
				message
			)


		"RESET_DETECTION_CACHE":

			reset_detection_cache()


		_:

			# Preserve forward compatibility.
			# Unknown backend messages are ignored rather than
			# crashing the Digital Twin.
			pass


# ============================================================
# COMMAND FROM SYSTEM A
# ============================================================

func _handle_command(
	command: Dictionary
) -> void:

	var command_id: String = str(
		command.get(
			"command_id",
			""
		)
	)


	var drone_id: String = str(
		command.get(
			"drone_id",
			""
		)
	)


	var command_type: String = str(
		command.get(
			"command",
			""
		)
	).to_upper()


	backend_event.emit(
		"COMMAND RECEIVED | %s | %s"
		% [
			drone_id,
			command_type
		]
	)


	var accepted: bool = false
	var reason: String = ""


	if fleet == null:

		reason = \
			"DroneFleet reference is null."

	else:

		if fleet.has_method(
			"execute_resqnet_command"
		):

			var result: Variant = fleet.call(
				"execute_resqnet_command",
				command
			)


			if result is Dictionary:

				var result_dict: Dictionary = \
					result as Dictionary


				accepted = bool(
					result_dict.get(
						"accepted",
						false
					)
				)


				reason = str(
					result_dict.get(
						"reason",
						""
					)
				)


			elif result is bool:

				accepted = bool(
					result
				)

		else:

			reason = \
				"DroneFleet does not expose execute_resqnet_command()."


	_send_command_ack(
		command_id,
		drone_id,
		accepted,
		reason
	)


	# Immediately return command result as an additional
	# event so the frontend can update without waiting for
	# the next telemetry cycle.
	_send_json({

		"type":
			"COMMAND_EXECUTION_RESULT",

		"session_id":
			SESSION_ID,

		"command_id":
			command_id,

		"drone_id":
			drone_id,

		"command":
			command_type,

		"accepted":
			accepted,

		"reason":
			reason,

		"timestamp":
			Time.get_unix_time_from_system()
	})


# ============================================================
# COMMAND ACK
# ============================================================

func _send_command_ack(
	command_id: String,
	drone_id: String,
	accepted: bool,
	reason: String
) -> void:

	_send_json({

		"type":
			"COMMAND_ACK",

		"ack": {

			"command_id":
				command_id,

			"drone_id":
				drone_id,

			"status":
				"ACCEPTED"
				if accepted
				else
				"REJECTED",

			"reason":
				reason,

			"timestamp":
				Time.get_unix_time_from_system()
		}
	})


# ============================================================
# COMMAND RESULT
# ============================================================

func _handle_command_result(
	message: Dictionary
) -> void:

	var command_id: String = str(
		message.get(
			"command_id",
			""
		)
	)

	var status: String = str(
		message.get(
			"status",
			message.get(
				"result",
				""
			)
		)
	)

	backend_event.emit(
		"SYSTEM A  |  COMMAND RESULT | %s | %s"
		% [
			command_id,
			status
		]
	)


# ============================================================
# SIMULATION CONTROL
# ============================================================

func _handle_simulation_control(
	message: Dictionary
) -> void:

	if main_controller == null:
		return


	var action: String = str(
		message.get(
			"action",
			""
		)
	).to_upper()


	match action:

		"PAUSE":

			if main_controller.has_method(
				"_toggle_pause"
			):

				main_controller.call(
					"_toggle_pause"
				)


		"RESUME":

			if main_controller.has_method(
				"_toggle_pause"
			):

				main_controller.call(
					"_toggle_pause"
				)


		"RESET":

			if main_controller.has_method(
				"_reset_scenario"
			):

				main_controller.call(
					"_reset_scenario"
				)


		"EARTHQUAKE":

			if main_controller.has_method(
				"_trigger_demo"
			):

				main_controller.call(
					"_trigger_demo"
				)


		"FIRE":

			if main_controller.has_method(
				"_trigger_fire"
			):

				main_controller.call(
					"_trigger_fire"
				)


		"FLOOD":

			if main_controller.has_method(
				"_trigger_flood"
			):

				main_controller.call(
					"_trigger_flood"
				)


		"VICTIMS":

			if main_controller.has_method(
				"_spawn_victims_manual"
			):

				main_controller.call(
					"_spawn_victims_manual"
				)


		"SPAWN_VICTIMS":

			if main_controller.has_method(
				"_spawn_victims_manual"
			):

				main_controller.call(
					"_spawn_victims_manual"
				)


		_:

			backend_event.emit(
				"SYSTEM A | UNKNOWN CONTROL | %s"
				% action
			)


# ============================================================
# TELEMETRY
# ============================================================

func _send_telemetry() -> void:

	if fleet == null:
		return


	var drones_value: Variant = \
		fleet.get("drones")


	if not (
		drones_value is Array
	):

		return


	var packets: Array = []


	for drone_value: Variant in \
		drones_value as Array:

		if not (
			drone_value is Dictionary
		):

			continue


		var drone: Dictionary = \
			drone_value as Dictionary


		var node_value: Variant = \
			drone.get("node")


		if not (
			node_value is Node3D
		):

			continue


		var drone_node: Node3D = \
			node_value as Node3D


		if not is_instance_valid(
			drone_node
		):

			continue


		var position: Vector3 = \
			drone_node.global_position


		var velocity: Vector3 = Vector3.ZERO


		var velocity_value: Variant = \
			drone.get("velocity")


		if velocity_value is Vector3:

			velocity = \
				velocity_value as Vector3


		var drone_id: String = str(
			drone.get(
				"id",
				drone_node.name
			)
		)


		var drone_type: String = str(
			drone.get(
				"type",
				"SCOUT"
			)
		)


		var battery: float = float(
			drone.get(
				"battery",
				100.0
			)
		)


		var mission_id: String = str(
			drone.get(
				"mission_id",
				""
			)
		)


		var status: String = \
			_get_drone_status(
				drone
			)


		var grid_cell: int = int(
			drone.get(
				"grid_cell",
				-1
			)
		)


		var grid_name: String = \
			_grid_name(grid_cell)


		var cell_bounds: Dictionary = \
			_get_grid_cell_bounds(
				grid_cell
			)


		packets.append({

			"drone_id":
				drone_id,

			"drone_type":
				drone_type,

			"capabilities":
				_capabilities_for_type(
					drone_type
				),

			"timestamp":
				Time.get_unix_time_from_system(),

			"position":
				_vector_to_dictionary(
					position
				),

			"velocity":
				_vector_to_dictionary(
					velocity
				),

			"heading":
				rad_to_deg(
					drone_node.rotation.y
				),

			"battery_percent":
				battery,

			"battery_voltage":
				24.0,

			"current_draw_a":
				14.5,

			"altitude_agl_m":
				maxf(
					0.0,
					position.y
				),

			"communication_quality":
				1.0,

			"status":
				status,

			"current_waypoint_index":
				int(
					drone.get(
						"waypoint_index",
						0
					)
				),

			"mission_id":
				mission_id,

			"grid_cell":
				grid_cell,

			"grid_name":
				grid_name,

			"grid_bounds":
				cell_bounds,

			"search_direction":
				"NORTH_SOUTH"
				if drone_type.to_upper() == "SCOUT"
				else "RESPONSE"
		})


	if packets.is_empty():
		return


	_send_json({

		"type":
			"TELEMETRY_BATCH",

		"session_id":
			SESSION_ID,

		"timestamp":
			Time.get_unix_time_from_system(),

		"packets":
			packets
	})


# ============================================================
# LIVE FLEET STATE
# ============================================================

func _send_fleet_state() -> void:

	if fleet == null:
		return


	var drones_value: Variant = \
		fleet.get(
			"drones"
		)


	if not (
		drones_value is Array
	):

		return


	var drones_state: Array = []


	var available_medical: int = 0
	var available_heavy: int = 0
	var available_rescue: int = 0


	for drone_value: Variant in \
		drones_value as Array:

		if not (
			drone_value is Dictionary
		):

			continue


		var drone: Dictionary = \
			drone_value as Dictionary


		var drone_id: String = str(
			drone.get(
				"id",
				""
			)
		)


		var drone_type: String = str(
			drone.get(
				"type",
				""
			)
		).to_upper()


		var status: String = \
			_get_drone_status(
				drone
			)


		var node_value: Variant = \
			drone.get(
				"node"
			)


		var position: Vector3 = Vector3.ZERO


		if node_value is Node3D:

			var node: Node3D = \
				node_value as Node3D

			if is_instance_valid(node):

				position = \
					node.global_position


		var available: bool = \
			_is_response_drone_available(
				drone,
				status
			)


		if available:

			match drone_type:

				"MEDICAL":
					available_medical += 1

				"HEAVY LIFT":
					available_heavy += 1

				"RESCUE":
					available_rescue += 1


		drones_state.append({

			"drone_id":
				drone_id,

			"type":
				drone_type,

			"status":
				status,

			"available":
				available,

			"position":
				_vector_to_dictionary(
					position
				),

			"battery_percent":
				float(
					drone.get(
						"battery",
						100.0
					)
				),

			"grid_cell":
				int(
					drone.get(
						"grid_cell",
						-1
					)
				),

			"grid_name":
				_grid_name(
					int(
						drone.get(
							"grid_cell",
							-1
						)
					)
				),

			"mission_id":
				str(
					drone.get(
						"mission_id",
						""
					)
				)
		})


	_send_json({

		"type":
			"FLEET_STATE",

		"session_id":
			SESSION_ID,

		"timestamp":
			Time.get_unix_time_from_system(),

		"fleet": {

			"total":
				TOTAL_DRONE_COUNT,

			"scout":
				SCOUT_COUNT,

			"medical":
				MEDICAL_COUNT,

			"heavy_lift":
				HEAVY_LIFT_COUNT,

			"rescue":
				RESCUE_COUNT,

			"available_medical":
				available_medical,

			"available_heavy_lift":
				available_heavy,

			"available_rescue":
				available_rescue,

			"drones":
				drones_state
		},

		"search_grid":
			_build_grid_state()
	})


# ============================================================
# DRONE STATUS
# ============================================================

func _get_drone_status(
	drone: Dictionary
) -> String:

	var external_control: bool = bool(
		drone.get(
			"external_control",
			false
		)
	)


	if external_control:

		return str(
			drone.get(
				"backend_status",
				drone.get(
					"mission",
					"EN_ROUTE"
				)
			)
		)


	var mission: String = str(
		drone.get(
			"mission",
			"IDLE"
		)
	).to_upper()


	match mission:

		"IDLE":
			return "IDLE"

		# Response aircraft are deliberately kept in reserve at startup.
		# "STANDBY" is a parked/available state, not an EN_ROUTE state.
		# Treating it as EN_ROUTE incorrectly disabled all response buttons.
		"STANDBY":
			return "IDLE"

		"SURVEY":
			return "SEARCHING"

		"SEARCH":
			return "SEARCHING"

		"RETURN_TO_BASE":
			return "RETURNING"

		"RESCUE":
			return "RESCUE_IN_PROGRESS"

		"MEDICAL":
			return "MEDICAL_IN_PROGRESS"

		"HEAVY_LIFT":
			return "HEAVY_LIFT_IN_PROGRESS"

		_:
			return "EN_ROUTE"


# ============================================================
# CAPABILITIES
# ============================================================

func _capabilities_for_type(
	drone_type: String
) -> Array:

	var kind: String = drone_type.to_upper()

	# System A validates telemetry capabilities against the
	# DroneCapability enum. Only these wire values are legal:
	# SCOUT, MEDICAL, HEAVY_LIFT, RELAY, INSPECTION, RESCUE.
	# Operational features such as camera/victim detection are
	# deliberately not transmitted as capabilities.

	if kind == "SCOUT":
		return ["SCOUT"]

	if kind == "MEDICAL":
		return ["MEDICAL"]

	if kind == "HEAVY LIFT" or kind == "HEAVY_LIFT":
		return ["HEAVY_LIFT"]

	if kind == "RESCUE":
		return ["RESCUE"]

	if kind == "RELAY":
		return ["RELAY"]

	if kind == "INSPECTION":
		return ["INSPECTION"]

	return ["SCOUT"]


# ============================================================
# SIMULATION STATE
# ============================================================

func _send_simulation_state() -> void:

	if disaster == null:
		return


	var hazards: Array = []


	# --------------------------------------------------------
	# FIRE
	# --------------------------------------------------------

	var fires_value: Variant = \
		disaster.get(
			"fires"
		)


	if fires_value is Array:

		var fire_index: int = 0


		for fire_value: Variant in \
			fires_value as Array:

			if not (
				fire_value is Node3D
			):

				continue


			var fire_node: Node3D = \
				fire_value as Node3D


			if not is_instance_valid(
				fire_node
			):

				continue


			hazards.append({

				"id":
					"HAZ-FIRE-%03d"
					% fire_index,

				"type":
					"FIRE",

				"center":
					_vector_to_dictionary(
						_clamp_world_position(
							fire_node.global_position
						)
					),

				"radius_m":
					30.0,

				"intensity":
					0.85
			})


			fire_index += 1


	# --------------------------------------------------------
	# FLOOD
	# --------------------------------------------------------

	var flood_active: bool = false


	var flood_value: Variant = \
		disaster.get(
			"flood_active"
		)


	if flood_value != null:

		flood_active = bool(
			flood_value
		)


	if flood_active:

		var flood_front_z: float = 0.0


		var front_value: Variant = \
			disaster.get(
				"flood_front_z"
			)


		if front_value != null:

			flood_front_z = \
				float(front_value)


		flood_front_z = clampf(
			flood_front_z,
			MAP_MIN_Z,
			MAP_MAX_Z
		)


		hazards.append({

			"id":
				"HAZ-FLOOD-FRONT",

			"type":
				"FLOOD",

			"center":
				_vector_to_dictionary(
					Vector3(
						0.0,
						0.0,
						flood_front_z
					)
				),

			"radius_m":
				90.0,

			"intensity":
				1.0
		})


	# --------------------------------------------------------
	# SIMULATION CLOCK
	# --------------------------------------------------------

	var simulation_time: float = 0.0


	if main_controller != null:

		var time_value: Variant = \
			main_controller.get(
				"sim_time"
			)


		if time_value != null:

			simulation_time = \
				float(time_value)


	# --------------------------------------------------------
	# DISASTER
	# --------------------------------------------------------

	var disaster_active: bool = false


	var active_value: Variant = \
		disaster.get(
			"active"
		)


	if active_value != null:

		disaster_active = \
			bool(active_value)


	var disaster_type: String = \
		"NONE"


	var type_value: Variant = \
		disaster.get(
			"disaster_type"
		)


	if type_value != null:

		disaster_type = \
			str(type_value)


	var seismic: float = 0.0


	if disaster_active:

		seismic = 5.5


	if disaster_type.to_upper() == \
		"EARTHQUAKE":

		seismic = 6.5


	var state: Dictionary = {

		"simulation_time":
			simulation_time,

		"disaster_type":
			disaster_type,

		"disaster_active":
			disaster_active,

		"seismic_activity_richter":
			seismic,

		"hazards":
			hazards,

		"map_bounds": {

			"min_x":
				MAP_MIN_X,

			"max_x":
				MAP_MAX_X,

			"min_z":
				MAP_MIN_Z,

			"max_z":
				MAP_MAX_Z
		},

		"search_grid":
			_build_grid_state(),

		"response_fleet":
			_build_response_availability()
	}


	_send_json({

		"type":
			"SIMULATION_STATE",

		"session_id":
			SESSION_ID,

		"timestamp":
			Time.get_unix_time_from_system(),

		"state":
			state
	})


	simulation_state_changed.emit(
		state
	)


# ============================================================
# VICTIM SCAN
#
# IMPORTANT:
#
# This function remains here for backward compatibility.
#
# Physical movement belongs to DroneFleet.
#
# Detection authority is constrained by:
#   1. SCOUT type
#   2. assigned grid cell
#   3. local sensor radius
#
# A scout cannot detect a victim from another grid.
# ============================================================

func _scan_for_victims() -> void:
	# Physical reconnaissance is owned by DroneFleet. Keeping this method
	# as a no-op preserves the existing timer/API without creating a second
	# grid or duplicate victim IDs.
	return


# ============================================================
# AUTHORITATIVE FLEET VICTIM EVENTS
# ============================================================

func _on_fleet_victim_detected(data: Dictionary) -> void:
	var victim_id := str(data.get("victim_id", ""))
	if victim_id.is_empty():
		return

	var location_value: Variant = data.get("location", Vector3.ZERO)
	var location := Vector3.ZERO
	if location_value is Vector3:
		location = _clamp_world_position(location_value as Vector3)
	elif location_value is Dictionary:
		var ld: Dictionary = location_value as Dictionary
		location = _clamp_world_position(
			Vector3(
				float(ld.get("x", 0.0)),
				float(ld.get("y", 0.0)),
				float(ld.get("z", 0.0))
			)
		)

	if detected_victims.has(victim_id):
		return

	detected_victims[victim_id] = true

	var drone_id := str(
		data.get("drone_id", data.get("captured_by", "UNKNOWN"))
	)
	var hazard := str(
		data.get("hazard_type", "UNKNOWN")
	).to_upper()
	var corridor_id := str(
		data.get("corridor_id", data.get("grid_name", ""))
	)

	# The fleet now sends the camera frame in this same detection packet.
	# Do NOT discard it and start a second asynchronous camera request.
	var image_base64 := str(data.get("image_base64", ""))
	var image_mime_type := str(
		data.get("image_mime_type", "image/jpeg")
	)

	var confidence := float(data.get("confidence", 0.70))
	var victim_state := str(
		data.get("victim_state", "DETECTED")
	).to_upper()
	var trapped_by_structure := bool(
		data.get("trapped_by_structure", false)
	)
	var flood_capture := bool(
		data.get("flood_capture", false)
	)
	var cause := str(
		data.get("cause", hazard)
	).to_upper()

	var civilian := _find_civilian_by_victim_id(victim_id)
	if civilian != null and is_instance_valid(civilian):
		victim_state = str(
			civilian.get_meta("status", victim_state)
		).to_upper()
		trapped_by_structure = bool(
			civilian.get_meta(
				"trapped_by_structure",
				trapped_by_structure
			)
		)
		flood_capture = bool(
			civilian.get_meta("flood_capture", flood_capture)
		)
		cause = str(
			civilian.get_meta("cause", cause)
		).to_upper()

	var hazard_info: Dictionary = {}
	var hazard_value: Variant = data.get("hazard", {})
	if hazard_value is Dictionary:
		hazard_info = hazard_value as Dictionary

	victim_states[victim_id] = {
		"victim_id": victim_id,
		"status": victim_state,
		"location": location,
		"source_drone_id": drone_id,
		"hazard_type": hazard,
		"cause": cause,
		"trapped_by_structure": trapped_by_structure,
		"flood_capture": flood_capture,
		"corridor_id": corridor_id,
		"evidence_available": not image_base64.is_empty()
	}

	var observation := {
		"observation_id": "OBS-%s-%d" % [
			victim_id,
			Time.get_ticks_msec()
		],
		"timestamp": Time.get_unix_time_from_system(),
		"source_drone_id": drone_id,
		"type": "VICTIM_LOCATED",
		"location": _vector_to_dictionary(location),
		"confidence": confidence,
		"raw_reading": {
			"victim_id": victim_id,
			"people_count": 1,
			"search_axis": "Z",
			"corridor_id": corridor_id,
			"hazard_type": hazard,
			"hazard_info": hazard_info,
			"victim_state": victim_state,
			"cause": cause,
			"trapped_by_structure": trapped_by_structure,
			"flood_capture": flood_capture,
			"image_capture": "GODOT_DIGITAL_TWIN_DRONE_CAMERA"
		},
		"notes": "Scout detected victim and captured an actual Digital-Twin drone-camera frame.",
		"image_base64": image_base64,
		"image_mime_type": image_mime_type,
		"hazard_type": hazard,
		"corridor_id": corridor_id
	}

	# This single observation now carries BOTH the victim ID and the
	# actual image. FastAPI/IncidentAgent already supports these optional
	# evidence fields and will store them on that victim record.
	_send_json({
		"type": "OBSERVATION",
		"session_id": SESSION_ID,
		"observation": observation
	})

	victim_detected.emit(data)

	backend_event.emit(
		"VICTIM DETECTED | %s | %s | %s | CAMERA %s" % [
			victim_id,
			hazard,
			drone_id,
			"CAPTURED" if not image_base64.is_empty() else "FAILED"
		]
	)

	# If the first capture failed, retain the existing retry mechanism
	# instead of pretending an image exists.
	if image_base64.is_empty():
		_request_victim_evidence(
			victim_id,
			civilian,
			drone_id,
			location,
			-1
		)


func _on_fleet_response_event(data: Dictionary) -> void:
	if not data is Dictionary:
		return
	var event_data: Dictionary = data as Dictionary
	response_event.emit(event_data)
	_send_json({
		"type": "SIMULATION_EVENT",
		"session_id": SESSION_ID,
		"timestamp": Time.get_unix_time_from_system(),
		"event": event_data
	})


# ============================================================
# VICTIM EVIDENCE REQUEST
# ============================================================

func _request_victim_evidence(
	victim_id: String,
	civilian: Node3D,
	drone_id: String,
	location: Vector3,
	grid_cell: int
) -> void:

	if fleet == null:
		return


	# --------------------------------------------------------
	# Preferred API.
	#
	# DroneFleet should eventually expose:
	#
	# capture_victim_evidence(
	#     civilian,
	#     victim_id,
	#     drone_id
	# )
	#
	# This client intentionally supports multiple method names
	# so we don't destroy an existing fleet implementation.
	# --------------------------------------------------------

	var result: Variant = null
	var captured: bool = false


	if fleet.has_method(
		"capture_victim_evidence"
	):

		result = fleet.call(
			"capture_victim_evidence",
			civilian,
			victim_id,
			drone_id
	)

		captured = true


	elif fleet.has_method(
		"capture_victim_image"
	):

		result = fleet.call(
			"capture_victim_image",
			civilian,
			victim_id,
			drone_id
	)

		captured = true


	elif fleet.has_method(
		"capture_evidence"
	):

		result = fleet.call(
			"capture_evidence",
			civilian,
			victim_id,
			drone_id
		)

		captured = true


	if not captured:

		backend_event.emit(
			"EVIDENCE | %s | CAMERA API NOT YET EXPOSED BY DRONE FLEET"
			% victim_id
		)

		# Tell System A that evidence is pending rather than
		# pretending a photograph exists.
		pending_evidence[victim_id] = {

			"victim_id":
				victim_id,

			"drone_id":
				drone_id,

			"location":
				location,

			"grid_cell":
				grid_cell
		}

		return


	if result is Dictionary:

		var evidence: Dictionary = \
			result as Dictionary


		_process_victim_evidence(
			victim_id,
			drone_id,
			location,
			grid_cell,
			evidence
		)

	else:

		backend_event.emit(
			"EVIDENCE | %s | CAMERA REQUEST ACCEPTED"
			% victim_id
		)


# ============================================================
# PROCESS VICTIM EVIDENCE
# ============================================================

func _process_victim_evidence(
	victim_id: String,
	drone_id: String,
	location: Vector3,
	grid_cell: int,
	evidence: Dictionary
) -> void:

	var image_base64: String = str(
		evidence.get(
			"image_base64",
			""
		)
	)


	var image_url: String = str(
		evidence.get(
			"image_url",
			""
		)
	)


	var mime_type: String = str(
		evidence.get(
			"mime_type",
			"image/jpeg"
		)
	)


	if (
		image_base64.is_empty()
		and
		image_url.is_empty()
	):

		pending_evidence[victim_id] = {

			"victim_id":
				victim_id,

			"drone_id":
				drone_id,

			"location":
				location,

			"grid_cell":
				grid_cell
		}

		return


	var evidence_packet: Dictionary = {

		"victim_id":
			victim_id,

		"drone_id":
			drone_id,

		"location":
			_vector_to_dictionary(
				location
			),

		"grid_cell":
			grid_cell,

		"grid_name":
			_grid_name(
				grid_cell
			),

		"image_base64":
			image_base64,

		"image_url":
			image_url,

		"mime_type":
			mime_type,

		"captured_at":
			Time.get_unix_time_from_system(),

		"source":
			"GODOT_DIGITAL_TWIN_CAMERA"
	}


	_send_json({

		"type":
			"VICTIM_EVIDENCE",

		"session_id":
			SESSION_ID,

		"evidence":
			evidence_packet
	})


	pending_evidence.erase(
		victim_id
	)


	if victim_states.has(
		victim_id
	):

		var victim_state: Dictionary = \
			victim_states[victim_id]

		victim_state[
			"evidence_available"
		] = true

		victim_states[
			victim_id
		] = victim_state


	victim_evidence_captured.emit(
		evidence_packet
	)


	backend_event.emit(
		"EVIDENCE CAPTURED | %s | %s | %s"
		% [
			victim_id,
			drone_id,
			mime_type
		]
	)


# ============================================================
# RETRY PENDING EVIDENCE
# ============================================================

func _retry_pending_evidence() -> void:

	if pending_evidence.is_empty():
		return

	if fleet == null:
		return


	# Evidence requests are retried only if the fleet now
	# exposes a camera API.
	if not (
		fleet.has_method(
			"capture_victim_evidence"
		)
		or
		fleet.has_method(
			"capture_victim_image"
		)
		or
		fleet.has_method(
			"capture_evidence"
		)
	):

		return


	var retry_list: Array = []

	for victim_id in pending_evidence.keys():

		retry_list.append(
			str(victim_id)
		)


	for victim_id_value in retry_list:

		var victim_id: String = \
			str(victim_id_value)

		var item: Dictionary = \
			pending_evidence.get(
				victim_id,
				{}
			)

		if item.is_empty():
			continue


		# Find the civilian again.
		var civilian: Node3D = \
			_find_civilian_by_victim_id(
				victim_id
			)


		if civilian == null:
			continue


		_request_victim_evidence(
			victim_id,
			civilian,
			str(
				item.get(
					"drone_id",
					""
				)
			),
			_vector_from_dictionary(
				item.get(
					"location",
					{}
				)
			),
			int(
				item.get(
					"grid_cell",
					-1
				)
			)
		)


# ============================================================
# FIND CIVILIAN
# ============================================================

func _find_civilian_by_victim_id(
	victim_id: String
) -> Node3D:

	if disaster == null:
		return null


	var civilians_value: Variant = \
		disaster.get(
			"civilians"
		)


	if not (
		civilians_value is Array
	):

		return null


	for value: Variant in \
		civilians_value as Array:

		if not (
			value is Node3D
		):

			continue


		var person: Node3D = \
			value as Node3D


		if not is_instance_valid(
			person
		):

			continue


		var id: String = str(
			person.get_meta(
				"resqnet_victim_id",
				""
			)
		)


		if id == victim_id:
			return person


	return null


# ============================================================
# VICTIM HAZARD
# ============================================================

func _classify_victim_hazard(
	civilian: Node3D
) -> String:

	var cause: String = str(
		civilian.get_meta(
			"cause",
			""
		)
	).to_upper()


	if cause.contains(
		"FLOOD"
	):

		return "FLOOD"


	if (
		cause.contains(
			"FIRE"
		)
		or
		cause.contains(
			"SMOKE"
		)
	):

		return "SMOKE"


	if (
		cause.contains(
			"DEBRIS"
		)
		or
		cause.contains(
			"COLLAPSE"
		)
	):

		return "STRUCTURAL_COLLAPSE"


	if disaster != null:

		var disaster_type_value: Variant = \
			disaster.get(
				"disaster_type"
			)


		if (
			disaster_type_value != null
			and
			str(
				disaster_type_value
			).to_upper()
			==
			"EARTHQUAKE"
		):

			return "EARTHQUAKE"


	return "EXPOSED"


# ============================================================
# MANUAL VICTIM FORWARDING
#
# Existing API preserved.
# ============================================================

func send_victim_detection(
	victim_id: String,
	hazard_type: String,
	location: Vector3,
	drone_id: String,
	confidence: float = 0.90,
	image_url: String = ""
) -> void:

	if not connected:
		return


	var grid_cell: int = \
		_get_grid_cell_for_position(
			location
		)


	var observation: Dictionary = {

		"observation_id":
			"OBS-%s"
			% victim_id,

		"timestamp":
			Time.get_unix_time_from_system(),

		"source_drone_id":
			drone_id,

		"type":
			"VICTIM_LOCATED",

		"location":
			_vector_to_dictionary(
				_clamp_world_position(
					location
				)
			),

		"confidence":
			confidence,

		"raw_reading": {

			"victim_id":
				victim_id,

			"grid_cell":
				grid_cell,

			"grid_name":
				_grid_name(
					grid_cell
				)
		},

		"notes":
			"Victim detected by simulated drone.",

		"hazard_type":
			hazard_type,

		"grid_cell":
			grid_cell
	}


	if not image_url.is_empty():

		observation[
			"image_url"
		] = image_url


	_send_json({

		"type":
			"OBSERVATION",

		"session_id":
			SESSION_ID,

		"observation":
			observation
	})


	victim_detected.emit({

		"victim_id":
			victim_id,

		"hazard_type":
			hazard_type,

		"location":
			location,

		"drone_id":
			drone_id,

		"grid_cell":
			grid_cell,

		"confidence":
			confidence,

		"image_url":
			image_url
	})


# ============================================================
# RESPONSE MISSION
# ============================================================

func _handle_response_mission(
	message: Dictionary
) -> void:

	var mission: Dictionary = {}


	var mission_value: Variant = \
		message.get(
			"mission",
			message
		)


	if mission_value is Dictionary:

		mission = \
			mission_value as Dictionary


	if mission.is_empty():
		return


	var mission_id: String = str(
		mission.get(
			"mission_id",
			""
		)
	)


	var victim_id: String = str(
		mission.get(
			"victim_id",
			""
		)
	)


	var drone_id: String = str(
		mission.get(
			"drone_id",
			""
		)
	)


	var mission_type: String = str(
		mission.get(
			"mission_type",
			mission.get(
				"type",
				""
			)
		)
	).to_upper()


	if not mission_id.is_empty():

		active_response_missions[
			mission_id
		] = mission


	if not victim_id.is_empty():

		if victim_states.has(
			victim_id
		):

			var state: Dictionary = \
				victim_states[victim_id]

			state[
				"response_status"
			] = "DISPATCHED"

			state[
				"response_mission_id"
			] = mission_id

			state[
				"response_drone_id"
			] = drone_id

			state[
				"response_type"
			] = mission_type

			victim_states[
				victim_id
			] = state


	response_event.emit({

		"event":
			"RESPONSE_DISPATCHED",

		"mission_id":
			mission_id,

		"victim_id":
			victim_id,

		"drone_id":
			drone_id,

		"mission_type":
			mission_type
	})


	backend_event.emit(
		"RESPONSE DISPATCHED | %s | %s | %s"
		% [
			victim_id,
			drone_id,
			mission_type
		]
	)


# ============================================================
# RESPONSE COMMAND
# ============================================================

func _handle_response_command(
	message: Dictionary
) -> void:

	var command_value: Variant = \
		message.get(
			"command",
			message
		)


	if not (
		command_value is Dictionary
	):

		return


	_handle_command(
		command_value as Dictionary
	)


# ============================================================
# RESCUE COMPLETE
# ============================================================

func _handle_rescue_complete(
	message: Dictionary
) -> void:

	var victim_id: String = str(
		message.get(
			"victim_id",
			""
		)
	)


	var mission_id: String = str(
		message.get(
			"mission_id",
			""
		)
	)


	var drone_id: String = str(
		message.get(
			"drone_id",
			""
		)
	)


	if not victim_id.is_empty():

		victim_states[victim_id] = {

			"victim_id":
				victim_id,

			"status":
				"EVACUATED",

			"response_status":
				"COMPLETE",

			"response_mission_id":
				mission_id,

			"response_drone_id":
				drone_id
		}


	if not mission_id.is_empty():

		completed_response_missions[
			mission_id
		] = message

		active_response_missions.erase(
			mission_id
		)


	# Tell the local Digital Twin if the disaster controller
	# supports victim rescue state.
	_mark_local_victim_rescued(
		victim_id
	)


	_send_json({

		"type":
			"RESCUE_COMPLETION_ACK",

		"session_id":
			SESSION_ID,

		"victim_id":
			victim_id,

		"mission_id":
			mission_id,

		"drone_id":
			drone_id,

		"status":
			"EVACUATED",

		"timestamp":
			Time.get_unix_time_from_system()
	})


	response_event.emit({

		"event":
			"RESCUE_COMPLETE",

		"victim_id":
			victim_id,

		"mission_id":
			mission_id,

		"drone_id":
			drone_id
	})


	backend_event.emit(
		"RESCUE COMPLETE | %s | %s | %s | GREEN SAFE STATE"
		% [
			victim_id,
			drone_id,
			mission_id
		]
	)


# ============================================================
# VICTIM STATUS
# ============================================================

func _handle_victim_status(
	message: Dictionary
) -> void:

	var victim_id: String = str(
		message.get(
			"victim_id",
			""
		)
	)


	if victim_id.is_empty():
		return


	var status: String = str(
		message.get(
			"status",
			""
		)
	).to_upper()


	if victim_states.has(
		victim_id
	):

		var state: Dictionary = \
			victim_states[victim_id]

		state[
			"status"
		] = status

		victim_states[
			victim_id
		] = state


	if (
		status == "RESCUED"
		or
		status == "EVACUATED"
	):

		_mark_local_victim_rescued(
			victim_id
		)


# ============================================================
# MARK LOCAL VICTIM RESCUED
# ============================================================

func _mark_local_victim_rescued(
	victim_id: String
) -> void:

	if victim_id.is_empty():
		return


	var victim: Node3D = \
		_find_civilian_by_victim_id(
			victim_id
		)


	if victim == null:
		return


	victim.set_meta(
		"rescued",
		true
	)

	victim.set_meta(
		"status",
		"EVACUATED"
	)

	victim.set_meta(
		"resqnet_safe",
		true
	)


	# If DisasterController already has a dedicated method,
	# let it perform its own visual/state handling.
	if disaster != null:

		if disaster.has_method(
			"mark_victim_rescued"
		):

			disaster.call(
				"mark_victim_rescued",
				victim_id
			)

		elif disaster.has_method(
			"rescue_victim"
		):

			disaster.call(
				"rescue_victim",
				victim_id
			)


# ============================================================
# RESET VICTIM CACHE
# ============================================================

func reset_detection_cache() -> void:

	detected_victims.clear()

	pending_evidence.clear()

	victim_states.clear()

	active_response_missions.clear()

	completed_response_missions.clear()

	victim_counter = 100


	backend_event.emit(
		"SYSTEM B | VICTIM DETECTION STATE RESET"
	)


# ============================================================
# HEARTBEAT
# ============================================================

func _send_heartbeat() -> void:

	_send_json({

		"type":
			"HEARTBEAT",

		"session_id":
			SESSION_ID,

		"timestamp":
			Time.get_unix_time_from_system(),

		"status":
			"ONLINE",

		"simulation_authority":
			"GODOT"
	})


# ============================================================
# GRID STATE
# ============================================================

func _build_grid_state() -> Array:
	var cells: Array = []
	var corridor_width := (MAP_MAX_X - MAP_MIN_X) / float(GRID_CELL_COUNT)
	for i in range(GRID_CELL_COUNT):
		var min_x := MAP_MIN_X + float(i) * corridor_width
		var max_x := min_x + corridor_width
		cells.append({
			"cell": i,
			"name": "L%02d" % (i + 1),
			"owner_drone_id": "DRONE-S%02d" % (i + 1),
			"search_enabled": true,
			"search_direction": "SOUTH_NORTH_BIDIRECTIONAL",
			"movement_axis": "Z",
			"east_west_allowed": false,
			"bounds": {"min_x": min_x, "max_x": max_x, "min_z": MAP_MIN_Z, "max_z": MAP_MAX_Z}
		})
	return cells


# ============================================================
# GRID / CORRIDOR BOUNDS
# ============================================================

func _get_grid_cell_bounds(cell_index: int) -> Dictionary:
	if cell_index < 0 or cell_index >= GRID_CELL_COUNT:
		return {}
	var width := (MAP_MAX_X - MAP_MIN_X) / float(GRID_CELL_COUNT)
	var min_x := MAP_MIN_X + float(cell_index) * width
	return {"min_x": min_x, "max_x": min_x + width, "min_z": MAP_MIN_Z, "max_z": MAP_MAX_Z}


# ============================================================
# GRID NAME
# ============================================================

func _grid_name(
	cell_index: int
) -> String:

	if (
		cell_index < 0
		or
		cell_index >= GRID_CELL_COUNT
	):

		return "UNASSIGNED"


	return "G%02d" % (
		cell_index + 1
	)


# ============================================================
# POSITION -> GRID
# ============================================================

func _get_grid_cell_for_position(position: Vector3) -> int:
	var p := _clamp_world_position(position)
	var normalized_x := (p.x - MAP_MIN_X) / (MAP_MAX_X - MAP_MIN_X)
	return clampi(int(floor(normalized_x * float(GRID_CELL_COUNT))), 0, GRID_CELL_COUNT - 1)


# ============================================================
# RESPONSE AVAILABILITY
# ============================================================

func _build_response_availability() -> Dictionary:

	var medical: int = 0
	var heavy: int = 0
	var rescue: int = 0


	if fleet == null:

		return {

			"medical":
				0,

			"heavy_lift":
				0,

			"rescue":
				0
		}


	var drones_value: Variant = \
		fleet.get(
			"drones"
		)


	if not (
		drones_value is Array
	):

		return {

			"medical":
				0,

			"heavy_lift":
				0,

			"rescue":
				0
		}


	for value: Variant in \
		drones_value as Array:

		if not (
			value is Dictionary
		):

			continue


		var drone: Dictionary = \
			value as Dictionary


		var type: String = str(
			drone.get(
				"type",
				""
			)
		).to_upper()


		var status: String = \
			_get_drone_status(
				drone
			)


		if not _is_response_drone_available(
			drone,
			status
		):

			continue


		match type:

			"MEDICAL":
				medical += 1

			"HEAVY LIFT":
				heavy += 1

			"RESCUE":
				rescue += 1


	return {

		"medical":
			medical,

		"heavy_lift":
			heavy,

		"rescue":
			rescue
	}


# ============================================================
# RESPONSE DRONE AVAILABLE
# ============================================================

func _is_response_drone_available(
	drone: Dictionary,
	status: String
) -> bool:

	var type: String = str(
		drone.get(
			"type",
			""
		)
	).to_upper()


	if (
		type != "MEDICAL"
		and
		type != "HEAVY LIFT"
		and
		type != "RESCUE"
	):

		return false


	var battery: float = float(
		drone.get(
			"battery",
			100.0
		)
	)


	if battery <= 20.0:
		return false


	if bool(
		drone.get(
			"external_control",
			false
		)
	):

		return false


	if (
		status == "RETURNING"
		or
		status == "EN_ROUTE"
		or
		status == "RESCUE_IN_PROGRESS"
		or
		status == "MEDICAL_IN_PROGRESS"
		or
		status == "HEAVY_LIFT_IN_PROGRESS"
	):

		return false


	return true


# ============================================================
# CLAMP WORLD POSITION
# ============================================================

func _clamp_world_position(
	position: Vector3
) -> Vector3:

	return Vector3(

		clampf(
			position.x,
			MAP_MIN_X,
			MAP_MAX_X
		),

		clampf(
			position.y,
			MAP_MIN_Y,
			MAP_MAX_Y
		),

		clampf(
			position.z,
			MAP_MIN_Z,
			MAP_MAX_Z
		)
	)


# ============================================================
# VECTOR -> DICTIONARY
# ============================================================

func _vector_to_dictionary(
	value: Vector3
) -> Dictionary:

	return {

		"x":
			value.x,

		"y":
			value.y,

		"z":
			value.z
	}


# ============================================================
# DICTIONARY -> VECTOR
# ============================================================

func _vector_from_dictionary(
	value: Variant
) -> Vector3:

	if not (
		value is Dictionary
	):

		return Vector3.ZERO


	var data: Dictionary = \
		value as Dictionary


	return Vector3(

		float(
			data.get(
				"x",
				0.0
			)
		),

		float(
			data.get(
				"y",
				80.0
			)
		),

		float(
			data.get(
				"z",
				0.0
			)
		)
	)


# ============================================================
# SEND JSON
# ============================================================

func _send_json(
	data: Dictionary
) -> void:

	if (
		socket.get_ready_state()
		!=
		WebSocketPeer.STATE_OPEN
	):

		return


	var json_text: String = \
		JSON.stringify(
			data
		)


	var error: Error = \
		socket.send_text(
			json_text
		)


	if error != OK:

		backend_event.emit(
			"SYSTEM A | SEND ERROR | %s"
			% error
		)


# ============================================================
# EXIT
# ============================================================

func _exit_tree() -> void:

	if (
		socket.get_ready_state()
		!=
		WebSocketPeer.STATE_CLOSED
	):

		socket.close()
