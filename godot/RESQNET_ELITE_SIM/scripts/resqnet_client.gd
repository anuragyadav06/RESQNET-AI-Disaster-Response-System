class_name ResQNetClient
extends Node

# ============================================================
# RESQNET SYSTEM B <-> SYSTEM A
# Godot 4.7.2
#
# EXISTING SIMULATION REMAINS AUTHORITATIVE.
#
# This client handles:
#   Godot -> FastAPI
#       registration
#       telemetry
#       simulation state
#       victim observations
#       heartbeat
#
#   FastAPI -> Godot
#       drone commands
#       simulation controls
# ============================================================


signal connection_changed(connected: bool)
signal backend_event(text: String)
signal victim_detected(data: Dictionary)


# ============================================================
# CONFIG
# ============================================================

const BACKEND_URL: String = \
	"ws://127.0.0.1:8000/ws/simulation/metro_godot_01"

const SESSION_ID: String = \
	"metro_godot_01"

const CLIENT_VERSION: String = \
	"Godot_4.7.2"


const TELEMETRY_INTERVAL: float = 0.25
const STATE_INTERVAL: float = 0.50
const HEARTBEAT_INTERVAL: float = 5.0
const RECONNECT_INTERVAL: float = 3.0
const VICTIM_SCAN_INTERVAL: float = 0.75


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


# ============================================================
# VICTIM CACHE
# ============================================================

var detected_victims: Dictionary = {}
var victim_counter: int = 100


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


# ============================================================
# CONNECT
# ============================================================

func connect_to_backend() -> void:

	if connection_attempted:
		return

	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
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
			"SYSTEM A  |  CONNECTION FAILED  |  ERROR %s"
			% error
		)


# ============================================================
# PROCESS
# ============================================================

func _process(delta: float) -> void:

	socket.poll()

	var socket_state: WebSocketPeer.State = \
		socket.get_ready_state()


	if socket_state == WebSocketPeer.STATE_OPEN:

		if not connected:
			_on_connected()

		_read_messages()

		telemetry_timer += delta
		state_timer += delta
		heartbeat_timer += delta
		victim_scan_timer += delta


		if telemetry_timer >= TELEMETRY_INTERVAL:

			telemetry_timer = 0.0

			_send_telemetry()


		if state_timer >= STATE_INTERVAL:

			state_timer = 0.0

			_send_simulation_state()


		if heartbeat_timer >= HEARTBEAT_INTERVAL:

			heartbeat_timer = 0.0

			_send_heartbeat()


		if victim_scan_timer >= VICTIM_SCAN_INTERVAL:

			victim_scan_timer = 0.0

			_scan_for_victims()


	elif socket_state == WebSocketPeer.STATE_CLOSED:

		if connected:

			connected = false

			connection_changed.emit(false)

			backend_event.emit(
				"SYSTEM A  |  COMMAND PLATFORM DISCONNECTED"
			)


		connection_attempted = false

		reconnect_timer += delta


		if reconnect_timer >= RECONNECT_INTERVAL:

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

	connection_changed.emit(true)

	backend_event.emit(
		"SYSTEM A  |  COMMAND CHANNEL ONLINE"
	)


	_send_json({
		"type": "REGISTER_SIMULATION",

		"session_id": SESSION_ID,

		"client_version": CLIENT_VERSION,

		"environment_name":
			"RESQNET Elite Metro Disaster Twin",

		"grid_bounds": {
			"min_x": -600.0,
			"max_x": 600.0,
			"min_z": -600.0,
			"max_z": 600.0
		}
	})


	backend_event.emit(
		"SYSTEM A  |  SIMULATION REGISTERED  |  %s"
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


		if not (parsed is Dictionary):

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
		message.get("type", "")
	).to_upper()


	match message_type:

		"COMMAND":

			var command_value: Variant = \
				message.get("command", {})


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

			backend_event.emit(
				"SYSTEM A  |  COMMAND RESULT"
			)


		_:

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
		"COMMAND RECEIVED  |  %s  |  %s"
		% [
			drone_id,
			command_type
		]
	)


	var accepted: bool = false
	var reason: String = ""


	if fleet != null:

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

				accepted = bool(result)


		else:

			reason = \
				"DroneFleet does not expose execute_resqnet_command()"


	else:

		reason = \
			"DroneFleet reference is null."


	_send_command_ack(
		command_id,
		drone_id,
		accepted,
		reason
	)


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

			main_controller.call(
				"_toggle_pause"
			)


		"RESUME":

			main_controller.call(
				"_toggle_pause"
			)


		"RESET":

			main_controller.call(
				"_reset_scenario"
			)


		"EARTHQUAKE":

			main_controller.call(
				"_trigger_demo"
			)


		"FIRE":

			main_controller.call(
				"_trigger_fire"
			)


		"FLOOD":

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
				"SYSTEM A  |  UNKNOWN CONTROL  |  %s"
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


	if not (drones_value is Array):
		return


	var packets: Array = []


	for drone_value: Variant in \
		drones_value as Array:


		if not (drone_value is Dictionary):
			continue


		var drone: Dictionary = \
			drone_value as Dictionary


		var node_value: Variant = \
			drone.get("node")


		if not (node_value is Node3D):
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
				mission_id
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
				"EN_ROUTE"
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

		"SURVEY":
			return "EN_ROUTE"

		"RETURN_TO_BASE":
			return "RETURNING"

		_:
			return "EN_ROUTE"


# ============================================================
# CAPABILITIES
# ============================================================

func _capabilities_for_type(
	drone_type: String
) -> Array:

	match drone_type.to_upper():

		"SCOUT":

			return [
				"SCOUT"
			]


		"MEDICAL":

			return [
				"MEDICAL"
			]


		"HEAVY LIFT":

			return [
				"HEAVY_LIFT"
			]


		"RELAY":

			return [
				"RELAY"
			]


		"INSPECTION":

			return [
				"INSPECTION"
			]


		_:

			return [
				"SCOUT"
			]


# ============================================================
# SIMULATION STATE
# ============================================================

func _send_simulation_state() -> void:

	if disaster == null:
		return


	var hazards: Array = []


	var fires_value: Variant = \
		disaster.get("fires")


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
						fire_node.global_position
					),

				"radius_m":
					30.0,

				"intensity":
					0.85
			})


			fire_index += 1


	var flood_active: bool = false


	var flood_value: Variant = \
		disaster.get("flood_active")


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

			flood_front_z = float(
				front_value
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


	var simulation_time: float = 0.0


	if main_controller != null:

		var time_value: Variant = \
			main_controller.get(
				"sim_time"
			)


		if time_value != null:

			simulation_time = float(
				time_value
			)


	var disaster_active: bool = false


	var active_value: Variant = \
		disaster.get("active")


	if active_value != null:

		disaster_active = bool(
			active_value
		)


	var disaster_type: String = "NONE"


	var type_value: Variant = \
		disaster.get(
			"disaster_type"
		)


	if type_value != null:

		disaster_type = str(
			type_value
		)


	var seismic: float = 0.0


	if disaster_active:

		seismic = 5.5


	if disaster_type.to_upper() == \
		"EARTHQUAKE":

		seismic = 6.5


	_send_json({

		"type":
			"SIMULATION_STATE",

		"session_id":
			SESSION_ID,

		"timestamp":
			Time.get_unix_time_from_system(),

		"state": {

			"simulation_time":
				simulation_time,

			"disaster_type":
				disaster_type,

			"disaster_active":
				disaster_active,

			"seismic_activity_richter":
				seismic,

			"hazards":
				hazards
		}
	})


# ============================================================
# VICTIM SCAN
# ============================================================

func _scan_for_victims() -> void:

	if disaster == null:
		return

	if fleet == null:
		return


	var civilians_value: Variant = \
		disaster.get(
			"civilians"
		)


	if not (
		civilians_value is Array
	):

		return


	var drones_value: Variant = \
		fleet.get(
			"drones"
		)


	if not (
		drones_value is Array
	):

		return


	for civilian_value: Variant in \
		civilians_value as Array:


		if not (
			civilian_value is Node3D
		):

			continue


		var civilian: Node3D = \
			civilian_value as Node3D


		if not is_instance_valid(
			civilian
		):

			continue


		var rescued: bool = bool(
			civilian.get_meta(
				"rescued",
				false
			)
		)


		if rescued:
			continue


		var status: String = str(
			civilian.get_meta(
				"status",
				""
			)
		).to_upper()


		if (
			status.is_empty()
			or
			status == "ROAMING"
			or
			status == "SAFE"
		):

			continue


		var nearest_drone_id: String = ""
		var nearest_distance: float = INF


		for drone_value: Variant in \
			drones_value as Array:


			if not (
				drone_value is Dictionary
			):

				continue


			var drone: Dictionary = \
				drone_value as Dictionary


			var drone_type: String = str(
				drone.get(
					"type",
					""
				)
			).to_upper()


			if (
				drone_type != "SCOUT"
				and
				drone_type != "INSPECTION"
			):

				continue


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


			var distance: float = \
				drone_node.global_position.distance_to(
					civilian.global_position
				)


			if distance < nearest_distance:

				nearest_distance = distance

				nearest_drone_id = str(
					drone.get(
						"id",
						drone_node.name
					)
				)


		if nearest_drone_id.is_empty():
			continue


		if nearest_distance > 190.0:
			continue


		var cache_key: String = str(
			civilian.get_instance_id()
		)


		if detected_victims.has(
			cache_key
		):

			continue


		victim_counter += 1


		var victim_id: String = \
			"VIC-%03d" % victim_counter


		detected_victims[
			cache_key
		] = victim_id


		civilian.set_meta(
			"resqnet_victim_id",
			victim_id
		)


		var hazard_type: String = \
			_classify_victim_hazard(
				civilian
			)


		var observation: Dictionary = {

			"observation_id":
				"OBS-%s-%d"
				% [
					victim_id,
					Time.get_ticks_msec()
				],

			"timestamp":
				Time.get_unix_time_from_system(),

			"source_drone_id":
				nearest_drone_id,

			"type":
				"VICTIM_LOCATED",

			"location":
				_vector_to_dictionary(
					civilian.global_position
				),

			"confidence":
				0.94,

			"raw_reading": {

				"victim_id":
					victim_id,

				"hazard_type":
					hazard_type,

				"people_count":
					1,

				"medical_severity": 0.0,

				"urgency":
					0.90
			},

			"notes":
				"Victim detected by simulated drone sensor.",

			"hazard_type":
				hazard_type
		}


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
				civilian.global_position,

			"drone_id":
				nearest_drone_id,

			"confidence":
				0.94
		})


		backend_event.emit(
			"VICTIM DETECTED  |  %s  |  %s  |  %s"
			% [
				victim_id,
				hazard_type,
				nearest_drone_id
			]
		)


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
		cause.contains("FIRE")
		or
		cause.contains("SMOKE")
	):

		return "SMOKE"


	if (
		cause.contains("DEBRIS")
		or
		cause.contains("COLLAPSE")
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
				location
			),

		"confidence":
			confidence,

		"raw_reading": {

			"victim_id":
				victim_id
		},

		"notes":
			"Victim detected by simulated drone.",

		"hazard_type":
			hazard_type
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

		"confidence":
			confidence,

		"image_url":
			image_url
	})


# ============================================================
# RESET VICTIM CACHE
# ============================================================

func reset_detection_cache() -> void:

	detected_victims.clear()

	victim_counter = 100


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
			Time.get_unix_time_from_system()
	})


# ============================================================
# VECTOR
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
# SEND
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
		JSON.stringify(data)


	var error: Error = \
		socket.send_text(
			json_text
		)


	if error != OK:

		backend_event.emit(
			"SYSTEM A  |  SEND ERROR  |  %s"
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