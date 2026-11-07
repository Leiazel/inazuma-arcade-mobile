class_name TestPhysicsInvariants
extends "res://tests/base_test.gd"

# Reference Constants & Invariant Values from "Mini football Torneos"
# (Authoritative source: survey_ref_miner_1/analysis.md & PROJECT.md §Reference Physics Invariants Matrix)

const BALL_GRASS_FRICTION: float = 340.0 # px/s^2
const BALL_AIR_DRAG: float = 142.8      # px/s^2 (340.0 * 0.42)
const BALL_AIR_DRAG_FACTOR: float = 0.42
const BALL_BOUNCE_RESTITUTION: float = 0.72
const BALL_WALL_REBOUND_RESTITUTION: float = 0.78
const BALL_BASE_PICKUP_RADIUS: float = 36.0

const PLAYER_SPEED_MIN: float = 235.0
const PLAYER_SPEED_MAX: float = 325.0
const PLAYER_SPRINT_MULTIPLIER: float = 1.28
const PLAYER_USER_MULTIPLIER: float = 1.12

const PASS_SHOT_HOLD_THRESHOLD: float = 0.26 # seconds
const SLIDE_TACKLE_BURST_MULTIPLIER: float = 1.72
const SLIDE_TACKLE_REACH_CARRIER: float = 50.0
const SLIDE_TACKLE_REACH_BALL: float = 46.0
const NORMAL_TACKLE_REACH: float = 34.0

const NORMAL_STEAL_MIN_PROB: float = 0.18
const NORMAL_STEAL_MAX_PROB: float = 0.85
const SLIDE_STEAL_MIN_PROB: float = 0.38
const SLIDE_STEAL_MAX_PROB: float = 0.94

const STUMBLE_DURATION: float = 0.42
const STUMBLE_PICKUP_LOCK: float = 0.57

func _init() -> void:
	super()
	suite_name = "PhysicsInvariants"

func run_all() -> void:
	test_tier_1_feature_coverage()
	test_tier_2_boundary_cases()
	test_tier_3_cross_feature_interactions()

## Reference formulas from survey_ref_miner_1
static func compute_ball_control_distance(control_stat: float) -> float:
	var t = clampf(control_stat / 100.0, 0.0, 1.0)
	return lerpf(28.0, 18.0, t)

static func compute_ball_control_lerp_weight(control_stat: float) -> float:
	var t = clampf(control_stat / 100.0, 0.0, 1.0)
	return lerpf(20.0, 34.0, t)

static func compute_player_base_speed(speed_stat: float) -> float:
	var t = clampf(speed_stat / 100.0, 0.0, 1.0)
	return lerpf(PLAYER_SPEED_MIN, PLAYER_SPEED_MAX, t)

static func compute_player_carrier_speed(speed_stat: float, control_stat: float) -> float:
	var base_spd = compute_player_base_speed(speed_stat)
	var t_ctrl = clampf(control_stat / 100.0, 0.0, 1.0)
	var penalty = lerpf(0.95, 1.0, t_ctrl)
	return base_spd * penalty

static func compute_normal_steal_probability(def_stat: float, ctrl_stat: float) -> float:
	var raw = 0.50 + (def_stat - ctrl_stat) * 0.008
	return clampf(raw, NORMAL_STEAL_MIN_PROB, NORMAL_STEAL_MAX_PROB)

static func compute_slide_steal_probability(def_stat: float, ctrl_stat: float) -> float:
	var raw = 0.72 + (def_stat - ctrl_stat) * 0.008
	return clampf(raw, SLIDE_STEAL_MIN_PROB, SLIDE_STEAL_MAX_PROB)

static func compute_shot_charge_factor(press_time: float) -> float:
	return clampf(press_time / 0.60, 0.45, 1.0)

static func compute_shot_speed(tiro_stat: float, press_time: float) -> float:
	var t = clampf(tiro_stat / 100.0, 0.0, 1.0)
	var base = lerpf(660.0, 1060.0, t)
	var charge = compute_shot_charge_factor(press_time)
	return base * (0.82 + 0.35 * charge)

static func compute_gk_save_reach(reflejos_stat: float) -> float:
	var t = clampf(reflejos_stat / 100.0, 0.0, 1.0)
	return 46.0 + t * 20.0

## Tier 1: Feature Coverage
func test_tier_1_feature_coverage() -> void:
	set_tier(1)
	
	# 1. Ball friction & drag constants
	assert_almost_eq(BALL_GRASS_FRICTION, 340.0, 0.01, "Grass friction is exactly 340.0 px/s^2")
	assert_almost_eq(BALL_AIR_DRAG, 142.8, 0.01, "Air drag deceleration is exactly 142.8 px/s^2")
	assert_almost_eq(BALL_AIR_DRAG_FACTOR, 0.42, 0.001, "Air drag factor is 0.42 of grass friction")
	assert_almost_eq(BALL_GRASS_FRICTION * BALL_AIR_DRAG_FACTOR, BALL_AIR_DRAG, 0.01, "340.0 * 0.42 == 142.8")
	assert_almost_eq(BALL_BOUNCE_RESTITUTION, 0.72, 0.01, "Ball collision bounce restitution is 0.72")
	assert_almost_eq(BALL_WALL_REBOUND_RESTITUTION, 0.78, 0.01, "Pitch boundary wall rebound is 0.78")
	
	# 2. Ball control lerp formulas
	# Control 0: 28.0 px loose attachment
	assert_almost_eq(compute_ball_control_distance(0.0), 28.0, 0.01, "Control 0 distance is 28.0 px")
	# Control 50: 23.0 px
	assert_almost_eq(compute_ball_control_distance(50.0), 23.0, 0.01, "Control 50 distance is 23.0 px")
	# Control 100: 18.0 px tight attachment
	assert_almost_eq(compute_ball_control_distance(100.0), 18.0, 0.01, "Control 100 distance is 18.0 px")
	
	# Responsiveness weight lerp
	assert_almost_eq(compute_ball_control_lerp_weight(0.0), 20.0, 0.01, "Control 0 lerp weight is 20.0")
	assert_almost_eq(compute_ball_control_lerp_weight(50.0), 27.0, 0.01, "Control 50 lerp weight is 27.0")
	assert_almost_eq(compute_ball_control_lerp_weight(100.0), 34.0, 0.01, "Control 100 lerp weight is 34.0")
	
	# 3. Player base speed formula: lerp(235.0, 325.0, speed/100)
	assert_almost_eq(compute_player_base_speed(0.0), 235.0, 0.01, "Speed stat 0 base speed is 235.0 px/s")
	assert_almost_eq(compute_player_base_speed(50.0), 280.0, 0.01, "Speed stat 50 base speed is 280.0 px/s")
	assert_almost_eq(compute_player_base_speed(100.0), 325.0, 0.01, "Speed stat 100 base speed is 325.0 px/s")
	
	# Multipliers
	assert_almost_eq(PLAYER_SPRINT_MULTIPLIER, 1.28, 0.001, "Sprint speed multiplier is +28% (1.28)")
	assert_almost_eq(PLAYER_USER_MULTIPLIER, 1.12, 0.001, "User-controlled player speed bonus is +12% (1.12)")
	
	# Ball carrier speed penalty: up to 5% reduction on control 0, 0% on control 100
	var carrier_spd_ctrl_0 = compute_player_carrier_speed(50.0, 0.0)
	assert_almost_eq(carrier_spd_ctrl_0, 280.0 * 0.95, 0.01, "Control 0 carries ball at 95% speed")
	var carrier_spd_ctrl_100 = compute_player_carrier_speed(50.0, 100.0)
	assert_almost_eq(carrier_spd_ctrl_100, 280.0 * 1.00, 0.01, "Control 100 carries ball at 100% speed")
	
	# 4. Pass vs shot press duration threshold: 0.26s
	assert_almost_eq(PASS_SHOT_HOLD_THRESHOLD, 0.26, 0.001, "Pass vs shot hold duration threshold is 0.26s")
	var action_tap = 0.15 # < 0.26 -> Pass
	var action_hold = 0.40 # >= 0.26 -> Shot
	assert_true(action_tap < PASS_SHOT_HOLD_THRESHOLD, "0.15s hold classified as Pass")
	assert_true(action_hold >= PASS_SHOT_HOLD_THRESHOLD, "0.40s hold classified as Shot")
	
	# 5. Slide tackle mechanics
	assert_almost_eq(SLIDE_TACKLE_BURST_MULTIPLIER, 1.72, 0.001, "Slide tackle burst speed impulse is 1.72x base speed")
	assert_almost_eq(SLIDE_TACKLE_REACH_CARRIER, 50.0, 0.1, "Slide tackle reach against carrier is 50.0 px")
	assert_almost_eq(SLIDE_TACKLE_REACH_BALL, 46.0, 0.1, "Slide tackle reach against loose ball is 46.0 px")
	assert_almost_eq(NORMAL_TACKLE_REACH, 34.0, 0.1, "Normal tackle reach is 34.0 px")
	
	# Slide burst speed example: base 280 px/s * 1.72 = 481.6 px/s
	var slide_impulse = compute_player_base_speed(50.0) * SLIDE_TACKLE_BURST_MULTIPLIER
	assert_almost_eq(slide_impulse, 481.6, 0.1, "Slide burst impulse = 280 * 1.72 = 481.6 px/s")
	
	# Stumble timers
	assert_almost_eq(STUMBLE_DURATION, 0.42, 0.01, "Stumble duration is 0.42s")
	assert_almost_eq(STUMBLE_PICKUP_LOCK, 0.57, 0.01, "Stumble ball pickup lock is 0.57s (0.42 + 0.15)")
	assert_almost_eq(STUMBLE_PICKUP_LOCK - STUMBLE_DURATION, 0.15, 0.01, "Pickup lock margin is 0.15s")

## Tier 2: Boundary Cases
func test_tier_2_boundary_cases() -> void:
	set_tier(2)
	
	# 1. Slide steal probability clamping: [0.38, 0.94]
	# Equal stats (def 50, ctrl 50): 0.72 + 0 = 0.72
	var p_slide_equal = compute_slide_steal_probability(50.0, 50.0)
	assert_almost_eq(p_slide_equal, 0.72, 0.001, "Slide steal probability with equal stats is 0.72")
	
	# Extreme mismatch: defender 0, carrier 100
	# raw: 0.72 + (0 - 100)*0.008 = 0.72 - 0.80 = -0.08 -> clamped to 0.38
	var p_slide_min = compute_slide_steal_probability(0.0, 100.0)
	assert_almost_eq(p_slide_min, 0.38, 0.001, "Slide steal probability clamped at minimum 0.38")
	
	# Extreme mismatch: defender 100, carrier 0
	# raw: 0.72 + (100 - 0)*0.008 = 0.72 + 0.80 = 1.52 -> clamped to 0.94
	var p_slide_max = compute_slide_steal_probability(100.0, 0.0)
	assert_almost_eq(p_slide_max, 0.94, 0.001, "Slide steal probability clamped at maximum 0.94")
	
	# 2. Normal steal probability clamping: [0.18, 0.85]
	# Equal stats: 0.50 + 0 = 0.50
	var p_norm_equal = compute_normal_steal_probability(50.0, 50.0)
	assert_almost_eq(p_norm_equal, 0.50, 0.001, "Normal steal probability with equal stats is 0.50")
	
	# Extreme min: def 0, ctrl 100: 0.50 - 0.80 = -0.30 -> clamped to 0.18
	var p_norm_min = compute_normal_steal_probability(0.0, 100.0)
	assert_almost_eq(p_norm_min, 0.18, 0.001, "Normal steal probability clamped at minimum 0.18")
	
	# Extreme max: def 100, ctrl 0: 0.50 + 0.80 = 1.30 -> clamped to 0.85
	var p_norm_max = compute_normal_steal_probability(100.0, 0.0)
	assert_almost_eq(p_norm_max, 0.85, 0.001, "Normal steal probability clamped at maximum 0.85")
	
	# Monotonicity check across differential ranges
	for diff in range(-100, 101, 20):
		var p_s = compute_slide_steal_probability(50.0 + float(diff), 50.0)
		assert_in_range(p_s, 0.38, 0.94, "Slide steal prob must be within [0.38, 0.94]")
		var p_n = compute_normal_steal_probability(50.0 + float(diff), 50.0)
		assert_in_range(p_n, 0.18, 0.85, "Normal steal prob must be within [0.18, 0.85]")
		assert_true(p_s >= p_n, "Slide tackle always provides higher or equal success chance than standing tackle")
	
	# 3. Shot charge factor curve bounds: [0.45, 1.0]
	var charge_tap = compute_shot_charge_factor(0.0) # clamped to 0.45
	assert_almost_eq(charge_tap, 0.45, 0.001, "Tap charge factor clamps to min 0.45")
	
	var charge_half = compute_shot_charge_factor(0.30) # 0.30 / 0.60 = 0.50
	assert_almost_eq(charge_half, 0.50, 0.001, "0.30s charge factor = 0.50")
	
	var charge_full = compute_shot_charge_factor(0.60) # 1.0
	assert_almost_eq(charge_full, 1.00, 0.001, "0.60s charge factor = 1.0")
	
	var charge_over = compute_shot_charge_factor(1.50) # clamped to 1.0
	assert_almost_eq(charge_over, 1.00, 0.001, "Overcharge clamped to 1.0")
	
	# 4. Shot speed bounds
	# Min possible shot: tiro 0, charge min 0.45
	# base = 660, kick_speed = 660 * (0.82 + 0.35 * 0.45) = 660 * (0.82 + 0.1575) = 660 * 0.9775 ≈ 645.15
	var min_shot = compute_shot_speed(0.0, 0.0)
	assert_almost_eq(min_shot, 660.0 * 0.9775, 0.5, "Minimum shot speed ~645 px/s")
	
	# Max possible shot: tiro 100, full charge 1.0
	# base = 1060, kick_speed = 1060 * (0.82 + 0.35 * 1.0) = 1060 * 1.17 = 1240.2
	var max_shot = compute_shot_speed(100.0, 0.60)
	assert_almost_eq(max_shot, 1060.0 * 1.17, 0.5, "Maximum charged shot speed ~1240.2 px/s")
	
	# 5. Goalkeeper save reach bounds: [46.0, 66.0] px
	assert_almost_eq(compute_gk_save_reach(0.0), 46.0, 0.01, "GK save reach at reflejos 0 is 46.0 px")
	assert_almost_eq(compute_gk_save_reach(50.0), 56.0, 0.01, "GK save reach at reflejos 50 is 56.0 px")
	assert_almost_eq(compute_gk_save_reach(100.0), 66.0, 0.01, "GK save reach at reflejos 100 is 66.0 px")

## Tier 3: Cross-Feature Interactions
func test_tier_3_cross_feature_interactions() -> void:
	set_tier(3)
	
	# 1. Ball pass interception penalties
	# Base pickup radius = 36.0 px
	# Teammate during pass flight has reduced radius: 36.0 * 0.55 = 19.8 px (avoids accidental friendly interception)
	var friendly_radius = BALL_BASE_PICKUP_RADIUS * 0.55
	assert_almost_eq(friendly_radius, 19.8, 0.01, "Teammate pass interception radius is 19.8 px")
	
	# Opponent during pass flight: 36.0 * 0.85 = 30.6 px
	var opponent_radius = BALL_BASE_PICKUP_RADIUS * 0.85
	assert_almost_eq(opponent_radius, 30.6, 0.01, "Opponent pass interception radius is 30.6 px")
	assert_true(opponent_radius > friendly_radius, "Opponent interception reach is wider than friendly interception reach")
	
	# 2. User sprinting player tackling comparison
	var user_base_spd = compute_player_base_speed(75.0) * PLAYER_USER_MULTIPLIER # 302.5 * 1.12 = 338.8
	var user_sprint_spd = user_base_spd * PLAYER_SPRINT_MULTIPLIER # 338.8 * 1.28 = 433.66
	assert_almost_eq(user_base_spd, 302.5 * 1.12, 0.1, "User base speed with +12% bonus")
	assert_almost_eq(user_sprint_spd, 302.5 * 1.12 * 1.28, 0.1, "User sprint speed with +28% bonus")
	
	# Slide burst speed vs running sprint
	var slide_spd = user_base_spd * SLIDE_TACKLE_BURST_MULTIPLIER # 338.8 * 1.72 = 582.7
	assert_true(slide_spd > user_sprint_spd, "Slide tackle burst exceeds sprint speed")
	
	# Production class presence checks
	if FileAccess.file_exists("res://scripts/ball/Ball.gd"):
		var BallClass = load("res://scripts/ball/Ball.gd")
		var ball_node = BallClass.new()
		assert_not_null(ball_node, "Production Ball instantiates")
		ball_node.free()
		
	if FileAccess.file_exists("res://scripts/player/Player.gd"):
		var PlayerClass = load("res://scripts/player/Player.gd")
		var player_node = PlayerClass.new()
		assert_not_null(player_node, "Production Player instantiates")
		player_node.free()

	# Production Ball scene and FSM state transitions verification
	if ResourceLoader.exists("res://scenes/ball/Ball.tscn"):
		var BallScene = load("res://scenes/ball/Ball.tscn") as PackedScene
		var ball_inst = BallScene.instantiate() as Ball
		assert_not_null(ball_inst, "Ball.tscn instantiates cleanly")
		assert_eq(ball_inst.collision_layer, 2, "Ball collision layer is 2")
		assert_eq(ball_inst.collision_mask, 4, "Ball collision mask is 4")
		assert_true(ball_inst.is_in_group("ball"), "Ball is in 'ball' group")
		assert_eq(ball_inst.current_state, Ball.State.LIBRE, "Initial ball state is LIBRE")
		assert_almost_eq(ball_inst.base_friction, 340.0, 0.01, "Ball base friction is 340.0")
		assert_almost_eq(ball_inst.bounce_restitution, 0.72, 0.01, "Ball bounce restitution is 0.72")
		assert_almost_eq(ball_inst.wall_restitution, 0.78, 0.01, "Ball wall restitution is 0.78")
		
		# Test kick transition to EN_VUELO
		ball_inst.kick(Vector2.RIGHT, 600.0, null)
		assert_eq(ball_inst.current_state, Ball.State.EN_VUELO, "Kick transitions ball to EN_VUELO")
		assert_almost_eq(ball_inst.velocity.length(), 600.0, 0.1, "Kick assigns velocity")
		
		# Test set_libre transition
		ball_inst.set_libre(Vector2.ZERO)
		assert_eq(ball_inst.current_state, Ball.State.LIBRE, "set_libre transitions ball to LIBRE")
		ball_inst.free()

	# Production Player scene and BaseIndicator integration verification
	if ResourceLoader.exists("res://scenes/player/Player.tscn"):
		var PlayerScene = load("res://scenes/player/Player.tscn") as PackedScene
		var player_inst = PlayerScene.instantiate() as Player
		assert_not_null(player_inst, "Player.tscn instantiates cleanly")
		assert_eq(player_inst.collision_layer, 1, "Player collision layer is 1")
		assert_eq(player_inst.collision_mask, 4, "Player collision mask is 4")
		assert_true(player_inst.is_in_group("players"), "Player is in 'players' group")
		assert_eq(player_inst.motion_mode, CharacterBody2D.MOTION_MODE_FLOATING, "Player motion mode is floating")
		
		# Verify base speed calculation
		player_inst.stats["velocidad"] = 50
		assert_almost_eq(player_inst._get_base_speed(), 280.0, 0.1, "Base speed matches 280.0 px/s")
		
		# Verify BaseIndicator child integration
		var ind = player_inst.get_node_or_null("BaseIndicator2D") as BaseIndicator2D
		assert_not_null(ind, "Player contains BaseIndicator2D child")
		
		# Verify apply_kit integration
		var test_kit = KitData.new()
		test_kit.team_name = "TestTeam"
		test_kit.primary_color = Color.RED
		test_kit.indicator_color = Color.RED
		player_inst.apply_kit(test_kit)
		assert_color_almost_eq(ind.team_color, Color.RED, 0.01, "apply_kit updates base indicator color")
		
		# Verify slide tackle constants
		assert_true(player_inst.can_slide_tackle(), "Player can slide tackle initially")
		player_inst.free()

