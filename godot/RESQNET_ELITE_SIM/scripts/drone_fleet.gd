class_name DroneFleet
extends Node3D

## RESQNET — AUTHORITATIVE DIGITAL TWIN DRONE FLEET
##
## FLEET:
##   16 SCOUT
##    5 MEDICAL
##    5 HEAVY LIFT
##    5 RESCUE
##   ----------------
##   31 TOTAL
##
## SCOUT DOCTRINE:
##   16 fixed X coordinates.
##   Each scout owns exactly one X coordinate.
##   Scouts move ONLY along Z.
##   Scouts sweep SOUTH -> NORTH -> SOUTH repeatedly.
##   No rectangular 4x4 cells are used.
##
## RESPONSE DOCTRINE:
##   Medical / Heavy Lift / Rescue aircraft remain at a dedicated standby line
##   along the SOUTH X-axis edge of the operational map. They never sit at
##   the command-center origin. System-A dispatches them to the victim.

signal drone_event(text: String)
signal victim_detected(data: Dictionary)
signal response_event(data: Dictionary)

# ---------------------------------------------------------------------------
# MAP
# ---------------------------------------------------------------------------

const MAP_MIN: float = -360.0
const MAP_MAX: float = 360.0

const MAP_MIN_Y: float = 55.0
const MAP_MAX_Y: float = 240.0

const SCOUT_COUNT: int = 16
const MEDICAL_COUNT: int = 5
const HEAVY_LIFT_COUNT: int = 5
const RESCUE_COUNT: int = 5
const TOTAL_DRONE_COUNT: int = 31

const CORRIDOR_MARGIN: float = 10.0

const SCOUT_ALTITUDE: float = 150.0
const RESPONSE_ALTITUDE: float = 105.0

const SCOUT_SPEED: float = 24.0
const RESPONSE_SPEED: float = 34.0

# Corridor spacing is about 46.7 m. A 60 m sensor radius gives overlap
# between adjacent search lines while keeping each scout's motion fixed.
const SCOUT_SENSOR_RADIUS: float = 60.0

const RESPONSE_ON_SITE_TIME: float = 4.0

const BASE_POSITION: Vector3 = Vector3(0.0, RESPONSE_ALTITUDE, MAP_MIN + CORRIDOR_MARGIN)

# Response fleet staging line: all 15 standby aircraft are parked on the
# southern X-axis boundary, spread across X. They launch from here and return
# to their exact individual slots after completing a mission.
const RESPONSE_BASE_Z: float = MAP_MIN + CORRIDOR_MARGIN
const RESPONSE_BASE_X_MIN: float = MAP_MIN + 28.0
const RESPONSE_BASE_X_MAX: float = MAP_MAX - 28.0

# ---------------------------------------------------------------------------
# REFERENCES
# ---------------------------------------------------------------------------

var city: MetroCity = null
var disaster: Node = null

# ---------------------------------------------------------------------------
# STATE
# ---------------------------------------------------------------------------

var drones: Array = []
var demo_started: bool = false

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var grid_cells: Array = []
var grid_root: Node3D = null
var label_root: Node3D = null

var next_scout_scan_time: float = 0.0
var victim_counter: int = 100
var mission_sequence: int = 0

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------

func setup(p_city: MetroCity) -> void:
	city = p_city

	disaster = get_parent().get_node_or_null("DisasterEngine")
	if disaster == null:
		disaster = get_parent().get_node_or_null("Disaster")

	rng.seed = 20260905

	_build_search_grid()
	_spawn_fleet()

	drone_event.emit(
		"FLEET INITIALIZED | 31 UAVS | 16 SCOUT | 5 MEDICAL | 5 HEAVY-LIFT | 5 RESCUE"
	)

# ---------------------------------------------------------------------------
# START
# ---------------------------------------------------------------------------

func start_demo() -> void:
	demo_started = true
	next_scout_scan_time = 0.0

	for d in drones:
		var kind: String = str(d.get("type", ""))

		if kind == "SCOUT":
			d["phase"] = 1
			d["mission"] = "GRID_SEARCH"
			d["external_control"] = false
			d["backend_status"] = "EN_ROUTE"
		else:
			d["phase"] = 0
			d["mission"] = "STANDBY"
			d["external_control"] = false
			d["backend_status"] = "IDLE"

	drone_event.emit(
		"FLEET DEPLOYMENT | 16 SCOUT CORRIDORS ACTIVE"
	)
	drone_event.emit(
		"SEARCH DOCTRINE | FIXED X | Z-AXIS ONLY | SOUTH <-> NORTH"
	)

# ---------------------------------------------------------------------------
# FLEET CREATION
# ---------------------------------------------------------------------------

func _spawn_fleet() -> void:
	drones.clear()

	for i in range(SCOUT_COUNT):
		var corridor_x: float = _scout_x(i)
		var start_z: float

		if i % 2 == 0:
			start_z = MAP_MAX - CORRIDOR_MARGIN
		else:
			start_z = MAP_MIN + CORRIDOR_MARGIN

		var start_position: Vector3 = Vector3(
			corridor_x,
			SCOUT_ALTITUDE,
			start_z
		)

		var extra: Dictionary = {
			"corridor_index": i,
			"corridor_id": "L%02d" % (i + 1),
			"corridor_x": corridor_x,
			"search_direction": -1 if i % 2 == 0 else 1,
			"search_axis": "Z",
			"east_west_allowed": false
		}

		_spawn_drone(
			"DRONE-S%02d" % (i + 1),
			"SCOUT",
			start_position,
			extra
		)

	for i in range(1, MEDICAL_COUNT + 1):
		_spawn_drone(
			"DRONE-M%02d" % i,
			"MEDICAL",
			_base_slot(i, 0),
			{"base_slot": i, "response_capability": "MEDICAL"}
		)

	for i in range(1, HEAVY_LIFT_COUNT + 1):
		_spawn_drone(
			"DRONE-H%02d" % i,
			"HEAVY LIFT",
			_base_slot(i, 1),
			{"base_slot": i, "response_capability": "HEAVY_LIFT"}
		)

	for i in range(1, RESCUE_COUNT + 1):
		_spawn_drone(
			"DRONE-R%02d" % i,
			"RESCUE",
			_base_slot(i, 2),
			{"base_slot": i, "response_capability": "RESCUE"}
		)

	drone_event.emit(
		"RESPONSE STAGING | 15 STANDBY UAVS PARKED ON SOUTH X-AXIS LAUNCH LINE"
	)

func _scout_x(index: int) -> float:
	if SCOUT_COUNT <= 1:
		return 0.0

	return lerpf(
		MAP_MIN + CORRIDOR_MARGIN,
		MAP_MAX - CORRIDOR_MARGIN,
		float(index) / float(SCOUT_COUNT - 1)
	)

func _base_slot(index: int, row: int) -> Vector3:
	# All 15 response drones are staged on one dedicated X-axis line at the
	# southern starting edge of the map. The row is intentionally ignored so
	# medical, heavy-lift and rescue aircraft share the same launch axis rather
	# than forming three groups in the middle of the city.
	var total_response: int = MEDICAL_COUNT + HEAVY_LIFT_COUNT + RESCUE_COUNT
	var slot_index: int = row * MEDICAL_COUNT + (index - 1)
	var t: float = 0.0

	if total_response > 1:
		t = float(slot_index) / float(total_response - 1)

	var x: float = lerpf(RESPONSE_BASE_X_MIN, RESPONSE_BASE_X_MAX, t)

	return Vector3(
		x,
		RESPONSE_ALTITUDE,
		RESPONSE_BASE_Z
	)

func _spawn_drone(
	id: String,
	kind: String,
	p: Vector3,
	extra: Dictionary
) -> void:
	var root: Node3D = Node3D.new()
	root.name = id
	root.position = _clamp_map_position(p, p.y)
	root.set_meta("simulation_id", id)

	# Body
	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(3.6, 0.8, 3.6)
	body.mesh = box
	body.material_override = _mat(_drone_color(kind), 0.4)
	root.add_child(body)

	# Four arms and rotors
	for side_value in [-1.0, 1.0]:
		var side: float = float(side_value)

		for front_value in [-1.0, 1.0]:
			var front: float = float(front_value)

			var arm: MeshInstance3D = MeshInstance3D.new()
			var arm_mesh: CylinderMesh = CylinderMesh.new()
			arm_mesh.top_radius = 0.12
			arm_mesh.bottom_radius = 0.12
			arm_mesh.height = 2.8
			arm.mesh = arm_mesh
			arm.rotation_degrees = Vector3(0.0, 45.0, 90.0)
			arm.position = Vector3(side * 2.0, 0.0, front * 2.0)
			root.add_child(arm)

			var rotor: MeshInstance3D = MeshInstance3D.new()
			var rotor_mesh: CylinderMesh = CylinderMesh.new()
			rotor_mesh.top_radius = 0.75
			rotor_mesh.bottom_radius = 0.75
			rotor_mesh.height = 0.08
			rotor.mesh = rotor_mesh
			rotor.position = Vector3(side * 2.0, 0.5, front * 2.0)
			rotor.material_override = _mat(Color(0.04, 0.05, 0.06), 0.25)
			root.add_child(rotor)

	add_child(root)

	var initial_mission: String = "IDLE"
	if kind != "SCOUT":
		initial_mission = "STANDBY"

	var d: Dictionary = {
		"id": id,
		"type": kind,
		"node": root,
		"home": root.position,
		"target": root.position,
		"phase": 0,
		"battery": 100.0,
		"velocity": Vector3.ZERO,
		"mission": initial_mission,
		"external_control": false,
		"backend_status": "IDLE",
		"mission_id": "",
		"target_victim_id": "",
		"response_action": "",
		"waypoints": [],
		"waypoint_index": 0,
		"response_stage": "",
		"on_site_elapsed": 0.0,
		"last_response_result": {}
	}

	for key in extra.keys():
		d[key] = extra[key]

	drones.append(d)

# ---------------------------------------------------------------------------
# VISUALS
# ---------------------------------------------------------------------------

func _drone_color(kind: String) -> Color:
	if kind == "SCOUT":
		return Color(0.08, 0.75, 0.95)
	if kind == "MEDICAL":
		return Color(0.15, 0.90, 0.45)
	if kind == "HEAVY LIFT":
		return Color(0.95, 0.60, 0.10)
	if kind == "RESCUE":
		return Color(0.95, 0.20, 0.25)

	return Color(0.45, 0.45, 0.48)

func _build_search_grid() -> void:
	if is_instance_valid(grid_root):
		grid_root.queue_free()

	if is_instance_valid(label_root):
		label_root.queue_free()

	grid_cells.clear()

	grid_root = Node3D.new()
	grid_root.name = "SEARCH-CORRIDORS-16"
	add_child(grid_root)

	label_root = Node3D.new()
	label_root.name = "SEARCH-CORRIDOR-LABELS"
	add_child(label_root)

	for index in range(SCOUT_COUNT):
		var corridor_x: float = _scout_x(index)
		var drone_id: String = "DRONE-S%02d" % (index + 1)
		var corridor_id: String = "L%02d" % (index + 1)

		grid_cells.append({
			"cell": index,
			"id": corridor_id,
			"name": corridor_id,
			"owner_drone_id": drone_id,
			"drone_id": drone_id,
			"min_x": corridor_x,
			"max_x": corridor_x,
			"min_z": MAP_MIN,
			"max_z": MAP_MAX,
			"corridor_x": corridor_x,
			"movement_axis": "Z",
			"search_direction": "SOUTH_NORTH_NORTH_SOUTH",
			"east_west_allowed": false
		})

		_add_corridor_line(corridor_x, index)
		_add_grid_label(
			corridor_id,
			Vector3(
				corridor_x,
				SCOUT_ALTITUDE + 3.0,
				MAP_MIN + 18.0
			)
		)

func _add_corridor_line(x: float, index: int) -> void:
	var line: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()

	mesh.size = Vector3(
		0.28,
		0.14,
		MAP_MAX - MAP_MIN
	)

	line.mesh = mesh
	line.position = Vector3(x, SCOUT_ALTITUDE - 1.0, 0.0)

	var alpha: float = 0.28
	if index % 2 != 0:
		alpha = 0.18

	line.material_override = _mat(
		Color(0.05, 0.75, 0.95, alpha),
		0.45
	)

	grid_root.add_child(line)

func _add_grid_label(text: String, p: Vector3) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = 32
	label.outline_size = 6
	label.modulate = Color(0.35, 0.95, 1.0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = p
	label_root.add_child(label)

# ---------------------------------------------------------------------------
# RESET
# ---------------------------------------------------------------------------

func reset_fleet() -> void:
	demo_started = false
	next_scout_scan_time = 0.0
	victim_counter = 100

	for i in range(SCOUT_COUNT):
		var drone_id: String = "DRONE-S%02d" % (i + 1)

		for d in drones:
			if str(d.get("id", "")) != drone_id:
				continue

			var node: Node3D = d["node"] as Node3D
			var start_z: float

			if i % 2 == 0:
				start_z = MAP_MAX - CORRIDOR_MARGIN
			else:
				start_z = MAP_MIN + CORRIDOR_MARGIN

			node.position = Vector3(
				_scout_x(i),
				SCOUT_ALTITUDE,
				start_z
			)

			d["corridor_x"] = _scout_x(i)
			d["search_direction"] = -1 if i % 2 == 0 else 1
			_reset_drone_state(d, "IDLE")
			break

	for d in drones:
		if str(d.get("type", "")) == "SCOUT":
			continue

		var response_node: Node3D = d["node"] as Node3D
		response_node.position = d["home"] as Vector3
		_reset_drone_state(d, "STANDBY")

	drone_event.emit(
		"FLEET RESET | 31 UAVS RETURNED TO INITIAL POSITIONS"
	)

func _reset_drone_state(d: Dictionary, mission_name: String) -> void:
	d["external_control"] = false
	d["mission"] = mission_name
	d["backend_status"] = "IDLE"
	d["mission_id"] = ""
	d["target_victim_id"] = ""
	d["response_action"] = ""
	d["response_stage"] = ""
	d["waypoints"] = []
	d["waypoint_index"] = 0
	d["battery"] = 100.0
	d["velocity"] = Vector3.ZERO
	d["on_site_elapsed"] = 0.0
	d["last_response_result"] = {}

# ---------------------------------------------------------------------------
# SYSTEM-A COMMAND EXECUTION
# ---------------------------------------------------------------------------

func execute_resqnet_command(command: Dictionary) -> Dictionary:
	var command_type: String = str(command.get("command", "")).to_upper()
	var drone_id: String = str(command.get("drone_id", ""))

	var selected: Dictionary = {}

	for d in drones:
		if str(d.get("id", "")) == drone_id:
			selected = d
			break

	if selected.is_empty():
		return {
			"accepted": false,
			"reason": "Drone %s is not present in the Digital Twin." % drone_id
		}

	var node: Node3D = selected["node"] as Node3D
	if node == null or not is_instance_valid(node):
		return {
			"accepted": false,
			"reason": "Drone node is unavailable."
		}

	var constraints: Dictionary = {}
	var constraints_value: Variant = command.get("constraints", {})
	if constraints_value is Dictionary:
		constraints = constraints_value as Dictionary

	var response_action: String = str(
		constraints.get("response_action", "")
	).to_upper()

	var mission_id: String = str(
		constraints.get("mission_id", command.get("mission_id", ""))
	)

	var victim_id: String = str(
		command.get(
			"target_victim_id",
			constraints.get("target_victim_id", "")
		)
	)

	if command_type == "ABORT":
		selected["external_control"] = true
		selected["mission"] = "RETURN_TO_BASE"
		selected["backend_status"] = "RETURNING"
		selected["target"] = selected["home"]
		selected["response_stage"] = "RETURNING"

		drone_event.emit(
			"COMMAND EXECUTED | %s | ABORT -> RETURN TO BASE" % drone_id
		)

		return {
			"accepted": true,
			"reason": "Mission aborted; aircraft returning to base."
		}

	if command_type == "RETURN_TO_BASE" or command_type == "LAND":
		selected["external_control"] = true
		selected["mission"] = "RETURN_TO_BASE"
		selected["backend_status"] = "RETURNING"
		selected["target"] = selected["home"]
		selected["response_stage"] = "RETURNING"

		return {
			"accepted": true,
			"reason": "Drone returning to base."
		}

	var movement_command: bool = false
	if command_type == "TAKEOFF":
		movement_command = true
	elif command_type == "NAVIGATE":
		movement_command = true
	elif command_type == "SURVEY":
		movement_command = true
	elif command_type == "DELIVER_SUPPLIES":
		movement_command = true
	elif command_type == "HOVER":
		movement_command = true

	if not movement_command:
		return {
			"accepted": false,
			"reason": "Unsupported command type %s." % command_type
		}

	if not response_action.is_empty():
		if victim_id.is_empty():
			return {
				"accepted": false,
				"reason": "Response command has no target victim ID."
			}

		if not _is_response_drone_for_action(selected, response_action):
			return {
				"accepted": false,
				"reason": "Drone %s cannot perform %s." % [
					drone_id,
					response_action
				]
			}

	var waypoints: Array = []
	var waypoints_value: Variant = command.get("waypoints", [])

	if waypoints_value is Array:
		waypoints = waypoints_value as Array

	# If System-A sends a response command without waypoints, derive the
	# target directly from the authoritative Digital Twin victim node.
	if waypoints.is_empty() and not victim_id.is_empty() and disaster != null:
		if disaster.has_method("get_victim_by_resq_id"):
			var target_victim: Variant = disaster.call(
				"get_victim_by_resq_id",
				victim_id
			)

			if target_victim is Node3D:
				var victim_node: Node3D = target_victim as Node3D
				if is_instance_valid(victim_node):
					waypoints = [{
						"position": {
							"x": victim_node.global_position.x,
							"y": RESPONSE_ALTITUDE,
							"z": victim_node.global_position.z
						}
					}]

	if waypoints.is_empty():
		return {
			"accepted": false,
			"reason": "Command contains no waypoint."
		}

	selected["external_control"] = true
	selected["mission"] = response_action if not response_action.is_empty() else command_type
	selected["backend_status"] = "EN_ROUTE"
	selected["mission_id"] = mission_id
	selected["target_victim_id"] = victim_id
	selected["response_action"] = response_action
	selected["waypoints"] = waypoints
	selected["waypoint_index"] = 0
	selected["on_site_elapsed"] = 0.0

	if response_action.is_empty():
		selected["response_stage"] = "COMMAND"
	else:
		selected["response_stage"] = "EN_ROUTE"

	var target_position: Vector3 = _extract_waypoint_position(
		waypoints[0],
		RESPONSE_ALTITUDE
	)

	selected["target"] = target_position

	drone_event.emit(
		"COMMAND EXECUTED | %s | %s | TARGET %s" % [
			drone_id,
			selected["mission"],
			victim_id if not victim_id.is_empty() else "MISSION"
		]
	)

	return {
		"accepted": true,
		"reason": "Command accepted by authoritative Digital Twin."
	}

# ---------------------------------------------------------------------------
# RESPONSE CAPABILITY
# ---------------------------------------------------------------------------

func _is_response_drone_for_action(
	d: Dictionary,
	action: String
) -> bool:
	var kind: String = str(d.get("type", ""))

	if action == "RESCUE_EXTRACTION" or action == "RESCUE_TRIAGE":
		return kind == "RESCUE"

	if action == "MEDICAL_SUPPLY_DROP":
		return kind == "MEDICAL"

	if action == "HEAVY_EXTRICATION":
		return kind == "HEAVY LIFT"

	return false

# ---------------------------------------------------------------------------
# FRAME LOOP
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	for d in drones:
		var node: Node3D = d["node"] as Node3D

		if node == null or not is_instance_valid(node):
			continue

		var kind: String = str(d.get("type", ""))
		var external_control: bool = bool(d.get("external_control", false))

		if demo_started and kind == "SCOUT" and not external_control:
			_process_scout(d, delta)
		elif external_control:
			_process_response_drone(d, delta)

		if demo_started and (kind == "SCOUT" or external_control):
			var drain: float = 0.10
			if kind != "SCOUT":
				drain = 0.18

			d["battery"] = maxf(
				0.0,
				float(d.get("battery", 100.0)) - delta * drain
			)

	if demo_started:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now >= next_scout_scan_time:
			next_scout_scan_time = now + 0.35
			_scan_active_scouts()

# ---------------------------------------------------------------------------
# SCOUT MOVEMENT — FIXED X / Z ONLY
# ---------------------------------------------------------------------------

func _process_scout(d: Dictionary, delta: float) -> void:
	var node: Node3D = d["node"] as Node3D
	var corridor_x: float = float(d.get("corridor_x", node.position.x))
	var direction: int = int(d.get("search_direction", -1))

	var north_z: float = MAP_MIN + CORRIDOR_MARGIN
	var south_z: float = MAP_MAX - CORRIDOR_MARGIN

	var target_z: float = north_z
	if direction > 0:
		target_z = south_z

	if absf(target_z - node.position.z) <= 1.5:
		direction = -direction
		d["search_direction"] = direction

		if direction < 0:
			target_z = north_z
		else:
			target_z = south_z

	var next_z: float = move_toward(
		node.position.z,
		target_z,
		SCOUT_SPEED * delta
	)

	node.position = Vector3(
		corridor_x,
		SCOUT_ALTITUDE,
		clampf(next_z, north_z, south_z)
	)

	d["target"] = Vector3(
		corridor_x,
		SCOUT_ALTITUDE,
		target_z
	)

	d["velocity"] = Vector3(
		0.0,
		0.0,
		float(direction) * SCOUT_SPEED
	)

	if direction < 0:
		node.rotation.y = 0.0
	else:
		node.rotation.y = PI

# ---------------------------------------------------------------------------
# RESPONSE MOVEMENT
# ---------------------------------------------------------------------------

func _process_response_drone(d: Dictionary, delta: float) -> void:
	var node: Node3D = d["node"] as Node3D
	var stage: String = str(d.get("response_stage", "EN_ROUTE"))

	if stage == "RETURNING":
		var home: Vector3 = d["home"] as Vector3
		_move_node_to(d, home, RESPONSE_SPEED, delta)

		if node.position.distance_to(home) < 2.0:
			d["external_control"] = false
			d["mission"] = "STANDBY"
			d["backend_status"] = "IDLE"
			d["mission_id"] = ""
			d["target_victim_id"] = ""
			d["response_action"] = ""
			d["response_stage"] = ""
			d["waypoints"] = []
			d["waypoint_index"] = 0
			d["velocity"] = Vector3.ZERO

			response_event.emit({
				"event": "DRONE_RETURNED",
				"drone_id": d["id"]
			})

		return

	var waypoints: Array = d.get("waypoints", [])
	var waypoint_index: int = int(d.get("waypoint_index", 0))

	if waypoint_index < waypoints.size():
		var target: Vector3 = _extract_waypoint_position(
			waypoints[waypoint_index],
			RESPONSE_ALTITUDE
		)

		d["target"] = target
		_move_node_to(d, target, RESPONSE_SPEED, delta)

		if node.position.distance_to(target) < 2.5:
			d["waypoint_index"] = waypoint_index + 1
	else:
		_perform_response_action(d, delta)

func _move_node_to(
	d: Dictionary,
	target: Vector3,
	speed: float,
	delta: float
) -> void:
	var node: Node3D = d["node"] as Node3D
	var safe_target: Vector3 = _clamp_map_position(target, target.y)
	var delta_vector: Vector3 = safe_target - node.position

	if delta_vector.length() < 0.1:
		d["velocity"] = Vector3.ZERO
		return

	var velocity: Vector3 = delta_vector.normalized() * speed
	var next_position: Vector3 = node.position + velocity * delta
	next_position = _clamp_map_position(next_position, next_position.y)

	node.position = next_position
	d["velocity"] = velocity

	if velocity.length() > 0.01:
		node.look_at(node.position + velocity, Vector3.UP)

# ---------------------------------------------------------------------------
# WAYPOINT PARSER
# ---------------------------------------------------------------------------

func _extract_waypoint_position(
	waypoint_value: Variant,
	default_y: float
) -> Vector3:
	var position_data: Dictionary = {}

	if waypoint_value is Dictionary:
		var waypoint: Dictionary = waypoint_value as Dictionary
		var position_value: Variant = waypoint.get("position", {})

		if position_value is Dictionary:
			position_data = position_value as Dictionary

	var x: float = float(position_data.get("x", 0.0))
	var y: float = float(position_data.get("y", default_y))
	var z: float = float(position_data.get("z", 0.0))

	return _clamp_map_position(
		Vector3(x, y, z),
		default_y
	)

# ---------------------------------------------------------------------------
# RESPONSE ACTION
# ---------------------------------------------------------------------------

func _perform_response_action(
	d: Dictionary,
	delta: float
) -> void:
	var victim_id: String = str(d.get("target_victim_id", ""))

	if victim_id.is_empty() or disaster == null:
		_finish_response(d, false, "No victim target available")
		return

	if not disaster.has_method("get_victim_by_resq_id"):
		_finish_response(
			d,
			false,
			"Disaster engine victim registry unavailable"
		)
		return

	var victim_value: Variant = disaster.call(
		"get_victim_by_resq_id",
		victim_id
	)

	if not victim_value is Node3D:
		_finish_response(
			d,
			false,
			"Victim no longer exists in Digital Twin"
		)
		return

	var victim: Node3D = victim_value as Node3D

	if not is_instance_valid(victim):
		_finish_response(
			d,
			false,
			"Victim node is invalid"
		)
		return

	var stage: String = str(d.get("response_stage", "EN_ROUTE"))
	var action: String = str(d.get("response_action", "")).to_upper()

	if stage == "EN_ROUTE":
		d["response_stage"] = "ON_SITE"
		d["on_site_elapsed"] = 0.0

		response_event.emit({
			"event": "RESPONSE_ON_SITE",
			"drone_id": d["id"],
			"victim_id": victim_id,
			"action": action,
			"position": {
				"x": victim.global_position.x,
				"y": victim.global_position.y,
				"z": victim.global_position.z
			}
		})

		return

	d["on_site_elapsed"] = (
		float(d.get("on_site_elapsed", 0.0)) + delta
	)

	var hover_height: float = 22.0

	if action == "RESCUE_EXTRACTION" or action == "RESCUE_TRIAGE":
		hover_height = 28.0
	elif action == "HEAVY_EXTRICATION":
		hover_height = 32.0

	var hover_position: Vector3 = (
		victim.global_position + Vector3.UP * hover_height
	)

	_move_node_to(
		d,
		hover_position,
		RESPONSE_SPEED,
		delta
	)

	if action == "RESCUE_EXTRACTION" or action == "RESCUE_TRIAGE":
		victim.position.y = minf(
			12.0,
			victim.position.y + delta * 2.2
		)

	if float(d["on_site_elapsed"]) < RESPONSE_ON_SITE_TIME:
		return

	var result: Dictionary = {}

	if disaster.has_method("apply_response_action"):
		var result_value: Variant = disaster.call(
			"apply_response_action",
			victim_id,
			action
		)

		if result_value is Dictionary:
			result = result_value as Dictionary

	var success: bool = bool(result.get("success", false))
	var message: String = str(
		result.get("message", "Response completed")
	)

	_finish_response(
		d,
		success,
		message,
		result
	)

# ---------------------------------------------------------------------------
# RESPONSE FINISH
# ---------------------------------------------------------------------------

func _finish_response(
	d: Dictionary,
	success: bool,
	message: String,
	result: Dictionary = {}
) -> void:
	var drone_id: String = str(d.get("id", ""))
	var victim_id: String = str(d.get("target_victim_id", ""))
	var mission_id: String = str(d.get("mission_id", ""))
	var action: String = str(d.get("response_action", ""))

	d["last_response_result"] = result

	var event_name: String = "RESPONSE_FAILED"
	if success:
		event_name = "RESPONSE_COMPLETED"

	response_event.emit({
		"event": event_name,
		"drone_id": drone_id,
		"victim_id": victim_id,
		"mission_id": mission_id,
		"action": action,
		"success": success,
		"message": message,
		"result": result
	})

	drone_event.emit(
		"RESPONSE | %s | %s | %s" % [
			drone_id,
			action,
			"COMPLETED" if success else "FAILED"
		]
	)

	d["mission"] = "RETURN_TO_BASE"
	d["backend_status"] = "RETURNING"
	d["response_stage"] = "RETURNING"
	d["target"] = d["home"]

# ---------------------------------------------------------------------------
# VICTIM SEARCH
# ---------------------------------------------------------------------------

func _scan_active_scouts() -> void:
	if disaster == null:
		return

	if not disaster.has_method("get_searchable_victims"):
		return

	var searchable_value: Variant = disaster.call(
		"get_searchable_victims"
	)

	if not searchable_value is Array:
		return

	var searchable: Array = searchable_value as Array

	for d in drones:
		if str(d.get("type", "")) != "SCOUT":
			continue

		if str(d.get("mission", "")) != "GRID_SEARCH":
			continue

		var node: Node3D = d["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue

		var corridor_x: float = float(
			d.get("corridor_x", node.position.x)
		)

		for victim_value in searchable:
			if not victim_value is Node3D:
				continue

			var victim: Node3D = victim_value as Node3D
			if victim == null or not is_instance_valid(victim):
				continue

			if bool(victim.get_meta("resqnet_detected", false)):
				continue

			# Detection is based on the scout's fixed X corridor and
			# actual Z proximity. The scout never changes X.
			var lateral_distance: float = absf(
				victim.global_position.x - corridor_x
			)

			if lateral_distance > SCOUT_SENSOR_RADIUS:
				continue

			var horizontal_distance: float = Vector2(
				victim.global_position.x - node.global_position.x,
				victim.global_position.z - node.global_position.z
			).length()

			if horizontal_distance > SCOUT_SENSOR_RADIUS:
				continue

			_detect_victim(d, victim)

# ---------------------------------------------------------------------------
# VICTIM DETECTION
# ---------------------------------------------------------------------------

func _detect_victim(
	d: Dictionary,
	victim: Node3D
) -> void:
	victim.set_meta("resqnet_detected", true)

	victim_counter += 1

	var victim_id: String = "VIC-%03d" % victim_counter
	victim.set_meta("resqnet_victim_id", victim_id)

	var hazard: String = str(
		victim.get_meta("cause", "EXPOSED")
	).to_upper()

	if hazard.is_empty():
		hazard = "EXPOSED"

	var hazard_info: Dictionary = _get_nearest_hazard(
		victim.global_position
	)

	drone_event.emit(
		"SEARCH CONTACT | %s | %s | %s" % [
			d["id"],
			victim_id,
			hazard
		]
	)

	_capture_and_emit_victim_evidence(
		d,
		victim,
		victim_id,
		hazard,
		hazard_info
	)

# ---------------------------------------------------------------------------
# VICTIM EVIDENCE
# ---------------------------------------------------------------------------

func _capture_and_emit_victim_evidence(
	d: Dictionary,
	victim: Node3D,
	victim_id: String,
	hazard: String,
	hazard_info: Dictionary
) -> void:
	var drone_node: Node3D = d["node"] as Node3D

	var image_base64: String = await _capture_victim_camera(
		drone_node,
		victim
	)

	var data: Dictionary = {
		"victim_id": victim_id,
		"hazard_type": hazard,
		"hazard": hazard_info,
		"location": {
			"x": victim.global_position.x,
			"y": victim.global_position.y,
			"z": victim.global_position.z
		},
		"drone_id": d["id"],
		"confidence": 0.97,
		"image_base64": image_base64,
		"image_mime_type": "image/jpeg",
		"capture_type": "GODOT_DIGITAL_TWIN_DRONE_CAMERA",
		"captured_at": Time.get_unix_time_from_system()
	}

	victim_detected.emit(data)

# ---------------------------------------------------------------------------
# HAZARD CONTEXT
# ---------------------------------------------------------------------------

func _get_nearest_hazard(position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF

	if disaster == null:
		return best

	# Fire
	var fires_value: Variant = disaster.get("fires")

	if fires_value is Array:
		var fire_array: Array = fires_value as Array

		for fire_value in fire_array:
			if not fire_value is Node3D:
				continue

			var fire: Node3D = fire_value as Node3D
			if fire == null or not is_instance_valid(fire):
				continue

			var fire_distance: float = (
				fire.global_position.distance_to(position)
			)

			if fire_distance < best_distance:
				best_distance = fire_distance
				best = {
					"type": "FIRE",
					"distance_m": fire_distance,
					"position": {
						"x": fire.global_position.x,
						"y": fire.global_position.y,
						"z": fire.global_position.z
					}
				}

	# Flood
	var flood_value: Variant = disaster.get("flood_active")
	var flood_active: bool = false

	if flood_value != null:
		flood_active = bool(flood_value)

	if flood_active:
		var flood_front_value: Variant = disaster.get("flood_front_z")
		var flood_z: float = MAP_MAX

		if flood_front_value != null:
			flood_z = float(flood_front_value)

		var flood_distance: float = absf(position.z - flood_z)

		if flood_distance < best_distance:
			best_distance = flood_distance
			best = {
				"type": "FLOOD",
				"distance_m": flood_distance,
				"position": {
					"x": position.x,
					"y": 0.0,
					"z": flood_z
				}
			}

	# Earthquake
	var disaster_type_value: Variant = disaster.get("disaster_type")
	var disaster_type: String = ""

	if disaster_type_value != null:
		disaster_type = str(disaster_type_value).to_upper()

	if disaster_type == "EARTHQUAKE":
		var quake_value: Variant = disaster.get(
			"current_disaster_position"
		)

		var quake_position: Vector3 = Vector3.ZERO

		if quake_value is Vector3:
			quake_position = quake_value as Vector3

		var quake_distance: float = (
			position.distance_to(quake_position)
		)

		if quake_distance < best_distance:
			best_distance = quake_distance
			best = {
				"type": "EARTHQUAKE",
				"distance_m": quake_distance,
				"position": {
					"x": quake_position.x,
					"y": quake_position.y,
					"z": quake_position.z
				}
			}

	return best

# ---------------------------------------------------------------------------
# PUBLIC EVIDENCE API
# ---------------------------------------------------------------------------

func capture_victim_evidence(
	victim: Node3D,
	victim_id: String,
	drone_id: String
) -> Dictionary:
	if victim == null or not is_instance_valid(victim):
		return {
			"success": false,
			"message": "Victim node unavailable."
	}

	var selected: Dictionary = {}

	for d in drones:
		if str(d.get("id", "")) == drone_id:
			selected = d
			break

	if selected.is_empty():
		return {
			"success": false,
			"message": "Drone %s unavailable." % drone_id
		}

	var drone_node: Node3D = selected["node"] as Node3D
	var image_base64: String = await _capture_victim_camera(
		drone_node,
		victim
	)

	return {
		"success": not image_base64.is_empty(),
		"victim_id": victim_id,
		"drone_id": drone_id,
		"image_base64": image_base64,
		"image_mime_type": "image/jpeg",
		"capture_type": "GODOT_DIGITAL_TWIN_DRONE_CAMERA",
		"captured_at": Time.get_unix_time_from_system()
	}

func capture_victim_image(
	victim: Node3D,
	victim_id: String,
	drone_id: String
) -> Dictionary:
	return await capture_victim_evidence(
		victim,
		victim_id,
		drone_id
	)

func capture_evidence(
	victim: Node3D,
	victim_id: String,
	drone_id: String
) -> Dictionary:
	return await capture_victim_evidence(
		victim,
		victim_id,
		drone_id
	)

# ---------------------------------------------------------------------------
# GODOT CAMERA EVIDENCE CAPTURE
# ---------------------------------------------------------------------------

func _capture_victim_camera(
	drone_node: Node3D,
	victim: Node3D
) -> String:
	if drone_node == null or victim == null:
		return ""

	if not is_instance_valid(drone_node):
		return ""

	if not is_instance_valid(victim):
		return ""

	var viewport: SubViewport = SubViewport.new()
	viewport.name = "EvidenceViewport_%d" % Time.get_ticks_msec()
	viewport.size = Vector2i(480, 320)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var current_viewport: Viewport = get_viewport()

	if current_viewport != null:
		viewport.world_3d = current_viewport.world_3d

	add_child(viewport)

	var camera: Camera3D = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.5
	camera.far = 1200.0
	camera.current = true
	camera.position = drone_node.global_position

	viewport.add_child(camera)

	camera.look_at(
		victim.global_position + Vector3(0.0, 2.8, 0.0),
		Vector3.UP
	)

	await get_tree().process_frame
	await get_tree().process_frame

	var image: Image = viewport.get_texture().get_image()

	if image == null:
		viewport.queue_free()
		return ""

	image.resize(
		480,
		320,
		Image.INTERPOLATE_LANCZOS
	)

	var bytes: PackedByteArray = image.save_jpg_to_buffer(0.86)

	viewport.queue_free()

	return Marshalls.raw_to_base64(bytes)

# ---------------------------------------------------------------------------
# GRID / CORRIDOR API
# ---------------------------------------------------------------------------

func get_grid_cells() -> Array:
	return grid_cells.duplicate(true)

func get_search_grid_metadata() -> Dictionary:
	return {
		"rows": 1,
		"cols": 16,
		"cell_size_m": 0.0,
		"map_min": MAP_MIN,
		"map_max": MAP_MAX,
		"scout_count": SCOUT_COUNT,
		"corridors": SCOUT_COUNT,
		"movement_axis": "Z",
		"direction": "SOUTH_NORTH_NORTH_SOUTH",
		"north_south_only_scout_search": true,
		"east_west_allowed": false,
		"geometry": "16_FIXED_X_VERTICAL_SEARCH_CORRIDORS"
	}

# ---------------------------------------------------------------------------
# FLEET STATE API
# ---------------------------------------------------------------------------

func get_fleet_state() -> Array:
	var state: Array = []

	for d in drones:
		var node: Node3D = d["node"] as Node3D

		if node == null or not is_instance_valid(node):
			continue

		var velocity: Vector3 = d.get(
			"velocity",
			Vector3.ZERO
		) as Vector3

		state.append({
			"id": str(d.get("id", "")),
			"type": str(d.get("type", "")),
			"position": {
				"x": node.global_position.x,
				"y": node.global_position.y,
				"z": node.global_position.z
			},
			"battery": float(d.get("battery", 100.0)),
			"velocity": {
				"x": velocity.x,
				"y": velocity.y,
				"z": velocity.z
			},
			"mission": str(d.get("mission", "IDLE")),
			"backend_status": str(d.get("backend_status", "IDLE")),
			"target_victim_id": str(d.get("target_victim_id", "")),
			"corridor_id": str(d.get("corridor_id", "")),
			"corridor_x": float(
				d.get("corridor_x", node.position.x)
			),
			"search_axis": str(d.get("search_axis", "")),
			"search_direction": int(
				d.get("search_direction", 0)
			),
			"response_action": str(
				d.get("response_action", "")
			),
			"mission_id": str(
				d.get("mission_id", "")
			)
		})

	return state

# ---------------------------------------------------------------------------
# BOUNDARIES
# ---------------------------------------------------------------------------

func _clamp_map_position(
	p: Vector3,
	forced_y: float
) -> Vector3:
	return Vector3(
		clampf(
			p.x,
			MAP_MIN + 2.0,
			MAP_MAX - 2.0
		),
		clampf(
			forced_y,
			MAP_MIN_Y,
			MAP_MAX_Y
		),
		clampf(
			p.z,
			MAP_MIN + 2.0,
			MAP_MAX - 2.0
		)
	)

# ---------------------------------------------------------------------------
# MATERIAL
# ---------------------------------------------------------------------------

func _mat(
	c: Color,
	roughness: float = 0.8,
	metallic: float = 0.0
) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = c
	material.roughness = roughness
	material.metallic = metallic
	return material
