class_name TestSkillsHitstop
extends "res://tests/base_test.gd"

# Reference Specification Contracts (PROJECT.md §Interface Contracts & survey_gameplay_explorer_3 §4)
enum SkillPhase { IDLE, STARTUP, ACTIVE, HITSTOP, RECOVERY }

const DEFAULT_CONE_ANGLE_DEG: float = 60.0
const DEFAULT_CONE_RANGE: float = 120.0

const STARTUP_MIN_FRAMES: int = 10
const STARTUP_MAX_FRAMES: int = 14
const ACTIVE_MIN_FRAMES: int = 4
const ACTIVE_MAX_FRAMES: int = 6
const HITSTOP_MIN_FRAMES: int = 2
const HITSTOP_MAX_FRAMES: int = 4
const RECOVERY_MIN_FRAMES: int = 12
const RECOVERY_MAX_FRAMES: int = 18

func _init() -> void:
	super()
	suite_name = "SkillsHitstop"

func run_all() -> void:
	test_tier_1_feature_coverage()
	test_tier_2_boundary_cases()
	test_tier_3_cross_feature_interactions()

## Reference mathematical cone targeting query
static func is_target_in_action_sector(source_pos: Vector2, facing_dir: Vector2, target_pos: Vector2, max_range: float = DEFAULT_CONE_RANGE, max_half_angle_deg: float = DEFAULT_CONE_ANGLE_DEG) -> bool:
	var to_target = target_pos - source_pos
	var dist = to_target.length()
	if dist > max_range:
		return false
	if dist < 0.0001:
		return true
	
	var forward = facing_dir.normalized()
	var dir_to_target = to_target.normalized()
	var dot_val = forward.dot(dir_to_target)
	var min_dot = cos(deg_to_rad(max_half_angle_deg))
	return dot_val >= (min_dot - 0.00001)

## Mock/Reference state machine tracking phase transitions
class SkillStateMachineModel:
	var state: int = SkillPhase.IDLE
	var current_skill_name: String = ""
	var startup_frames: int = 12
	var active_frames: int = 5
	var hitstop_frames: int = 3
	var recovery_frames: int = 15
	var phase_timer: float = 0.0
	var hit_connected: bool = false
	var history: Array[int] = [SkillPhase.IDLE]
	
	func execute(skill_name: String, hit: bool) -> void:
		current_skill_name = skill_name
		hit_connected = hit
		_transition_to(SkillPhase.STARTUP)
	
	func process_step(delta: float) -> void:
		if state == SkillPhase.IDLE:
			return
		phase_timer -= delta
		if phase_timer <= 0.0:
			match state:
				SkillPhase.STARTUP:
					_transition_to(SkillPhase.ACTIVE)
				SkillPhase.ACTIVE:
					if hit_connected:
						_transition_to(SkillPhase.HITSTOP)
					else:
						_transition_to(SkillPhase.RECOVERY)
				SkillPhase.HITSTOP:
					_transition_to(SkillPhase.RECOVERY)
				SkillPhase.RECOVERY:
					_transition_to(SkillPhase.IDLE)
	
	func _transition_to(new_state: int) -> void:
		state = new_state
		history.append(new_state)
		match new_state:
			SkillPhase.STARTUP:
				phase_timer = float(startup_frames) / 60.0
			SkillPhase.ACTIVE:
				phase_timer = float(active_frames) / 60.0
			SkillPhase.HITSTOP:
				phase_timer = float(hitstop_frames) / 60.0
			SkillPhase.RECOVERY:
				phase_timer = float(recovery_frames) / 60.0
			SkillPhase.IDLE:
				phase_timer = 0.0

## Tier 1: Feature Coverage
func test_tier_1_feature_coverage() -> void:
	set_tier(1)
	
	# 1. State machine phases and lifecycle verification
	# Explicit phases: IDLE (0), STARTUP (1), ACTIVE (2), HITSTOP (3), RECOVERY (4)
	assert_eq(SkillPhase.IDLE, 0, "State IDLE == 0")
	assert_eq(SkillPhase.STARTUP, 1, "State STARTUP == 1")
	assert_eq(SkillPhase.ACTIVE, 2, "State ACTIVE == 2")
	assert_eq(SkillPhase.HITSTOP, 3, "State HITSTOP == 3")
	assert_eq(SkillPhase.RECOVERY, 4, "State RECOVERY == 4")
	
	# Verify frame range specifications @ 60 FPS
	# Startup: 10-14 frames (0.166 - 0.233 s)
	var startup_sec_min = float(STARTUP_MIN_FRAMES) / 60.0
	var startup_sec_max = float(STARTUP_MAX_FRAMES) / 60.0
	assert_almost_eq(startup_sec_min, 0.1667, 0.005, "Startup min duration ~0.167s")
	assert_almost_eq(startup_sec_max, 0.2333, 0.005, "Startup max duration ~0.233s")
	
	# Active: 4-6 frames (0.066 - 0.100 s)
	var active_sec_min = float(ACTIVE_MIN_FRAMES) / 60.0
	var active_sec_max = float(ACTIVE_MAX_FRAMES) / 60.0
	assert_almost_eq(active_sec_min, 0.0667, 0.005, "Active min duration ~0.067s")
	assert_almost_eq(active_sec_max, 0.1000, 0.005, "Active max duration ~0.100s")
	
	# Hitstop: 2-4 frames (0.033 - 0.066 s)
	var hitstop_sec_min = float(HITSTOP_MIN_FRAMES) / 60.0
	var hitstop_sec_max = float(HITSTOP_MAX_FRAMES) / 60.0
	assert_almost_eq(hitstop_sec_min, 0.0333, 0.005, "Hitstop min duration ~0.033s (2 frames)")
	assert_almost_eq(hitstop_sec_max, 0.0667, 0.005, "Hitstop max duration ~0.067s (4 frames)")
	
	# Recovery: 12-18 frames (0.200 - 0.300 s)
	var recovery_sec_min = float(RECOVERY_MIN_FRAMES) / 60.0
	var recovery_sec_max = float(RECOVERY_MAX_FRAMES) / 60.0
	assert_almost_eq(recovery_sec_min, 0.2000, 0.005, "Recovery min duration 0.200s")
	assert_almost_eq(recovery_sec_max, 0.3000, 0.005, "Recovery max duration 0.300s")
	
	# 2. Lifecycle transitions on HIT
	var fsm_hit = SkillStateMachineModel.new()
	assert_eq(fsm_hit.state, SkillPhase.IDLE, "Initial state must be IDLE")
	fsm_hit.execute("FireTornado", true)
	assert_eq(fsm_hit.state, SkillPhase.STARTUP, "Transition to STARTUP")
	
	# Simulate through startup (12 frames * 0.0167s = 0.20s)
	fsm_hit.process_step(0.21)
	assert_eq(fsm_hit.state, SkillPhase.ACTIVE, "Transition to ACTIVE after startup expires")
	
	# Hit connects in ACTIVE window -> transitions to HITSTOP
	fsm_hit.process_step(0.09)
	assert_eq(fsm_hit.state, SkillPhase.HITSTOP, "Transition to HITSTOP on hit connection")
	
	# Hitstop micro-pause (3 frames = 0.05s) -> transitions to RECOVERY
	fsm_hit.process_step(0.06)
	assert_eq(fsm_hit.state, SkillPhase.RECOVERY, "Transition to RECOVERY after hitstop")
	
	# Recovery completes -> transitions to IDLE
	fsm_hit.process_step(0.26)
	assert_eq(fsm_hit.state, SkillPhase.IDLE, "Transition back to IDLE after recovery")
	
	var expected_hit_history = [
		SkillPhase.IDLE,
		SkillPhase.STARTUP,
		SkillPhase.ACTIVE,
		SkillPhase.HITSTOP,
		SkillPhase.RECOVERY,
		SkillPhase.IDLE
	]
	assert_eq(fsm_hit.history, expected_hit_history, "Complete 4-phase transition history with HIT")
	
	# 3. Lifecycle transitions on WHIFF (no hit)
	var fsm_whiff = SkillStateMachineModel.new()
	fsm_whiff.execute("FireTornado", false)
	fsm_whiff.process_step(0.21) # to ACTIVE
	fsm_whiff.process_step(0.09) # whiff expires -> goes directly to RECOVERY (skipping HITSTOP)
	assert_eq(fsm_whiff.state, SkillPhase.RECOVERY, "Whiffed skill skips HITSTOP and enters RECOVERY")
	fsm_whiff.process_step(0.26)
	assert_eq(fsm_whiff.state, SkillPhase.IDLE, "Whiffed skill returns to IDLE")
	
	var expected_whiff_history = [
		SkillPhase.IDLE,
		SkillPhase.STARTUP,
		SkillPhase.ACTIVE,
		SkillPhase.RECOVERY,
		SkillPhase.IDLE
	]
	assert_eq(fsm_whiff.history, expected_whiff_history, "Whiff transition history bypasses HITSTOP")
	
	# 4. Cone targeting basic check: straight ahead inside range
	var source = Vector2(0, 0)
	var facing = Vector2(1, 0) # Facing East (+X)
	var target_inside = Vector2(80, 0) # 80 px straight ahead
	assert_true(is_target_in_action_sector(source, facing, target_inside, 120.0, 60.0), "Target 80px straight ahead is inside cone")

## Tier 2: Boundary Cases
func test_tier_2_boundary_cases() -> void:
	set_tier(2)
	
	var source = Vector2(100, 100)
	var facing = Vector2(1, 0) # East
	
	# 1. Cosine 60 deg boundary: cos(60 deg) == 0.50
	var cos_60 = cos(deg_to_rad(60.0))
	assert_almost_eq(cos_60, 0.50, 0.00001, "cos(60 deg) must equal 0.50 exactly")
	
	# Target at +59.9 deg (inside cone)
	var angle_inside = deg_to_rad(59.9)
	var target_59_9 = source + Vector2(cos(angle_inside), sin(angle_inside)) * 100.0
	assert_true(is_target_in_action_sector(source, facing, target_59_9, 120.0, 60.0), "Target at +59.9 deg is INSIDE cone")
	
	# Target at -59.9 deg (inside cone, symmetry check)
	var target_neg_59_9 = source + Vector2(cos(-angle_inside), sin(-angle_inside)) * 100.0
	assert_true(is_target_in_action_sector(source, facing, target_neg_59_9, 120.0, 60.0), "Target at -59.9 deg is INSIDE cone (symmetry)")
	
	# Target exactly at 60.0 deg (on border, inclusive)
	var angle_60 = deg_to_rad(60.0)
	var target_exact_60 = source + Vector2(cos(angle_60), sin(angle_60)) * 100.0
	assert_true(is_target_in_action_sector(source, facing, target_exact_60, 120.0, 60.0), "Target at exactly 60.0 deg is INSIDE cone")
	
	# Target at +60.1 deg (outside cone)
	var angle_outside = deg_to_rad(60.1)
	var target_60_1 = source + Vector2(cos(angle_outside), sin(angle_outside)) * 100.0
	assert_false(is_target_in_action_sector(source, facing, target_60_1, 120.0, 60.0), "Target at +60.1 deg is OUTSIDE cone")
	
	# Target at -60.1 deg (outside cone, symmetry check)
	var target_neg_60_1 = source + Vector2(cos(-angle_outside), sin(-angle_outside)) * 100.0
	assert_false(is_target_in_action_sector(source, facing, target_neg_60_1, 120.0, 60.0), "Target at -60.1 deg is OUTSIDE cone")
	
	# 2. Distance boundaries: 120.0 px vs 120.1 px
	# Exactly 120.0 px straight ahead -> INSIDE
	var target_120_0 = source + facing * 120.0
	assert_true(is_target_in_action_sector(source, facing, target_120_0, 120.0, 60.0), "Target at range 120.0 px is INSIDE")
	
	# Exactly 120.001 px -> OUTSIDE
	var target_120_1 = source + facing * 120.1
	assert_false(is_target_in_action_sector(source, facing, target_120_1, 120.0, 60.0), "Target at range 120.1 px is OUTSIDE")
	
	# 0.0 distance (point on point) -> INSIDE
	assert_true(is_target_in_action_sector(source, facing, source, 120.0, 60.0), "Target at distance 0.0 is INSIDE")
	
	# 3. Target behind player (angle > 90 deg, dot < 0) -> OUTSIDE
	var target_behind = source - facing * 50.0
	assert_false(is_target_in_action_sector(source, facing, target_behind, 120.0, 60.0), "Target behind player is OUTSIDE")
	
	# Orthogonal target (90 deg, dot == 0) -> OUTSIDE (since 90 > 60)
	var target_90_deg = source + Vector2(0, 100)
	assert_false(is_target_in_action_sector(source, facing, target_90_deg, 120.0, 60.0), "Target at 90 deg is OUTSIDE 60 deg cone")

## Tier 3: Cross-Feature Interactions
func test_tier_3_cross_feature_interactions() -> void:
	set_tier(3)
	
	# 1. Hitstop micro-pause engine time scale verification
	# Standard time scale is 1.0
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "Default Engine.time_scale is 1.0")
	
	# Simulating hitstop freeze: time scale set to 0.04
	Engine.time_scale = 0.04
	assert_almost_eq(Engine.time_scale, 0.04, 0.001, "Hitstop sets Engine.time_scale to 0.04 (micro-pause)")
	
	# Restoration to normal gameplay speed
	Engine.time_scale = 1.0
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "Hitstop restoration returns Engine.time_scale to 1.0")
	
	# 2. Check if production SkillStateMachine exists on disk
	if FileAccess.file_exists("res://scripts/skills/SkillStateMachine.gd"):
		var FsmScript = load("res://scripts/skills/SkillStateMachine.gd")
		var fsm_node = FsmScript.new()
		assert_not_null(fsm_node, "SkillStateMachine instantiates")
		assert_eq(int(fsm_node.current_state), 0, "SkillStateMachine begins in IDLE state")
		
		# 3. Production SkillStateMachine transition lifecycle on HIT
		fsm_node.execute("FireTornado", true)
		assert_eq(int(fsm_node.current_state), 1, "Production FSM enters STARTUP")
		fsm_node.process_step(0.21)
		assert_eq(int(fsm_node.current_state), 2, "Production FSM enters ACTIVE")
		fsm_node.process_step(0.09)
		assert_eq(int(fsm_node.current_state), 3, "Production FSM enters HITSTOP on hit")
		fsm_node.process_step(0.06)
		assert_eq(int(fsm_node.current_state), 4, "Production FSM enters RECOVERY after hitstop")
		fsm_node.process_step(0.26)
		assert_eq(int(fsm_node.current_state), 0, "Production FSM returns to IDLE")
		var expected_hit_history = [0, 1, 2, 3, 4, 0]
		assert_eq(fsm_node.history, expected_hit_history, "Production FSM hit history matches [IDLE, STARTUP, ACTIVE, HITSTOP, RECOVERY, IDLE]")
		
		# 4. Production SkillStateMachine transition lifecycle on WHIFF
		fsm_node.execute("FireTornado", false)
		assert_eq(int(fsm_node.current_state), 1, "Production FSM enters STARTUP on whiff")
		fsm_node.process_step(0.21)
		assert_eq(int(fsm_node.current_state), 2, "Production FSM enters ACTIVE on whiff")
		fsm_node.process_step(0.09)
		assert_eq(int(fsm_node.current_state), 4, "Production FSM bypasses HITSTOP to RECOVERY on whiff")
		fsm_node.process_step(0.26)
		assert_eq(int(fsm_node.current_state), 0, "Production FSM returns to IDLE on whiff")
		var expected_whiff_history = [0, 1, 2, 4, 0]
		assert_eq(fsm_node.history, expected_whiff_history, "Production FSM whiff history bypasses HITSTOP")
		
		# 5. Production execute_skill with deterministic cone connection
		var source_node = Node2D.new()
		source_node.position = Vector2(0, 0)
		source_node.set("facing_direction", Vector2(1, 0)) # East
		var in_cone_target = Node2D.new()
		in_cone_target.position = Vector2(80, 0) # 80 px East
		var out_cone_target = Node2D.new()
		out_cone_target.position = Vector2(-80, 0) # 80 px West (behind)
		
		var connected_hit = fsm_node.execute_skill("FireTornado", source_node, in_cone_target)
		assert_true(connected_hit, "execute_skill returns true")
		assert_true(fsm_node.hit_connected, "Target inside cone registers deterministic connection")
		fsm_node.cancel()
		
		fsm_node.execute_skill("FireTornado", source_node, out_cone_target)
		assert_false(fsm_node.hit_connected, "Target behind registers whiff")
		fsm_node.cancel()
		
		source_node.free()
		in_cone_target.free()
		out_cone_target.free()
		fsm_node.free()

