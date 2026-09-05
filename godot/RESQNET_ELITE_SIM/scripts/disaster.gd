class_name DisasterController
extends Node3D

signal event_changed(text: String)

# ============================================================
# RESQNET — SYSTEM B
# DISASTER ENGINE
#
# SUPPORTED:
#   EARTHQUAKE
#   FIRE
#   FLOOD
#
# FLOOD:
#   SOUTH → NORTH
#   Progressive water expansion
#   Increasing water depth
#   Civilian capture
#   Exterior building support
#   Rooftop stranding
#   Floating civilians (fallback)
#   Floating debris
#   Distress beacons
#   Rescue-ready victim state
# ============================================================


# ============================================================
# GENERAL STATE
# ============================================================

var active: bool = false
var elapsed: float = 0.0
var quake_intensity: float = 0.0

var disaster_type: String = "NONE"

var fires: Array = []
var debris: Array = []
var victims: Array = []
var civilians: Array = []
var response_relief_zones: Dictionary = {}
var response_labels: Dictionary = {}

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var civilian_rng: RandomNumberGenerator = RandomNumberGenerator.new()

var city


# ============================================================
# EARTHQUAKE / FIRE STATE
# ============================================================

var current_disaster_position: Vector3 = Vector3.ZERO
var disaster_radius: float = 80.0
var primary_fire_position: Vector3 = Vector3.ZERO

# Earthquake visual state. The city is never deleted or replaced; only a
# temporary procedural shake/crack overlay is applied while seismic energy is active.
var _earthquake_visual_root: Node3D = null
var _earthquake_base_city_position: Vector3 = Vector3.ZERO
var _earthquake_cracks: Array[Node3D] = []
var _earthquake_buildings: Array[Node3D] = []
var _earthquake_building_base: Dictionary = {}
var _earthquake_camera: Camera3D = null
var _earthquake_camera_base_position: Vector3 = Vector3.ZERO
var _earthquake_camera_base_rotation: Vector3 = Vector3.ZERO
var _earthquake_rumble: float = 0.0

# Controlled structural-collapse simulation.
# Each entry stores the live building node, its original transform, the
# selected impact point, and any generated collapse debris.
var _earthquake_collapses: Array[Dictionary] = []
var _earthquake_collapse_started: bool = false
var _earthquake_collapse_completed: bool = false
var _earthquake_collapse_duration: float = 1.25
var _earthquake_collapse_trigger_time: float = 1.35
var _earthquake_collapse_impact_radius: float = 34.0
var _earthquake_collapse_debris_roots: Array[Node3D] = []


# ============================================================
# FLOOD STATE
# ============================================================

var flood_active: bool = false

# +Z = SOUTH
# -Z = NORTH

# Flood begins outside southern boundary.
var flood_front_z: float = 358.0

# Final northern boundary.
var flood_end_z: float = -358.0

# Movement speed of flood front.
var flood_speed: float = 32.0

# Current depth.
var flood_depth: float = 0.0

# Maximum water depth.
var max_flood_depth: float = 7.5

# Actual water surface.
var flood_water_y: float = 0.35

# Main water mesh.
var flood_water: MeshInstance3D = null

var flood_material: StandardMaterial3D = null

var flood_front_marker: MeshInstance3D = null
var flood_front_marker_material: StandardMaterial3D = null

# Floating debris.
var flood_debris: Array = []

# Event protection.
var flood_25_reported: bool = false
var flood_50_reported: bool = false
var flood_75_reported: bool = false
var flood_100_reported: bool = false


# ============================================================
# FLOOD PARAMETERS
# ============================================================

const FLOOD_START_Z: float = 358.0
const FLOOD_END_Z: float = -358.0
const FLOOD_WIDTH: float = 716.0

const FLOOD_CAPTURE_MARGIN: float = 16.0

# Current multiplier for floating civilians.
const FLOOD_CURRENT_MULTIPLIER: float = 0.42

# Slight sideways drift.
const FLOOD_LATERAL_DRIFT: float = 0.22

# Exterior-structure rescue behaviour.
const FLOOD_WALL_OFFSET: float = 2.2
const FLOOD_PERSON_RADIUS: float = 1.8
const FLOOD_BUILDING_SEARCH_RADIUS: float = 90.0
const FLOOD_ROOF_TRIGGER_DEPTH: float = 2.8
const FLOOD_ROOF_OFFSET: float = 2.8
const FLOOD_WALL_HEIGHT_OFFSET: float = 1.5

const FLOOD_WALL_STRANDED: String = "FLOOD_WALL_STRANDED"
const FLOOD_ROOFTOP_STRANDED: String = "FLOOD_ROOFTOP_STRANDED"


# ============================================================
# CIVILIANS
# ============================================================

const CIVILIAN_COUNT: int = 42
const CIVILIAN_SPEED: float = 4.0

const EARTHQUAKE_VICTIM_RADIUS: float = 72.0
const FIRE_VICTIM_RADIUS: float = 48.0

# Human visual size.
const HUMAN_SCALE: float = 1.45


# ============================================================
# SETUP
# ============================================================

func setup(p_city) -> void:

	city = p_city

	rng.seed = 445566
	civilian_rng.seed = 20260904

	_spawn_city_population()

	event_changed.emit(
		"CIVILIAN NETWORK  |  %02d ACTIVE RESIDENTS"
		% civilians.size()
	)


# ============================================================
# START EARTHQUAKE
# ============================================================

func start_demo() -> void:

	_reset_disaster_only()

	active = true
	disaster_type = "EARTHQUAKE"

	elapsed = 0.0

	current_disaster_position = _get_random_city_position()

	disaster_radius = rng.randf_range(
		62.0,
		88.0
	)

	event_changed.emit(
		"EARTHQUAKE DETECTED  |  MAGNITUDE 7.1  |  EPICENTER %.0f, %.0f"
		% [
			current_disaster_position.x,
			current_disaster_position.z
		]
	)


# ============================================================
# START FLOOD
# ============================================================

func start_flood() -> void:

	_reset_disaster_only()

	active = true
	disaster_type = "FLOOD"
	flood_active = true

	elapsed = 0.0

	flood_front_z = FLOOD_START_Z
	flood_end_z = FLOOD_END_Z

	flood_speed = 32.0

	flood_depth = 0.15
	flood_water_y = 0.35

	flood_25_reported = false
	flood_50_reported = false
	flood_75_reported = false
	flood_100_reported = false

	current_disaster_position = Vector3(
		0.0,
		0.0,
		flood_front_z
	)

	_create_flood_water()
	_create_flood_front_marker()
	_spawn_flood_debris()

	event_changed.emit(
		"FLOOD WARNING  |  SOUTHERN WATER INGRESS DETECTED"
	)

	event_changed.emit(
		"FLOOD CONTROL  |  CURRENT ESTABLISHED  |  SOUTH → NORTH"
	)

	event_changed.emit(
		"FLOOD RESPONSE  |  WATER FRONT ADVANCING TOWARD NORTH"
	)


# ============================================================
# RESET EVERYTHING
# ============================================================

func reset() -> void:

	_reset_disaster_only()

	# --------------------------------------------------------
	# Restore all civilians.
	# --------------------------------------------------------

	for person in civilians:

		if not is_instance_valid(person):
			continue

		person.set_meta(
			"status",
			"ROAMING"
		)

		person.set_meta(
			"detected",
			false
		)

		person.set_meta("resqnet_detected", false)
		person.set_meta("resqnet_victim_id", "")
		person.set_meta("medical_supplied", false)
		person.set_meta("extrication_complete", false)
		person.set_meta("hazard_mitigation", 0.0)

		person.set_meta(
			"rescued",
			false
		)

		person.set_meta(
			"priority",
			0
		)

		person.set_meta(
			"cause",
			""
		)

		person.set_meta(
			"target",
			_get_random_civilian_target()
		)

		person.set_meta(
			"flood_capture",
			false
		)

		person.set_meta("flood_building_id", "")
		person.set_meta("flood_building", Vector3.ZERO)
		person.set_meta("flood_building_size", Vector3.ZERO)
		person.set_meta("flood_building_height", 0.0)
		person.set_meta("flood_wall_point", Vector3.ZERO)
		person.set_meta("flood_roof_point", Vector3.ZERO)

		_set_civilian_beacon(
			person,
			false
		)

		person.position.y = 0.0


	# --------------------------------------------------------
	# Restore buildings.
	# --------------------------------------------------------

	if city != null:

		if "buildings" in city:

			for b in city.buildings:

				if b is Dictionary:

					b["damage"] = 0.0


	event_changed.emit(
		"DISASTER ENGINE  |  RESET COMPLETE"
	)


# ============================================================
# RESET CURRENT DISASTER
# ============================================================

func _reset_disaster_only() -> void:

	for zone in response_relief_zones.values():
		if is_instance_valid(zone):
			zone.queue_free()
	for label in response_labels.values():
		if is_instance_valid(label):
			label.queue_free()
	response_relief_zones.clear()
	response_labels.clear()

	_clear_earthquake_visuals()

	active = false
	disaster_type = "NONE"

	elapsed = 0.0
	quake_intensity = 0.0

	flood_active = false

	# --------------------------------------------------------
	# Remove fires.
	# --------------------------------------------------------

	for fire in fires:

		if is_instance_valid(fire):
			fire.queue_free()

	fires.clear()


	# --------------------------------------------------------
	# Remove earthquake debris.
	# --------------------------------------------------------

	for d in debris:

		if is_instance_valid(d):
			d.queue_free()

	debris.clear()


	# --------------------------------------------------------
	# Remove flood debris.
	# --------------------------------------------------------

	for d in flood_debris:

		if is_instance_valid(d):
			d.queue_free()

	flood_debris.clear()


	# --------------------------------------------------------
	# Remove water.
	# --------------------------------------------------------

	if is_instance_valid(flood_water):

		flood_water.queue_free()

	flood_water = null
	flood_material = null

	if is_instance_valid(flood_front_marker):
		flood_front_marker.queue_free()

	flood_front_marker = null
	flood_front_marker_material = null


	# --------------------------------------------------------
	# IMPORTANT:
	# Release previous victims when switching scenarios.
	# --------------------------------------------------------

	for person in victims:

		if not is_instance_valid(person):
			continue

		person.set_meta(
			"status",
			"ROAMING"
		)

		person.set_meta(
			"detected",
			false
		)

		person.set_meta("resqnet_detected", false)
		person.set_meta("resqnet_victim_id", "")
		person.set_meta("medical_supplied", false)
		person.set_meta("extrication_complete", false)
		person.set_meta("hazard_mitigation", 0.0)

		person.set_meta(
			"rescued",
			false
		)

		person.set_meta(
			"priority",
			0
		)

		person.set_meta(
			"cause",
			""
		)

		person.set_meta(
			"flood_capture",
			false
		)

		person.set_meta("flood_building_id", "")
		person.set_meta("flood_building", Vector3.ZERO)
		person.set_meta("flood_building_size", Vector3.ZERO)
		person.set_meta("flood_building_height", 0.0)
		person.set_meta("flood_wall_point", Vector3.ZERO)
		person.set_meta("flood_roof_point", Vector3.ZERO)

		person.position.y = 0.0

		_set_civilian_beacon(
			person,
			false
		)

	victims.clear()


# ============================================================
# MAIN PROCESS
# ============================================================

func _process(delta: float) -> void:

	# Civilians continue moving even when no disaster is active.
	_update_civilians(delta)
	_update_response_relief(delta)


	if not active:
		return

	if city == null:
		return


	elapsed += delta


	# ========================================================
	# EARTHQUAKE
	# ========================================================

	if disaster_type == "EARTHQUAKE":

		_process_earthquake()
		_process_building_collapses()


	# ========================================================
	# FLOOD
	# ========================================================

	elif disaster_type == "FLOOD":

		_process_flood(delta)


	# ========================================================
	# EARTHQUAKE COMMON HAZARDS
	# ========================================================

	if disaster_type == "EARTHQUAKE":

		if elapsed > 5.0 and fires.is_empty():

			_spawn_primary_fire()

			event_changed.emit(
				"T+00:05  |  STRUCTURAL DAMAGE  |  SECONDARY FIRE"
			)


		if elapsed > 10.0 and debris.is_empty():

			_spawn_debris()

			event_changed.emit(
				"T+00:10  |  ROAD OBSTRUCTION  |  SEARCH AREA EXPANDING"
			)


		_update_civilian_exposure()


		if elapsed > 25.0 and fires.size() < 3:

			_spawn_secondary_fire()

			event_changed.emit(
				"T+00:25  |  FIRE PROPAGATION  |  NEW HAZARD"
			)


		_animate_hazards()


# ============================================================
# EARTHQUAKE PROCESSING
# ============================================================

func _process_earthquake() -> void:
	# Short, strong earthquake waveform.
	# Main shaking ends at exactly 4 seconds; trapped victims, debris,
	# fires and collapse hazards remain active after the ground stabilizes.
	if elapsed < 0.8:
		var onset: float = elapsed / 0.8
		quake_intensity = lerpf(0.0, 1.0, onset * onset)
	elif elapsed < 2.8:
		var sustain: float = (elapsed - 0.8) / 2.0
		quake_intensity = 0.82 + sin(sustain * PI) * 0.18
	elif elapsed < 4.0:
		var decay: float = 1.0 - ((elapsed - 2.8) / 1.2)
		quake_intensity = maxf(0.0, decay) * 0.82
	else:
		quake_intensity = 0.0

	quake_intensity = clampf(quake_intensity, 0.0, 1.0)
	_update_earthquake_visuals()


func _update_earthquake_visuals() -> void:
	if city == null or not is_instance_valid(city):
		return

	if _earthquake_visual_root == null:
		_earthquake_visual_root = city
		_earthquake_base_city_position = city.position
		_cache_earthquake_buildings()
		_cache_earthquake_camera()
		_create_earthquake_cracks()

	var intensity: float = quake_intensity

	if intensity > 0.005:
		var horizontal: float = 1.15 * intensity
		var vertical: float = 0.32 * intensity
		var city_offset := Vector3(
			sin(elapsed * 43.0) * horizontal + sin(elapsed * 71.0) * horizontal * 0.32,
			abs(sin(elapsed * 49.0)) * vertical,
			cos(elapsed * 47.0) * horizontal + cos(elapsed * 79.0) * horizontal * 0.28
		)
		city.position = _earthquake_base_city_position + city_offset
		_earthquake_rumble = intensity
		_shake_earthquake_buildings(intensity)
		_shake_earthquake_camera(intensity)
	else:
		city.position = _earthquake_base_city_position
		_earthquake_rumble = 0.0
		_restore_earthquake_buildings()
		_restore_earthquake_camera()

	var crack_pulse: float = 0.82 + sin(elapsed * 11.0) * 0.12 + intensity * 0.24
	for crack in _earthquake_cracks:
		if not is_instance_valid(crack):
			continue
		crack.visible = intensity > 0.025
		crack.scale = Vector3.ONE * crack_pulse


func _cache_earthquake_buildings() -> void:
	_earthquake_buildings.clear()
	_earthquake_building_base.clear()

	var nodes: Array[Node] = []
	_collect_earthquake_nodes(city, nodes)

	for node in nodes:
		if not (node is Node3D):
			continue
		var n := node as Node3D
		var lower: String = n.name.to_lower()
		var looks_like_building: bool = (
			lower.contains("building") or
			lower.contains("tower") or
			lower.contains("structure") or
			lower.contains("block") or
			lower.contains("skyscraper") or
			lower.contains("house")
		)
		if not looks_like_building or n == city:
			continue
		_earthquake_buildings.append(n)
		_earthquake_building_base[n.get_instance_id()] = {
			"node": n,
			"position": n.position,
			"rotation": n.rotation
		}


func _collect_earthquake_nodes(root: Node, output: Array[Node]) -> void:
	for child in root.get_children():
		if not is_instance_valid(child):
			continue
		output.append(child)
		if child.get_child_count() > 0:
			_collect_earthquake_nodes(child, output)


func _cache_earthquake_camera() -> void:
	_earthquake_camera = null
	var root: Node = get_tree().current_scene
	if root == null:
		return

	var nodes: Array[Node] = []
	_collect_earthquake_nodes(root, nodes)

	for node in nodes:
		if node is Camera3D:
			var candidate := node as Camera3D
			if candidate.current:
				_earthquake_camera = candidate
				_earthquake_camera_base_position = candidate.position
				_earthquake_camera_base_rotation = candidate.rotation
				return


func _shake_earthquake_buildings(intensity: float) -> void:
	var lateral: float = 0.26 * intensity
	var vertical: float = 0.10 * intensity
	var twist: float = 0.018 * intensity

	for n in _earthquake_buildings:
		if not is_instance_valid(n):
			continue

		var base: Variant = _earthquake_building_base.get(n.get_instance_id(), null)
		if base == null:
			continue

		var phase: float = float(n.get_instance_id() % 31) * 0.37
		var offset := Vector3(
			sin(elapsed * 31.0 + phase) * lateral,
			abs(sin(elapsed * 37.0 + phase)) * vertical,
			cos(elapsed * 34.0 + phase) * lateral
		)
		var base_position: Vector3 = base["position"]
		var base_rotation: Vector3 = base["rotation"]

		n.position = base_position + offset
		n.rotation = base_rotation + Vector3(
			sin(elapsed * 28.0 + phase) * twist,
			cos(elapsed * 22.0 + phase) * twist * 0.45,
			sin(elapsed * 33.0 + phase) * twist
		)


func _restore_earthquake_buildings() -> void:
	for id in _earthquake_building_base.keys():
		var data: Dictionary = _earthquake_building_base[id]
		var n: Node3D = data["node"]
		if not is_instance_valid(n):
			continue
		n.position = data["position"]
		n.rotation = data["rotation"]


func _shake_earthquake_camera(intensity: float) -> void:
	if _earthquake_camera == null or not is_instance_valid(_earthquake_camera):
		return

	var camera_under_city: bool = city.is_ancestor_of(_earthquake_camera)
	var positional_strength: float = 0.20 * intensity
	var rotational_strength: float = 0.012 * intensity
	if camera_under_city:
		positional_strength = 0.0

	var phase: float = elapsed * 53.0
	_earthquake_camera.position = _earthquake_camera_base_position + Vector3(
		sin(phase) * positional_strength,
		cos(phase * 1.13) * positional_strength * 0.55,
		sin(phase * 0.87) * positional_strength
	)
	_earthquake_camera.rotation = _earthquake_camera_base_rotation + Vector3(
		sin(phase * 0.91) * rotational_strength,
		cos(phase * 0.73) * rotational_strength * 0.7,
		sin(phase * 1.07) * rotational_strength
	)


func _restore_earthquake_camera() -> void:
	if _earthquake_camera == null or not is_instance_valid(_earthquake_camera):
		return
	_earthquake_camera.position = _earthquake_camera_base_position
	_earthquake_camera.rotation = _earthquake_camera_base_rotation


func _create_earthquake_cracks() -> void:
	if not _earthquake_cracks.is_empty():
		return

	var root := Node3D.new()
	root.name = "EarthquakeCracks"
	city.add_child(root)

	var offsets := [
		Vector3(-72.0, 0.30, -42.0),
		Vector3(-34.0, 0.31, 18.0),
		Vector3(18.0, 0.30, -30.0),
		Vector3(54.0, 0.31, 28.0),
		Vector3(-5.0, 0.32, 62.0),
		Vector3(76.0, 0.30, -8.0)
	]

	for i in range(offsets.size()):
		var crack := MeshInstance3D.new()
		crack.name = "SeismicCrack_%02d" % (i + 1)
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)

		var p: Vector3 = offsets[i]
		var length_scale: float = 10.0 + float(i % 3) * 4.0
		mesh.surface_add_vertex(p)
		mesh.surface_add_vertex(p + Vector3(length_scale, 0.0, 2.0))
		mesh.surface_add_vertex(p + Vector3(length_scale, 0.0, 2.0))
		mesh.surface_add_vertex(p + Vector3(length_scale + 4.0, 0.0, -3.0))
		mesh.surface_add_vertex(p + Vector3(length_scale * 0.55, 0.0, 1.0))
		mesh.surface_add_vertex(p + Vector3(length_scale * 0.35, 0.0, 7.0))
		mesh.surface_end()

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.025, 0.018, 0.012)
		mat.emission_enabled = true
		mat.emission = Color(0.16, 0.07, 0.025)
		mat.emission_energy_multiplier = 2.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		crack.material_override = mat
		root.add_child(crack)
		_earthquake_cracks.append(crack)


func _clear_earthquake_visuals() -> void:
	_clear_building_collapse_state()
	_restore_earthquake_buildings()
	_restore_earthquake_camera()

	if is_instance_valid(city):
		city.position = _earthquake_base_city_position

	if _earthquake_visual_root != null and is_instance_valid(_earthquake_visual_root):
		var crack_root := _earthquake_visual_root.get_node_or_null("EarthquakeCracks")
		if crack_root != null:
			crack_root.queue_free()

	_earthquake_cracks.clear()
	_earthquake_buildings.clear()
	_earthquake_building_base.clear()
	_earthquake_visual_root = null
	_earthquake_camera = null
	_earthquake_rumble = 0.0


# ============================================================
# CONTROLLED BUILDING COLLAPSE
# ============================================================
# The collapse is deterministic and simulation-safe rather than relying on
# unconstrained rigid bodies. A real building node is tilted/fallen, debris
# is generated at the impact point, and nearby civilians become trapped.
# This keeps the digital twin stable while still producing a convincing
# structural-failure event.

func _process_building_collapses() -> void:
	if disaster_type != "EARTHQUAKE" or not active:
		return

	# Give the earthquake enough time to visibly build before the first
	# structural failure.
	if not _earthquake_collapse_started and elapsed >= _earthquake_collapse_trigger_time:
		_start_building_collapse()

	for collapse in _earthquake_collapses:
		var building: Node3D = collapse.get("building", null)
		if building == null or not is_instance_valid(building):
			continue

		var progress: float = clampf(
			(elapsed - float(collapse["start_time"])) / _earthquake_collapse_duration,
			0.0,
			1.0
		)

		# Ease-in gives the structure a short hesitation before it commits
		# to the fall, then accelerates toward the impact.
		var eased: float = progress * progress * (3.0 - 2.0 * progress)
		var start_rotation: Vector3 = collapse["start_rotation"]
		var target_rotation: Vector3 = collapse["target_rotation"]
		building.rotation = start_rotation.lerp(target_rotation, eased)

		# Slight lateral movement makes the collapse feel less like a simple
		# rotation while remaining deterministic.
		var base_position: Vector3 = collapse["base_position"]
		var fall_direction: Vector3 = collapse["fall_direction"]
		building.position = base_position + fall_direction * (18.0 * eased)

		if progress >= 0.72 and not bool(collapse["impact_created"]):
			collapse["impact_created"] = true
			_create_collapse_impact(
				collapse["impact_position"],
				collapse["collapse_id"]
			)

		if progress >= 1.0 and not bool(collapse["event_reported"]):
			collapse["event_reported"] = true
			_earthquake_collapse_completed = true
			event_changed.emit(
				"STRUCTURAL COLLAPSE  |  %s  |  BUILDING DOWN  |  IMPACT ZONE SECURED"
				% str(collapse["collapse_id"])
			)


func _start_building_collapse() -> void:
	_earthquake_collapse_started = true

	if city == null or _earthquake_buildings.is_empty():
		event_changed.emit(
			"STRUCTURAL FAILURE  |  NO COLLAPSIBLE BUILDING VISUAL FOUND"
		)
		return

	var victim: Node3D = _find_best_collapse_victim()
	var building: Node3D = _find_building_for_collapse(victim)

	if building == null:
		event_changed.emit(
			"STRUCTURAL FAILURE  |  BUILDING TARGET UNAVAILABLE"
		)
		return

	var base: Variant = _earthquake_building_base.get(
		building.get_instance_id(),
		null
	)

	if base == null:
		return

	var building_position: Vector3 = building.global_position
	var impact_position: Vector3 = building_position
	var fall_direction := Vector3(
		rng.randf_range(-1.0, 1.0),
		0.0,
		rng.randf_range(-1.0, 1.0)
	)

	if victim != null and is_instance_valid(victim):
		var to_victim := victim.global_position - building_position
		to_victim.y = 0.0
		if to_victim.length() > 0.1:
			fall_direction = to_victim.normalized()
			impact_position = victim.global_position
	else:
		if fall_direction.length() > 0.1:
			fall_direction = fall_direction.normalized()

	impact_position.y = 0.0

	# Tilt primarily toward the selected impact direction.
	var target_rotation: Vector3 = base["rotation"]
	if absf(fall_direction.x) >= absf(fall_direction.z):
		target_rotation.x += deg_to_rad(68.0) * signf(fall_direction.z)
		target_rotation.z += deg_to_rad(12.0) * signf(fall_direction.x)
	else:
		target_rotation.x += deg_to_rad(12.0) * signf(fall_direction.z)
		target_rotation.z -= deg_to_rad(68.0) * signf(fall_direction.x)

	var collapse_id: String = "COLLAPSE-%02d" % (_earthquake_collapses.size() + 1)

	var collapse: Dictionary = {
		"collapse_id": collapse_id,
		"building": building,
		"base_position": base["position"],
		"start_rotation": base["rotation"],
		"target_rotation": target_rotation,
		"fall_direction": fall_direction,
		"impact_position": impact_position,
		"start_time": elapsed,
		"impact_created": false,
		"event_reported": false,
		"victim": victim
	}

	_earthquake_collapses.append(collapse)

	# Increase logical structural damage if the city exposes building data.
	_mark_city_building_damaged(building.global_position)

	event_changed.emit(
		"EARTHQUAKE COLLAPSE WARNING  |  %s  |  STRUCTURE FAILING"
		% collapse_id
	)

	if victim != null and is_instance_valid(victim):
		_mark_victim_trapped_by_collapse(
			victim,
			collapse_id,
			impact_position
		)


func _find_best_collapse_victim() -> Node3D:
	var best: Node3D = null
	var best_score: float = INF

	for person in civilians:
		if not is_instance_valid(person):
			continue

		var status: String = str(person.get_meta("status", "ROAMING"))
		if status != "ROAMING":
			continue
		if bool(person.get_meta("rescued", false)):
			continue

		var distance_to_epicenter: float = person.global_position.distance_to(
			current_disaster_position
		)

		if distance_to_epicenter <= disaster_radius + 65.0:
			if distance_to_epicenter < best_score:
				best_score = distance_to_epicenter
				best = person

	if best != null:
		return best

	# Fallback: choose the closest still-roaming civilian so the demo can
	# demonstrate an actual collapse→trapped→rescue chain.
	for person in civilians:
		if not is_instance_valid(person):
			continue
		if str(person.get_meta("status", "ROAMING")) != "ROAMING":
			continue
		if bool(person.get_meta("rescued", false)):
			continue

		var distance_to_epicenter: float = person.global_position.distance_to(
			current_disaster_position
		)
		if distance_to_epicenter < best_score:
			best_score = distance_to_epicenter
			best = person

	return best


func _find_building_for_collapse(victim: Node3D) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF

	if victim != null and is_instance_valid(victim):
		for candidate in _earthquake_buildings:
			if not is_instance_valid(candidate):
				continue
			var d: float = candidate.global_position.distance_to(
				victim.global_position
			)
			if d < best_distance:
				best_distance = d
				best = candidate

		if best != null:
			return best

	# No victim available: choose a structure closest to the epicenter.
	best_distance = INF
	for candidate in _earthquake_buildings:
		if not is_instance_valid(candidate):
			continue
		var d: float = candidate.global_position.distance_to(
			current_disaster_position
		)
		if d < best_distance:
			best_distance = d
			best = candidate

	return best


func _mark_victim_trapped_by_collapse(
	victim: Node3D,
	collapse_id: String,
	impact_position: Vector3
) -> void:
	if not is_instance_valid(victim):
		return

	victim.set_meta("status", "TRAPPED")
	victim.set_meta("cause", "BUILDING COLLAPSE")
	victim.set_meta("detected", false)
	victim.set_meta("resqnet_detected", false)
	victim.set_meta("rescued", false)
	victim.set_meta("priority", 10)
	victim.set_meta("collapse_id", collapse_id)
	victim.set_meta("collapse_impact_position", impact_position)
	victim.set_meta("trapped_by_structure", true)

	_set_civilian_beacon(victim, true)

	event_changed.emit(
		"VICTIM TRAPPED  |  %s  |  %s  |  PRIORITY 10"
		% [victim.name, collapse_id]
	)


func _mark_city_building_damaged(position: Vector3) -> void:
	if city == null:
		return
	if not ("buildings" in city):
		return

	var closest_index: int = -1
	var closest_distance: float = INF

	for i in range(city.buildings.size()):
		var b = city.buildings[i]
		if not (b is Dictionary):
			continue
		if not b.has("position"):
			continue

		var bp: Vector3 = b["position"]
		var d: float = bp.distance_to(position)
		if d < closest_distance:
			closest_distance = d
			closest_index = i

	if closest_index >= 0 and closest_distance <= 70.0:
		var building_data: Dictionary = city.buildings[closest_index]
		building_data["damage"] = maxf(
			float(building_data.get("damage", 0.0)),
			0.85
		)
		city.buildings[closest_index] = building_data


func _create_collapse_impact(position: Vector3, collapse_id: String) -> void:
	var root := Node3D.new()
	root.name = "CollapseImpact_%s" % collapse_id
	root.position = position
	add_child(root)
	_earthquake_collapse_debris_roots.append(root)

	# Central dust/impact volume.
	var dust := MeshInstance3D.new()
	dust.name = "CollapseDust"
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = 3.0
	dust_mesh.height = 6.0
	dust.mesh = dust_mesh
	dust.scale = Vector3(1.0, 0.35, 1.0)

	var dust_material := StandardMaterial3D.new()
	dust_material.albedo_color = Color(0.42, 0.38, 0.32, 0.72)
	dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust.material_override = dust_material
	root.add_child(dust)

	# Directional debris chunks.
	for i in range(16):
		var chunk := MeshInstance3D.new()
		chunk.name = "FallingDebris_%02d" % i

		var box := BoxMesh.new()
		var size := rng.randf_range(0.8, 3.4)
		box.size = Vector3(
			size,
			rng.randf_range(0.6, 2.2),
			rng.randf_range(0.8, 3.0)
		)
		chunk.mesh = box

		chunk.position = Vector3(
			rng.randf_range(-5.0, 5.0),
			rng.randf_range(0.5, 9.0),
			rng.randf_range(-5.0, 5.0)
		)

		chunk.rotation = Vector3(
			rng.randf_range(-PI, PI),
			rng.randf_range(-PI, PI),
			rng.randf_range(-PI, PI)
		)

		var material := StandardMaterial3D.new()
		material.albedo_color = Color(
			rng.randf_range(0.20, 0.42),
			rng.randf_range(0.18, 0.36),
			rng.randf_range(0.14, 0.30)
		)
		chunk.material_override = material
		root.add_child(chunk)

	# Ground impact ring.
	var ring := MeshInstance3D.new()
	ring.name = "ImpactRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 2.0
	ring_mesh.outer_radius = 2.6
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.16, 0.12, 0.09)
	ring.material_override = ring_material
	root.add_child(ring)

	event_changed.emit(
		"COLLAPSE IMPACT  |  %s  |  DEBRIS CLOUD  |  VICTIM ZONE"
		% collapse_id
	)


func _clear_building_collapse_state() -> void:
	# Restore all live building transforms from the earthquake cache.
	for collapse in _earthquake_collapses:
		var building: Node3D = collapse.get("building", null)
		if building != null and is_instance_valid(building):
			var base: Variant = _earthquake_building_base.get(
				building.get_instance_id(),
				null
			)
			if base != null:
				building.position = base["position"]
				building.rotation = base["rotation"]

	for root in _earthquake_collapse_debris_roots:
		if is_instance_valid(root):
			root.queue_free()

	_earthquake_collapse_debris_roots.clear()
	_earthquake_collapses.clear()
	_earthquake_collapse_started = false
	_earthquake_collapse_completed = false


func _process_flood(delta: float) -> void:

	if not flood_active:
		return


	# --------------------------------------------------------
	# SOUTH → NORTH
	# +Z → -Z
	# --------------------------------------------------------

	flood_front_z = maxf(FLOOD_END_Z, flood_front_z - flood_speed * delta)


	# --------------------------------------------------------
	# Progress
	# --------------------------------------------------------

	var total_distance: float = (
		FLOOD_START_Z -
		FLOOD_END_Z
	)

	var travelled: float = (
		FLOOD_START_Z -
		flood_front_z
	)

	var progress: float = clamp(
		travelled /
		total_distance,
		0.0,
		1.0
	)


	# --------------------------------------------------------
	# Water depth gradually increases.
	# --------------------------------------------------------

	flood_depth = lerpf(
		0.15,
		max_flood_depth,
		progress
	)


	flood_water_y = (
		0.35 +
		flood_depth * 0.35
	)


	# --------------------------------------------------------
	# Move / expand water.
	# --------------------------------------------------------

	_update_flood_water(
		progress
	)

	_update_flood_front_marker()


	# --------------------------------------------------------
	# Detect civilians.
	# --------------------------------------------------------

	_update_flood_civilians()


	# --------------------------------------------------------
	# Float captured civilians.
	# --------------------------------------------------------

	_update_floating_victims(
		delta
	)


	# --------------------------------------------------------
	# Move floating debris.
	# --------------------------------------------------------

	_update_flood_debris(
		delta
	)


	# --------------------------------------------------------
	# Flood progress events.
	# --------------------------------------------------------

	if progress >= 0.25 and not flood_25_reported:

		flood_25_reported = true

		event_changed.emit(
			"FLOOD FRONT  |  25%% CITY PENETRATION"
		)


	if progress >= 0.50 and not flood_50_reported:

		flood_50_reported = true

		event_changed.emit(
			"FLOOD FRONT  |  50%% CITY PENETRATION"
		)


	if progress >= 0.75 and not flood_75_reported:

		flood_75_reported = true

		event_changed.emit(
			"FLOOD FRONT  |  75%% CITY PENETRATION"
		)


	if progress >= 1.0 and not flood_100_reported:

		flood_100_reported = true

		event_changed.emit(
			"FLOOD FRONT  |  CITY FULLY IMPACTED"
		)


# ============================================================
# FLOOD FRONT MARKER
# ============================================================

func _create_flood_front_marker() -> void:
	flood_front_marker = MeshInstance3D.new()
	flood_front_marker.name = "FLOOD-FRONT-MARKER"

	var mesh := BoxMesh.new()
	mesh.size = Vector3(FLOOD_WIDTH, 0.35, 4.0)
	flood_front_marker.mesh = mesh
	flood_front_marker.position = Vector3(0.0, flood_water_y + 0.25, flood_front_z)

	flood_front_marker_material = StandardMaterial3D.new()
	flood_front_marker_material.albedo_color = Color(0.02, 0.45, 0.95)
	flood_front_marker_material.emission_enabled = true
	flood_front_marker_material.emission = Color(0.02, 0.35, 0.9)
	flood_front_marker_material.emission_energy_multiplier = 2.0
	flood_front_marker.material_override = flood_front_marker_material
	add_child(flood_front_marker)


func _update_flood_front_marker() -> void:
	if not is_instance_valid(flood_front_marker):
		return

	flood_front_marker.position = Vector3(0.0, flood_water_y + 0.25, flood_front_z)

	if flood_front_marker_material != null:
		flood_front_marker_material.emission_energy_multiplier = 1.5 + sin(elapsed * 5.0) * 0.5


# ============================================================
# CREATE FLOOD WATER
# ============================================================

func _create_flood_water() -> void:

	flood_water = MeshInstance3D.new()

	flood_water.name = "FLOOD-WATER"

	var mesh := PlaneMesh.new()

	mesh.size = Vector2(
		FLOOD_WIDTH,
		80.0
	)

	mesh.subdivide_width = 32
	mesh.subdivide_depth = 32

	flood_water.mesh = mesh

	flood_water.position = Vector3(
		0.0,
		flood_water_y,
		flood_front_z - 40.0
	)


	# --------------------------------------------------------
	# Water material.
	# --------------------------------------------------------

	flood_material = StandardMaterial3D.new()

	flood_material.albedo_color = Color(
		0.015,
		0.22,
		0.48,
		0.92
	)

	flood_material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)

	flood_material.roughness = 0.16
	flood_material.metallic = 0.08

	flood_material.emission_enabled = true

	flood_material.emission = Color(
		0.01,
		0.08,
		0.16
	)

	flood_material.emission_energy_multiplier = 1.15

	flood_material.cull_mode = (
		BaseMaterial3D.CULL_DISABLED
	)

	flood_water.material_override = flood_material

	add_child(flood_water)


# ============================================================
# UPDATE FLOOD WATER
# ============================================================

func _update_flood_water(
	progress: float
) -> void:

	if not is_instance_valid(flood_water):
		return


	# --------------------------------------------------------
	# Flooded region extends from south edge to current front.
	#
	# Water covers:
	#
	# SOUTH
	#    ↓
	#    ↓
	#    ↓
	# FLOOD FRONT
	#    ↓
	# NORTH
	# --------------------------------------------------------

	var flooded_length: float = maxf(
		80.0,
		FLOOD_START_Z -
		flood_front_z
	)


	var water_center_z: float = (
		FLOOD_START_Z +
		flood_front_z
	) * 0.5


	flood_water.position = Vector3(
		0.0,
		flood_water_y,
		water_center_z
	)


	var mesh := (
		flood_water.mesh
		as PlaneMesh
	)


	if mesh != null:

		mesh.size = Vector2(
			FLOOD_WIDTH,
			flooded_length
		)


	# --------------------------------------------------------
	# Animated water surface.
	# --------------------------------------------------------

	flood_water.rotation_degrees.y = (
		sin(elapsed * 0.35) *
		0.5
	)

	flood_water.position.y = flood_water_y


	# --------------------------------------------------------
	# Slight material animation.
	# --------------------------------------------------------

	if flood_material != null:

		var pulse: float = (
			0.55 +
			sin(elapsed * 1.8) *
			0.08
		)

		flood_material.emission_energy_multiplier = pulse


# ============================================================
# FLOOD DEBRIS
# ============================================================

func _spawn_flood_debris() -> void:

	for i in range(28):

		var d := MeshInstance3D.new()

		var mesh := BoxMesh.new()

		mesh.size = Vector3(
			rng.randf_range(
				1.0,
				4.5
			),
			rng.randf_range(
				0.4,
				2.0
			),
			rng.randf_range(
				1.0,
				4.5
			)
		)

		d.mesh = mesh


		d.position = Vector3(
			rng.randf_range(
				-350.0,
				350.0
			),
			0.5,
			rng.randf_range(
				350.0,
				358.0
			)
		)


		d.rotation = Vector3(
			rng.randf_range(
				0.0,
				TAU
			),
			rng.randf_range(
				0.0,
				TAU
			),
			rng.randf_range(
				0.0,
				TAU
			)
		)


		d.material_override = _mat(
			Color(
				0.24,
				0.22,
				0.18
			),
			0.9
		)


		d.name = (
			"FLOOD-DEBRIS-%03d"
			% i
		)


		add_child(d)

		flood_debris.append(d)


# ============================================================
# FLOOD DEBRIS MOVEMENT
# ============================================================

func _update_flood_debris(
	delta: float
) -> void:

	for d in flood_debris:

		if not is_instance_valid(d):
			continue

		d.position.z -= (
			flood_speed *
			0.75 *
			delta
		)

		d.position.y = (
			flood_water_y +
			0.5 +
			sin(
				elapsed * 2.0 +
				float(
					d.get_instance_id() % 13
				)
			) *
			0.25
		)

		d.rotation.y += (
			delta *
			0.6
		)


# ============================================================
# FLOOD CIVILIAN DETECTION
# ============================================================

func _update_flood_civilians() -> void:
	if not flood_active:
		return

	for person in civilians:
		if not is_instance_valid(person):
			continue

		var status: String = str(person.get_meta("status", "ROAMING"))
		if status != "ROAMING":
			continue

		if person.position.z >= flood_front_z - FLOOD_CAPTURE_MARGIN:
			_strand_civilian_flood(person)


# ============================================================
# FLOOD STRANDING / STRUCTURE SEEKING
# ============================================================

func _strand_civilian_flood(person: Node3D) -> void:
	if not is_instance_valid(person):
		return

	if str(person.get_meta("status", "")) != "ROAMING":
		return

	var building_data: Dictionary = _find_nearest_flood_building(person.position)
	if building_data.is_empty():
		_make_floating_flood_victim(person)
		return

	var building_id: String = str(building_data.get("id", ""))
	var building_position: Vector3 = building_data["position"]
	var building_size: Vector3 = building_data["size"]
	var building_height: float = float(building_data["height"])
	var wall_point: Vector3 = _get_nearest_building_wall_point(person.position, building_position, building_size)

	person.set_meta("flood_building_id", building_id)
	person.set_meta("flood_building", building_position)
	person.set_meta("flood_building_size", building_size)
	person.set_meta("flood_building_height", building_height)
	person.set_meta("flood_wall_point", wall_point)
	person.set_meta("flood_roof_point", Vector3(building_position.x, building_height + FLOOD_ROOF_OFFSET, building_position.z))
	person.set_meta("flood_capture", true)
	person.set_meta("cause", "FLOOD")
	person.set_meta("detected", false)
	person.set_meta("rescued", false)
	person.set_meta("priority", 8)

	# Hard rule: the civilian is always placed outside the building.
	person.position = wall_point
	person.set_meta("status", FLOOD_WALL_STRANDED)

	if not victims.has(person):
		victims.append(person)

	_set_civilian_beacon(person, true)
	event_changed.emit("FLOOD DISTRESS  |  %s  |  EXTERIOR BUILDING SUPPORT" % person.name)


func _find_nearest_flood_building(p: Vector3) -> Dictionary:
	if city == null or not ("buildings" in city) or city.buildings.is_empty():
		return {}

	var best: Dictionary = {}
	var best_distance: float = FLOOD_BUILDING_SEARCH_RADIUS

	for raw_building in city.buildings:
		if not (raw_building is Dictionary):
			continue

		var b: Dictionary = raw_building
		if not b.has("position"):
			continue

		var bp: Vector3 = b["position"]
		var distance: float = Vector2(p.x, p.z).distance_to(Vector2(bp.x, bp.z))
		if distance >= best_distance:
			continue

		var normalized: Dictionary = _normalize_flood_building(b)
		if normalized.is_empty():
			continue

		best_distance = distance
		best = normalized

	return best


func _normalize_flood_building(building: Dictionary) -> Dictionary:
	if not building.has("position"):
		return {}

	var position: Vector3 = building["position"]
	var height: float = float(building.get("height", 20.0))
	var size := Vector3(30.0, height, 30.0)
	var building_id: String = str(building.get("id", ""))

	if building.has("size") and building["size"] is Vector3:
		size = building["size"]

	# Current city data exposes building IDs/heights but not always
	# footprints, so derive the real footprint from rendered meshes.
	if building_id != "" and city != null:
		var root: Node = city.get_node_or_null(NodePath(building_id))
		if root != null:
			var bounds: AABB = _get_building_world_bounds(root)
			if bounds.size.x > 0.1 and bounds.size.z > 0.1:
				size.x = bounds.size.x
				size.z = bounds.size.z
				height = maxf(height, bounds.size.y)
				position = Vector3(bounds.position.x + bounds.size.x * 0.5, 0.0, bounds.position.z + bounds.size.z * 0.5)

	size.x = maxf(4.0, absf(size.x))
	size.z = maxf(4.0, absf(size.z))
	height = maxf(4.0, absf(height))

	return {"id": building_id, "position": Vector3(position.x, 0.0, position.z), "size": Vector3(size.x, height, size.z), "height": height}


func _get_building_world_bounds(root: Node) -> AABB:
	var found: bool = false
	var result := AABB()
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)

	for node in meshes:
		if not (node is MeshInstance3D):
			continue
		var mesh_instance: MeshInstance3D = node
		var world_bounds: AABB = _transform_aabb(mesh_instance.global_transform, mesh_instance.get_aabb())
		if not found:
			result = world_bounds
			found = true
		else:
			result = result.merge(world_bounds)

	return result


func _transform_aabb(transform: Transform3D, box: AABB) -> AABB:
	var min_corner: Vector3 = box.position
	var max_corner: Vector3 = box.position + box.size
	var corners: Array[Vector3] = [
		Vector3(min_corner.x, min_corner.y, min_corner.z),
		Vector3(max_corner.x, min_corner.y, min_corner.z),
		Vector3(min_corner.x, max_corner.y, min_corner.z),
		Vector3(max_corner.x, max_corner.y, min_corner.z),
		Vector3(min_corner.x, min_corner.y, max_corner.z),
		Vector3(max_corner.x, min_corner.y, max_corner.z),
		Vector3(min_corner.x, max_corner.y, max_corner.z),
		Vector3(max_corner.x, max_corner.y, max_corner.z)
	]

	var first: Vector3 = transform * corners[0]
	var out := AABB(first, Vector3.ZERO)
	for i in range(1, corners.size()):
		out = out.expand(transform * corners[i])
	return out


func _get_nearest_building_wall_point(person_position: Vector3, building_position: Vector3, building_size: Vector3) -> Vector3:
	var half_x: float = building_size.x * 0.5
	var half_z: float = building_size.z * 0.5
	var local_x: float = person_position.x - building_position.x
	var local_z: float = person_position.z - building_position.z
	var left: float = absf(local_x + half_x)
	var right: float = absf(local_x - half_x)
	var front: float = absf(local_z + half_z)
	var back: float = absf(local_z - half_z)
	var smallest: float = minf(minf(left, right), minf(front, back))
	var result := Vector3(person_position.x, 0.0, person_position.z)

	if smallest == left:
		result.x = building_position.x - half_x - FLOOD_WALL_OFFSET
		result.z = clampf(person_position.z, building_position.z - half_z + FLOOD_PERSON_RADIUS, building_position.z + half_z - FLOOD_PERSON_RADIUS)
	elif smallest == right:
		result.x = building_position.x + half_x + FLOOD_WALL_OFFSET
		result.z = clampf(person_position.z, building_position.z - half_z + FLOOD_PERSON_RADIUS, building_position.z + half_z - FLOOD_PERSON_RADIUS)
	elif smallest == front:
		result.z = building_position.z - half_z - FLOOD_WALL_OFFSET
		result.x = clampf(person_position.x, building_position.x - half_x + FLOOD_PERSON_RADIUS, building_position.x + half_x - FLOOD_PERSON_RADIUS)
	else:
		result.z = building_position.z + half_z + FLOOD_WALL_OFFSET
		result.x = clampf(person_position.x, building_position.x - half_x + FLOOD_PERSON_RADIUS, building_position.x + half_x - FLOOD_PERSON_RADIUS)

	return result


func _make_floating_flood_victim(person: Node3D) -> void:
	person.set_meta("status", "FLOOD_STRANDED")
	person.set_meta("detected", false)
	person.set_meta("rescued", false)
	person.set_meta("cause", "FLOOD")
	person.set_meta("priority", 7)
	person.set_meta("flood_capture", true)
	person.set_meta("flood_building_id", "")

	if not victims.has(person):
		victims.append(person)

	person.position.y = flood_water_y + 2.0
	_set_civilian_beacon(person, true)
	event_changed.emit("FLOOD DISTRESS  |  %s  |  NO SAFE STRUCTURE" % person.name)


func _update_floating_victims(delta: float) -> void:
	for person in victims:
		if not is_instance_valid(person):
			continue

		var status: String = str(person.get_meta("status", ""))
		if status == FLOOD_ROOFTOP_STRANDED:
			_hold_rooftop_victim(person)
			continue

		if status == FLOOD_WALL_STRANDED:
			_update_wall_stranded_victim(person)
			continue

		if status != "FLOOD_STRANDED":
			continue

		var bob: float = sin(elapsed * 2.8 + float(person.get_instance_id() % 17)) * 0.35
		person.position.y = flood_water_y + 2.0 + bob
		person.position.z -= flood_speed * FLOOD_CURRENT_MULTIPLIER * delta
		var drift: float = sin(elapsed * 0.8 + float(person.get_instance_id() % 11))
		person.position.x += drift * FLOOD_LATERAL_DRIFT * delta
		person.position.x = clampf(person.position.x, -680.0, 680.0)
		person.rotation.y = PI


func _update_wall_stranded_victim(person: Node3D) -> void:
	var building_position: Vector3 = person.get_meta("flood_building", Vector3.ZERO)
	var building_size: Vector3 = person.get_meta("flood_building_size", Vector3(30.0, 20.0, 30.0))
	var building_height: float = float(person.get_meta("flood_building_height", 20.0))

	# Pin to the exterior support point every frame. The current
	# cannot push this civilian through the building.
	var wall_point: Vector3 = _get_nearest_building_wall_point(person.position, building_position, building_size)
	person.position.x = wall_point.x
	person.position.z = wall_point.z
	person.position.y = maxf(0.0, flood_water_y + FLOOD_WALL_HEIGHT_OFFSET)
	person.set_meta("flood_wall_point", person.position)

	if flood_depth >= FLOOD_ROOF_TRIGGER_DEPTH:
		var roof_point := Vector3(building_position.x, building_height + FLOOD_ROOF_OFFSET, building_position.z)
		person.set_meta("flood_roof_point", roof_point)
		person.position = roof_point
		person.set_meta("status", FLOOD_ROOFTOP_STRANDED)
		person.set_meta("priority", 10)
		event_changed.emit("FLOOD RESCUE  |  %s  |  ROOFTOP STRANDED" % person.name)


func _hold_rooftop_victim(person: Node3D) -> void:
	var roof_point: Vector3 = person.get_meta("flood_roof_point", person.position)
	person.position = roof_point
	person.position.y = maxf(person.position.y, flood_water_y + 1.0)
	person.rotation.y = PI
	person.set_meta("priority", 10)
	person.set_meta("detected", true)
	person.set_meta("flood_capture", true)
	_set_civilian_beacon(person, true)


# ============================================================
# NORMAL CIVILIAN POPULATION
# ============================================================

func _spawn_city_population() -> void:

	if city == null:
		return

	if not ("graph" in city):
		return

	if city.graph == null:
		return


	var road_nodes: Array = (
		city.graph.nodes.keys()
	)


	if road_nodes.is_empty():
		return


	for i in range(
		CIVILIAN_COUNT
	):

		var node_id: String = road_nodes[
			civilian_rng.randi_range(
				0,
				road_nodes.size() - 1
			)
		]


		var position: Vector3 = (
			city.graph.nodes[
				node_id
			]["position"]
		)


		position += Vector3(
			civilian_rng.randf_range(
				-6.0,
				6.0
			),
			0.0,
			civilian_rng.randf_range(
				-6.0,
				6.0
			)
		)


		_create_civilian(
			position,
			i
		)


# ============================================================
# CREATE CIVILIAN
# ============================================================

func _create_civilian(
	position: Vector3,
	index: int
) -> void:

	var person := _build_human(
		position,
		index
	)


	person.name = (
		"CIVILIAN-%03d"
		% index
	)


	person.set_meta(
		"simulation_id",
		person.name
	)

	person.set_meta(
		"status",
		"ROAMING"
	)

	person.set_meta(
		"detected",
		false
	)

	person.set_meta(
		"rescued",
		false
	)

	person.set_meta(
		"priority",
		0
	)

	person.set_meta(
		"cause",
		""
	)

	person.set_meta(
		"flood_capture",
		false
	)

	person.set_meta(
		"target",
		_get_random_civilian_target()
	)


	add_child(person)

	civilians.append(person)


# ============================================================
# HUMAN MODEL
# ============================================================

func _build_human(
	position: Vector3,
	index: int
) -> Node3D:

	var person := Node3D.new()


	person.position = Vector3(
		position.x,
		0.0,
		position.z
	)


	person.scale = (
		Vector3.ONE *
		HUMAN_SCALE
	)


	# ========================================================
	# MATERIALS
	# ========================================================

	var skin := StandardMaterial3D.new()

	skin.albedo_color = Color(
		0.92,
		0.67,
		0.48
	)

	skin.roughness = 0.85


	var shirt := StandardMaterial3D.new()

	var clothing: Array[Color] = [

		Color(
			0.82,
			0.12,
			0.10
		),

		Color(
			0.10,
			0.28,
			0.70
		),

		Color(
			0.12,
			0.55,
			0.28
		),

		Color(
			0.72,
			0.52,
			0.10
		),

		Color(
			0.55,
			0.18,
			0.58
		),

		Color(
			0.12,
			0.12,
			0.14
		),

		Color(
			0.20,
			0.48,
			0.60
		)
	]


	shirt.albedo_color = clothing[
		civilian_rng.randi_range(
			0,
			clothing.size() - 1
		)
	]

	shirt.roughness = 0.82


	var pants := StandardMaterial3D.new()

	pants.albedo_color = Color(
		0.18,
		0.19,
		0.22
	)

	pants.roughness = 0.9


	var shoes := StandardMaterial3D.new()

	shoes.albedo_color = Color(
		0.035,
		0.04,
		0.045
	)

	shoes.roughness = 0.9


	var hair := StandardMaterial3D.new()

	hair.albedo_color = Color(
		0.045,
		0.025,
		0.015
	)

	hair.roughness = 0.95


	# ========================================================
	# LEGS
	# ========================================================

	_add_capsule(
		person,
		0.40,
		2.25,
		Vector3(
			-0.43,
			1.50,
			0.0
		),
		pants
	)


	_add_capsule(
		person,
		0.40,
		2.25,
		Vector3(
			0.43,
			1.50,
			0.0
		),
		pants
	)


	# ========================================================
	# SHOES
	# ========================================================

	_add_box(
		person,
		Vector3(
			0.70,
			0.32,
			1.10
		),
		Vector3(
			-0.43,
			0.36,
			-0.10
		),
		shoes
	)


	_add_box(
		person,
		Vector3(
			0.70,
			0.32,
			1.10
		),
		Vector3(
			0.43,
			0.36,
			-0.10
		),
		shoes
	)


	# ========================================================
	# TORSO
	# ========================================================

	_add_box(
		person,
		Vector3(
			1.65,
			2.15,
			0.90
		),
		Vector3(
			0.0,
			3.35,
			0.0
		),
		shirt
	)


	# ========================================================
	# NECK
	# ========================================================

	var neck := MeshInstance3D.new()

	var neck_mesh := CylinderMesh.new()

	neck_mesh.top_radius = 0.27
	neck_mesh.bottom_radius = 0.27
	neck_mesh.height = 0.38

	neck.mesh = neck_mesh

	neck.position = Vector3(
		0.0,
		4.57,
		0.0
	)

	neck.material_override = skin

	person.add_child(neck)


	# ========================================================
	# HEAD
	# ========================================================

	var head := MeshInstance3D.new()

	var head_mesh := SphereMesh.new()

	head_mesh.radius = 0.66
	head_mesh.height = 1.32

	head.mesh = head_mesh

	head.position = Vector3(
		0.0,
		5.30,
		0.0
	)

	head.material_override = skin

	person.add_child(head)


	# ========================================================
	# HAIR
	# ========================================================

	var hair_mesh := MeshInstance3D.new()

	var hair_shape := SphereMesh.new()

	hair_shape.radius = 0.68
	hair_shape.height = 0.65

	hair_mesh.mesh = hair_shape

	hair_mesh.position = Vector3(
		0.0,
		5.74,
		0.0
	)

	hair_mesh.material_override = hair

	person.add_child(hair_mesh)


	# ========================================================
	# ARMS
	# ========================================================

	var left_arm := _add_capsule(
		person,
		0.30,
		1.75,
		Vector3(
			-1.08,
			3.38,
			0.0
		),
		shirt
	)


	left_arm.rotation_degrees = Vector3(
		0.0,
		0.0,
		-8.0
	)


	var right_arm := _add_capsule(
		person,
		0.30,
		1.75,
		Vector3(
			1.08,
			3.38,
			0.0
		),
		shirt
	)


	right_arm.rotation_degrees = Vector3(
		0.0,
		0.0,
		8.0
	)


	# ========================================================
	# HANDS
	# ========================================================

	_add_sphere(
		person,
		0.30,
		Vector3(
			-1.20,
			2.58,
			0.0
		),
		skin
	)


	_add_sphere(
		person,
		0.30,
		Vector3(
			1.20,
			2.58,
			0.0
		),
		skin
	)


	# ========================================================
	# DISTRESS BEACON
	# ========================================================

	var beacon := MeshInstance3D.new()

	var beacon_mesh := SphereMesh.new()

	beacon_mesh.radius = 0.16
	beacon_mesh.height = 0.32

	beacon.mesh = beacon_mesh

	beacon.position = Vector3(
		0.0,
		6.25,
		0.0
	)

	beacon.name = "StatusBeacon"


	var beacon_material := StandardMaterial3D.new()

	beacon_material.albedo_color = Color(
		0.20,
		0.28,
		0.30
	)

	beacon_material.emission_enabled = true

	beacon_material.emission = Color(
		0.05,
		0.08,
		0.09
	)

	beacon_material.emission_energy_multiplier = 1.5

	beacon.material_override = beacon_material

	person.add_child(beacon)


	return person


# ============================================================
# MESH HELPERS
# ============================================================

func _add_box(
	parent: Node3D,
	size: Vector3,
	position: Vector3,
	material: Material
) -> MeshInstance3D:

	var mesh_instance := MeshInstance3D.new()

	var mesh := BoxMesh.new()

	mesh.size = size

	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material

	parent.add_child(
		mesh_instance
	)

	return mesh_instance


func _add_capsule(
	parent: Node3D,
	radius: float,
	height: float,
	position: Vector3,
	material: Material
) -> MeshInstance3D:

	var mesh_instance := MeshInstance3D.new()

	var mesh := CapsuleMesh.new()

	mesh.radius = radius
	mesh.height = height

	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material

	parent.add_child(
		mesh_instance
	)

	return mesh_instance


func _add_sphere(
	parent: Node3D,
	radius: float,
	position: Vector3,
	material: Material
) -> MeshInstance3D:

	var mesh_instance := MeshInstance3D.new()

	var mesh := SphereMesh.new()

	mesh.radius = radius
	mesh.height = radius * 2.0

	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = material

	parent.add_child(
		mesh_instance
	)

	return mesh_instance


# ============================================================
# RANDOM CITY POSITION
# ============================================================

func _get_random_city_position() -> Vector3:

	if city == null:
		return Vector3.ZERO

	if not ("graph" in city):
		return Vector3.ZERO

	if city.graph == null:
		return Vector3.ZERO


	var ids: Array = (
		city.graph.nodes.keys()
	)


	if ids.is_empty():
		return Vector3.ZERO


	var id: String = ids[
		rng.randi_range(
			0,
			ids.size() - 1
		)
	]


	var p: Vector3 = (
		city.graph.nodes[
			id
		]["position"]
	)


	return Vector3(
		p.x,
		0.0,
		p.z
	)


# ============================================================
# RANDOM BUILDING POSITION
# ============================================================

func _get_random_building_position() -> Vector3:

	if city == null:
		return Vector3.ZERO

	if not ("buildings" in city):
		return Vector3.ZERO


	if city.buildings.is_empty():

		return _get_random_city_position()


	var building: Dictionary = city.buildings[
		rng.randi_range(
			0,
			city.buildings.size() - 1
		)
	]


	var p: Vector3 = (
		building["position"]
	)


	return Vector3(
		p.x,
		0.0,
		p.z
	)


# ============================================================
# RANDOM CIVILIAN TARGET
# ============================================================

func _get_random_civilian_target() -> Vector3:

	if city == null:
		return Vector3.ZERO

	if not ("graph" in city):
		return Vector3.ZERO

	if city.graph == null:
		return Vector3.ZERO


	var nodes: Array = (
		city.graph.nodes.keys()
	)


	if nodes.is_empty():
		return Vector3.ZERO


	var id: String = nodes[
		civilian_rng.randi_range(
			0,
			nodes.size() - 1
		)
	]


	var target: Vector3 = (
		city.graph.nodes[
			id
		]["position"]
	)


	target += Vector3(
		civilian_rng.randf_range(
			-5.0,
			5.0
		),
		0.0,
		civilian_rng.randf_range(
			-5.0,
			5.0
		)
	)


	return target


# ============================================================
# CIVILIAN MOVEMENT
# ============================================================

func _update_civilians(
	delta: float
) -> void:

	for person in civilians:

		if not is_instance_valid(person):
			continue


		var status: String = str(
			person.get_meta(
				"status",
				"ROAMING"
			)
		)


		# ----------------------------------------------------
		# Disaster victims stop walking.
		# ----------------------------------------------------

		if status == "STRANDED":
			continue

		if status == "FLOOD_STRANDED":
			continue

		if status == FLOOD_WALL_STRANDED:
			continue

		if status == FLOOD_ROOFTOP_STRANDED:
			continue

		if status == "RESCUE_IN_PROGRESS":
			continue

		if status == "RESCUED":
			continue


		var target: Vector3 = person.get_meta(
			"target",
			person.position
		)


		var direction: Vector3 = (
			target -
			person.position
		)


		direction.y = 0.0


		if direction.length() < 4.0:

			person.set_meta(
				"target",
				_get_random_civilian_target()
			)

			continue


		direction = direction.normalized()


		person.position += (
			direction *
			CIVILIAN_SPEED *
			delta
		)


		person.position.y = 0.0


		if direction.length_squared() > 0.01:

			person.look_at(
				person.position +
				direction,
				Vector3.UP
			)


# ============================================================
# EARTHQUAKE / FIRE EXPOSURE
# ============================================================

func _update_civilian_exposure() -> void:

	if not active:
		return

	if disaster_type != "EARTHQUAKE":
		return


	for person in civilians:

		if not is_instance_valid(person):
			continue


		var status: String = str(
			person.get_meta(
				"status",
				"ROAMING"
			)
		)


		if status != "ROAMING":
			continue


		var earthquake_distance: float = (
			person.position.distance_to(
				current_disaster_position
			)
		)


		if earthquake_distance <= (
			EARTHQUAKE_VICTIM_RADIUS
		):

			_strand_civilian(
				person,
				"EARTHQUAKE"
			)

			continue


		for fire in fires:

			if not is_instance_valid(fire):
				continue


			var fire_distance: float = (
				person.position.distance_to(
					fire.position
				)
			)


			if fire_distance <= (
				FIRE_VICTIM_RADIUS
			):

				_strand_civilian(
					person,
					"FIRE"
				)

				break


# ============================================================
# STANDARD STRANDED CIVILIAN
# ============================================================

func _strand_civilian(
	person: Node3D,
	cause: String
) -> void:

	if not is_instance_valid(person):
		return


	person.set_meta(
		"status",
		"STRANDED"
	)

	person.set_meta(
		"detected",
		false
	)

	person.set_meta(
		"rescued",
		false
	)

	person.set_meta(
		"cause",
		cause
	)

	person.set_meta(
		"priority",
		5
	)


	if not victims.has(person):

		victims.append(person)


	_set_civilian_beacon(
		person,
		true
	)


	event_changed.emit(
		"CIVILIAN DISTRESS  |  %s  |  %s"
		% [
			person.name,
			cause
		]
	)


# ============================================================
# MANUAL SPAWN PEOPLE
#
# IMPORTANT:
# If FLOOD is active, people are selected from the
# already-flooded portion of the city.
# ============================================================

func _spawn_victims() -> void:

	if civilians.is_empty():
		return


	var affected: Array = []


	# ========================================================
	# FLOOD
	# ========================================================

	if disaster_type == "FLOOD" and flood_active:

		for person in civilians:

			if not is_instance_valid(person):
				continue


			if str(
				person.get_meta(
					"status",
					"ROAMING"
				)
			) != "ROAMING":

				continue


			if person.position.z >= (
				flood_front_z -
				80.0
			):

				affected.append(
					person
				)


	# ========================================================
	# EARTHQUAKE / FIRE
	# ========================================================

	else:

		if not active:

			current_disaster_position = (
				_get_random_city_position()
			)


		for person in civilians:

			if not is_instance_valid(person):
				continue


			if str(
				person.get_meta(
					"status",
					"ROAMING"
				)
			) != "ROAMING":

				continue


			var distance: float = (
				person.position.distance_to(
					current_disaster_position
				)
			)


			if distance <= 100.0:

				affected.append(
					person
				)


	# ========================================================
	# FALLBACK
	# ========================================================

	if affected.is_empty():

		var candidates: Array = []


		for person in civilians:

			if not is_instance_valid(person):
				continue


			if str(
				person.get_meta(
					"status",
					"ROAMING"
				)
			) != "ROAMING":

				continue


			candidates.append(
				person
			)


		# For flood choose civilians nearest to flood front.
		if disaster_type == "FLOOD":

			candidates.sort_custom(
				func(a, b):

					return abs(
						a.position.z -
						flood_front_z
					) < abs(
						b.position.z -
						flood_front_z
					)
			)

		else:

			candidates.sort_custom(
				func(a, b):

					return (
						a.position.distance_to(
							current_disaster_position
						)
						<
						b.position.distance_to(
							current_disaster_position
						)
					)
			)


		for i in range(
			min(
				9,
				candidates.size()
			)
		):

			affected.append(
				candidates[i]
			)


	# ========================================================
	# STRAND PEOPLE
	# ========================================================

	var limit: int = min(
		9,
		affected.size()
	)


	for i in range(limit):

		if disaster_type == "FLOOD":

			_strand_civilian_flood(
				affected[i]
			)

		else:

			_strand_civilian(
				affected[i],
				"MANUAL INCIDENT"
			)


	event_changed.emit(
		"MANUAL CONTROL  |  %02d CIVILIAN DISTRESS SIGNALS"
		% limit
	)


# ============================================================
# PRIMARY FIRE
# ============================================================

func _spawn_primary_fire() -> void:

	var position := (
		_get_random_building_position()
	)


	position.y = 0.0

	primary_fire_position = position
	current_disaster_position = position


	var fire := _fire_node(
		position,
		32.0,
		1.0
	)


	add_child(fire)

	fires.append(fire)


	event_changed.emit(
		"FIRE HAZARD  |  LOCATION %.0f, %.0f"
		% [
			position.x,
			position.z
		]
	)


# ============================================================
# SECONDARY FIRE
# ============================================================

func _spawn_secondary_fire() -> void:

	var position := (
		_get_random_building_position()
	)


	var attempts: int = 0


	while (
		position.distance_to(
			primary_fire_position
		) < 100.0
		and attempts < 12
	):

		position = (
			_get_random_building_position()
		)

		attempts += 1


	var fire := _fire_node(
		position,
		22.0,
		0.7
	)


	add_child(fire)

	fires.append(fire)


# ============================================================
# FIRE NODE
# ============================================================

func _fire_node(
	p: Vector3,
	radius: float,
	scale_value: float
) -> Node3D:

	var root := Node3D.new()


	root.name = (
		"HAZARD-FIRE-%03d"
		% fires.size()
	)


	root.set_meta(
		"hazard_id",
		root.name
	)

	root.set_meta(
		"hazard_type",
		"FIRE"
	)


	root.position = (
		p +
		Vector3(
			0.0,
			18.0,
			0.0
		)
	)


	var glow := OmniLight3D.new()

	glow.light_color = Color(
		1.0,
		0.23,
		0.04
	)

	glow.light_energy = (
		7.0 *
		scale_value
	)

	glow.omni_range = (
		radius *
		2.2
	)

	root.add_child(glow)


	for i in range(9):

		var flame := MeshInstance3D.new()

		var sm := SphereMesh.new()

		var flame_radius: float = (
			rng.randf_range(
				3.0,
				7.0
			) *
			scale_value
		)


		sm.radius = flame_radius

		sm.height = (
			flame_radius *
			2.2
		)


		flame.mesh = sm


		flame.position = Vector3(
			rng.randf_range(
				-10.0,
				10.0
			),
			rng.randf_range(
				-5.0,
				16.0
			),
			rng.randf_range(
				-10.0,
				10.0
			)
		)


		var mat := StandardMaterial3D.new()

		mat.albedo_color = Color(
			1.0,
			rng.randf_range(
				0.12,
				0.42
			),
			0.015
		)


		mat.emission_enabled = true

		mat.emission = Color(
			1.0,
			0.08,
			0.01
		)

		mat.emission_energy_multiplier = 4.0

		flame.material_override = mat

		root.add_child(flame)


	var smoke := MeshInstance3D.new()

	var smoke_mesh := SphereMesh.new()

	smoke_mesh.radius = (
		radius *
		0.48
	)

	smoke_mesh.height = (
		radius *
		0.9
	)

	smoke.mesh = smoke_mesh

	smoke.position = Vector3(
		0.0,
		35.0,
		0.0
	)


	var smoke_mat := StandardMaterial3D.new()

	smoke_mat.albedo_color = Color(
		0.035,
		0.035,
		0.04,
		0.68
	)

	smoke_mat.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)

	smoke_mat.roughness = 1.0

	smoke.material_override = smoke_mat

	root.add_child(smoke)


	return root


# ============================================================
# EARTHQUAKE DEBRIS
# ============================================================

func _spawn_debris() -> void:

	for i in range(34):

		var d := MeshInstance3D.new()

		var bm := BoxMesh.new()

		bm.size = Vector3(
			rng.randf_range(
				1.0,
				5.0
			),
			rng.randf_range(
				1.0,
				5.0
			),
			rng.randf_range(
				1.0,
				5.0
			)
		)

		d.mesh = bm


		var angle: float = (
			rng.randf_range(
				0.0,
				TAU
			)
		)


		var distance: float = (
			rng.randf_range(
				5.0,
				65.0
			)
		)


		d.position = (
			current_disaster_position +
			Vector3(
				cos(angle) * distance,
				rng.randf_range(
					0.0,
					6.0
				),
				sin(angle) * distance
			)
		)


		d.rotation = Vector3(
			rng.randf_range(
				0.0,
				3.0
			),
			rng.randf_range(
				0.0,
				3.0
			),
			rng.randf_range(
				0.0,
				3.0
			)
		)


		d.material_override = _mat(
			Color(
				0.28,
				0.26,
				0.24
			),
			0.9
		)


		d.name = (
			"DEBRIS-%03d"
			% i
		)


		add_child(d)

		debris.append(d)


# ============================================================
# HAZARD ANIMATION
# ============================================================

func _animate_hazards() -> void:

	for fire in fires:

		if not is_instance_valid(fire):
			continue


		var pulse: float = (
			1.0 +
			sin(
				elapsed * 8.0 +
				float(
					fire.get_instance_id() % 20
				)
			) *
			0.08
		)


		fire.scale = (
			Vector3.ONE *
			pulse
		)


	# Earthquake movement is handled by the city/building visual system.
	# Never accumulate random fire.position offsets frame after frame.
	if quake_intensity > 0.0:
		for fire in fires:
			if is_instance_valid(fire):
				var fire_phase: float = float(fire.get_instance_id() % 17) * 0.4
				var fire_scale: float = 1.0 + quake_intensity * 0.12 + sin(elapsed * 18.0 + fire_phase) * 0.05
				fire.scale = Vector3.ONE * fire_scale


# ============================================================
# CIVILIAN BEACON
# ============================================================

func _set_civilian_beacon(
	person: Node3D,
	active_beacon: bool
) -> void:

	if not is_instance_valid(person):
		return


	var beacon := person.get_node_or_null(
		"StatusBeacon"
	)


	if beacon == null:
		return


	var material := StandardMaterial3D.new()

	if bool(person.get_meta("rescued", false)):
		material.albedo_color = Color(0.05, 1.0, 0.25)
		material.emission_enabled = true
		material.emission = Color(0.02, 1.0, 0.18)
		material.emission_energy_multiplier = 8.0
		beacon.material_override = material
		return

	if active_beacon:

		material.albedo_color = Color(
			1.0,
			0.08,
			0.02
		)

		material.emission_enabled = true

		material.emission = Color(
			1.0,
			0.04,
			0.01
		)

		material.emission_energy_multiplier = 6.0

	else:

		material.albedo_color = Color(
			0.20,
			0.28,
			0.30
		)

		material.emission_enabled = true

		material.emission = Color(
			0.05,
			0.08,
			0.09
		)

		material.emission_energy_multiplier = 1.5


	beacon.material_override = material


# ============================================================
# MATERIAL
# ============================================================

func _mat(
	color: Color,
	roughness: float = 0.8,
	metallic: float = 0.0
) -> StandardMaterial3D:

	var material := StandardMaterial3D.new()

	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic

	return material

# ============================================================
# CLOSED-LOOP SEARCH / RESPONSE API
# ============================================================

func get_searchable_victims() -> Array:
	var result: Array = []
	for person in victims:
		if not is_instance_valid(person):
			continue
		if bool(person.get_meta("rescued", false)):
			continue
		if bool(person.get_meta("resqnet_detected", false)):
			continue
		var status := str(person.get_meta("status", ""))
		if status == "STRANDED" or status == "TRAPPED" or status == "FLOOD_STRANDED" or status == FLOOD_WALL_STRANDED or status == FLOOD_ROOFTOP_STRANDED:
			result.append(person)
	return result

func get_victim_by_resq_id(victim_id: String) -> Node3D:
	for person in civilians:
		if not is_instance_valid(person):
			continue
		if str(person.get_meta("resqnet_victim_id", "")) == victim_id:
			return person
	return null

func apply_response_action(victim_id: String, action: String) -> Dictionary:
	var victim := get_victim_by_resq_id(victim_id)
	if victim == null:
		return {"success": false, "message": "Victim %s is not present in the Digital Twin." % victim_id}
	var normalized := action.to_upper()
	if bool(victim.get_meta("rescued", false)):
		return {"success": true, "message": "Victim is already safe.", "victim_status": "RESCUED", "green_light": true}

	if normalized == "MEDICAL_SUPPLY_DROP":
		victim.set_meta("medical_supplied", true)
		victim.set_meta("status", "RESCUED")
		victim.set_meta("rescued", true)
		victim.set_meta("hazard_mitigation", 0.35)
		_set_civilian_beacon(victim, false)
		_create_relief_zone(victim, Color(0.1, 0.9, 0.55))
		_set_response_label(victim, "RESCUED • MEDICAL STABILIZED", Color(0.2, 1.0, 0.55))
		event_changed.emit("MEDICAL RESPONSE  |  %s  |  SURVIVOR STABILIZED  |  GREEN SAFE STATE" % victim_id)
		return {"success": true, "message": "Medical response completed; survivor stabilized and marked safe.", "victim_status": "RESCUED", "green_light": true}

	if normalized == "HEAVY_EXTRICATION" or normalized == "STRUCTURAL_SURVEY":
		victim.set_meta("extrication_complete", true)
		victim.set_meta("hazard_mitigation", 1.0)
		_create_relief_zone(victim, Color(0.1, 0.9, 0.55))
		_set_response_label(victim, "RESCUED • EXTRICATION COMPLETE", Color(0.2, 1.0, 0.3))
		if city != null and "buildings" in city:
			for b in city.buildings:
				if b is Dictionary and b.has("position"):
					var bp: Vector3 = b["position"]
					if Vector2(bp.x, bp.z).distance_to(Vector2(victim.position.x, victim.position.z)) < 55.0:
						b["damage"] = maxf(0.0, float(b.get("damage", 0.0)) * 0.45)
		victim.set_meta("rescued", true)
		victim.set_meta("status", "RESCUED")
		_set_civilian_beacon(victim, false)
		event_changed.emit("HEAVY LIFT  |  %s  |  EXTRICATION COMPLETE  |  SURVIVOR SAFE" % victim_id)
		return {"success": true, "message": "Extrication completed; survivor marked safe and local structural risk reduced.", "victim_status": "RESCUED", "green_light": true}

	if normalized == "RESCUE_EXTRACTION" or normalized == "RESCUE_TRIAGE":
		victim.set_meta("status", "RESCUED")
		victim.set_meta("rescued", true)
		victim.set_meta("hazard_mitigation", 1.0)
		victim.set_meta("rescue_completed_at", Time.get_unix_time_from_system())
		_set_civilian_beacon(victim, false)
		_create_relief_zone(victim, Color(0.1, 1.0, 0.3))
		_set_response_label(victim, "RESCUED • SAFE", Color(0.2, 1.0, 0.3))
		event_changed.emit("RESCUE COMPLETE  |  %s  |  SURVIVOR EXTRACTED  |  GREEN SAFE LIGHT" % victim_id)
		return {"success": true, "message": "Survivor extracted and local zone marked safe.", "victim_status": "RESCUED", "green_light": true}

	return {"success": false, "message": "Unsupported response action %s." % action}

func _set_response_label(victim: Node3D, text: String, label_color: Color) -> void:
	var victim_id := str(victim.get_meta("resqnet_victim_id", victim.name))
	if response_labels.has(victim_id) and is_instance_valid(response_labels[victim_id]):
		response_labels[victim_id].queue_free()
	var label := Label3D.new()
	label.text = text
	label.font_size = 32
	label.outline_size = 7
	label.modulate = label_color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = victim.position + Vector3(0.0, 9.0, 0.0)
	add_child(label)
	response_labels[victim_id] = label

func _create_relief_zone(victim: Node3D, zone_color: Color) -> void:
	var victim_id := str(victim.get_meta("resqnet_victim_id", victim.name))
	if response_relief_zones.has(victim_id):
		return
	var zone := MeshInstance3D.new()
	zone.name = "SAFE-ZONE-" + victim_id
	var mesh := CylinderMesh.new()
	mesh.top_radius = 18.0
	mesh.bottom_radius = 18.0
	mesh.height = 0.12
	zone.mesh = mesh
	zone.position = victim.position + Vector3(0.0, 0.08, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(zone_color.r, zone_color.g, zone_color.b, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = zone_color
	material.emission_energy_multiplier = 2.5
	zone.material_override = material
	add_child(zone)
	response_relief_zones[victim_id] = zone

func _update_response_relief(delta: float) -> void:
	for victim_id in response_relief_zones.keys():
		var zone = response_relief_zones[victim_id]
		if not is_instance_valid(zone):
			response_relief_zones.erase(victim_id)
			continue
		zone.rotation.y += delta * 0.35
		var pulse := 1.0 + sin(elapsed * 3.0) * 0.08
		zone.scale = Vector3.ONE * pulse
		if response_labels.has(victim_id) and is_instance_valid(response_labels[victim_id]):
			var victim := get_victim_by_resq_id(victim_id)
			if victim != null:
				response_labels[victim_id].position = victim.position + Vector3(0.0, 9.0, 0.0)
		for fire in fires:
			if is_instance_valid(fire) and fire.global_position.distance_to(zone.global_position) < 55.0:
				fire.scale = fire.scale.lerp(Vector3.ONE * 0.18, delta * 0.15)
				if fire.scale.x < 0.22:
					fire.queue_free()
					fires.erase(fire)
