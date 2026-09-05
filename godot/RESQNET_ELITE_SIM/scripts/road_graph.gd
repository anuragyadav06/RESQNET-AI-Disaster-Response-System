class_name RoadGraph
extends RefCounted

# Authoritative routing data. Rendering consumes this graph.

enum RoadType { HIGHWAY, ARTERIAL, COLLECTOR, LOCAL, SERVICE }

var nodes: Dictionary = {}
var edges: Dictionary = {}

func add_node(id: String, position: Vector3, district: String) -> void:
	if nodes.has(id):
		return
	nodes[id] = {"id": id, "position": position, "district": district, "connections": []}

func add_edge(id: String, a: String, b: String, road_type: int) -> void:
	if edges.has(id) or not nodes.has(a) or not nodes.has(b):
		return
	var length: float = nodes[a]["position"].distance_to(nodes[b]["position"])
	edges[id] = {"id": id, "from": a, "to": b, "type": road_type, "length": length, "accessible": true, "blocked": false, "capacity": _capacity(road_type)}
	nodes[a]["connections"].append(id)
	nodes[b]["connections"].append(id)

func _capacity(t: int) -> int:
	match t:
		RoadType.HIGHWAY: return 8
		RoadType.ARTERIAL: return 6
		RoadType.COLLECTOR: return 3
		_: return 1

func neighbors(id: String) -> Array:
	var out: Array = []
	if not nodes.has(id):
		return out
	for edge_id in nodes[id]["connections"]:
		var e: Dictionary = edges[edge_id]
		out.append(e["to"] if e["from"] == id else e["from"])
	return out

func nearest_node(p: Vector3) -> String:
	var best: String = ""
	var best_d: float = INF
	for id in nodes:
		var d: float = nodes[id]["position"].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = id
	return best

func validate() -> Dictionary:
	if nodes.is_empty():
		return {"connected": false, "nodes": 0, "edges": 0}
	var visited: Dictionary = {}
	var q: Array = [nodes.keys()[0]]
	while not q.is_empty():
		var id: String = q.pop_front()
		if visited.has(id):
			continue
		visited[id] = true
		for n in neighbors(id):
			if not visited.has(n):
				q.append(n)
	return {"connected": visited.size() == nodes.size(), "nodes": nodes.size(), "edges": edges.size(), "visited": visited.size()}
