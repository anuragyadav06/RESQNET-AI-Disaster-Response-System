class_name TrafficSystem
extends Node3D

var cars: Array=[]
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var graph: RoadGraph

func setup(p_graph: RoadGraph)->void:
	graph=p_graph
	rng.seed=1212
	var ids: Array = graph.edges.keys()
	for i in range(min(28,ids.size())):
		var e:Dictionary=graph.edges[ids[i]]
		var a:Vector3=graph.nodes[e["from"]]["position"]
		var b:Vector3=graph.nodes[e["to"]]["position"]
		var car: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new();bm.size=Vector3(2.2,1.0,4.2);car.mesh=bm
		var m: StandardMaterial3D=StandardMaterial3D.new();m.albedo_color=Color(0.55+rng.randf()*0.3,0.12+rng.randf()*0.18,0.08+rng.randf()*0.2);m.roughness=0.6
		car.material_override=m
		add_child(car)
		cars.append({"node":car,"a":a,"b":b,"t":rng.randf()})

func _process(delta:float)->void:
	for c in cars:
		c["t"]=fmod(float(c["t"])+delta*0.045,1.0)
		var p:Vector3=c["a"].lerp(c["b"],c["t"])
		c["node"].position=p+Vector3.UP*0.9
		c["node"].look_at(c["b"],Vector3.UP)
