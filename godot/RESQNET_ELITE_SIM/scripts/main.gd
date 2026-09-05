extends Node3D

# ============================================================
# RESQNET — SYSTEM B
# METRO DISASTER TWIN
# Main Simulation Controller
# Godot 4.7+
#
# SYSTEM B RESPONSIBILITIES
# ------------------------------------------------------------
# • Digital Twin / City Simulation
# • Disaster Simulation
# • Drone Fleet Simulation
# • Victim Intelligence
# • Event Feed
# • System A Connection State
# • Remote Command Hooks
# • Operator Controls
#
# IMPORTANT
# ------------------------------------------------------------
# This script preserves the existing:
# MetroCity
# DisasterController
# DroneFleet
# TrafficSystem
# RoadGraph
#
# architecture.
# ============================================================


# ============================================================
# SYSTEM REFERENCES
# ============================================================

var city: Node = null
var disaster: Node = null
var fleet: Node = null
var traffic: Node = null


# ============================================================
# CAMERA
# ============================================================

var cam: Camera3D = null
var camera_root: Node3D = null

var strategic: bool = true
var paused: bool = false


# ============================================================
# SIMULATION
# ============================================================

var sim_time: float = 0.0
var sim_scale: float = 1.0

var demo_started: bool = false


# ============================================================
# SYSTEM A CONNECTION
# ============================================================

var system_a_connected: bool = false
var system_a_status: String = "DISCONNECTED"

# This can be assigned by the WebSocket/client layer later.
var system_a_client: Node = null


# ============================================================
# EVENT FEED
# ============================================================

var event_lines: Array[String] = []


# ============================================================
# VICTIM INTELLIGENCE
# ============================================================
#
# Every victim is represented using:
#
# {
#   "victim_id": "V001",
#   "hazard_type": "FIRE",
#   "location": Vector3(...),
#   "image": "",
#   "captured_by": "D03",
#   "priority": "HIGH",
#   "severity": "CRITICAL",
#   "status": "DETECTED",
#   "timestamp": 0.0
# }
#
# ============================================================

var victim_intelligence: Array[Dictionary] = []

var victim_counter: int = 0

var selected_victim_id: String = ""


# ============================================================
# UI REFERENCES
# ============================================================

var clock_label: Label = null
var stats_label: Label = null
var event_label: Label = null
var connection_label: Label = null
var mode_label: Label = null
var disaster_label: Label = null
var control_panel: PanelContainer = null

var victim_panel: PanelContainer = null
var victim_list_label: Label = null
var victim_detail_label: Label = null


# ============================================================
# LIFECYCLE
# ============================================================

func _ready() -> void:

	_build_environment()
	_build_city()
	_build_camera()
	_build_ui()

	# System B is fully constructed before the System A client starts.
	# This keeps the existing simulation authoritative and only adds the
	# communication layer around it.
	var client_script: Script = preload("res://scripts/resqnet_client.gd")
	var client: Node = client_script.new()
	client.name = "ResQNetClient"
	add_child(client)
	attach_system_a_client(client)

	# IMPORTANT: startup is intentionally non-destructive.
	# Do NOT auto-start any disaster when the Digital Twin opens.
	# Earthquake / fire / flood can only begin from explicit operator input
	# or an authenticated System-A remote command.
	_on_event("SYSTEM B  |  READY  |  DISASTER ENGINE STANDBY")


# ============================================================
# ENVIRONMENT
# ============================================================

func _build_environment() -> void:

	var world_environment: WorldEnvironment = WorldEnvironment.new()

	world_environment.name = "WorldEnvironment"


	var environment: Environment = Environment.new()

	environment.background_mode = Environment.BG_SKY


	# --------------------------------------------------------
	# SKY
	# --------------------------------------------------------

	var sky: Sky = Sky.new()

	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()

	sky_material.sky_top_color = Color(
		0.025,
		0.065,
		0.12
	)

	sky_material.sky_horizon_color = Color(
		0.48,
		0.55,
		0.58
	)

	sky_material.ground_bottom_color = Color(
		0.035,
		0.04,
		0.045
	)

	sky_material.ground_horizon_color = Color(
		0.30,
		0.32,
		0.30
	)

	sky.sky_material = sky_material

	environment.sky = sky


	# --------------------------------------------------------
	# LIGHTING
	# --------------------------------------------------------

	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY

	environment.ambient_light_energy = 0.9

	environment.tonemap_mode = Environment.TONE_MAPPER_ACES


	# --------------------------------------------------------
	# FOG
	# --------------------------------------------------------

	environment.fog_enabled = true

	environment.fog_light_color = Color(
		0.30,
		0.38,
		0.43
	)

	environment.fog_density = 0.0011


	world_environment.environment = environment

	add_child(world_environment)


	# --------------------------------------------------------
	# SUN
	# --------------------------------------------------------

	var sun: DirectionalLight3D = DirectionalLight3D.new()

	sun.name = "Sun"

	sun.rotation_degrees = Vector3(
		-48.0,
		-28.0,
		0.0
	)

	sun.light_energy = 1.45

	sun.shadow_enabled = true

	add_child(sun)


# ============================================================
# CITY + SIMULATION SYSTEMS
# ============================================================

func _build_city() -> void:

	# --------------------------------------------------------
	# CITY
	# --------------------------------------------------------

	city = MetroCity.new()

	city.name = "RESQ_METRO"

	add_child(city)

	var graph: Variant = city.build()


	# --------------------------------------------------------
	# TRAFFIC
	# --------------------------------------------------------

	traffic = TrafficSystem.new()

	traffic.name = "Traffic"

	add_child(traffic)

	traffic.setup(graph)


	# --------------------------------------------------------
	# DISASTER ENGINE
	# --------------------------------------------------------

	disaster = DisasterController.new()

	disaster.name = "DisasterEngine"

	add_child(disaster)

	disaster.setup(city)

	if not disaster.event_changed.is_connected(_on_event):
		disaster.event_changed.connect(_on_event)


	# --------------------------------------------------------
	# DRONE FLEET
	# --------------------------------------------------------

	fleet = DroneFleet.new()

	fleet.name = "DroneFleet"

	add_child(fleet)

	fleet.setup(city)

	if not fleet.drone_event.is_connected(_on_event):
		fleet.drone_event.connect(_on_event)


	# --------------------------------------------------------
	# GRAPH VALIDATION
	# --------------------------------------------------------

	var validation: Dictionary = graph.validate()

	var connected: bool = bool(
		validation.get("connected", false)
	)

	var node_count: int = int(
		validation.get("nodes", 0)
	)

	var edge_count: int = int(
		validation.get("edges", 0)
	)

	_on_event(
		"GRAPH VALIDATION  |  CONNECTED=%s  |  NODES=%d  |  EDGES=%d"
		% [
			str(connected),
			node_count,
			edge_count
		]
	)


# ============================================================
# CAMERA
# ============================================================

func _build_camera() -> void:

	camera_root = Node3D.new()

	camera_root.name = "CommandCamera"

	add_child(camera_root)


	cam = Camera3D.new()

	cam.name = "MainCamera"

	cam.current = true

	cam.fov = 62.0

	camera_root.add_child(cam)


	_reset_camera()


# ============================================================
# STRATEGIC CAMERA
# ============================================================

func _reset_camera() -> void:

	strategic = true

	camera_root.position = Vector3(
		0.0,
		420.0,
		620.0
	)

	camera_root.rotation_degrees = Vector3(
		-31.0,
		0.0,
		0.0
	)


# ============================================================
# USER INTERFACE
# ============================================================

func _build_ui() -> void:

	var layer: CanvasLayer = CanvasLayer.new()

	layer.name = "SimulationUI"

	add_child(layer)


	# ========================================================
	# TOP STATUS PANEL
	# ========================================================

	var top: PanelContainer = PanelContainer.new()

	top.name = "TopStatusPanel"

	top.set_anchors_preset(Control.PRESET_TOP_LEFT)

	top.position = Vector2(
		20.0,
		18.0
	)

	top.size = Vector2(
		535.0,
		190.0
	)

	layer.add_child(top)


	var top_margin: MarginContainer = MarginContainer.new()

	top_margin.add_theme_constant_override(
		"margin_left",
		18
	)

	top_margin.add_theme_constant_override(
		"margin_right",
		18
	)

	top_margin.add_theme_constant_override(
		"margin_top",
		12
	)

	top_margin.add_theme_constant_override(
		"margin_bottom",
		12
	)

	top.add_child(top_margin)


	var top_column: VBoxContainer = VBoxContainer.new()

	top_column.add_theme_constant_override(
		"separation",
		5
	)

	top_margin.add_child(top_column)


	# --------------------------------------------------------
	# TITLE
	# --------------------------------------------------------

	var title: Label = Label.new()

	title.text = "RESQNET  //  SYSTEM B"

	title.add_theme_font_size_override(
		"font_size",
		25
	)

	top_column.add_child(title)


	# --------------------------------------------------------
	# SUBTITLE
	# --------------------------------------------------------

	var subtitle: Label = Label.new()

	subtitle.text = (
		"DIGITAL TWIN  •  METRO DISASTER SIMULATION"
	)

	subtitle.add_theme_font_size_override(
		"font_size",
		11
	)

	top_column.add_child(subtitle)


	# --------------------------------------------------------
	# CLOCK
	# --------------------------------------------------------

	clock_label = Label.new()

	clock_label.add_theme_font_size_override(
		"font_size",
		18
	)

	top_column.add_child(clock_label)


	# --------------------------------------------------------
	# STATISTICS
	# --------------------------------------------------------

	stats_label = Label.new()

	stats_label.add_theme_font_size_override(
		"font_size",
		12
	)

	top_column.add_child(stats_label)


	# --------------------------------------------------------
	# DISASTER STATE
	# --------------------------------------------------------

	disaster_label = Label.new()

	disaster_label.text = (
		"DISASTER STATUS  •  STANDBY"
	)

	disaster_label.add_theme_font_size_override(
		"font_size",
		12
	)

	top_column.add_child(disaster_label)


	# --------------------------------------------------------
	# SYSTEM A CONNECTION
	# --------------------------------------------------------

	connection_label = Label.new()

	connection_label.text = (
		"SYSTEM A LINK  •  DISCONNECTED  •  WAITING"
	)

	connection_label.add_theme_font_size_override(
		"font_size",
		11
	)

	top_column.add_child(connection_label)


	# ========================================================
	# LIVE EVENT FEED
	# ========================================================

	var event_box: PanelContainer = PanelContainer.new()

	event_box.name = "EventFeed"

	event_box.set_anchors_preset(
		Control.PRESET_BOTTOM_LEFT
	)

	event_box.position = Vector2(
		20.0,
		-175.0
	)

	event_box.size = Vector2(
		700.0,
		155.0
	)

	layer.add_child(event_box)


	var event_margin: MarginContainer = MarginContainer.new()

	event_margin.add_theme_constant_override(
		"margin_left",
		16
	)

	event_margin.add_theme_constant_override(
		"margin_right",
		16
	)

	event_margin.add_theme_constant_override(
		"margin_top",
		10
	)

	event_margin.add_theme_constant_override(
		"margin_bottom",
		10
	)

	event_box.add_child(event_margin)


	var event_column: VBoxContainer = VBoxContainer.new()

	event_column.add_theme_constant_override(
		"separation",
		5
	)

	event_margin.add_child(event_column)


	var event_header: Label = Label.new()

	event_header.text = "LIVE EVENT FEED"

	event_header.add_theme_font_size_override(
		"font_size",
		13
	)

	event_column.add_child(event_header)


	event_label = Label.new()

	event_label.custom_minimum_size = Vector2(
		0.0,
		105.0
	)

	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	event_label.add_theme_font_size_override(
		"font_size",
		11
	)

	event_column.add_child(event_label)


	# ========================================================
	# VICTIM INTELLIGENCE PANEL
	# ========================================================

	victim_panel = PanelContainer.new()

	victim_panel.name = "VictimIntelligence"

	victim_panel.set_anchors_preset(
		Control.PRESET_TOP_RIGHT
	)

	victim_panel.position = Vector2(
		-390.0,
		18.0
	)

	victim_panel.size = Vector2(
		370.0,
		330.0
	)

	layer.add_child(victim_panel)


	var victim_margin: MarginContainer = MarginContainer.new()

	victim_margin.add_theme_constant_override(
		"margin_left",
		16
	)

	victim_margin.add_theme_constant_override(
		"margin_right",
		16
	)

	victim_margin.add_theme_constant_override(
		"margin_top",
		12
	)

	victim_margin.add_theme_constant_override(
		"margin_bottom",
		12
	)

	victim_panel.add_child(victim_margin)


	var victim_column: VBoxContainer = VBoxContainer.new()

	victim_column.add_theme_constant_override(
		"separation",
		6
	)

	victim_margin.add_child(victim_column)


	var victim_header: Label = Label.new()

	victim_header.text = "VICTIM INTELLIGENCE"

	victim_header.add_theme_font_size_override(
		"font_size",
		16
	)

	victim_column.add_child(victim_header)


	var victim_subtitle: Label = Label.new()

	victim_subtitle.text = (
		"LIVE PERSON DETECTION  •  DRONE SOURCED"
	)

	victim_subtitle.add_theme_font_size_override(
		"font_size",
		10
	)

	victim_column.add_child(victim_subtitle)


	victim_list_label = Label.new()

	victim_list_label.custom_minimum_size = Vector2(
		0.0,
		175.0
	)

	victim_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	victim_list_label.add_theme_font_size_override(
		"font_size",
		10
	)

	victim_column.add_child(victim_list_label)


	victim_detail_label = Label.new()

	victim_detail_label.custom_minimum_size = Vector2(
		0.0,
		70.0
	)

	victim_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	victim_detail_label.add_theme_font_size_override(
		"font_size",
		10
	)

	victim_column.add_child(victim_detail_label)


	# ========================================================
	# RESPONSIVE CONTROL PANEL
	# ========================================================

	control_panel = PanelContainer.new()

	control_panel.name = "SimulationControls"

	control_panel.set_anchors_preset(
		Control.PRESET_BOTTOM_RIGHT
	)

	control_panel.position = Vector2(
		-390.0,
		-325.0
	)

	control_panel.size = Vector2(
		370.0,
		310.0
	)

	layer.add_child(control_panel)


	var control_margin: MarginContainer = MarginContainer.new()

	control_margin.add_theme_constant_override(
		"margin_left",
		18
	)

	control_margin.add_theme_constant_override(
		"margin_right",
		18
	)

	control_margin.add_theme_constant_override(
		"margin_top",
		14
	)

	control_margin.add_theme_constant_override(
		"margin_bottom",
		14
	)

	control_panel.add_child(control_margin)


	var control_column: VBoxContainer = VBoxContainer.new()

	control_column.add_theme_constant_override(
		"separation",
		7
	)

	control_margin.add_child(control_column)


	# --------------------------------------------------------
	# HEADER
	# --------------------------------------------------------

	var control_header: Label = Label.new()

	control_header.text = "SIMULATION CONTROL"

	control_header.add_theme_font_size_override(
		"font_size",
		16
	)

	control_column.add_child(control_header)


	mode_label = Label.new()

	mode_label.text = "MODE  •  STRATEGIC COMMAND"

	mode_label.add_theme_font_size_override(
		"font_size",
		11
	)

	control_column.add_child(mode_label)


	# --------------------------------------------------------
	# BUTTON ROW 1
	# --------------------------------------------------------

	var row_1: HBoxContainer = HBoxContainer.new()

	row_1.add_theme_constant_override(
		"separation",
		6
	)

	control_column.add_child(row_1)


	var pause_button: Button = Button.new()

	pause_button.text = "PAUSE / RESUME"

	pause_button.custom_minimum_size = Vector2(
		160.0,
		34.0
	)

	pause_button.pressed.connect(
		_toggle_pause
	)

	row_1.add_child(pause_button)


	var reset_button: Button = Button.new()

	reset_button.text = "RESET"

	reset_button.custom_minimum_size = Vector2(
		100.0,
		34.0
	)

	reset_button.pressed.connect(
		_reset_scenario
	)

	row_1.add_child(reset_button)


	# --------------------------------------------------------
	# BUTTON ROW 2
	# --------------------------------------------------------

	var row_2: HBoxContainer = HBoxContainer.new()

	row_2.add_theme_constant_override(
		"separation",
		6
	)

	control_column.add_child(row_2)


	var quake_button: Button = Button.new()

	quake_button.text = "EARTHQUAKE"

	quake_button.custom_minimum_size = Vector2(
		160.0,
		34.0
	)

	quake_button.pressed.connect(
		_trigger_demo
	)

	row_2.add_child(quake_button)


	var fire_button: Button = Button.new()

	fire_button.text = "SPAWN FIRE"

	fire_button.custom_minimum_size = Vector2(
		100.0,
		34.0
	)

	fire_button.pressed.connect(
		_trigger_fire
	)

	row_2.add_child(fire_button)


	# --------------------------------------------------------
	# BUTTON ROW 3
	# --------------------------------------------------------

	var row_3: HBoxContainer = HBoxContainer.new()

	row_3.add_theme_constant_override(
		"separation",
		6
	)

	control_column.add_child(row_3)


	var victim_button: Button = Button.new()

	victim_button.text = "SPAWN PEOPLE"

	victim_button.custom_minimum_size = Vector2(
		160.0,
		34.0
	)

	victim_button.pressed.connect(
		_spawn_victims_manual
	)

	row_3.add_child(victim_button)


	var camera_button: Button = Button.new()

	camera_button.text = "CAMERA"

	camera_button.custom_minimum_size = Vector2(
		100.0,
		34.0
	)

	camera_button.pressed.connect(
		_toggle_camera
	)

	row_3.add_child(camera_button)


	# --------------------------------------------------------
	# BUTTON ROW 4
	# --------------------------------------------------------

	var row_4: HBoxContainer = HBoxContainer.new()

	row_4.add_theme_constant_override(
		"separation",
		6
	)

	control_column.add_child(row_4)


	var flood_button: Button = Button.new()

	flood_button.text = "FLOOD"

	flood_button.custom_minimum_size = Vector2(
		160.0,
		34.0
	)

	flood_button.pressed.connect(
		_trigger_flood
	)

	row_4.add_child(flood_button)


	var detect_button: Button = Button.new()

	detect_button.text = "DETECT"

	detect_button.custom_minimum_size = Vector2(
		100.0,
		34.0
	)

	detect_button.pressed.connect(
		_demo_victim_detection
	)

	row_4.add_child(detect_button)


	# --------------------------------------------------------
	# CAMERA INSTRUCTIONS
	# --------------------------------------------------------

	var shortcut_text: Label = Label.new()

	shortcut_text.text = (
		"[WASD] Move    [Q/E] Altitude    [TAB] Camera\n"
		+ "[SPACE] Pause    [T] Earthquake    [F] Fire    [G] Flood\n"
		+ "[R] Reset    [V] Detect Victim"
	)

	shortcut_text.add_theme_font_size_override(
		"font_size",
		10
	)

	control_column.add_child(shortcut_text)


# ============================================================
# DEMO START
# ============================================================

func _start_demo_after_delay() -> void:
	# Retained as a compatibility hook for older scenes/scripts.
	# It deliberately does nothing: RESQNET must never create a disaster
	# automatically merely because the simulation has launched.
	_on_event("SYSTEM B  |  STARTUP AUTO-DISASTER DISABLED")


func _begin_demo() -> void:
	# Legacy compatibility entry point. If called explicitly, it behaves
	# like an operator-triggered earthquake. It is never called by _ready().
	_trigger_demo()


# ============================================================
# EVENT SYSTEM
# ============================================================

func _on_event(text: String) -> void:

	event_lines.push_front(text)

	if event_lines.size() > 7:
		event_lines.pop_back()


	if event_label != null:

		event_label.text = "\n".join(
			event_lines
		)


# ============================================================
# MAIN SIMULATION LOOP
# ============================================================

func _process(delta: float) -> void:

	if not paused:

		sim_time += (
			delta
			* sim_scale
		)


	_update_camera(delta)

	_update_ui()

	_update_victim_intelligence()


# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:

	if not event is InputEventKey:
		return


	var key_event: InputEventKey = event as InputEventKey


	if not key_event.pressed:
		return


	if key_event.echo:
		return


	match key_event.keycode:

		KEY_T:
			_trigger_demo()

		KEY_F:
			_trigger_fire()

		KEY_R:
			_reset_scenario()

		KEY_G:
			_trigger_flood()

		KEY_V:
			_demo_victim_detection()

		KEY_TAB:
			_toggle_camera()

		KEY_SPACE:
			_toggle_pause()


# ============================================================
# PAUSE
# ============================================================

func _toggle_pause() -> void:

	paused = not paused


	if paused:

		_on_event(
			"SIMULATION  |  PAUSED"
		)

	else:

		_on_event(
			"SIMULATION  |  RESUMED"
		)


# ============================================================
# MANUAL EARTHQUAKE
# ============================================================

func _trigger_demo() -> void:

	demo_started = true


	if disaster != null:

		disaster.start_demo()


	if fleet != null:

		fleet.start_demo()


	_on_event(
		"MANUAL CONTROL  |  EARTHQUAKE SCENARIO TRIGGERED"
	)


# ============================================================
# MANUAL FIRE
# ============================================================

func _trigger_fire() -> void:

	if disaster != null:

		if disaster.has_method(
			"_spawn_secondary_fire"
		):

			disaster.call(
				"_spawn_secondary_fire"
			)

			_on_event(
				"MANUAL CONTROL  |  FIRE HAZARD INJECTED"
			)

		else:

			_on_event(
				"FIRE CONTROL  |  FIRE SPAWNER UNAVAILABLE"
			)


# ============================================================
# MANUAL VICTIMS
# ============================================================

func _spawn_victims_manual() -> void:

	if disaster == null:

		_on_event(
			"VICTIM CONTROL  |  DISASTER ENGINE UNAVAILABLE"
		)

		return


	if disaster.has_method(
		"_spawn_victims"
		):

		disaster.call(
			"_spawn_victims"
		)

		_register_existing_disaster_victims()

		_on_event(
			"MANUAL CONTROL  |  CIVILIANS SPAWNED"
		)

	else:

		_on_event(
			"VICTIM CONTROL  |  VICTIM SYSTEM UNAVAILABLE"
		)


# ============================================================
# REGISTER EXISTING DISASTER VICTIMS
# ============================================================

func _register_existing_disaster_victims() -> void:

	if disaster == null:
		return

	if not ("victims" in disaster):
		return

	var victims_value: Variant = disaster.get("victims")

	if not (victims_value is Array):
		return

	var victims_array: Array = victims_value

	for victim_value: Variant in victims_array:

		if not (victim_value is Dictionary):
			continue

		var victim_data: Dictionary = victim_value

		var location: Vector3 = Vector3.ZERO

		if victim_data.has("position"):
			var position_value: Variant = victim_data.get("position")

			if position_value is Vector3:
				location = position_value

		var victim_id: String = str(
			victim_data.get(
				"victim_id",
				""
			)
		)

		if victim_id.is_empty():
			victim_id = _generate_victim_id()

		_register_victim(
			victim_id,
			str(
				victim_data.get(
					"hazard_type",
					"UNKNOWN"
				)
			),
			location,
			str(
				victim_data.get(
					"image",
					""
				)
			),
			str(
				victim_data.get(
					"drone_id",
					"SYSTEM_B"
				)
			),
			str(
				victim_data.get(
					"priority",
					"MEDIUM"
				)
			),
			str(
				victim_data.get(
					"severity",
					"UNKNOWN"
				)
			)
		)


# ============================================================
# VICTIM ID GENERATOR
# ============================================================

func _generate_victim_id() -> String:

	victim_counter += 1

	return "V%03d" % victim_counter


# ============================================================
# VICTIM INTELLIGENCE REGISTRATION
# ============================================================

func _register_victim(
	victim_id: String,
	hazard_type: String,
	location: Vector3,
	image: String,
	drone_id: String,
	priority: String,
	severity: String
) -> Dictionary:

	# --------------------------------------------------------
	# Prevent duplicates
	# --------------------------------------------------------

	for existing_value: Variant in victim_intelligence:

		if not (existing_value is Dictionary):
			continue

		var existing: Dictionary = existing_value

		if str(
			existing.get(
				"victim_id",
				""
			)
		) == victim_id:

			existing["location"] = location
			existing["hazard_type"] = hazard_type
			existing["image"] = image
			existing["captured_by"] = drone_id
			existing["priority"] = priority
			existing["severity"] = severity
			existing["timestamp"] = sim_time

			return existing


	# --------------------------------------------------------
	# Create new intelligence record
	# --------------------------------------------------------

	var record: Dictionary = {
		"victim_id": victim_id,
		"hazard_type": hazard_type,
		"location": location,
		"image": image,
		"captured_by": drone_id,
		"priority": priority,
		"severity": severity,
		"status": "DETECTED",
		"timestamp": sim_time
	}

	victim_intelligence.append(record)

	selected_victim_id = victim_id


	_on_event(
		"VICTIM DETECTED  |  %s  |  DRONE=%s  |  PRIORITY=%s"
		% [
			victim_id,
			drone_id,
			priority
		]
	)


	_publish_victim_event(record)


	return record


# ============================================================
# PUBLIC VICTIM DETECTION API
# ============================================================
#
# This function is intentionally public so DroneController /
# DroneFleet / perception logic can call:
#
# register_victim_detection(...)
#
# ============================================================

func register_victim_detection(
	victim_id: String,
	hazard_type: String,
	location: Vector3,
	image: String,
	drone_id: String,
	priority: String = "MEDIUM",
	severity: String = "UNKNOWN"
) -> Dictionary:

	if victim_id.is_empty():

		victim_id = _generate_victim_id()


	return _register_victim(
		victim_id,
		hazard_type,
		location,
		image,
		drone_id,
		priority,
		severity
	)


# ============================================================
# DEMO VICTIM DETECTION
# ============================================================
#
# This creates a realistic intelligence record for testing
# the complete dashboard / backend pipeline.
#
# It does NOT replace the real disaster victim system.
# ============================================================

func _demo_victim_detection() -> void:

	var location: Vector3 = Vector3(
		48.0,
		4.0,
		-72.0
	)

	var drone_id: String = _get_detection_drone_id()

	var victim_id: String = _generate_victim_id()

	register_victim_detection(
		victim_id,
		"EARTHQUAKE_DEBRIS",
		location,
		"victim_capture_%s.jpg" % victim_id,
		drone_id,
		"HIGH",
		"CRITICAL"
	)

	_on_event(
		"PERCEPTION  |  HUMAN DETECTION CONFIRMED  |  %s"
		% victim_id
	)


# ============================================================
# GET DETECTION DRONE
# ============================================================

func _get_detection_drone_id() -> String:

	if fleet == null:
		return "D01"

	if not ("drones" in fleet):
		return "D01"

	var drones_value: Variant = fleet.get("drones")

	if not (drones_value is Array):
		return "D01"

	var drones_array: Array = drones_value

	if drones_array.is_empty():
		return "D01"

	var first_drone: Variant = drones_array[0]

	if first_drone is Node:

		var drone_node: Node = first_drone as Node

		if drone_node.has_meta("drone_id"):

			return str(
				drone_node.get_meta(
					"drone_id"
				)
			)

		if "drone_id" in drone_node:

			return str(
				drone_node.get(
					"drone_id"
				)
			)

	return "D01"


# ============================================================
# VICTIM EVENT TO SYSTEM A
# ============================================================

func _publish_victim_event(victim: Dictionary) -> void:

	# --------------------------------------------------------
	# If a dedicated client exists, pass the complete record.
	# --------------------------------------------------------

	if system_a_client != null:

		if system_a_client.has_method(
			"send_victim_detection"
		):

			system_a_client.call(
				"send_victim_detection",
				victim
			)

			return


	# --------------------------------------------------------
	# Otherwise keep it locally available.
	# --------------------------------------------------------

	# The WebSocket integration layer can call:
	#
	# get_victim_intelligence()
	#
	# and transmit these records to System A.


# ============================================================
# PUBLIC VICTIM INTELLIGENCE ACCESS
# ============================================================

func get_victim_intelligence() -> Array[Dictionary]:

	return victim_intelligence


# ============================================================
# SELECT VICTIM
# ============================================================

func select_victim(victim_id: String) -> void:

	for victim_value: Variant in victim_intelligence:

		if not (victim_value is Dictionary):
			continue

		var victim: Dictionary = victim_value

		if str(
			victim.get(
				"victim_id",
				""
			)
		) == victim_id:

			selected_victim_id = victim_id

			_update_victim_detail(victim)

			_on_event(
				"VICTIM INTELLIGENCE  |  SELECTED %s"
				% victim_id
			)

			return


# ============================================================
# VICTIM INTELLIGENCE UI UPDATE
# ============================================================

func _update_victim_intelligence() -> void:

	if victim_list_label == null:
		return


	if victim_intelligence.is_empty():

		victim_list_label.text = (
			"NO VICTIMS DETECTED\n\n"
			+ "Awaiting aerial reconnaissance..."
		)

		victim_detail_label.text = (
			"VICTIM DETAIL\n"
			+ "No active detection."
		)

		return


	var output: String = ""

	var displayed: int = 0


	for victim_value: Variant in victim_intelligence:

		if not (victim_value is Dictionary):
			continue

		var victim: Dictionary = victim_value

		var victim_id: String = str(
			victim.get(
				"victim_id",
				"UNKNOWN"
			)
		)

		var hazard: String = str(
			victim.get(
				"hazard_type",
				"UNKNOWN"
			)
		)

		var drone: String = str(
			victim.get(
				"captured_by",
				"UNKNOWN"
			)
		)

		var priority: String = str(
			victim.get(
				"priority",
				"MEDIUM"
			)
		)

		var location: Vector3 = Vector3.ZERO

		var location_value: Variant = victim.get(
			"location",
			Vector3.ZERO
		)

		if location_value is Vector3:

			location = location_value as Vector3


		output += (
			"[%s]  %s\n"
			% [
				priority,
				victim_id
			]
		)

		output += (
			"  HAZARD: %s\n"
			% hazard
		)

		output += (
			"  POS: %.1f, %.1f, %.1f\n"
			% [
				location.x,
				location.y,
				location.z
			]
		)

		output += (
			"  CAPTURED BY: %s\n\n"
			% drone
		)

		displayed += 1

		if displayed >= 4:
			break


	victim_list_label.text = output


	# --------------------------------------------------------
	# Selected victim
	# --------------------------------------------------------

	if selected_victim_id.is_empty():

		selected_victim_id = str(
			victim_intelligence[0].get(
				"victim_id",
				""
			)
		)


	for victim_value: Variant in victim_intelligence:

		if not (victim_value is Dictionary):
			continue

		var victim: Dictionary = victim_value

		if str(
			victim.get(
				"victim_id",
				""
			)
		) == selected_victim_id:

			_update_victim_detail(victim)

			break


# ============================================================
# VICTIM DETAIL
# ============================================================

func _update_victim_detail(victim: Dictionary) -> void:

	if victim_detail_label == null:
		return


	var location: Vector3 = Vector3.ZERO

	var location_value: Variant = victim.get(
		"location",
		Vector3.ZERO
	)

	if location_value is Vector3:

		location = location_value as Vector3


	var victim_id: String = str(
		victim.get(
			"victim_id",
			"UNKNOWN"
		)
	)

	var hazard: String = str(
		victim.get(
			"hazard_type",
			"UNKNOWN"
		)
	)

	var drone: String = str(
		victim.get(
			"captured_by",
			"UNKNOWN"
		)
	)

	var priority: String = str(
		victim.get(
			"priority",
			"UNKNOWN"
		)
	)

	var severity: String = str(
		victim.get(
			"severity",
			"UNKNOWN"
		)
	)

	var image: String = str(
		victim.get(
			"image",
			"NO IMAGE"
		)
	)


	victim_detail_label.text = (
		"SELECTED  %s  |  %s\n"
		+ "SEVERITY: %s  |  PRIORITY: %s\n"
		+ "COORD: (%.1f, %.1f, %.1f)\n"
		+ "DRONE: %s  |  IMAGE: %s"
	) % [
		victim_id,
		hazard,
		severity,
		priority,
		location.x,
		location.y,
		location.z,
		drone,
		image
	]


# ============================================================
# RESET SCENARIO
# ============================================================

func _reset_scenario() -> void:

	if disaster != null:

		disaster.reset()


	if fleet != null:

		if "demo_started" in fleet:

			fleet.set(
				"demo_started",
				false
			)


	sim_time = 0.0

	paused = false

	demo_started = false

	event_lines.clear()

	victim_intelligence.clear()

	selected_victim_id = ""

	victim_counter = 0

	if system_a_client != null and system_a_client.has_method("reset_detection_cache"):
		system_a_client.call("reset_detection_cache")


	_on_event(
		"SCENARIO RESET  |  CITY STATE RESTORED"
	)


# ============================================================
# CAMERA MODE
# ============================================================

func _toggle_camera() -> void:

	strategic = not strategic


	if strategic:

		_reset_camera()

		_on_event(
			"CAMERA  |  STRATEGIC COMMAND VIEW"
		)

	else:

		camera_root.position = Vector3(
			0.0,
			32.0,
			135.0
		)

		camera_root.rotation_degrees = Vector3(
			-6.0,
			180.0,
			0.0
		)

		_on_event(
			"CAMERA  |  STREET-LEVEL RESPONSE VIEW"
		)


# ============================================================
# CAMERA MOVEMENT
# ============================================================

func _update_camera(delta: float) -> void:

	if camera_root == null:
		return


	var movement: Vector3 = Vector3.ZERO


	# --------------------------------------------------------
	# HORIZONTAL
	# --------------------------------------------------------

	if Input.is_key_pressed(KEY_A):

		movement.x -= 1.0


	if Input.is_key_pressed(KEY_D):

		movement.x += 1.0


	# --------------------------------------------------------
	# ALTITUDE
	# --------------------------------------------------------

	if Input.is_key_pressed(KEY_Q):

		movement.y -= 1.0


	if Input.is_key_pressed(KEY_E):

		movement.y += 1.0


	# --------------------------------------------------------
	# FORWARD / BACK
	# --------------------------------------------------------

	if Input.is_key_pressed(KEY_W):

		movement.z -= 1.0


	if Input.is_key_pressed(KEY_S):

		movement.z += 1.0


	var speed: float = 95.0


	if not strategic:

		speed = 38.0


	if movement.length_squared() > 0.0:

		movement = movement.normalized()


		camera_root.position += (
			camera_root.global_transform.basis
			* movement
			* speed
			* delta
		)


	# --------------------------------------------------------
	# ALTITUDE LIMITS
	# --------------------------------------------------------

	if strategic:

		camera_root.position.y = clamp(
			camera_root.position.y,
			150.0,
			900.0
		)

	else:

		camera_root.position.y = clamp(
			camera_root.position.y,
			5.0,
			180.0
		)


# ============================================================
# UI UPDATE
# ============================================================

func _update_ui() -> void:

	if clock_label == null:
		return


	# --------------------------------------------------------
	# CLOCK
	# --------------------------------------------------------

	var total_seconds: int = int(
		sim_time
	)

	var minutes: int = (
		total_seconds / 60
	)

	var seconds: int = (
		total_seconds % 60
	)


	clock_label.text = (
		"SIM CLOCK   T+%02d:%02d   •   %.1fx"
		% [
			minutes,
			seconds,
			sim_scale
		]
	)


	# --------------------------------------------------------
	# COUNTERS
	# --------------------------------------------------------

	var fire_count: int = 0
	var victim_count: int = 0
	var drone_count: int = 0
	var building_count: int = 0


	if disaster != null:

		if "fires" in disaster:

			var fires_value: Variant = disaster.get(
				"fires"
			)

			if fires_value is Array:

				fire_count = (
					fires_value as Array
				).size()


		if "victims" in disaster:

			var victims_value: Variant = disaster.get(
				"victims"
			)

			if victims_value is Array:

				victim_count = (
					victims_value as Array
				).size()


	if fleet != null:

		if "drones" in fleet:

			var drones_value: Variant = fleet.get(
				"drones"
			)

			if drones_value is Array:

				drone_count = (
					drones_value as Array
				).size()


	if city != null:

		if "buildings" in city:

			var buildings_value: Variant = city.get(
				"buildings"
			)

			if buildings_value is Array:

				building_count = (
					buildings_value as Array
				).size()


	# --------------------------------------------------------
	# STATISTICS
	# --------------------------------------------------------

	stats_label.text = (
		"HAZARDS %02d    "
		+ "VICTIMS %02d    "
		+ "DRONES %02d    "
		+ "BUILDINGS %03d    "
		+ "FPS %03d"
	) % [
		fire_count,
		victim_count,
		drone_count,
		building_count,
		Engine.get_frames_per_second()
	]


	# --------------------------------------------------------
	# DISASTER STATE
	# --------------------------------------------------------

	if disaster != null:

		if "active" in disaster:

			var active_value: Variant = disaster.get(
				"active"
			)

			if bool(active_value):

				var active_type: String = "UNKNOWN"

				if "disaster_type" in disaster:

					active_type = str(
						disaster.get(
							"disaster_type"
						)
					)

				disaster_label.text = (
					"DISASTER STATUS  •  ACTIVE  •  %s"
					% active_type
				)

			else:

				disaster_label.text = (
					"DISASTER STATUS  •  STANDBY"
				)

		else:

			disaster_label.text = (
				"DISASTER STATUS  •  STANDBY"
			)


	# --------------------------------------------------------
	# CAMERA MODE
	# --------------------------------------------------------

	if mode_label != null:

		if strategic:

			mode_label.text = (
				"MODE  •  STRATEGIC COMMAND"
			)

		else:

			mode_label.text = (
				"MODE  •  STREET RESPONSE"
			)


	# --------------------------------------------------------
	# CONNECTION
	# --------------------------------------------------------

	if connection_label != null:

		if system_a_connected:

			connection_label.text = (
				"SYSTEM A LINK  •  CONNECTED  •  "
				+ "COMMAND CHANNEL READY"
			)

		else:

			connection_label.text = (
				"SYSTEM A LINK  •  %s  •  WAITING"
				% system_a_status
			)


# ============================================================
# SYSTEM A CONNECTION API
# ============================================================

func set_system_a_connection(
	connected: bool,
	status: String = ""
) -> void:

	system_a_connected = connected

	if status.is_empty():

		if connected:

			system_a_status = "CONNECTED"

		else:

			system_a_status = "DISCONNECTED"

	else:

		system_a_status = status


	if connected:

		_on_event(
			"SYSTEM A  |  COMMAND LINK ESTABLISHED"
		)

	else:

		_on_event(
			"SYSTEM A  |  COMMAND LINK LOST"
		)


# ============================================================
# ATTACH SYSTEM A CLIENT
# ============================================================

func attach_system_a_client(client: Node) -> void:

	system_a_client = client

	if system_a_client == null:
		set_system_a_connection(false, "DISCONNECTED")
		return

	# The client node existing does NOT mean the socket is connected.
	# Connection state changes only after WebSocketPeer reaches OPEN.
	set_system_a_connection(false, "CONNECTING")

	if system_a_client.has_signal("connection_changed"):
		if system_a_client.connect(
			"connection_changed",
			Callable(self, "_on_system_a_connection_changed")
		) != OK:
			pass

	if system_a_client.has_signal("backend_event"):
		if system_a_client.connect(
			"backend_event",
			Callable(self, "_on_system_a_backend_event")
		) != OK:
			pass

	if system_a_client.has_signal("victim_detected"):
		if system_a_client.connect(
			"victim_detected",
			Callable(self, "_on_system_a_victim_detected")
		) != OK:
			pass

	if system_a_client.has_method("setup"):
		system_a_client.call("setup", self, fleet, disaster)

	if system_a_client.has_method("connect_to_backend"):
		system_a_client.call("connect_to_backend")


func _on_system_a_connection_changed(is_connected: bool) -> void:

	if is_connected:
		set_system_a_connection(true, "CONNECTED")
	else:
		set_system_a_connection(false, "DISCONNECTED")


func _on_system_a_backend_event(text: String) -> void:

	var upper_text: String = text.to_upper()

	if upper_text.contains("CONNECTING"):
		system_a_status = "CONNECTING"
	elif upper_text.contains("CONNECTION FAILED"):
		system_a_status = "RETRYING"
	elif upper_text.contains("DISCONNECTED") or upper_text.contains("CHANNEL LOST"):
		system_a_status = "DISCONNECTED"

	_on_event(text)


func _on_system_a_victim_detected(data: Dictionary) -> void:

	var victim_id: String = str(data.get("victim_id", "UNKNOWN"))
	_on_event("SYSTEM A  |  VICTIM INTELLIGENCE RECEIVED  |  %s" % victim_id)


# ============================================================
# REMOTE COMMAND HOOK
# ============================================================
#
# Backend / System A can call:
#
# execute_remote_command({
#   "command": "EARTHQUAKE"
# })
#
# or:
#
# execute_remote_command({
#   "command": "FIRE"
# })
#
# or:
#
# execute_remote_command({
#   "command": "FLOOD"
# })
#
# ============================================================

func execute_remote_command(command_data: Dictionary) -> bool:

	var command: String = str(
		command_data.get(
			"command",
			""
		)
	).to_upper()


	match command:

		"EARTHQUAKE":

			_trigger_demo()

			return true


		"FIRE":

			_trigger_fire()

			return true


		"FLOOD":

			_trigger_flood()

			return true


		"SPAWN_VICTIMS":

			_spawn_victims_manual()

			return true


		"DETECT_VICTIM":

			_demo_victim_detection()

			return true


		"RESET":

			_reset_scenario()

			return true


		"PAUSE":

			if not paused:

				_toggle_pause()

			return true


		"RESUME":

			if paused:

				_toggle_pause()

			return true


		"CAMERA":

			_toggle_camera()

			return true


		_:

			_on_event(
				"COMMAND  |  UNKNOWN COMMAND  |  %s"
				% command
			)

			return false


# ============================================================
# REMOTE DRONE COMMAND
# ============================================================
#
# This is the bridge point for System A.
#
# Existing DroneFleet remains authoritative for drone
# behaviour.
#
# ============================================================

func execute_drone_command(
	command_data: Dictionary
) -> bool:

	if fleet == null:

		_on_event(
			"DRONE COMMAND  |  FLEET UNAVAILABLE"
		)

		return false


	var drone_id: String = str(
		command_data.get(
			"drone_id",
			""
		)
	)

	var command: String = str(
		command_data.get(
			"command",
			""
		)
	).to_upper()


	if drone_id.is_empty():

		_on_event(
			"DRONE COMMAND  |  DRONE ID REQUIRED"
		)

		return false


	# --------------------------------------------------------
	# If DroneFleet has a command interface, use it.
	# --------------------------------------------------------

	if fleet.has_method(
		"execute_command"
	):

		var result: Variant = fleet.call(
			"execute_command",
			command_data
		)

		if result is bool:

			return bool(result)

		return true


	# --------------------------------------------------------
	# Existing fleet may use another command interface.
	# --------------------------------------------------------

	if fleet.has_method(
		"command_drone"
	):

		var command_result: Variant = fleet.call(
			"command_drone",
			drone_id,
			command_data
		)

		if command_result is bool:

			return bool(command_result)

		return true


	_on_event(
		"DRONE COMMAND  |  %s  |  %s"
		% [
			drone_id,
			command
		]
	)

	return false


# ============================================================
# MANUAL FIRE
# ============================================================

# Kept separate so the original button/key behaviour remains.
# ============================================================


# ============================================================
# FLOOD
# ============================================================

func _trigger_flood() -> void:

	if disaster == null:

		_on_event(
			"FLOOD CONTROL  |  DISASTER ENGINE UNAVAILABLE"
		)

		return


	if not disaster.has_method(
		"start_flood"
		):

		_on_event(
			"FLOOD CONTROL  |  FLOOD ENGINE UNAVAILABLE"
		)

		return


	# Prevent the delayed autonomous earthquake
	# from overwriting the manually selected flood.

	demo_started = true

	disaster.call(
		"start_flood"
	)


	# Activate the response fleet for the flood scenario.

	if fleet != null:

		if fleet.has_method(
			"start_demo"
		):

			fleet.call(
				"start_demo"
			)


	_on_event(
		"MANUAL CONTROL  |  FLOOD SCENARIO TRIGGERED"
	)


# ============================================================
# EXTERNAL VICTIM UPDATE
# ============================================================
#
# Useful when the backend sends an AI/perception result back
# into Godot.
#
# ============================================================

func update_victim_from_system_a(
	victim_data: Dictionary
) -> void:

	var victim_id: String = str(
		victim_data.get(
			"victim_id",
			""
		)
	)

	var hazard_type: String = str(
		victim_data.get(
			"hazard_type",
			"UNKNOWN"
		)
	)

	var image: String = str(
		victim_data.get(
			"image",
			""
		)
	)

	var drone_id: String = str(
		victim_data.get(
			"captured_by",
			victim_data.get(
				"drone_id",
				"UNKNOWN"
			)
		)
	)

	var priority: String = str(
		victim_data.get(
			"priority",
			"MEDIUM"
		)
	)

	var severity: String = str(
		victim_data.get(
			"severity",
			"UNKNOWN"
		)
	)

	var location: Vector3 = Vector3.ZERO

	var location_value: Variant = victim_data.get(
		"location",
		Vector3.ZERO
	)

	if location_value is Vector3:

		location = location_value as Vector3

	elif location_value is Dictionary:

		var location_dictionary: Dictionary = (
			location_value as Dictionary
		)

		location.x = float(
			location_dictionary.get(
				"x",
				0.0
			)
		)

		location.y = float(
			location_dictionary.get(
				"y",
				0.0
			)
		)

		location.z = float(
			location_dictionary.get(
				"z",
				0.0
			)
		)


	register_victim_detection(
		victim_id,
		hazard_type,
		location,
		image,
		drone_id,
		priority,
		severity
	)


# ============================================================
# CLEAR VICTIMS
# ============================================================

func clear_victim_intelligence() -> void:

	victim_intelligence.clear()

	selected_victim_id = ""

	_update_victim_intelligence()

	_on_event(
		"VICTIM INTELLIGENCE  |  DATABASE CLEARED"
	)


# ============================================================
# GET SELECTED VICTIM
# ============================================================

func get_selected_victim() -> Dictionary:

	if selected_victim_id.is_empty():

		return {}


	for victim_value: Variant in victim_intelligence:

		if not (victim_value is Dictionary):
			continue

		var victim: Dictionary = victim_value

		if str(
			victim.get(
				"victim_id",
				""
			)
		) == selected_victim_id:

			return victim


	return {}


# ============================================================
# SYSTEM STATUS SNAPSHOT
# ============================================================

func get_system_snapshot() -> Dictionary:

	var fire_count: int = 0
	var victim_count: int = victim_intelligence.size()
	var drone_count: int = 0
	var building_count: int = 0


	if disaster != null:

		if "fires" in disaster:

			var fires_value: Variant = disaster.get(
				"fires"
			)

			if fires_value is Array:

				fire_count = (
					fires_value as Array
				).size()


	if fleet != null:

		if "drones" in fleet:

			var drones_value: Variant = fleet.get(
				"drones"
			)

			if drones_value is Array:

				drone_count = (
					drones_value as Array
				).size()


	if city != null:

		if "buildings" in city:

			var buildings_value: Variant = city.get(
				"buildings"
			)

			if buildings_value is Array:

				building_count = (
					buildings_value as Array
				).size()


	var disaster_active: bool = false

	if disaster != null:

		if "active" in disaster:

			disaster_active = bool(
				disaster.get(
					"active"
				)
			)


	var snapshot: Dictionary = {
		"system": "RESQNET_SYSTEM_B",
		"simulation_time": sim_time,
		"paused": paused,
		"system_a_connected": system_a_connected,
		"system_a_status": system_a_status,
		"disaster_active": disaster_active,
		"hazards": fire_count,
		"victims": victim_count,
		"drones": drone_count,
		"buildings": building_count,
		"victim_intelligence": victim_intelligence.duplicate(true)
	}

	return snapshot
