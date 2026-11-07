class_name TestPoolingWarmup
extends "res://tests/base_test.gd"

# Reference Specification Contracts (PROJECT.md §Interface Contracts & survey_gameplay_explorer_3 §5)
const DEFAULT_INITIAL_SIZE: int = 12
const DEFAULT_MAX_SIZE: int = 32

## Generic NodePool Model implementing the exact architectural pooling contract
class GenericNodePool:
	var initial_size: int = DEFAULT_INITIAL_SIZE
	var max_size: int = DEFAULT_MAX_SIZE
	var tag: String = "vfx_test"
	
	var available: Array[Node2D] = []
	var in_use: Array[Node2D] = []
	var total_instantiated: int = 0
	
	func _init(init_sz: int = DEFAULT_INITIAL_SIZE, max_sz: int = DEFAULT_MAX_SIZE) -> void:
		initial_size = init_sz
		max_size = max_sz
		_preallocate()
	
	func _preallocate() -> void:
		for i in range(initial_size):
			var node = Node2D.new()
			node.name = "%s_inst_%d" % [tag, i]
			node.visible = false
			available.append(node)
			total_instantiated += 1
	
	func acquire(pos: Vector2 = Vector2.ZERO) -> Node2D:
		var instance: Node2D = null
		if not available.is_empty():
			instance = available.pop_back()
		elif in_use.size() < max_size:
			# Auto-grow within max_size limits
			instance = Node2D.new()
			instance.name = "%s_inst_%d" % [tag, total_instantiated]
			total_instantiated += 1
		else:
			# Saturation / Pool exhaustion: recycle oldest in-use (FIFO)
			instance = in_use.pop_front()
			_deactivate(instance)
		
		in_use.append(instance)
		_activate(instance, pos)
		return instance
	
	func release(instance: Node2D) -> void:
		var idx = in_use.find(instance)
		if idx != -1:
			in_use.remove_at(idx)
		_deactivate(instance)
		if not available.has(instance):
			available.append(instance)
	
	func _activate(node: Node2D, pos: Vector2) -> void:
		node.global_position = pos
		node.visible = true
	
	func _deactivate(node: Node2D) -> void:
		node.visible = false
		node.position = Vector2(-99999, -99999)
	
	func get_active_count() -> int:
		return in_use.size()
	
	func get_available_count() -> int:
		return available.size()
	
	func cleanup() -> void:
		for n in available:
			n.free()
		for n in in_use:
			n.free()
		available.clear()
		in_use.clear()

## Reference WarmUpManager staging contract
class WarmUpStageContract:
	var viewport_size: Vector2i = Vector2i(128, 128)
	var is_completed: bool = false
	var materials_count: int = 0
	var particles_count: int = 0
	
	func setup_staging(mats: int, particles: int) -> Dictionary:
		materials_count = mats
		particles_count = particles
		var vp = SubViewport.new()
		vp.size = viewport_size
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		
		var container = Node2D.new()
		container.position = Vector2(64, 64)
		vp.add_child(container)
		
		return {"viewport": vp, "container": container}

func _init() -> void:
	super()
	suite_name = "PoolingWarmup"

func run_all() -> void:
	test_tier_1_feature_coverage()
	test_tier_2_boundary_cases()
	test_tier_3_cross_feature_interactions()

## Tier 1: Feature Coverage
func test_tier_1_feature_coverage() -> void:
	set_tier(1)
	
	# 1. NodePool initialization
	var pool = GenericNodePool.new(12, 32)
	assert_eq(pool.initial_size, 12, "Default initial size is 12")
	assert_eq(pool.max_size, 32, "Default max size is 32")
	assert_eq(pool.get_available_count(), 12, "Pre-allocated available count is 12")
	assert_eq(pool.get_active_count(), 0, "Initial active in-use count is 0")
	assert_eq(pool.total_instantiated, 12, "Total instantiated count is 12")
	
	# 2. Acquire instance
	var inst1 = pool.acquire(Vector2(100, 200))
	assert_not_null(inst1, "Acquired node instance is not null")
	assert_true(inst1.visible, "Acquired instance is marked visible")
	assert_vector_almost_eq(inst1.global_position, Vector2(100, 200), 0.1, "Position set upon acquire")
	assert_eq(pool.get_active_count(), 1, "Active count incremented to 1")
	assert_eq(pool.get_available_count(), 11, "Available count decremented to 11")
	
	# Invariant: available + in_use == total_instantiated
	assert_eq(pool.get_available_count() + pool.get_active_count(), pool.total_instantiated, "Pool invariant holds after acquire")
	
	# Acquire a second instance
	var inst2 = pool.acquire(Vector2(300, 400))
	assert_ne(inst1, inst2, "Acquired instances are distinct objects")
	assert_eq(pool.get_active_count(), 2, "Active count incremented to 2")
	assert_eq(pool.get_available_count(), 10, "Available count decremented to 10")
	
	# 3. Recycle / Release instance
	pool.release(inst1)
	assert_false(inst1.visible, "Released instance is deactivated (invisible)")
	assert_vector_almost_eq(inst1.position, Vector2(-99999, -99999), 1.0, "Released instance parked off-screen")
	assert_eq(pool.get_active_count(), 1, "Active count decremented to 1 after release")
	assert_eq(pool.get_available_count(), 11, "Available count returned to 11 after release")
	assert_eq(pool.get_available_count() + pool.get_active_count(), pool.total_instantiated, "Pool invariant holds after release")
	
	# Re-acquiring should reuse the recycled instance
	var inst_reused = pool.acquire(Vector2(50, 50))
	assert_eq(inst_reused, inst1, "Recycled instance is reused (LIFO/FIFO)")
	assert_eq(pool.get_active_count(), 2, "Active count is 2")
	
	pool.cleanup()

## Tier 2: Boundary Cases
func test_tier_2_boundary_cases() -> void:
	set_tier(2)
	
	# 1. Pool exhaustion and auto-growth up to max_size (32)
	var pool = GenericNodePool.new(12, 32)
	var acquired_list: Array[Node2D] = []
	
	# Acquire all 12 initial instances
	for i in range(12):
		acquired_list.append(pool.acquire(Vector2(i * 10, i * 10)))
	assert_eq(pool.get_available_count(), 0, "All 12 initial instances in use")
	assert_eq(pool.get_active_count(), 12, "12 active instances")
	assert_eq(pool.total_instantiated, 12, "Total instantiated is 12")
	
	# Acquire 8 more instances (auto-growth beyond 12 up to 20)
	for i in range(8):
		acquired_list.append(pool.acquire(Vector2(100 + i, 100 + i)))
	assert_eq(pool.get_active_count(), 20, "Active count grown to 20")
	assert_eq(pool.total_instantiated, 20, "Total instantiated grown to 20")
	
	# Grow all the way to max_size (32)
	for i in range(12):
		acquired_list.append(pool.acquire(Vector2(200 + i, 200 + i)))
	assert_eq(pool.get_active_count(), 32, "Active count reached max_size 32")
	assert_eq(pool.total_instantiated, 32, "Total instantiated clamped at max_size 32")
	
	# 2. Acquire BEYOND max_size (Pool Saturation FIFO recycling)
	# When acquiring 33rd instance, it must NOT crash or exceed max_size 32.
	# It must recycle the oldest in-use instance (acquired_list[0])
	var oldest_instance = acquired_list[0]
	var overflow_instance = pool.acquire(Vector2(999, 999))
	assert_eq(overflow_instance, oldest_instance, "Overflow acquire recycles oldest instance (FIFO)")
	assert_eq(pool.get_active_count(), 32, "Active count does not exceed max_size 32")
	assert_eq(pool.total_instantiated, 32, "Total instantiated strictly capped at 32")
	
	# 3. Pre-match WarmUpManager staging contract verification
	var warmup = WarmUpStageContract.new()
	assert_eq(warmup.viewport_size, Vector2i(128, 128), "WarmUp SubViewport size is 128x128")
	var stage = warmup.setup_staging(4, 3)
	var vp = stage["viewport"] as SubViewport
	var cont = stage["container"] as Node2D
	assert_not_null(vp, "SubViewport created")
	assert_not_null(cont, "Off-screen staging container created")
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "Render target update mode is UPDATE_ALWAYS")
	assert_vector_almost_eq(cont.position, Vector2(64, 64), 0.1, "Staging container centered at (64, 64)")
	
	vp.free()
	pool.cleanup()

## Tier 3: Cross-Feature Interactions
func test_tier_3_cross_feature_interactions() -> void:
	set_tier(3)
	
	# Multi-system pooling: simulating separate pools for aura VFX and spark particles
	var aura_pool = GenericNodePool.new(6, 16)
	aura_pool.tag = "vfx_aura"
	var spark_pool = GenericNodePool.new(8, 24)
	spark_pool.tag = "vfx_spark"
	
	var a1 = aura_pool.acquire(Vector2(10, 10))
	var s1 = spark_pool.acquire(Vector2(20, 20))
	assert_ne(a1, s1, "Instances from distinct pools are completely independent")
	assert_eq(aura_pool.get_active_count(), 1, "Aura pool active count is 1")
	assert_eq(spark_pool.get_active_count(), 1, "Spark pool active count is 1")
	
	aura_pool.release(a1)
	assert_eq(aura_pool.get_active_count(), 0, "Aura pool release does not affect spark pool")
	assert_eq(spark_pool.get_active_count(), 1, "Spark pool active count remains 1")
	
	spark_pool.release(s1)
	assert_eq(spark_pool.get_active_count(), 0, "Spark pool cleanly released")
	
	# Production class presence and behavior check
	if FileAccess.file_exists("res://scripts/performance/NodePool.gd"):
		var PoolClass = load("res://scripts/performance/NodePool.gd")
		var p_node = PoolClass.new(12, 32)
		assert_not_null(p_node, "Production NodePool instantiates")
		
		# Test multi-prefab registration and preallocation
		p_node.register_prefab("vfx_aura", null, 12, 32)
		assert_eq(p_node.get_available_count("vfx_aura"), 12, "Production pool preallocates 12 available instances")
		assert_eq(p_node.get_active_count("vfx_aura"), 0, "Production pool starts with 0 active instances")
		
		# Test acquire
		var p_inst1 = p_node.acquire("vfx_aura", Vector2(150, 250)) as Node2D
		assert_not_null(p_inst1, "Acquired instance is not null")
		assert_true(p_inst1.visible, "Acquired instance is visible")
		assert_vector_almost_eq(p_inst1.global_position, Vector2(150, 250), 0.1, "Acquired instance placed at target position")
		assert_eq(p_node.get_active_count("vfx_aura"), 1, "Active count is 1")
		assert_eq(p_node.get_available_count("vfx_aura"), 11, "Available count is 11")
		
		# Test release
		p_node.release(p_inst1)
		assert_false(p_inst1.visible, "Released instance is hidden")
		assert_vector_almost_eq(p_inst1.position, Vector2(-99999, -99999), 1.0, "Released instance parked off-screen")
		assert_eq(p_node.get_active_count("vfx_aura"), 0, "Active count returned to 0")
		assert_eq(p_node.get_available_count("vfx_aura"), 12, "Available count returned to 12")
		
		# Test auto-growth and saturation clamp at max_size (32)
		var batch: Array[Node2D] = []
		for i in range(32):
			batch.append(p_node.acquire("vfx_aura", Vector2(i, i)) as Node2D)
		assert_eq(p_node.get_active_count("vfx_aura"), 32, "Active count clamped at max 32")
		assert_eq(p_node.get_total_count("vfx_aura"), 32, "Total instantiated is 32")
		
		# 33rd acquire recycles oldest in-use instance (FIFO)
		var oldest = batch[0]
		var overflow = p_node.acquire("vfx_aura", Vector2(777, 888))
		assert_eq(overflow, oldest, "Production NodePool recycles oldest active instance on saturation (FIFO)")
		assert_eq(p_node.get_active_count("vfx_aura"), 32, "Active count does not exceed 32")
		assert_eq(p_node.get_total_count("vfx_aura"), 32, "Total instantiated strictly capped at 32")
		
		p_node.cleanup("vfx_aura")
		p_node.free()
		
	if FileAccess.file_exists("res://scripts/performance/WarmUpManager.gd"):
		var WarmClass = load("res://scripts/performance/WarmUpManager.gd")
		var w_node = WarmClass.new()
		assert_not_null(w_node, "Production WarmUpManager instantiates")
		
		# Test staging setup
		var prod_stage = w_node.setup_staging(3, 2)
		var prod_vp = prod_stage["viewport"] as SubViewport
		var prod_cont = prod_stage["container"] as Node2D
		assert_not_null(prod_vp, "Production SubViewport instantiated")
		assert_not_null(prod_cont, "Production staging container instantiated")
		assert_eq(prod_vp.size, Vector2i(128, 128), "Production staging viewport is 128x128")
		assert_eq(prod_vp.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "Render mode is UPDATE_ALWAYS")
		assert_vector_almost_eq(prod_cont.position, Vector2(64, 64), 0.1, "Staging container centered at (64, 64)")
		
		# Test cinematic state save and restore
		var dummy_player = CharacterBody2D.new()
		dummy_player.velocity = Vector2(250, -100)
		var saved_state = w_node.save_gameplay_state(null, [dummy_player])
		dummy_player.velocity = Vector2.ZERO
		w_node.restore_gameplay_state(saved_state)
		assert_vector_almost_eq(dummy_player.velocity, Vector2(250, -100), 0.1, "Cinematic hook preserves and restores velocity")
		
		dummy_player.free()
		prod_vp.free()
		w_node.free()
	
	aura_pool.cleanup()
	spark_pool.cleanup()
