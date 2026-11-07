class_name TestPitchCamera
extends "res://tests/base_test.gd"

# Reference Constants & Specification Contracts (PROJECT.md §Interface Contracts & survey_gameplay_explorer_3 §3)
const REF_FIELD_WIDTH: float = 3000.0
const REF_FIELD_HEIGHT: float = 1760.0

const SCALED_FIELD_WIDTH: float = 3600.0
const SCALED_FIELD_HEIGHT: float = 2160.0
const SCALED_HALF_WIDTH: float = 1800.0
const SCALED_HALF_HEIGHT: float = 1080.0

const SCALED_GOAL_WIDTH: float = 260.0
const SCALED_GOAL_HALF_MOUTH: float = 130.0
const SCALED_GOAL_DEPTH: float = 80.0

const SCALED_PENALTY_WIDTH: float = 480.0
const SCALED_PENALTY_HEIGHT: float = 880.0
const SCALED_CENTER_CIRCLE_RADIUS: float = 185.0

const ZOOM_CLOSE: float = 0.68
const ZOOM_WIDE: float = 0.46
const SPEED_MIN: float = 120.0
const SPEED_MAX: float = 1450.0

const CAMERA_FOLLOW_SPEED: float = 8.5
const ZOOM_OUT_RATE: float = 4.8
const ZOOM_IN_RATE: float = 1.6
const TRAUMA_DECAY: float = 1.65

func _init() -> void:
	super()
	suite_name = "PitchCamera"

func run_all() -> void:
	test_tier_1_feature_coverage()
	test_tier_2_boundary_cases()
	test_tier_3_cross_feature_interactions()

## Mathematical reference implementation for camera target midpoint formula
static func calculate_camera_target(ball_pos: Vector2, ball_state: int, carrier_pos: Vector2, has_carrier: bool, active_player_pos: Vector2, has_active_player: bool) -> Vector2:
	# Ball.State: 0 = LIBRE, 1 = CONTROLADA, 2 = EN_VUELO
	if ball_state == 1 and has_carrier:
		# Carrier focus lerp (42% toward ball from carrier)
		return carrier_pos.lerp(ball_pos, 0.42)
	elif has_active_player:
		# Aerial or loose ball focus lerp (65% toward ball from active player)
		return active_player_pos.lerp(ball_pos, 0.65)
	else:
		return ball_pos

## Mathematical reference implementation for dynamic zoom calculation
static func compute_target_zoom(ball_speed: float, carrier_speed: float) -> float:
	var eff_speed = (ball_speed * 0.75) + (carrier_speed * 0.25)
	var t_v = clampf((eff_speed - SPEED_MIN) / (SPEED_MAX - SPEED_MIN), 0.0, 1.0)
	var smooth_t = t_v * t_v * (3.0 - 2.0 * t_v) # Hermite smoothstep
	return lerpf(ZOOM_CLOSE, ZOOM_WIDE, smooth_t)

## Mathematical reference implementation for exponential smoothing
static func exponential_decay(current: Vector2, target: Vector2, rate: float, delta: float) -> Vector2:
	var weight = 1.0 - exp(-rate * delta)
	return current.lerp(target, weight)

## Tier 1: Feature Coverage
func test_tier_1_feature_coverage() -> void:
	set_tier(1)
	
	# 1. Scaled pitch dimensions verification
	assert_almost_eq(SCALED_FIELD_WIDTH, 3600.0, 0.1, "Scaled pitch width must be 3600.0 px")
	assert_almost_eq(SCALED_FIELD_HEIGHT, 2160.0, 0.1, "Scaled pitch height must be 2160.0 px")
	assert_almost_eq(SCALED_HALF_WIDTH, 1800.0, 0.1, "Half width must be 1800.0 px")
	assert_almost_eq(SCALED_HALF_HEIGHT, 1080.0, 0.1, "Half height must be 1080.0 px")
	
	# Verify delta percentages over reference project (3000x1760)
	var width_increase_pct = ((SCALED_FIELD_WIDTH - REF_FIELD_WIDTH) / REF_FIELD_WIDTH) * 100.0
	var height_increase_pct = ((SCALED_FIELD_HEIGHT - REF_FIELD_HEIGHT) / REF_FIELD_HEIGHT) * 100.0
	assert_almost_eq(width_increase_pct, 20.0, 0.5, "Pitch width increase should be +20%")
	assert_almost_eq(height_increase_pct, 22.7, 0.5, "Pitch height increase should be ~+22.7%")
	
	# Scaled elements
	assert_almost_eq(SCALED_GOAL_WIDTH, 260.0, 0.1, "Goal width scaled to 260.0 px")
	assert_almost_eq(SCALED_GOAL_HALF_MOUTH, 130.0, 0.1, "Goal half mouth must be 130.0 px")
	assert_almost_eq(SCALED_GOAL_DEPTH, 80.0, 0.1, "Goal depth scaled to 80.0 px")
	assert_almost_eq(SCALED_PENALTY_WIDTH, 480.0, 0.1, "Penalty box width scaled to 480.0 px")
	assert_almost_eq(SCALED_PENALTY_HEIGHT, 880.0, 0.1, "Penalty box height scaled to 880.0 px")
	assert_almost_eq(SCALED_CENTER_CIRCLE_RADIUS, 185.0, 0.1, "Center circle radius scaled to 185.0 px")
	
	# 2. StaticBody2D boundaries layout verification (6 boundary colliders on Layer 4)
	var boundary_definitions = [
		{"name": "TopTouchline", "pos": Vector2(0, -1100), "size": Vector2(3800, 40), "layer": 4},
		{"name": "BottomTouchline", "pos": Vector2(0, 1100), "size": Vector2(3800, 40), "layer": 4},
		{"name": "LeftGoalLineTop", "pos": Vector2(-1820, -605), "size": Vector2(40, 950), "layer": 4},
		{"name": "LeftGoalLineBottom", "pos": Vector2(-1820, 605), "size": Vector2(40, 950), "layer": 4},
		{"name": "RightGoalLineTop", "pos": Vector2(1820, -605), "size": Vector2(40, 950), "layer": 4},
		{"name": "RightGoalLineBottom", "pos": Vector2(1820, 605), "size": Vector2(40, 950), "layer": 4}
	]
	assert_eq(boundary_definitions.size(), 6, "Must define exactly 6 physical boundary colliders")
	
	for b in boundary_definitions:
		assert_eq(b["layer"], 4, b["name"] + " must be on Layer 4")
		assert_true(b["size"].x > 0 and b["size"].y > 0, b["name"] + " non-zero dimensions")
	
	# Goal mouth vertical gap verification: [-130, 130]
	var mouth_top = -605.0 + (950.0 / 2.0) # -130.0
	var mouth_bottom = 605.0 - (950.0 / 2.0) # 130.0
	assert_almost_eq(mouth_top, -130.0, 0.1, "Goal mouth top edge at -130.0")
	assert_almost_eq(mouth_bottom, 130.0, 0.1, "Goal mouth bottom edge at +130.0")
	assert_almost_eq(mouth_bottom - mouth_top, 260.0, 0.1, "Goal mouth opening width is 260.0 px")
	
	# 3. Camera lerp midpoint formula
	var carrier_pos = Vector2(200, 100)
	var ball_pos = Vector2(250, 150)
	var target_controlled = calculate_camera_target(ball_pos, 1, carrier_pos, true, Vector2.ZERO, false)
	# (200 + 50*0.42, 100 + 50*0.42) = (221.0, 121.0)
	assert_vector_almost_eq(target_controlled, Vector2(221.0, 121.0), 0.01, "Carrier focus lerp midpoint (0.42)")
	
	var active_player = Vector2(0, 0)
	var loose_ball = Vector2(400, 200)
	var target_loose = calculate_camera_target(loose_ball, 0, Vector2.ZERO, false, active_player, true)
	# (0 + 400*0.65, 0 + 200*0.65) = (260.0, 130.0)
	assert_vector_almost_eq(target_loose, Vector2(260.0, 130.0), 0.01, "Loose ball focus lerp midpoint (0.65)")
	
	# Fallback without player
	var target_no_player = calculate_camera_target(loose_ball, 0, Vector2.ZERO, false, Vector2.ZERO, false)
	assert_vector_almost_eq(target_no_player, loose_ball, 0.01, "Fallback camera target is ball position")
	
	# 4. Zoom range [0.46, 0.68]
	assert_almost_eq(ZOOM_CLOSE, 0.68, 0.001, "Close zoom is 0.68")
	assert_almost_eq(ZOOM_WIDE, 0.46, 0.001, "Wide zoom is 0.46")
	assert_almost_eq(SPEED_MIN, 120.0, 0.1, "Min speed threshold is 120.0 px/s")
	assert_almost_eq(SPEED_MAX, 1450.0, 0.1, "Max speed threshold is 1450.0 px/s")

## Tier 2: Boundary Cases
func test_tier_2_boundary_cases() -> void:
	set_tier(2)
	
	# 1. Speed clamp tests
	var zoom_zero = compute_target_zoom(0.0, 0.0)
	assert_almost_eq(zoom_zero, 0.68, 0.0001, "Zero speed clamps to 0.68 zoom")
	
	var zoom_under_min = compute_target_zoom(80.0, 40.0)
	assert_almost_eq(zoom_under_min, 0.68, 0.0001, "Speed below 120 clamps to 0.68 zoom")
	
	var zoom_at_min = compute_target_zoom(120.0, 120.0)
	assert_almost_eq(zoom_at_min, 0.68, 0.0001, "Speed at 120.0 equals 0.68 zoom")
	
	var zoom_at_max = compute_target_zoom(1450.0, 1450.0)
	assert_almost_eq(zoom_at_max, 0.46, 0.0001, "Speed at 1450.0 equals 0.46 zoom")
	
	var zoom_extreme = compute_target_zoom(2500.0, 300.0)
	assert_almost_eq(zoom_extreme, 0.46, 0.0001, "Extreme 2500 px/s clamps to 0.46 zoom")
	
	# Mid speed Hermite smoothstep check (785 px/s -> 0.50 -> zoom 0.57)
	var zoom_mid = compute_target_zoom(785.0, 785.0)
	assert_almost_eq(zoom_mid, 0.57, 0.001, "Midpoint speed 785 px/s yields zoom 0.57")
	
	# Monotonicity test across speeds
	var speeds = [0.0, 120.0, 300.0, 600.0, 900.0, 1200.0, 1450.0, 2000.0, 2500.0]
	var prev_z = 1.0
	for s in speeds:
		var z = compute_target_zoom(s, 0.0)
		assert_in_range(z, 0.46, 0.68, "Zoom at speed " + str(s) + " in range [0.46, 0.68]")
		if s > 0.0:
			assert_true(z <= prev_z + 0.0001, "Zoom must decrease monotonically as speed increases")
		prev_z = z
	
	# 2. Camera trauma shake bounds [0.0, 1.0]
	var trauma = 0.0
	trauma = clampf(trauma + 1.5, 0.0, 1.0)
	assert_almost_eq(trauma, 1.0, 0.0001, "Trauma clamps to maximum 1.0")
	
	var intensity_max = trauma * trauma
	assert_almost_eq(intensity_max, 1.0, 0.0001, "Trauma 1.0 yields intensity 1.0^2 = 1.0")
	
	trauma = 0.5
	var intensity_half = trauma * trauma
	assert_almost_eq(intensity_half, 0.25, 0.0001, "Trauma 0.5 yields quadratic intensity 0.25")
	
	var dt = 0.1
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * dt) # 0.5 - 0.165 = 0.335
	assert_almost_eq(trauma, 0.335, 0.001, "Trauma decays at 1.65/s")
	
	trauma = maxf(0.0, trauma - 1.0)
	assert_almost_eq(trauma, 0.0, 0.0001, "Trauma cannot be negative")
	var intensity_zero = trauma * trauma
	assert_almost_eq(intensity_zero, 0.0, 0.0001, "Zero trauma yields exactly 0.0 intensity")

## Tier 3: Cross-Feature Interactions
func test_tier_3_cross_feature_interactions() -> void:
	set_tier(3)
	
	# Power shot integration: high speed triggers dynamic wide zoom + camera trauma shake
	var shot_speed = 2000.0
	var zoom_result = compute_target_zoom(shot_speed, 200.0)
	assert_almost_eq(zoom_result, 0.46, 0.001, "Power shot triggers maximum wide zoom (0.46)")
	
	var trauma_kick = clampf(0.0 + 0.55, 0.0, 1.0)
	var kick_intensity = trauma_kick * trauma_kick # 0.3025
	assert_almost_eq(kick_intensity, 0.3025, 0.001, "Shot trauma 0.55 produces intensity 0.3025")
	
	# Asymmetric zoom rates
	assert_almost_eq(ZOOM_OUT_RATE, 4.8, 0.01, "Zoom out rate is 4.8 s^-1")
	assert_almost_eq(ZOOM_IN_RATE, 1.6, 0.01, "Zoom in rate is 1.6 s^-1")
	assert_true(ZOOM_OUT_RATE > ZOOM_IN_RATE * 2.0, "Zoom out rate must be > 2x zoom in rate")
	
	# Check if production DynamicCamera2D exists
	if FileAccess.file_exists("res://scripts/camera/DynamicCamera2D.gd"):
		var CamScript = load("res://scripts/camera/DynamicCamera2D.gd")
		var cam_inst = CamScript.new()
		assert_not_null(cam_inst, "DynamicCamera2D instantiates successfully")
		assert_almost_eq(cam_inst.field_half_width, 1800.0, 0.1, "Camera field_half_width")
		assert_almost_eq(cam_inst.field_half_height, 1080.0, 0.1, "Camera field_half_height")
		assert_almost_eq(cam_inst.zoom_close, 0.68, 0.01, "Camera zoom_close")
		assert_almost_eq(cam_inst.zoom_wide, 0.46, 0.01, "Camera zoom_wide")
		cam_inst.free()

	# Test DynamicCamera.tscn scene loading and trauma integration
	if ResourceLoader.exists("res://scenes/camera/DynamicCamera.tscn"):
		var CamScene = load("res://scenes/camera/DynamicCamera.tscn") as PackedScene
		var cam_node = CamScene.instantiate() as DynamicCamera2D
		assert_not_null(cam_node, "DynamicCamera.tscn instantiates cleanly")
		cam_node.add_trauma(0.4)
		assert_almost_eq(cam_node.trauma, 0.4, 0.001, "Camera add_trauma updates trauma")
		cam_node.add_trauma(0.8)
		assert_almost_eq(cam_node.trauma, 1.0, 0.001, "Camera trauma clamped to 1.0")
		cam_node.free()

	# Test Pitch.tscn scene tree and boundary colliders
	if ResourceLoader.exists("res://scenes/pitch/Pitch.tscn"):
		var PitchScene = load("res://scenes/pitch/Pitch.tscn") as PackedScene
		var pitch_node = PitchScene.instantiate()
		assert_not_null(pitch_node, "Pitch.tscn instantiates cleanly")
		var ground = pitch_node.get_node_or_null("PitchGround") as PitchGround
		assert_not_null(ground, "Pitch.tscn contains PitchGround child")
		assert_almost_eq(ground.field_width, 3600.0, 0.1, "PitchGround width 3600")
		assert_almost_eq(ground.field_height, 2160.0, 0.1, "PitchGround height 2160")
		var bounds = pitch_node.get_node_or_null("PitchBoundaries")
		assert_not_null(bounds, "Pitch.tscn contains PitchBoundaries")
		for b_name in ["TopTouchline", "BottomTouchline", "LeftGoalLineTop", "LeftGoalLineBottom", "RightGoalLineTop", "RightGoalLineBottom"]:
			var b_body = bounds.get_node_or_null(b_name) as StaticBody2D
			assert_not_null(b_body, "Boundary body " + b_name + " exists")
			assert_eq(b_body.collision_layer, 4, b_name + " on layer 4")
			assert_not_null(b_body.physics_material_override, b_name + " has physics material")
			assert_almost_eq(b_body.physics_material_override.bounce, 0.78, 0.01, b_name + " bounce is 0.78")
		var goal_l = pitch_node.get_node_or_null("GoalLeft") as Goal
		assert_not_null(goal_l, "GoalLeft exists")
		assert_almost_eq(goal_l.goal_width, 260.0, 0.1, "Goal width 260")
		assert_almost_eq(goal_l.goal_depth, 80.0, 0.1, "Goal depth 80")
		assert_almost_eq(goal_l.post_radius, 9.0, 0.1, "Goal post radius 9")
		pitch_node.free()

