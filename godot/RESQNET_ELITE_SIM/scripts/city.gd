class_name MetroCity
extends Node3D

# ============================================================
# RESQNET — SYSTEM B
# METRO DISASTER TWIN
#
# COMPACT ISOMETRIC CITY
#
# Designed around the supplied reference:
# - Compact footprint
# - Symmetrical road grid
# - Central roundabout
# - Deliberate urban blocks
# - Small number of buildings
# - High-rise + low-rise hierarchy
# - Homes
# - Commercial buildings
# - Parks
# - Trees
# - Open plots
# - Emergency infrastructure
# - Flood zone
#
# Godot 4.7+
# ============================================================


# ============================================================
# PUBLIC DATA
# ============================================================

var graph: RoadGraph

var buildings: Array = []
var road_meshes: Array = []
var trees: Array = []
var parks: Array = []
var flood_zones: Array = []


# ============================================================
# RNG
# ============================================================

var rng := RandomNumberGenerator.new()


# ============================================================
# CITY DIMENSIONS
# ============================================================

const CITY_HALF := 360.0

const ROAD_SPACING := 180.0

const ROAD_WIDTH := 16.0

const SIDEWALK_WIDTH := 5.0


# ============================================================
# ROAD GRID
#
# Compact:
#
#       -270   -90    90    270
#
#       +------+------+------+
#       |      |      |      |
#       |      |      |      |
#       +------+------+------+
#       |      |      |      |
#       |      | CBD  |      |
#       +------+------+------+
#       |      |      |      |
#       |      |      |      |
#       +------+------+------+
#
# ============================================================

var grid_x: Array[float] = [
	-270.0,
	-90.0,
	90.0,
	270.0
]

var grid_z: Array[float] = [
	-270.0,
	-90.0,
	90.0,
	270.0
]


# ============================================================
# BUILD
# ============================================================

func build() -> RoadGraph:

	rng.seed = 9192026

	graph = RoadGraph.new()

	_make_ground()

	_make_road_network()

	_make_city_layout()

	_make_central_roundabout()

	_make_landmarks()


	_make_trees()

	_make_street_lights()

	_make_flood_zone()

	_make_hero_tower()

	return graph


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
# BOX
# ============================================================

func _box(
	parent: Node3D,
	size: Vector3,
	position: Vector3,
	material: Material,
	node_name: String = "Mesh"
) -> MeshInstance3D:

	var instance := MeshInstance3D.new()

	instance.name = node_name

	var mesh := BoxMesh.new()

	mesh.size = size

	instance.mesh = mesh
	instance.position = position
	instance.material_override = material

	parent.add_child(instance)

	return instance


# ============================================================
# GROUND
# ============================================================

func _make_ground() -> void:

	var ground := MeshInstance3D.new()

	ground.name = "CITY-GROUND"

	var mesh := PlaneMesh.new()

	mesh.size = Vector2(
		760.0,
		760.0
	)

	mesh.subdivide_width = 12
	mesh.subdivide_depth = 12

	ground.mesh = mesh

	ground.position = Vector3(
		0,
		-2,
		0
	)

	ground.material_override = _mat(
		Color(
			0.055,
			0.075,
			0.070
		),
		0.98
	)

	add_child(ground)


# ============================================================
# ROAD NETWORK
#
# Shared nodes guarantee connectivity.
# ============================================================

func _make_road_network() -> void:

	var lookup: Dictionary = {}

	# --------------------------------------------------------
	# INTERSECTIONS
	# --------------------------------------------------------

	for x_index in range(grid_x.size()):

		for z_index in range(grid_z.size()):

			var position := Vector3(
				grid_x[x_index],
				0,
				grid_z[z_index]
			)

			var node_id := "INTERSECTION-%d-%d" % [
				x_index,
				z_index
			]

			graph.add_node(
				node_id,
				position,
				"URBAN"
			)

			lookup[
				"%d_%d" % [
					x_index,
					z_index
				]
			] = node_id


	# --------------------------------------------------------
	# HORIZONTAL ROADS
	# --------------------------------------------------------

	for z_index in range(grid_z.size()):

		for x_index in range(grid_x.size() - 1):

			var a: String = lookup[
				"%d_%d" % [
					x_index,
					z_index
				]
			]

			var b: String = lookup[
				"%d_%d" % [
					x_index + 1,
					z_index
				]
			]

			graph.add_edge(
				"ARTERIAL-H-%d-%d" % [
					x_index,
					z_index
				],
				a,
				b,
				RoadGraph.RoadType.ARTERIAL
			)


	# --------------------------------------------------------
	# VERTICAL ROADS
	# --------------------------------------------------------

	for x_index in range(grid_x.size()):

		for z_index in range(grid_z.size() - 1):

			var a: String = lookup[
				"%d_%d" % [
					x_index,
					z_index
				]
			]

			var b: String = lookup[
				"%d_%d" % [
					x_index,
					z_index + 1
				]
			]

			graph.add_edge(
				"ARTERIAL-V-%d-%d" % [
					x_index,
					z_index
				],
				a,
				b,
				RoadGraph.RoadType.ARTERIAL
			)


	# --------------------------------------------------------
	# RENDER
	# --------------------------------------------------------

	for edge in graph.edges.values():

		_render_road(edge)


# ============================================================
# ROAD RENDERING
# ============================================================

func _render_road(edge: Dictionary) -> void:

	var a: Vector3 = graph.nodes[
		str(edge["from"])
	]["position"]

	var b: Vector3 = graph.nodes[
		str(edge["to"])
	]["position"]

	var midpoint := (
		a + b
	) * 0.5

	var length := a.distance_to(b)

	var root := Node3D.new()

	root.name = str(edge["id"])

	root.set_meta(
		"simulation_id",
		str(edge["id"])
	)

	add_child(root)

	# --------------------------------------------------------
	# ASPHALT
	# --------------------------------------------------------

	var asphalt := _mat(
		Color(
			0.035,
			0.045,
			0.055
		),
		0.95
	)

	var road := _box(
		root,
		Vector3(
			ROAD_WIDTH,
			0.35,
			length
		),
		Vector3(
			midpoint.x,
			0,
			midpoint.z
		),
		asphalt,
		"ROAD"
	)

	road.look_at(
		Vector3(
			b.x,
			0,
			b.z
		),
		Vector3.UP
	)

	road_meshes.append(road)


	# --------------------------------------------------------
	# CURBS
	# --------------------------------------------------------

	var curb_material := _mat(
		Color(
			0.32,
			0.33,
			0.31
		),
		0.9
	)

	for side in [-1.0, 1.0]:

		var curb := _box(
			root,
			Vector3(
				0.65,
				0.5,
				length
			),
			Vector3(
				midpoint.x +
				side * ROAD_WIDTH * 0.5,
				0.25,
				midpoint.z
			),
			curb_material,
			"CURB"
		)

		curb.look_at(
			Vector3(
				b.x,
				0.25,
				b.z
			),
			Vector3.UP
		)


	# --------------------------------------------------------
	# CENTER LINE
	# --------------------------------------------------------

	var marking := _box(
		root,
		Vector3(
			0.28,
			0.05,
			length * 0.78
		),
		Vector3(
			midpoint.x,
			0.21,
			midpoint.z
		),
		_mat(
			Color(
				0.72,
				0.65,
				0.35
			),
			0.75
		),
		"ROAD-MARKING"
	)

	marking.look_at(
		Vector3(
			b.x,
			0.21,
			b.z
		),
		Vector3.UP
	)


# ============================================================
# CITY LAYOUT
#
# Deliberately hand-designed.
# ============================================================

func _make_city_layout() -> void:

	# --------------------------------------------------------
	# WEST RESIDENTIAL
	# --------------------------------------------------------

	_make_house(
		Vector3(-225,0,-180),
		"RESIDENTIAL"
	)

	_make_house(
		Vector3(-135,0,-180),
		"RESIDENTIAL"
	)

	_make_house(
		Vector3(-225,0,-90),
		"RESIDENTIAL"
	)

	_make_house(
		Vector3(-135,0,-90),
		"RESIDENTIAL"
	)


	# --------------------------------------------------------
	# NORTH-WEST OPEN / PARK
	# --------------------------------------------------------

	_make_park(
		Vector3(-180,0,180),
		Vector2(140,125),
		"PARK-NW"
	)


	# --------------------------------------------------------
	# CENTRAL CBD
	# --------------------------------------------------------

	_make_tower(
		Vector3(-35,0,-35),
		72.0
	)

	_make_tower(
		Vector3(115,0,-35),
		105.0
	)

	_make_tower(
		Vector3(-35,0,115),
		88.0
	)

	_make_commercial(
		Vector3(115,0,115),
		Vector3(65,38,52)
	)


	# --------------------------------------------------------
	# EAST COMMERCIAL
	# --------------------------------------------------------

	_make_commercial(
		Vector3(225,0,-135),
		Vector3(70,42,48)
	)

	_make_commercial(
		Vector3(225,0,-45),
		Vector3(55,28,42)
	)


	# --------------------------------------------------------
	# NORTH-EAST
	# --------------------------------------------------------

	_make_commercial(
		Vector3(225,0,135),
		Vector3(70,32,48)
	)


	# --------------------------------------------------------
	# SOUTH-WEST HOMES
	# --------------------------------------------------------

	_make_house(
		Vector3(-225,0,135),
		"SUBURBAN"
	)

	_make_house(
		Vector3(-135,0,135),
		"SUBURBAN"
	)


	# --------------------------------------------------------
	# SOUTH-CENTRAL LOW RISE
	# --------------------------------------------------------

	_make_lowrise(
		Vector3(-35,0,225),
		Vector3(45,18,42)
	)

	_make_lowrise(
		Vector3(55,0,225),
		Vector3(55,24,45)
	)


	# --------------------------------------------------------
	# SOUTH-EAST INDUSTRIAL
	# --------------------------------------------------------

	_make_warehouse(
		Vector3(220,0,225)
	)

	# --------------------------------------------------------
	# SMALL OPEN PLOTS
	# --------------------------------------------------------

	_make_open_plot(
		Vector3(-225,0,45),
		Vector2(105,90)
	)

	_make_open_plot(
		Vector3(225,0,45),
		Vector2(95,80)
	)


# ============================================================
# HOUSE
# ============================================================

func _make_house(
	position: Vector3,
	district: String
) -> void:

	var root := Node3D.new()

	root.name = "HOUSE-%03d" % buildings.size()

	root.set_meta(
		"simulation_id",
		root.name
	)

	root.set_meta(
		"building_type",
		"RESIDENTIAL_HOUSE"
	)

	var width := 26.0
	var depth := 24.0
	var height := 10.0

	_box(
		root,
		Vector3(
			width,
			height,
			depth
		),
		Vector3(
			0,
			height * 0.5,
			0
		),
		_mat(
			Color(
				0.36,
				0.35,
				0.31
			),
			0.9
		)
	)

	# Roof.

	_box(
		root,
		Vector3(
			width + 3,
			1.5,
			depth + 3
		),
		Vector3(
			0,
			height + 0.75,
			0
		),
		_mat(
			Color(
				0.17,
				0.18,
				0.17
			),
			0.92
		)
	)

	# Porch.

	_box(
		root,
		Vector3(
			12,
			0.5,
			4
		),
		Vector3(
			0,
			0.25,
			14
		),
		_mat(
			Color(
				0.24,
				0.23,
				0.21
			),
			0.9
		)
	)

	root.position = position

	add_child(root)

	buildings.append({
		"id":root.name,
		"district":district,
		"position":position,
		"height":height,
		"damage":0.0,
		"building_type":"RESIDENTIAL_HOUSE",
		"flood_risk":0.65,
		"occupants":rng.randi_range(3,8)
	})


# ============================================================
# LOW RISE
# ============================================================

func _make_lowrise(
	position: Vector3,
	size: Vector3
) -> void:

	var root := Node3D.new()

	root.name = "LOWRISE-%03d" % buildings.size()

	_box(
		root,
		size,
		Vector3(
			0,
			size.y * 0.5,
			0
		),
		_mat(
			Color(
				0.38,
				0.39,
				0.37
			),
			0.82
		)
	)

	# Windows / facade.

	_box(
		root,
		Vector3(
			size.x * 0.7,
			size.y * 0.55,
			0.12
		),
		Vector3(
			0,
			size.y * 0.5,
			size.z * 0.501
		),
		_mat(
			Color(
				0.10,
				0.18,
				0.20
			),
			0.25
		)
	)

	root.position = position

	add_child(root)

	buildings.append({
		"id":root.name,
		"district":"COMMERCIAL",
		"position":position,
		"height":size.y,
		"damage":0.0,
		"building_type":"LOW_RISE",
		"flood_risk":0.45,
		"occupants":rng.randi_range(10,40)
	})


# ============================================================
# CBD TOWER
# ============================================================

func _make_tower(
	position: Vector3,
	height: float
) -> void:

	var root := Node3D.new()

	root.name = "CBD-TOWER-%03d" % buildings.size()

	root.set_meta(
		"simulation_id",
		root.name
	)

	root.set_meta(
		"building_type",
		"HIGH_RISE"
	)

	var width := 34.0
	var depth := 34.0

	_box(
		root,
		Vector3(
			width,
			height,
			depth
		),
		Vector3(
			0,
			height * 0.5,
			0
		),
		_mat(
			Color(
				0.31,
				0.37,
				0.41
			),
			0.35,
			0.08
		)
	)

	# Front glass.

	_box(
		root,
		Vector3(
			width * 0.70,
			height * 0.76,
			0.12
		),
		Vector3(
			0,
			height * 0.49,
			depth * 0.501
		),
		_mat(
			Color(
				0.07,
				0.16,
				0.20
			),
			0.22,
			0.08
		)
	)

	# Horizontal floor bands.

	for level in range(
		8,
		int(height),
		12
	):

		_box(
			root,
			Vector3(
				width + 1,
				0.35,
				depth + 1
			),
			Vector3(
				0,
				level,
				0
			),
			_mat(
				Color(
					0.24,
					0.27,
					0.28
				),
				0.75
			)
		)

	root.position = position

	add_child(root)

	buildings.append({
		"id":root.name,
		"district":"CBD",
		"position":position,
		"height":height,
		"damage":0.0,
		"building_type":"HIGH_RISE",
		"flood_risk":0.20,
		"occupants":rng.randi_range(40,120)
	})


# ============================================================
# COMMERCIAL
# ============================================================

func _make_commercial(
	position: Vector3,
	size: Vector3
) -> void:

	var root := Node3D.new()

	root.name = "COMMERCIAL-%03d" % buildings.size()

	_box(
		root,
		size,
		Vector3(
			0,
			size.y * 0.5,
			0
		),
		_mat(
			Color(
				0.40,
				0.41,
				0.39
			),
			0.76
		)
	)

	# Glass front.

	_box(
		root,
		Vector3(
			size.x * 0.76,
			size.y * 0.62,
			0.12
		),
		Vector3(
			0,
			size.y * 0.48,
			size.z * 0.501
		),
		_mat(
			Color(
				0.08,
				0.18,
				0.20
			),
			0.22
		)
	)

	root.position = position

	add_child(root)

	buildings.append({
		"id":root.name,
		"district":"COMMERCIAL",
		"position":position,
		"height":size.y,
		"damage":0.0,
		"building_type":"COMMERCIAL",
		"flood_risk":0.40,
		"occupants":rng.randi_range(15,70)
	})


# ============================================================
# WAREHOUSE
# ============================================================

func _make_warehouse(
	position: Vector3
) -> void:

	var root := Node3D.new()

	root.name = "INDUSTRIAL-WAREHOUSE-%03d" % buildings.size()

	var size := Vector3(
		82,
		20,
		58
	)

	_box(
		root,
		size,
		Vector3(
			0,
			10,
			0
		),
		_mat(
			Color(
				0.26,
				0.28,
				0.27
			),
			0.9
		)
	)

	# Loading bays.

	for x in [-25.0,0.0,25.0]:

		_box(
			root,
			Vector3(
				15,
				10,
				0.8
			),
			Vector3(
				x,
				5,
				29.5
			),
			_mat(
				Color(
					0.14,
					0.16,
					0.16
				),
				0.85
			)
		)

	root.position = position

	add_child(root)

	buildings.append({
		"id":root.name,
		"district":"INDUSTRIAL",
		"position":position,
		"height":20.0,
		"damage":0.0,
		"building_type":"WAREHOUSE",
		"flood_risk":0.80,
		"occupants":25
	})


# ============================================================
# OPEN PLOT
# ============================================================

func _make_open_plot(
	position: Vector3,
	size: Vector2
) -> void:

	var plot := MeshInstance3D.new()

	plot.name = "OPEN-PLOT-%03d" % parks.size()

	var mesh := PlaneMesh.new()

	mesh.size = size

	plot.mesh = mesh

	plot.position = Vector3(
		position.x,
		-1.45,
		position.z
	)

	plot.material_override = _mat(
		Color(
			0.075,
			0.105,
			0.080
		),
		0.98
	)

	add_child(plot)


# ============================================================
# PARK
# ============================================================

func _make_park(
	position: Vector3,
	size: Vector2,
	id: String
) -> void:

	var park := MeshInstance3D.new()

	park.name = id

	var mesh := PlaneMesh.new()

	mesh.size = size

	park.mesh = mesh

	park.position = Vector3(
		position.x,
		-1.45,
		position.z
	)

	park.material_override = _mat(
		Color(
			0.07,
			0.19,
			0.09
		),
		0.98
	)

	add_child(park)

	parks.append(park)


# ============================================================
# TREES
# ============================================================

func _make_trees() -> void:

	# --------------------------------------------------------
	# PARK TREES
	# --------------------------------------------------------

	for park in parks:

		for i in range(14):

			var x := rng.randf_range(
				-55,
				55
			)

			var z := rng.randf_range(
				-45,
				45
			)

			_make_tree(
				park.position +
				Vector3(
					x,
					1.0,
					z
				)
			)


	# --------------------------------------------------------
	# STREET TREES
	# --------------------------------------------------------

	var street_tree_positions := [
		Vector3(-180,0,-180),
		Vector3(-90,0,-180),
		Vector3(90,0,-180),
		Vector3(180,0,-180),

		Vector3(-180,0,180),
		Vector3(-90,0,180),
		Vector3(90,0,180),
		Vector3(180,0,180),

		Vector3(-180,0,0),
		Vector3(180,0,0)
	]

	for position in street_tree_positions:

		_make_tree(position)


# ============================================================
# TREE
# ============================================================

func _make_tree(position: Vector3) -> void:

	var root := Node3D.new()

	root.name = "TREE-%03d" % trees.size()

	_box(
		root,
		Vector3(
			1.2,
			5.5,
			1.2
		),
		Vector3(
			0,
			2.75,
			0
		),
		_mat(
			Color(
				0.24,
				0.15,
				0.08
			),
			0.95
		)
	)

	var crown := MeshInstance3D.new()

	var mesh := SphereMesh.new()

	mesh.radius = 4.2
	mesh.height = 8.4

	crown.mesh = mesh

	crown.position.y = 7

	crown.material_override = _mat(
		Color(
			0.06,
			0.20,
			0.08
		),
		0.95
	)

	root.add_child(crown)

	root.position = position

	add_child(root)

	trees.append(root)


# ============================================================
# CENTRAL ROUNDABOUT
#
# This is one of the major visual signatures of the reference.
# ============================================================

func _make_central_roundabout() -> void:

	var root := Node3D.new()

	root.name = "CENTRAL-ROUNDABOUT"

	add_child(root)

	# Outer road ring.

	var outer := MeshInstance3D.new()

	var outer_mesh := CylinderMesh.new()

	outer_mesh.top_radius = 38.0
	outer_mesh.bottom_radius = 38.0
	outer_mesh.height = 0.35

	outer.mesh = outer_mesh

	outer.position.y = 0.15

	outer.material_override = _mat(
		Color(
			0.035,
			0.045,
			0.055
		),
		0.95
	)

	root.add_child(outer)

	# Green central island.

	var island := MeshInstance3D.new()

	var island_mesh := CylinderMesh.new()

	island_mesh.top_radius = 21.0
	island_mesh.bottom_radius = 21.0
	island_mesh.height = 0.5

	island.mesh = island_mesh

	island.position.y = 0.45

	island.material_override = _mat(
		Color(
			0.08,
			0.20,
			0.10
		),
		0.95
	)

	root.add_child(island)

	# Monument.

	var monument := MeshInstance3D.new()

	var monument_mesh := CylinderMesh.new()

	monument_mesh.top_radius = 5.0
	monument_mesh.bottom_radius = 7.0
	monument_mesh.height = 12.0

	monument.mesh = monument_mesh

	monument.position.y = 6.5

	monument.material_override = _mat(
		Color(
			0.45,
			0.46,
			0.42
		),
		0.8
	)

	root.add_child(monument)


# ============================================================
# STREET LIGHTS
# ============================================================

func _make_street_lights() -> void:

	var positions := [
		Vector3(-90,0,-155),
		Vector3(90,0,-155),
		Vector3(-90,0,155),
		Vector3(90,0,155),

		Vector3(-155,0,-90),
		Vector3(-155,0,90),
		Vector3(155,0,-90),
		Vector3(155,0,90)
	]

	for position in positions:

		var pole := MeshInstance3D.new()

		var pole_mesh := CylinderMesh.new()

		pole_mesh.top_radius = 0.35
		pole_mesh.bottom_radius = 0.45
		pole_mesh.height = 7.0

		pole.mesh = pole_mesh

		pole.position = position + Vector3(
			0,
			3.5,
			0
		)

		pole.material_override = _mat(
			Color(
				0.12,
				0.13,
				0.13
			),
			0.8,
			0.2
		)

		add_child(pole)


# ============================================================
# EMERGENCY LANDMARKS
# ============================================================

func _make_landmarks() -> void:

	_make_emergency(
		"HOSPITAL-001",
		"HOSPITAL",
		Vector3(
			270,
			0,
			-90
		),
		Color(
			0.76,
			0.78,
			0.78
		)
	)

	_make_emergency(
		"HOSPITAL-002",
		"HOSPITAL",
		Vector3(
			-270,
			0,
			90
		),
		Color(
			0.76,
			0.78,
			0.78
		)
	)

	_make_emergency(
		"FIRESTATION-001",
		"FIRE STATION",
		Vector3(
			180,
			0,
			-270
		),
		Color(
			0.62,
			0.24,
			0.20
		)
	)

	_make_emergency(
		"POLICE-001",
		"POLICE",
		Vector3(
			-180,
			0,
			-270
		),
		Color(
			0.19,
			0.28,
			0.42
		)
	)


# ============================================================
# EMERGENCY BUILDING
# ============================================================

func _make_emergency(
	id: String,
	kind: String,
	position: Vector3,
	color: Color
) -> void:

	var root := Node3D.new()

	root.name = id

	root.set_meta(
		"simulation_id",
		id
	)

	root.set_meta(
		"type",
		kind
	)

	_box(
		root,
		Vector3(
			34,
			9,
			28
		),
		Vector3(
			0,
			4.5,
			0
		),
		_mat(
			color,
			0.75
		)
	)

	_box(
		root,
		Vector3(
			14,
			17,
			13
		),
		Vector3(
			0,
			13,
			0
		),
		_mat(
			Color(
				0.32,
				0.36,
				0.38
			),
			0.72
		)
	)

	root.position = position

	add_child(root)


# ============================================================
# FLOOD ZONE
#
# NOT ACTIVE visually.
# DisasterController can activate it later.
# ============================================================

func _make_flood_zone() -> void:

	var root := Node3D.new()

	root.name = "FLOOD-ZONE"

	root.set_meta(
		"floodable",
		true
	)

	root.set_meta(
		"flood_level",
		0.0
	)

	var water := MeshInstance3D.new()

	water.name = "FloodWater"

	var mesh := PlaneMesh.new()

	mesh.size = Vector2(
		700,
		75
	)

	water.mesh = mesh

	water.position = Vector3(
		0,
		-1.6,
		345
	)

	water.material_override = _mat(
		Color(
			0.02,
			0.12,
			0.18
		),
		0.35,
		0.1
	)

	# Hidden until flood event.

	water.visible = false

	root.add_child(water)

	add_child(root)

	flood_zones.append({
		"id":"FLOOD-ZONE",
		"node":root,
		"water":water,
		"center":Vector3(
			0,
			0,
			345
		),
		"level":0.0,
		"active":false
	})


# ============================================================
# HERO TOWER
#
# Existing DisasterController fire:
# Vector3(55,0,40)
#
# Therefore keep this building near that location.
# ============================================================

func _make_hero_tower() -> void:

	var root := Node3D.new()

	root.name = "BUILDING-CBD-HERO-001"

	root.set_meta(
		"simulation_id",
		root.name
	)

	root.set_meta(
		"type",
		"HIGH_RISE"
	)

	root.set_meta(
		"district",
		"CBD"
	)

	var height := 135.0

	_box(
		root,
		Vector3(
			44,
			height,
			44
		),
		Vector3(
			0,
			height * 0.5,
			0
		),
		_mat(
			Color(
				0.18,
				0.26,
				0.31
			),
			0.30,
			0.10
		)
	)

	# Glass facade.

	_box(
		root,
		Vector3(
			32,
			height * 0.76,
			0.12
		),
		Vector3(
			0,
			height * 0.49,
			22.1
		),
		_mat(
			Color(
				0.06,
				0.15,
				0.20
			),
			0.22,
			0.08
		)
	)

	# Floor bands.

	for level in range(
		8,
		128,
		10
	):

		_box(
			root,
			Vector3(
				47,
				0.45,
				47
			),
			Vector3(
				0,
				level,
				0
			),
			_mat(
				Color(
					0.27,
					0.30,
					0.30
				),
				0.7
			)
		)

	# Rooftop.

	_box(
		root,
		Vector3(
			18,
			9,
			18
		),
		Vector3(
			0,
			height + 4.5,
			0
		),
		_mat(
			Color(
				0.11,
				0.13,
				0.14
			),
			0.9
		)
	)

	root.position = Vector3(
		55,
		0,
		40
	)

	add_child(root)

	buildings.append({
		"id":root.name,
		"district":"CBD",
		"position":root.position,
		"height":height,
		"damage":0.0,
		"building_type":"HIGH_RISE_HERO",
		"flood_risk":0.20,
		"occupants":180
	})
