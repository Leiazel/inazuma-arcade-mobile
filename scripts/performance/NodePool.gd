class_name NodePool
extends Node

## Generic object recycling system for GPUParticles2D, auras, projectiles, and VFX.
## Pre-allocates instances per key and strictly avoids runtime instantiate() and queue_free()
## during active gameplay by recycling inactive hidden instances with auto-growth up to max_size.

const DEFAULT_INITIAL_SIZE: int = 12
const DEFAULT_MAX_SIZE: int = 32
const OFFSCREEN_POSITION: Vector2 = Vector2(-99999, -99999)

@export var scene_template: PackedScene = null
@export var initial_size: int = DEFAULT_INITIAL_SIZE
@export var max_size: int = DEFAULT_MAX_SIZE
@export var tag: String = "default"

# Internal bucket per key:
# key -> {
#   "prefab": PackedScene,
#   "initial_size": int,
#   "max_size": int,
#   "available": Array[Node],
#   "in_use": Array[Node],
#   "total_instantiated": int
# }
var _pools: Dictionary = {}
var _node_to_key: Dictionary = {}

# Backward/model compatibility properties for single default pool
var available: Array:
	get:
		var p = _get_or_create_pool(tag)
		return p["available"]
var in_use: Array:
	get:
		var p = _get_or_create_pool(tag)
		return p["in_use"]
var total_instantiated: int:
	get:
		var p = _get_or_create_pool(tag)
		return p["total_instantiated"]
	set(val):
		var p = _get_or_create_pool(tag)
		p["total_instantiated"] = val

func _init(init_sz: int = DEFAULT_INITIAL_SIZE, max_sz: int = DEFAULT_MAX_SIZE) -> void:
	initial_size = init_sz
	max_size = max_sz

func _ready() -> void:
	if scene_template != null and not _pools.has(tag):
		register_prefab(tag, scene_template, initial_size, max_size)

## Registers a prefab scene under an identified pool key and pre-allocates initial instances
func register_prefab(key: String, packed_scene: PackedScene, init_count: int = DEFAULT_INITIAL_SIZE, max_count: int = DEFAULT_MAX_SIZE) -> void:
	if _pools.has(key):
		cleanup(key)

	var bucket = {
		"prefab": packed_scene,
		"initial_size": init_count,
		"max_size": max_count,
		"available": [] as Array[Node],
		"in_use": [] as Array[Node],
		"total_instantiated": 0
	}
	_pools[key] = bucket

	# Pre-allocate inactive instances off-screen
	for i in range(init_count):
		var inst: Node = null
		if packed_scene != null:
			inst = packed_scene.instantiate()
		else:
			inst = Node2D.new()

		inst.name = "%s_inst_%d" % [key, i]
		_deactivate_instance(inst)
		add_child(inst)
		bucket["available"].append(inst)
		bucket["total_instantiated"] += 1
		_node_to_key[inst] = key

## Acquires a pooled instance by key and position, or (pos) using the default tag
func acquire(arg1 = null, arg2: Vector2 = Vector2.ZERO) -> Node:
	var key: String = tag
	var pos: Vector2 = Vector2.ZERO

	if arg1 is String:
		key = arg1
		pos = arg2
	elif arg1 is Vector2:
		pos = arg1
	elif arg1 == null:
		pos = arg2

	var pool = _get_or_create_pool(key)
	var available_list: Array = pool["available"]
	var in_use_list: Array = pool["in_use"]
	var instance: Node = null

	if not available_list.is_empty():
		instance = available_list.pop_back()
	elif in_use_list.size() < pool["max_size"]:
		# Auto-growth within max_size limits
		if pool["prefab"] != null:
			instance = (pool["prefab"] as PackedScene).instantiate()
		else:
			instance = Node2D.new()
		instance.name = "%s_inst_%d" % [key, pool["total_instantiated"]]
		pool["total_instantiated"] += 1
		add_child(instance)
		_node_to_key[instance] = key
	else:
		# Saturation / Pool exhaustion: recycle oldest in-use instance (FIFO)
		instance = in_use_list.pop_front()
		_deactivate_instance(instance)

	in_use_list.append(instance)
	_node_to_key[instance] = key
	_activate_instance(instance, pos)
	return instance

## Recycles/releases an active instance back to its pool
func release(instance: Node) -> void:
	if not is_instance_valid(instance):
		return

	var key: String = tag
	if _node_to_key.has(instance):
		key = _node_to_key[instance]

	var pool = _pools.get(key)
	if pool != null:
		var in_use_list: Array = pool["in_use"]
		var idx = in_use_list.find(instance)
		if idx != -1:
			in_use_list.remove_at(idx)
		_deactivate_instance(instance)
		var avail_list: Array = pool["available"]
		if not avail_list.has(instance):
			avail_list.append(instance)

## Alias for release conforming to (key, node) or (node)
func recycle(arg1, arg2: Node = null) -> void:
	if arg1 is Node:
		release(arg1)
	elif arg2 != null:
		release(arg2)

func _activate_instance(node: Node, pos: Vector2) -> void:
	if node is Node2D:
		var n2d := node as Node2D
		n2d.global_position = pos
		n2d.visible = true

	if node is GPUParticles2D:
		var gpu_p := node as GPUParticles2D
		gpu_p.emitting = true
		gpu_p.restart()
		if gpu_p.one_shot:
			if not gpu_p.finished.is_connected(release.bind(gpu_p)):
				gpu_p.finished.connect(release.bind(gpu_p), CONNECT_ONE_SHOT)

func _deactivate_instance(node: Node) -> void:
	if node is GPUParticles2D:
		var gpu_p := node as GPUParticles2D
		gpu_p.emitting = false

	if node is Node2D:
		var n2d := node as Node2D
		n2d.visible = false
		n2d.position = OFFSCREEN_POSITION

## Count of currently active (in-use) instances
func get_active_count(key: String = "") -> int:
	var target_key = key if not key.is_empty() else tag
	var pool = _pools.get(target_key)
	if pool != null:
		return pool["in_use"].size()
	return 0

## Count of available (idle pooled) instances
func get_available_count(key: String = "") -> int:
	var target_key = key if not key.is_empty() else tag
	var pool = _pools.get(target_key)
	if pool != null:
		return pool["available"].size()
	return 0

## Total count of instantiated instances for key
func get_total_count(key: String = "") -> int:
	var target_key = key if not key.is_empty() else tag
	var pool = _pools.get(target_key)
	if pool != null:
		return pool["total_instantiated"]
	return 0

func has_pool(key: String) -> bool:
	return _pools.has(key)

func _get_or_create_pool(key: String) -> Dictionary:
	if not _pools.has(key):
		register_prefab(key, scene_template, initial_size, max_size)
	return _pools[key]

## Cleans up all nodes in the given pool (or all pools if key is empty)
func cleanup(key: String = "") -> void:
	var keys_to_clean: Array = []
	if not key.is_empty():
		if _pools.has(key):
			keys_to_clean.append(key)
	else:
		keys_to_clean = _pools.keys().duplicate()

	for k in keys_to_clean:
		var pool = _pools[k]
		for node in pool["available"]:
			if is_instance_valid(node):
				_node_to_key.erase(node)
				node.free()
		for node in pool["in_use"]:
			if is_instance_valid(node):
				_node_to_key.erase(node)
				node.free()
		pool["available"].clear()
		pool["in_use"].clear()
		pool["total_instantiated"] = 0
		if not key.is_empty():
			_pools.erase(k)
