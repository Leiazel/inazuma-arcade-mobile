class_name TestAdversarialM5
extends "res://tests/base_test.gd"

# ==============================================================================
# Adversarial Integration & Stress Test Suite — Milestone M5
# Target: Godot Engine 4.3 Stable Headless CLI
# Usage: /home/damian/.local/bin/godot --headless --script tests/test_adversarial_m5.gd
# ==============================================================================

const MATCH_SCENE_PATH: String = "res://scenes/main/Match.tscn"
const HUD_SCENE_PATH: String = "res://scenes/hud/HUD.tscn"

const MatchControllerScript = preload("res://scripts/main/Match.gd")
const MatchHUDScript = preload("res://scripts/hud/HUD.gd")
const SkillBannerScript = preload("res://scripts/hud/SkillBanner.gd")
const SkillStateMachineScript = preload("res://scripts/skills/SkillStateMachine.gd")
const NodePoolScript = preload("res://scripts/performance/NodePool.gd")

func _init() -> void:
	super()
	suite_name = "AdversarialM5"

func run_all() -> void:
	test_tier_1_match_wiring_and_null_safety()
	test_tier_2_hud_sightlines_and_geometry()
	test_tier_3_skill_banner_rapid_firing_concurrency()
	test_tier_4_hitstop_concurrency_and_cone_boundaries()
	test_tier_5_nodepool_saturation_and_abuse()

# ------------------------------------------------------------------------------
# TEST 1: Match Scene Wiring, Goal Scoring & Null Safety
# ------------------------------------------------------------------------------
func test_tier_1_match_wiring_and_null_safety() -> void:
	set_tier(1)
	print("[ADVERSARIAL] Starting Test 1: Match Scene Wiring, Goal Scoring & Null Safety...")
	
	var match_packed = load(MATCH_SCENE_PATH) as PackedScene
	assert_not_null(match_packed, "Match.tscn must be loadable")
	var match_inst = match_packed.instantiate()
	assert_not_null(match_inst, "Match.tscn must instantiate")
	root.add_child(match_inst)
	match_inst._ready()
	
	# Verify child node links
	assert_not_null(match_inst.pitch, "Pitch must not be null")
	assert_not_null(match_inst.camera, "Camera must not be null")
	assert_not_null(match_inst.ball, "Ball must not be null")
	assert_not_null(match_inst.hud, "HUD must not be null")
	assert_not_null(match_inst.players_container, "Players container must not be null")
	
	# Verify physics process with normal state
	match_inst._physics_process(0.0166)
	assert_almost_eq(match_inst.elapsed_time, 0.0166, 0.001, "Elapsed time updates in _physics_process")
	
	# Stress test physics process when Ball is null
	var saved_ball = match_inst.ball
	match_inst.ball = null
	match_inst._physics_process(0.0166)
	assert_true(true, "Match._physics_process must survive null ball without crashing")
	match_inst.ball = saved_ball
	
	# Stress test physics process when Camera is null
	var saved_cam = match_inst.camera
	match_inst.camera = null
	match_inst._physics_process(0.0166)
	assert_true(true, "Match._physics_process must survive null camera without crashing")
	match_inst.camera = saved_cam
	
	# Stress test physics process when HUD is null
	var saved_hud = match_inst.hud
	match_inst.hud = null
	match_inst._physics_process(0.0166)
	assert_true(true, "Match._physics_process must survive null hud without crashing")
	match_inst.hud = saved_hud
	
	# Rapid goal scoring burst: 50 alternate goals
	for i in range(50):
		if i % 2 == 0:
			match_inst._on_goal_right_scored("GoalRight")
		else:
			match_inst._on_goal_left_scored("GoalLeft")
	
	assert_eq(match_inst.home_score, 25, "Home score must equal 25 after 25 right goals")
	assert_eq(match_inst.away_score, 25, "Away score must equal 25 after 25 left goals")
	assert_eq(match_inst.hud.home_score_label.text, "25", "HUD home score label reflects 25")
	assert_eq(match_inst.hud.away_score_label.text, "25", "HUD away score label reflects 25")
	assert_in_range(match_inst.camera.trauma, 0.0, 1.0, "Camera trauma clamped safely in [0.0, 1.0]")
	
	# Goal scoring when HUD/Camera are null
	match_inst.hud = null
	match_inst.camera = null
	match_inst._on_goal_right_scored("GoalRight")
	match_inst._on_goal_left_scored("GoalLeft")
	assert_eq(match_inst.home_score, 26, "Home score increments even if HUD/camera are null")
	assert_eq(match_inst.away_score, 26, "Away score increments even if HUD/camera are null")
	
	match_inst.queue_free()

# ------------------------------------------------------------------------------
# TEST 2: HUD Sightlines, Ergonomics & Geometry Audit
# ------------------------------------------------------------------------------
func test_tier_2_hud_sightlines_and_geometry() -> void:
	set_tier(2)
	print("[ADVERSARIAL] Starting Test 2: HUD Sightlines & Geometry Audit...")
	
	var hud_packed = load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(hud_packed, "HUD.tscn must load")
	var hud = hud_packed.instantiate()
	root.add_child(hud)
	hud._ready()
	
	# Viewport geometry constants
	const VP_W = 1280.0
	const VP_H = 720.0
	
	# Verify that no legacy panels exist anywhere in the hierarchy
	assert_null(hud.find_child("DiagnosticPanel", true, false), "DiagnosticPanel must NOT exist in HUD")
	assert_null(hud.find_child("DebugPanel", true, false), "DebugPanel must NOT exist in HUD")
	assert_null(hud.find_child("StatsPanel", true, false), "StatsPanel must NOT exist in HUD")
	
	# Audit top-left quadrant playfield clearance
	# Quadrant 1: The primary unobstructed playfield region [0, 460] x [0, 360]
	var primary_playfield_corridor = Rect2(0, 0, 460, 360)
	for child in hud.get_children():
		if child is Control and child.visible:
			var c_rect = Rect2(child.position, child.size)
			var intersects_primary = primary_playfield_corridor.intersects(c_rect)
			assert_false(intersects_primary, "HUD child '%s' must not intersect primary playfield corridor [0, 460] x [0, 360]" % child.name)
	
	assert_true(hud.is_top_left_unobstructed(), "hud.is_top_left_unobstructed() must evaluate to true")
	
	# Scoreboard geometric centering and dimensions
	var sb = hud.scoreboard_panel
	assert_not_null(sb, "Scoreboard panel must exist")
	assert_almost_eq(sb.position.y, 14.0, 1.0, "Scoreboard top margin y=14")
	assert_almost_eq(sb.size.x, 360.0, 1.0, "Scoreboard width = 360")
	assert_almost_eq(sb.size.y, 52.0, 1.0, "Scoreboard height = 52")
	
	var sb_center_x = sb.position.x + (sb.size.x * 0.5)
	assert_almost_eq(sb_center_x, VP_W * 0.5, 0.5, "Scoreboard must be precisely centered at x=640 (viewport center)")
	
	# Scoreboard stylebox transparency audit
	var sb_style = sb.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(sb_style, "Scoreboard stylebox must be StyleBoxFlat")
	assert_almost_eq(sb_style.bg_color.a, 0.75, 0.05, "Scoreboard background must be translucent (alpha ~ 0.75) for sightline clarity")
	
	# Verify SkillBanner default resting position
	var banner = hud.get_skill_banner()
	assert_not_null(banner, "SkillBanner must exist")
	assert_true(banner.position.x >= 1280.0 or not banner.visible, "Inactive SkillBanner must be off-screen or invisible")
	
	hud.queue_free()

# ------------------------------------------------------------------------------
# TEST 3: SkillBanner Rapid Firing & Tween Concurrency Stress
# ------------------------------------------------------------------------------
func test_tier_3_skill_banner_rapid_firing_concurrency() -> void:
	set_tier(3)
	print("[ADVERSARIAL] Starting Test 3: SkillBanner Rapid Concurrency...")
	
	var banner = SkillBannerScript.new()
	root.add_child(banner)
	banner._ready()
	
	# Rapid-fire 100 calls in the same frame
	var elements = ["FIRE", "WOOD", "AIR", "EARTH", "NEUTRAL", "CUSTOM_UNKNOWN", ""]
	for i in range(100):
		var elem = elements[i % elements.size()]
		banner.display_skill("PLAYER_%d" % i, "SKILL_%d" % i, elem)
	
	assert_true(banner.is_active, "Banner must be active after burst calls")
	assert_true(banner.visible, "Banner must be visible after burst calls")
	assert_eq(banner.current_player, "PLAYER_99", "Banner current_player must match final call")
	assert_eq(banner.current_skill, "SKILL_99", "Banner current_skill must match final call")
	
	# Rapid interleaving display_skill and reset_banner
	for i in range(50):
		banner.display_skill("P_%d" % i, "S_%d" % i, "FIRE")
		banner.reset_banner()
	
	assert_false(banner.is_active, "Banner must be inactive after final reset_banner")
	assert_false(banner.visible, "Banner must be invisible after final reset_banner")
	assert_almost_eq(banner.position.x, banner.offscreen_position.x, 1.0, "Banner must be parked off-screen")
	
	# Edge case: Empty strings and nulls
	banner.display_skill("", "", "")
	assert_true(banner.is_active, "Banner handles empty string arguments cleanly")
	banner.reset_banner()
	
	banner.queue_free()

# ------------------------------------------------------------------------------
# TEST 4: Hitstop Concurrency & Cone Query Boundary Conditions
# ------------------------------------------------------------------------------
func test_tier_4_hitstop_concurrency_and_cone_boundaries() -> void:
	set_tier(4)
	print("[ADVERSARIAL] Starting Test 4: Hitstop Concurrency & Cone Queries...")
	
	# Default Engine.time_scale invariant
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "Engine.time_scale must start at 1.0")
	
	# 1. Single FSM Hitstop lifecycle
	var fsm1 = SkillStateMachineScript.new()
	root.add_child(fsm1)
	fsm1.execute("FireTornado", true)
	fsm1.process_step(0.21) # STARTUP -> ACTIVE
	fsm1.process_step(0.09) # ACTIVE -> HITSTOP
	assert_eq(int(fsm1.current_state), 3, "fsm1 is in HITSTOP")
	assert_almost_eq(Engine.time_scale, 0.04, 0.001, "Engine.time_scale is 0.04 during hitstop")
	
	# Cancel while in hitstop
	fsm1.cancel()
	assert_eq(int(fsm1.current_state), 0, "fsm1 is IDLE after cancel")
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "Engine.time_scale must be restored to 1.0 on cancel")
	
	# 2. Destruction while in hitstop
	fsm1.execute("FireTornado", true)
	fsm1.process_step(0.21)
	fsm1.process_step(0.09)
	assert_eq(int(fsm1.current_state), 3, "fsm1 re-entered HITSTOP")
	assert_almost_eq(Engine.time_scale, 0.04, 0.001, "Engine.time_scale is 0.04")
	fsm1.free() # Direct destruction invokes NOTIFICATION_PREDELETE
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "Engine.time_scale restored to 1.0 upon node destruction")
	
	# 3. Concurrent overlapping FSMs
	var fsm_a = SkillStateMachineScript.new()
	var fsm_b = SkillStateMachineScript.new()
	root.add_child(fsm_a)
	root.add_child(fsm_b)
	
	fsm_a.execute("SkillA", true)
	fsm_b.execute("SkillB", true)
	fsm_a.process_step(0.21)
	fsm_b.process_step(0.21)
	
	# A enters hitstop
	fsm_a.process_step(0.09)
	assert_eq(int(fsm_a.current_state), 3, "fsm_a in HITSTOP")
	
	# B enters hitstop
	fsm_b.process_step(0.09)
	assert_eq(int(fsm_b.current_state), 3, "fsm_b in HITSTOP")
	
	# A leaves hitstop
	fsm_a.process_step(0.06)
	assert_eq(int(fsm_a.current_state), 4, "fsm_a in RECOVERY")
	
	# B leaves hitstop
	fsm_b.process_step(0.06)
	assert_eq(int(fsm_b.current_state), 4, "fsm_b in RECOVERY")
	
	# Final check: time_scale must be 1.0
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "Engine.time_scale cleanly restored after overlapping hitstops")
	
	fsm_a.free()
	fsm_b.free()
	
	# 4. Strict Cone Query Boundaries
	var src = Vector2(0, 0)
	var forward = Vector2(1, 0)
	
	# Exact Range Boundary: range = 120.0
	assert_true(SkillStateMachineScript.is_target_in_action_sector(src, forward, Vector2(120.0, 0), 120.0, 60.0), "Distance 120.0 is INSIDE")
	assert_false(SkillStateMachineScript.is_target_in_action_sector(src, forward, Vector2(120.01, 0), 120.0, 60.0), "Distance 120.01 is OUTSIDE")
	
	# Exact Angle Boundary: 60.0 deg half-angle
	var rad_60 = deg_to_rad(60.0)
	var tgt_60 = Vector2(cos(rad_60), sin(rad_60)) * 100.0
	assert_true(SkillStateMachineScript.is_target_in_action_sector(src, forward, tgt_60, 120.0, 60.0), "Angle exactly 60.0 deg is INSIDE")
	
	var rad_60_1 = deg_to_rad(60.1)
	var tgt_60_1 = Vector2(cos(rad_60_1), sin(rad_60_1)) * 100.0
	assert_false(SkillStateMachineScript.is_target_in_action_sector(src, forward, tgt_60_1, 120.0, 60.0), "Angle 60.1 deg is OUTSIDE")
	
	# Zero Distance: src == tgt
	assert_true(SkillStateMachineScript.is_target_in_action_sector(src, forward, src, 120.0, 60.0), "Zero distance is INSIDE")
	
	# Zero Facing Direction: should not crash, returns false
	assert_false(SkillStateMachineScript.is_target_in_action_sector(src, Vector2.ZERO, Vector2(50, 0), 120.0, 60.0), "Zero facing direction returns false cleanly")

# ------------------------------------------------------------------------------
# TEST 5: NodePool Saturation, Abuse & Invariant Stress
# ------------------------------------------------------------------------------
func test_tier_5_nodepool_saturation_and_abuse() -> void:
	set_tier(4)
	print("[ADVERSARIAL] Starting Test 5: NodePool Saturation & Abuse...")
	
	var pool = NodePoolScript.new(5, 10)
	root.add_child(pool)
	pool.tag = "stress_tag"
	pool.register_prefab("stress_tag", null, 5, 10)
	
	assert_eq(pool.get_available_count("stress_tag"), 5, "Initial available is 5 after register_prefab")
	assert_eq(pool.get_active_count("stress_tag"), 0, "Initial active is 0")
	assert_eq(pool.get_total_count("stress_tag"), 5, "Initial total is 5")
	
	# Exhaust all 5 initial nodes
	var acquired: Array[Node] = []
	for i in range(5):
		acquired.append(pool.acquire("stress_tag", Vector2(i, i)))
	assert_eq(pool.get_available_count("stress_tag"), 0, "Available is 0")
	assert_eq(pool.get_active_count("stress_tag"), 5, "Active is 5")
	
	# Auto-grow to max_size 10
	for i in range(5):
		acquired.append(pool.acquire("stress_tag", Vector2(10 + i, 10 + i)))
	assert_eq(pool.get_active_count("stress_tag"), 10, "Active is 10 (at max_size)")
	assert_eq(pool.get_total_count("stress_tag"), 10, "Total instantiated is 10")
	
	# Stress: 100 acquires while saturated
	for i in range(100):
		var n = pool.acquire("stress_tag", Vector2(100 + i, 100 + i))
		assert_not_null(n, "Acquire during saturation must return a valid node")
	
	# Active count and total count must remain strictly clamped at max_size (10)
	assert_eq(pool.get_active_count("stress_tag"), 10, "Active count must remain 10 under saturation")
	assert_eq(pool.get_total_count("stress_tag"), 10, "Total count must remain 10 under saturation")
	
	# Abuse: release(null)
	pool.release(null)
	assert_eq(pool.get_active_count("stress_tag"), 10, "release(null) safely ignored")
	
	# Abuse: double release of the same node
	var sample_node = acquired[9]
	pool.release(sample_node)
	assert_eq(pool.get_active_count("stress_tag"), 9, "Active count decrements to 9 after first release")
	assert_eq(pool.get_available_count("stress_tag"), 1, "Available count is 1 after first release")
	
	pool.release(sample_node) # Second release of same node
	assert_eq(pool.get_active_count("stress_tag"), 9, "Double release does not double-decrement active count")
	assert_eq(pool.get_available_count("stress_tag"), 1, "Double release does not duplicate node in available list")
	
	# Lazy creation on brand new tag
	var lazy_inst = pool.acquire("lazy_tag", Vector2(50, 50))
	assert_not_null(lazy_inst, "Lazy acquire creates bucket automatically")
	assert_eq(pool.get_active_count("lazy_tag"), 1, "Lazy tag active count is 1")
	assert_true(pool.has_pool("lazy_tag"), "Lazy tag pool is created")
	
	# Cleanup
	pool.cleanup("stress_tag")
	assert_eq(pool.get_available_count("stress_tag"), 0, "Available is 0 after cleanup")
	assert_eq(pool.get_active_count("stress_tag"), 0, "Active is 0 after cleanup")
	
	pool.cleanup("lazy_tag")
	pool.queue_free()
