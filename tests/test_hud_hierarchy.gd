class_name TestHUDHierarchy
extends "res://tests/base_test.gd"

# ==============================================================================
# Unit & Hierarchy Test Suite for HUD, Top-Center Scoreboard, SkillBanner & Match.tscn
# Target: Godot Engine 4.3 Stable Headless CLI
# Usage: /home/damian/.local/bin/godot --headless --script tests/test_hud_hierarchy.gd
# ==============================================================================

const HUD_SCENE_PATH: String = "res://scenes/hud/HUD.tscn"
const MATCH_SCENE_PATH: String = "res://scenes/main/Match.tscn"

const MatchHUDScript = preload("res://scripts/hud/HUD.gd")
const SkillBannerScript = preload("res://scripts/hud/SkillBanner.gd")
const MatchControllerScript = preload("res://scripts/main/Match.gd")

const EXPECTED_SCOREBOARD_POS: Vector2 = Vector2(460.0, 14.0)
const EXPECTED_SCOREBOARD_SIZE: Vector2 = Vector2(360.0, 52.0)
const EXPECTED_SCOREBOARD_BG: Color = Color(0.08, 0.11, 0.16, 0.75)

func _init() -> void:
	super()
	suite_name = "HUDHierarchy"

func run_all() -> void:
	test_tier_1_feature_coverage()
	test_tier_2_boundary_cases()
	test_tier_3_match_integration()

# ------------------------------------------------------------------------------
# TIER 1: Feature Coverage
# ------------------------------------------------------------------------------
func test_tier_1_feature_coverage() -> void:
	set_tier(1)
	
	# 1. Instantiate HUD Scene
	var hud_packed: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(hud_packed, "HUD.tscn packed scene must load cleanly")
	
	var hud = hud_packed.instantiate()
	assert_not_null(hud, "HUD instance must be non-null and inherit MatchHUD")
	assert_eq(hud.layer, 10, "HUD CanvasLayer must have layer = 10")
	
	# Add to root for full _ready lifecycle
	root.add_child(hud)
	hud._ready()
	
	# 2. Top-Center Scoreboard Dimensions and Position
	var sb: PanelContainer = hud.scoreboard_panel
	assert_not_null(sb, "TopCenterScoreboard node must exist in HUD")
	assert_vector_almost_eq(sb.position, EXPECTED_SCOREBOARD_POS, 0.5, "Scoreboard position must be at (460, 14)")
	assert_vector_almost_eq(sb.size, EXPECTED_SCOREBOARD_SIZE, 0.5, "Scoreboard size must be (360, 52)")
	
	# Scoreboard horizontal centering verification: center of 1280 is 640
	var sb_center_x = sb.position.x + (sb.size.x * 0.5)
	assert_almost_eq(sb_center_x, 640.0, 0.5, "Scoreboard must be centered horizontally at x=640")
	
	# 3. Glassmorphic StyleBox & Transparency
	var style: StyleBoxFlat = sb.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(style, "Scoreboard must use StyleBoxFlat")
	assert_color_almost_eq(style.bg_color, EXPECTED_SCOREBOARD_BG, 0.02, "Scoreboard background must be glassmorphic Color(0.08, 0.11, 0.16, 0.75)")
	assert_almost_eq(style.bg_color.a, 0.75, 0.05, "Scoreboard background must have alpha ~0.75")
	assert_true(style.corner_radius_top_left >= 6, "Scoreboard must have rounded corners")
	assert_true(style.corner_radius_top_right >= 6, "Scoreboard must have rounded corners")
	assert_true(style.corner_radius_bottom_left >= 6, "Scoreboard must have rounded corners")
	assert_true(style.corner_radius_bottom_right >= 6, "Scoreboard must have rounded corners")
	
	# 4. Scoreboard Labels Initial Content
	assert_not_null(hud.home_name_label, "HomeName label must exist")
	assert_not_null(hud.home_score_label, "HomeScore label must exist")
	assert_not_null(hud.time_label, "TimeLabel must exist")
	assert_not_null(hud.away_score_label, "AwayScore label must exist")
	assert_not_null(hud.away_name_label, "AwayName label must exist")
	
	assert_eq(hud.home_score_label.text, "0", "Initial home score text should be '0'")
	assert_eq(hud.away_score_label.text, "0", "Initial away score text should be '0'")
	assert_eq(hud.time_label.text, "00:00", "Initial match time should be '00:00'")
	
	# 5. Top-Left Quadrant Clearance ([0, 460] x [0, 360])
	assert_true(hud.is_top_left_unobstructed(), "Top-left quadrant must be 100% unobstructed")
	# Ensure no diagnostic panels from reference project exist
	assert_null(hud.get_node_or_null("DiagnosticPanel"), "DiagnosticPanel must not exist")
	assert_null(hud.get_node_or_null("DebugPanel"), "DebugPanel must not exist")
	assert_null(hud.get_node_or_null("StatsPanel"), "StatsPanel must not exist")
	
	# 6. Scoreboard API Updates
	hud.set_score(3, 1)
	assert_eq(hud.home_score, 3, "Home score property must be updated to 3")
	assert_eq(hud.away_score, 1, "Away score property must be updated to 1")
	assert_eq(hud.home_score_label.text, "3", "Home score label must reflect '3'")
	assert_eq(hud.away_score_label.text, "1", "Away score label must reflect '1'")
	
	hud.set_time(125.0)
	assert_almost_eq(hud.match_time_seconds, 125.0, 0.01, "Match time property must update")
	assert_eq(hud.time_label.text, "02:05", "125 seconds must format to '02:05'")
	
	hud.set_team_names("INAZUMA", "ALIUS")
	assert_eq(hud.home_team_name, "INAZUMA", "Home team name property must update")
	assert_eq(hud.away_team_name, "ALIUS", "Away team name property must update")
	assert_eq(hud.home_name_label.text, "INAZUMA", "Home name label must display 'INAZUMA'")
	assert_eq(hud.away_name_label.text, "ALIUS", "Away name label must display 'ALIUS'")
	
	# 7. SkillBanner Component
	var banner = hud.get_skill_banner()
	assert_not_null(banner, "SkillBanner must exist in HUD")
	assert_false(banner.is_active, "SkillBanner must be inactive by default")
	assert_true(banner.onscreen_position.x >= 800.0, "SkillBanner must be outside central corridor (x >= 800)")
	assert_true(banner.position.x >= 1200.0, "SkillBanner offscreen position must be >= 1200")
	
	hud.queue_free()

# ------------------------------------------------------------------------------
# TIER 2: Boundary & Corner Cases
# ------------------------------------------------------------------------------
func test_tier_2_boundary_cases() -> void:
	set_tier(2)
	
	var hud = MatchHUDScript.new()
	root.add_child(hud)
	hud._ready()
	
	# 1. Timer Boundary Values
	hud.set_time(0.0)
	assert_eq(hud.time_label.text, "00:00", "0.0s formats to '00:00'")
	
	hud.set_time(59.9)
	assert_eq(hud.time_label.text, "00:59", "59.9s formats to '00:59'")
	
	hud.set_time(60.0)
	assert_eq(hud.time_label.text, "01:00", "60.0s formats to '01:00'")
	
	hud.set_time(3599.0)
	assert_eq(hud.time_label.text, "59:59", "3599.0s formats to '59:59'")
	
	hud.set_time(-15.0)
	assert_eq(hud.time_label.text, "00:00", "Negative time clamps to '00:00'")
	assert_eq(hud.match_time_seconds, 0.0, "Negative seconds clamped to 0.0")
	
	# 2. Score Clamping & Large Values
	hud.set_score(-5, -2)
	assert_eq(hud.home_score, 0, "Negative home score clamps to 0")
	assert_eq(hud.away_score, 0, "Negative away score clamps to 0")
	assert_eq(hud.home_score_label.text, "0", "Negative score displayed as '0'")
	
	hud.set_score(99, 12)
	assert_eq(hud.home_score, 99, "Score 99 handled cleanly")
	assert_eq(hud.away_score, 12, "Score 12 handled cleanly")
	assert_eq(hud.home_score_label.text, "99", "Label displays '99'")
	assert_eq(hud.away_score_label.text, "12", "Label displays '12'")
	
	# 3. SkillBanner Tween Lifecycle Constants
	var banner = hud.get_skill_banner()
	assert_almost_eq(banner.SLIDE_IN_DURATION, 0.20, 0.001, "Slide-in duration must be 0.20s")
	assert_almost_eq(banner.HOLD_DURATION, 1.20, 0.001, "Hold duration must be 1.20s")
	assert_almost_eq(banner.SLIDE_OUT_DURATION, 0.20, 0.001, "Slide-out duration must be 0.20s")
	assert_almost_eq(banner.TOTAL_DURATION, 1.60, 0.001, "Total duration must be 1.60s")
	
	# 4. SkillBanner Trigger & Rapid Re-trigger
	hud.display_skill_banner("AXEL BLAZE", "FIRE TORNADO", "FIRE")
	assert_true(banner.is_active, "Banner must be active after display_skill")
	assert_eq(banner.current_player, "AXEL BLAZE", "Current player name matches")
	assert_eq(banner.current_skill, "FIRE TORNADO", "Current skill name matches")
	assert_eq(banner.current_element, "FIRE", "Current element matches")
	assert_true(banner.visible, "Banner must become visible")
	
	# Rapid re-trigger should interrupt and reset cleanly
	hud.display_skill_banner("MARK EVANS", "GOD HAND", "EARTH")
	assert_true(banner.is_active, "Banner remains active after re-trigger")
	assert_eq(banner.current_player, "MARK EVANS", "Updated to new player")
	assert_eq(banner.current_skill, "GOD HAND", "Updated to new skill")
	assert_eq(banner.current_element, "EARTH", "Updated to EARTH element")
	
	# Reset banner
	banner.reset_banner()
	assert_false(banner.is_active, "Banner must be inactive after reset")
	assert_false(banner.visible, "Banner must be hidden after reset")
	
	hud.queue_free()

# ------------------------------------------------------------------------------
# TIER 3: Cross-Feature Integration & Match Scene
# ------------------------------------------------------------------------------
func test_tier_3_match_integration() -> void:
	set_tier(3)
	
	# 1. Instantiate Composite Match Scene
	var match_packed: PackedScene = load(MATCH_SCENE_PATH) as PackedScene
	assert_not_null(match_packed, "Match.tscn packed scene must load cleanly")
	
	var match_node = match_packed.instantiate()
	assert_not_null(match_node, "Match scene instance must be MatchController")
	root.add_child(match_node)
	match_node._ready()
	
	# 2. Verify Integrated Component Nodes
	var pitch: Node2D = match_node.pitch
	assert_not_null(pitch, "Pitch node must exist in Match.tscn")
	var camera: DynamicCamera2D = match_node.camera
	assert_not_null(camera, "DynamicCamera node must exist in Match.tscn")
	var ball: Ball = match_node.ball
	assert_not_null(ball, "Ball node must exist in Match.tscn")
	var hud = match_node.hud
	assert_not_null(hud, "HUD node must exist in Match.tscn")
	
	# 3. Verify Physics Layers & Groups
	assert_true(ball.is_in_group("ball"), "Ball must be in 'ball' group")
	assert_eq(ball.collision_layer, 2, "Ball collision_layer must be 2")
	assert_eq(ball.collision_mask, 4, "Ball collision_mask must be 4 (pitch boundaries)")
	
	var players: Array = []
	if match_node.players_container != null:
		players = match_node.players_container.get_children()
	elif match_node.get_tree() != null:
		players = match_node.get_tree().get_nodes_in_group("players")
	assert_true(players.size() >= 4, "Match must have at least 4 player instances (home & away)")
	for p in players:
		if p is CharacterBody2D:
			assert_true(p.is_in_group("players"), "Player instance must be in 'players' group")
			assert_eq(p.collision_layer, 1, "Player collision_layer must be 1")
			assert_eq(p.collision_mask, 4, "Player collision_mask must be 4")
	
	# 4. Verify Goals on Pitch
	var goal_left: Goal = pitch.get_node_or_null("GoalLeft") as Goal
	var goal_right: Goal = pitch.get_node_or_null("GoalRight") as Goal
	assert_not_null(goal_left, "GoalLeft must exist on Pitch")
	assert_not_null(goal_right, "GoalRight must exist on Pitch")
	assert_false(goal_left.is_right_goal, "GoalLeft is_right_goal must be false")
	assert_true(goal_right.is_right_goal, "GoalRight is_right_goal must be true")
	
	# 5. Goal Scoring & HUD Score Update Simulation
	assert_eq(match_node.home_score, 0, "Initial match home score is 0")
	assert_eq(match_node.away_score, 0, "Initial match away score is 0")
	
	# Simulate Home goal (ball in right goal)
	match_node._on_goal_right_scored("GoalRight")
	assert_eq(match_node.home_score, 1, "Home score increments to 1")
	assert_eq(hud.home_score_label.text, "1", "HUD scoreboard reflects home score 1")
	
	# Simulate Away goal (ball in left goal)
	match_node._on_goal_left_scored("GoalLeft")
	assert_eq(match_node.away_score, 1, "Away score increments to 1")
	assert_eq(hud.away_score_label.text, "1", "HUD scoreboard reflects away score 1")
	
	# 6. Hissatsu Skill Trigger through MatchController
	match_node.trigger_hissatsu_banner("JUDE SHARP", "ILLUSION BALL", "WOOD")
	var banner = hud.get_skill_banner()
	assert_true(banner.is_active, "Banner is active after match trigger")
	assert_eq(banner.current_player, "JUDE SHARP", "Player name matches Jude Sharp")
	assert_eq(banner.current_skill, "ILLUSION BALL", "Skill name matches Illusion Ball")
	assert_eq(banner.current_element, "WOOD", "Element matches Wood")
	
	# Verify camera trauma shake triggered
	assert_true(camera.trauma > 0.0, "Camera trauma must be triggered by hissatsu activation")
	
	# 7. Clean Teardown
	match_node.queue_free()
