class_name DroneFleet
extends Node3D

signal drone_event(text: String)

var drones: Array = []
var city: MetroCity
var demo_started: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func setup(p_city: MetroCity) -> void:
	city=p_city
	rng.seed=20260904
	_spawn_drone("DRONE-S01","SCOUT",Vector3(-80,120,-120))
	_spawn_drone("DRONE-M01","MEDICAL",Vector3(140,100,-180))
	_spawn_drone("DRONE-H01","HEAVY LIFT",Vector3(300,150,150))
	_spawn_drone("DRONE-R01","RELAY",Vector3(-280,170,250))
	_spawn_drone("DRONE-I01","INSPECTION",Vector3(220,130,330))

func start_demo() -> void:
	demo_started=true
	for d in drones:
		d["phase"]=1
	drone_event.emit("DRONE FLEET DEPLOYMENT INITIATED")

func _spawn_drone(id: String, kind: String, p: Vector3) -> void:
	var root: Node3D = Node3D.new()
	root.name=id
	root.position=p
	root.set_meta("simulation_id",id)
	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size=Vector3(3.6,0.8,3.6)
	body.mesh=box
	body.material_override=_mat(Color(0.10,0.12,0.14),0.4)
	root.add_child(body)
	for side in [-1.0,1.0]:
		for front in [-1.0,1.0]:
			var arm: MeshInstance3D = MeshInstance3D.new()
			var bm: CylinderMesh = CylinderMesh.new()
			bm.top_radius=0.12
			bm.bottom_radius=0.12
			bm.height=2.8
			arm.mesh=bm
			arm.rotation_degrees=Vector3(0,45,90)
			arm.position=Vector3(side*2.0,0,front*2.0)
			root.add_child(arm)
			var rotor: MeshInstance3D = MeshInstance3D.new()
			var sm: CylinderMesh = CylinderMesh.new()
			sm.top_radius=0.75
			sm.bottom_radius=0.75
			sm.height=0.08
			rotor.mesh=sm
			rotor.position=Vector3(side*2.0,0.5,front*2.0)
			rotor.material_override=_mat(Color(0.04,0.05,0.06),0.25)
			root.add_child(rotor)
	add_child(root)
	drones.append({"id":id,"type":kind,"node":root,"home":p,"target":p,"phase":0,"battery":100.0,"velocity":Vector3.ZERO,"mission":"IDLE"})

func _mat(c: Color,r: float=0.8,m: float=0.0)->StandardMaterial3D:
	var x: StandardMaterial3D=StandardMaterial3D.new();x.albedo_color=c;x.roughness=r;x.metallic=m;return x

func _process(delta: float) -> void:
	for d in drones:
		var n: Node3D=d["node"]
		if demo_started:
			var t: float=Time.get_ticks_msec()/1000.0
			var offset: float = float(drones.find(d))*1.25
			var center: Vector3 = Vector3(55,95,40)
			var target: Vector3 = center+Vector3(cos(t*0.28+offset)*170.0, sin(t*0.55+offset)*24.0, sin(t*0.33+offset)*170.0)
			d["target"]=target
			d["mission"]="SURVEY"
		var desired: Vector3=d["target"]-n.position
		if desired.length()>2.0:
			var max_speed: float = 28.0
			d["velocity"]=d["velocity"].lerp(desired.normalized()*max_speed,delta*1.8)
			n.position += d["velocity"]*delta
			n.look_at(n.position+d["velocity"],Vector3.UP)
			# Keep drone altitude believable.
			n.position.y=clamp(n.position.y,55.0,240.0)
		if demo_started:
			d["battery"]=max(0.0,float(d["battery"])-delta*0.32)
