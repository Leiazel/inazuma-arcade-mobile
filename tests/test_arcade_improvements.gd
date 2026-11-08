class_name TestArcadeImprovements
extends "res://tests/base_test.gd"

# ==============================================================================
# E2E Verification Suite for Vertical-Slice Polish & 6-Round Tournament Upgrade
# Covers: Controls & Shot Charging, 4-Phase Hissatsu + GK Save Duels, VFX Pool,
# Procedural Audio, Broadcast Bottom HUD + MiniRadar, Golden Goal, & Tournament Save.
# ==============================================================================

const MATCH_SCENE_PATH: String = "res://scenes/main/Match.tscn"
const TEMP_SAVE_PATH: String = "user://test_tournament_save_verify.json"

func _init() -> void:
	super()
	suite_name = "ArcadeImprovements"

func run_all() -> void:
	test_tier_1_audio_controls_charging_and_bottom_hud()
	test_tier_2_goal_lock_golden_goal_and_color_clash()
	test_tier_3_hissatsu_gk_duel_merit_and_tournament()

func _active_root() -> Window:
	var ml := Engine.get_main_loop() as SceneTree
	if ml != null and ml.root != null:
		return ml.root
	return root

# ------------------------------------------------------------------------------
# TIER 1: Audio, Controls, Shot Hold Charging & Broadcast Bottom HUD
# ------------------------------------------------------------------------------
func test_tier_1_audio_controls_charging_and_bottom_hud() -> void:
	set_tier(1)

	var match_packed := load(MATCH_SCENE_PATH) as PackedScene
	assert_not_null(match_packed, "Match.tscn must load cleanly")
	var m := match_packed.instantiate() as MatchController
	m.tournament_save_path = TEMP_SAVE_PATH
	_active_root().add_child(m)

	# 1. Procedural Audio Synthesis
	var audio: Node = m.audio_manager
	assert_not_null(audio, "ArcadeAudioManager must be instantiated in Match")
	for sfx_key in ["ui_click", "pass", "charge", "shot", "slide", "steal", "hissatsu_start", "hissatsu_hit", "gk_save", "whistle_kickoff", "whistle_golden", "whistle_end", "goal", "bgm_match"]:
		assert_true(audio.call("has_sound", sfx_key), "Synthesized sound '%s' must exist in library" % sfx_key)

	audio.call("set_sfx_enabled", false)
	assert_false(bool(audio.get("sfx_enabled")), "SFX mute toggle updates state")
	audio.call("set_sfx_enabled", true)
	audio.call("set_music_volume", 0.5)
	assert_almost_eq(float(audio.get("music_volume")), 0.5, 0.01, "Music volume updates cleanly")

	# 2. Broadcast Bottom HUD, Portraits & Sightline Invariant
	var hud := m.hud as MatchHUD
	assert_not_null(hud, "HUD must exist")
	assert_not_null(hud.bottom_home_card, "BottomHomeCard must exist")
	assert_not_null(hud.mini_radar, "MiniRadar must exist")
	assert_not_null(hud.bottom_away_card, "BottomAwayCard must exist")
	assert_true(hud.bottom_home_card.position.y >= 624.0, "BottomHomeCard must sit at y >= 624")
	assert_true(hud.mini_radar.position.y >= 624.0, "MiniRadar must sit at y >= 624")
	assert_true(hud.bottom_away_card.position.y >= 624.0, "BottomAwayCard must sit at y >= 624")
	assert_false(hud.is_touch_controls_enabled(), "TouchControls must default to hidden on non-touch desktop/headless")
	assert_true(hud.is_top_left_unobstructed(), "Top-left corridor [0, 460] x [0, 360] must remain 100% unobstructed")

	# Mobile Multi-Touch & Independent Touch Tracking Invariant
	hud.set_touch_controls_enabled(true)
	assert_true(hud.is_touch_controls_enabled(), "TouchControls enable cleanly via HUD API")
	var tc: TouchControls = hud.touch_controls as TouchControls
	assert_not_null(tc, "TouchControls overlay node must exist")

	# Finger 0 (left thumb) touches dynamic joystick zone
	var ev_f0_down := InputEventScreenTouch.new()
	ev_f0_down.index = 0
	ev_f0_down.pressed = true
	ev_f0_down.position = Vector2(150.0, 520.0)
	tc._gui_input(ev_f0_down)
	assert_true(tc.move_dragging, "Finger 0 starts joystick dragging")

	# Finger 1 (right thumb) simultaneously taps pass pill button
	var ev_f1_down := InputEventScreenTouch.new()
	ev_f1_down.index = 1
	ev_f1_down.pressed = true
	ev_f1_down.position = tc._get_pass_rect().position + Vector2(10.0, 10.0)
	tc._gui_input(ev_f1_down)
	assert_true(tc.pass_button_down, "Finger 1 taps pass pill button while Finger 0 holds joystick")
	assert_true(tc.move_dragging, "Finger 0 joystick dragging remains active during simultaneous finger 1 press")

	# Finger 1 releases pass button
	var ev_f1_up := InputEventScreenTouch.new()
	ev_f1_up.index = 1
	ev_f1_up.pressed = false
	ev_f1_up.position = tc._get_pass_rect().position + Vector2(10.0, 10.0)
	tc._gui_input(ev_f1_up)
	assert_false(tc.pass_button_down, "Finger 1 pass button releases")
	assert_true(tc.move_dragging, "CRITICAL MULTI-TOUCH INVARIANT: Finger 0 joystick MUST remain active when finger 1 releases")

	# Finger 0 releases joystick
	var ev_f0_up := InputEventScreenTouch.new()
	ev_f0_up.index = 0
	ev_f0_up.pressed = false
	ev_f0_up.position = Vector2(150.0, 520.0)
	tc._gui_input(ev_f0_up)
	assert_false(tc.move_dragging, "Finger 0 joystick finishes dragging")

	# Safe area, Arc/Diamond buttons & on-screen pause button
	assert_not_null(tc._get_pause_rect(), "TouchControls has dedicated on-screen pause rect")
	assert_true(tc._get_pause_rect().position.x >= 1100.0, "Pause button sits in top-right corner")
	assert_true(tc._get_slide_rect().size.x >= 50.0, "Arc/Diamond layout includes dedicated BARRIDA (slide) button")
	assert_true(tc.ACTION_PAD_RADIUS >= 50.0, "Primary TIRO / CARGAR circular button is oversized (radius >= 50px)")

	# Touch hold-to-charge shot verification
	var ev_shot_down := InputEventScreenTouch.new()
	ev_shot_down.index = 2
	ev_shot_down.pressed = true
	ev_shot_down.position = tc._get_action_center()
	tc._gui_input(ev_shot_down)
	assert_true(tc.action_dragging, "Pressing TIRO button starts touch shot charging")
	assert_true(Input.is_action_pressed("action_shot"), "Hold-to-charge TIRO activates Input action_shot")
	var ev_shot_up := InputEventScreenTouch.new()
	ev_shot_up.index = 2
	ev_shot_up.pressed = false
	ev_shot_up.position = tc._get_action_center()
	tc._gui_input(ev_shot_up)
	assert_false(tc.action_dragging, "Releasing TIRO button ends touch shot charging")
	assert_false(Input.is_action_pressed("action_shot"), "Releasing TIRO releases Input action_shot")
	var pre_p := m._get_active_player()
	if pre_p != null:
		pre_p.is_sliding = false
		pre_p.slide_timer = 0.0
		pre_p.slide_recovery_timer = 0.0
		pre_p.slide_cooldown = 0.0

	# Touch/Mouse GUI clickability settings & Menu Block verification
	assert_true(bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", false)), "emulate_mouse_from_touch MUST be true so Android touch clicks standard GUI Buttons")
	assert_false(bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", true)), "emulate_touch_from_mouse MUST be false to avoid circular touch/mouse loop")

	hud.show_match_setup(m.team_catalog, m._build_tournament_ui_info())
	assert_true(tc.blocked_by_menu, "Opening Main Menu blocks TouchControls so menu buttons receive all clicks")
	assert_false(tc.visible, "TouchControls hides automatically while Main Menu is open")
	var tourn_cards: Array = hud.tournament_team_picker.get_meta("card_buttons", [])
	var quick_home_cards: Array = hud.home_team_picker.get_meta("card_buttons", [])
	var quick_away_cards: Array = hud.away_team_picker.get_meta("card_buttons", [])
	assert_eq(tourn_cards.size(), 9, "Tournament tab renders 9 direct-tap Team Cards in 3x3 grid")
	assert_eq(quick_home_cards.size(), 9, "Quick Match Home selector renders 9 direct-tap Team Cards")
	assert_eq(quick_away_cards.size(), 9, "Quick Match Away selector renders 9 direct-tap Team Cards")
	(tourn_cards[6] as Button).pressed.emit()
	assert_eq(hud.tournament_team_picker.selected, 6, "Tapping a Team Card in the 3x3 grid updates selected team index")
	hud._close_menu_layer()
	assert_false(tc.blocked_by_menu, "Closing Main Menu unblocks TouchControls for gameplay")
	assert_true(tc.visible, "TouchControls restores visibility when Main Menu closes")

	hud.set_touch_controls_enabled(false)
	assert_false(hud.is_touch_controls_enabled(), "TouchControls disable cleanly after test")

	# SkillBanner portrait rendering
	var active_p := m._get_active_player()
	assert_not_null(active_p, "Active user player must exist")
	assert_false(active_p.portrait_path.is_empty(), "Player portrait_path must load from players.json")
	hud.display_skill_banner(active_p.player_name, active_p.ability_name, "FIRE", active_p.portrait_path)
	var banner := hud.get_skill_banner() as SkillBanner
	assert_not_null(banner.portrait_rect, "SkillBanner PortraitRect must exist")
	assert_true(banner.portrait_rect.visible, "SkillBanner PortraitRect must be visible when valid portrait_path given")

	# 3. Ergonomic Actions & Real Shot Hold Charging
	for act in ["action_pass", "action_shot", "action_ability", "switch_player", "pause_game"]:
		assert_true(InputMap.has_action(act), "Input action '%s' must be registered" % act)

	m.ball.take_possession(active_p)
	active_p.pass_receive_grace_timer = 0.0
	active_p.facing_direction = Vector2.RIGHT

	var shot_state := {"fired": false, "speed": 0.0, "charge": 0.0}
	active_p.shot_executed.connect(func(_pl: Player, spd: float, chg: float):
		shot_state["fired"] = true
		shot_state["speed"] = spd
		shot_state["charge"] = chg
	)

	# Frame 1: Press and hold shot button
	Input.action_press("action_shot")
	active_p._physics_process(0.016)
	assert_true(active_p.is_charging_action, "Holding action_shot with ball enters is_charging_action")

	# Hold for ~0.40s across simulation frames
	for _i in range(25):
		active_p._physics_process(0.016)
	assert_true(active_p.pass_press_time >= 0.35, "Holding action_shot accumulates pass_press_time >= 0.35s")

	# Update HUD while charging and confirm top-left sightline still clear
	m._update_bottom_hud()
	assert_true(hud.is_top_left_unobstructed(), "Charging shot HUD state keeps top-left unobstructed")

	# Release shot button -> fires power kick!
	Input.action_release("action_shot")
	active_p._physics_process(0.016)
	assert_true(shot_state["fired"], "Releasing action_shot fires power kick")
	assert_true(float(shot_state["charge"]) >= 0.55, "Charged shot carries >= 55% charge factor")
	assert_true(float(shot_state["speed"]) >= 900.0, "Charged shot launches ball at high speed (>= 900 px/s)")
	assert_false(active_p.is_charging_action, "is_charging_action resets on shot release")

	# Auto-Sprint on full virtual joystick tilt (>= 78%)
	active_p.is_kicking = false
	active_p.kick_anim_timer = 0.0
	active_p.set_virtual_move(Vector2(0.95, 0.0))
	active_p._physics_process(0.016)
	assert_true(active_p.is_sprinting, "Tilting virtual joystick >= 78% triggers Auto-Sprint automatically")
	active_p.set_virtual_move(Vector2(0.45, 0.0))
	active_p._physics_process(0.016)
	assert_false(active_p.is_sprinting, "Tilting virtual joystick < 78% walks normally without sprinting")
	active_p.set_virtual_move(Vector2.ZERO)

	# Mobile Lifecycle & Focus Invariant: FOCUS_OUT must NOT pause the game (prevent ghost pauses)
	m.is_match_active = true
	m.is_paused = false
	m._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(m.is_paused, "NOTIFICATION_APPLICATION_FOCUS_OUT must NOT pause match to prevent spurious mobile auto-pauses")
	assert_true(m.is_match_active, "Match remains active during focus transitions")

	# Real App Backgrounding: APPLICATION_PAUSED must pause the game
	m._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_true(m.is_paused, "NOTIFICATION_APPLICATION_PAUSED pauses active match when minimized")
	m.set_paused_state(false)

	# Android Back Request: NOTIFICATION_WM_GO_BACK_REQUEST handles back button
	m._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_true(m.is_paused, "NOTIFICATION_WM_GO_BACK_REQUEST pauses active match")
	m._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_false(m.is_paused, "Second NOTIFICATION_WM_GO_BACK_REQUEST resumes active match")

	# Player sprite frames integrity verification (prevents invisible outfield players)
	assert_not_null(active_p.anim_sprite, "Player AnimatedSprite2D must exist")
	assert_not_null(active_p.anim_sprite.sprite_frames, "Player AnimatedSprite2D must have SpriteFrames")
	assert_true(active_p.anim_sprite.sprite_frames.has_animation("idle_down"), "Player must have idle_down animation")
	assert_true(active_p.anim_sprite.sprite_frames.get_frame_count("idle_down") > 0, "Player must have >= 1 frame loaded in idle_down")

	# Pause toggle test
	m.toggle_pause()
	assert_true(m.is_paused, "toggle_pause pauses active match")
	assert_false(m.is_match_active, "is_match_active is false while paused")
	assert_true(hud.pause_layer.visible, "PauseMenu becomes visible when paused")
	m.toggle_pause()
	assert_false(m.is_paused, "Second toggle_pause resumes match")
	assert_false(hud.pause_layer.visible, "PauseMenu hides on resume")

	m.free()

# ------------------------------------------------------------------------------
# TIER 2: Anti-Double-Goal Lock, Golden Goal Tiebreaker & Color Clash Arbitration
# ------------------------------------------------------------------------------
func test_tier_2_goal_lock_golden_goal_and_color_clash() -> void:
	set_tier(2)

	var match_packed := load(MATCH_SCENE_PATH) as PackedScene
	var m := match_packed.instantiate() as MatchController
	m.tournament_save_path = TEMP_SAVE_PATH
	_active_root().add_child(m)

	# 1. All 9 teams loaded with distinct clash-free colors in every pairing (81 matchups)
	assert_eq(m.team_catalog.size(), 9, "All 9 teams from teams.json must load into team_catalog")
	for i in range(m.team_catalog.size()):
		for j in range(m.team_catalog.size()):
			var mu := m._build_matchup(i, j, i == j)
			m._arbitrate_team_colors(mu)
			var dist := ColorClashDetector.calculate_color_distance(m.resolved_home_color, m.resolved_away_color)
			assert_true(dist >= ColorClashDetector.CLASH_THRESHOLD, "Arbitrated colors for team %d vs %d must exceed CLASH_THRESHOLD (got %.3f)" % [i, j, dist])

	# 2. Physical Goal Anti-Double-Score Lock during 1.5s celebration
	m.start_quick_match(4, 2, 60.0)
	var goal_right := m.pitch.get_node_or_null("GoalRight") as Goal
	var goal_left := m.pitch.get_node_or_null("GoalLeft") as Goal
	assert_not_null(goal_right, "GoalRight must exist")
	assert_true(goal_right.scoring_enabled, "GoalRight scoring_enabled starts true")

	# Simulate ball physically entering GoalRight 3 times during celebration window
	goal_right._on_body_entered(m.ball)
	goal_right._on_body_entered(m.ball)
	goal_right._on_body_entered(m.ball)
	assert_eq(m.home_score, 1, "Repeated physical ball entries during celebration must count as exactly 1 goal")
	assert_false(goal_right.scoring_enabled, "GoalRight scoring_enabled locked during celebration")

	# Advance past 1.5s celebration reset -> scoring re-enabled!
	m._physics_process(1.6)
	assert_true(goal_right.scoring_enabled, "GoalRight scoring_enabled restored after formation reset")

	# 3. Equalize 1-1 and advance clock to 00:00 -> Golden Goal triggers!
	goal_left._on_body_entered(m.ball)
	assert_eq(m.away_score, 1, "Away team equalizes 1-1")
	m._physics_process(1.6) # Finish celebration

	# Advance remaining regulation time past 60.0s
	m._physics_process(58.0)
	assert_true(m.is_golden_goal, "Tied score at 00:00 triggers Golden Goal sudden death")
	assert_true(m.is_match_active, "Match stays active during Golden Goal")
	assert_false(m.is_match_finished, "Match is not finished while tied in Golden Goal")

	# Score Golden Goal winner -> match ends after celebration!
	goal_right._on_body_entered(m.ball)
	assert_eq(m.home_score, 2, "Golden Goal increments home score to 2")
	m._physics_process(1.6)
	assert_true(m.is_match_finished, "Match finishes cleanly after Golden Goal celebration")
	assert_not_null(m.hud.result_layer, "MatchResultOverlay appears at end of match")

	m.free()

# ------------------------------------------------------------------------------
# TIER 3: 4-Phase Hissatsu, GK Save Duel, Merit Cooldowns & 6-Round Tournament
# ------------------------------------------------------------------------------
func test_tier_3_hissatsu_gk_duel_merit_and_tournament() -> void:
	set_tier(3)

	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))

	var match_packed := load(MATCH_SCENE_PATH) as PackedScene
	var m := match_packed.instantiate() as MatchController
	m.tournament_save_path = TEMP_SAVE_PATH
	_active_root().add_child(m)

	# Start Tournament Round 1 (Octavos de Final)
	m.start_tournament_round(4, 0, true)
	assert_true(m.is_tournament_mode, "Tournament mode is active")
	assert_eq(m.tournament_round_index, 0, "Starts at Round 1 (index 0)")
	assert_eq(m.target_score_to_win, 3, "Tournament target score is 3")
	assert_almost_eq(m.current_ai_difficulty, 0.85, 0.01, "Round 1 AI difficulty modifier is 0.85")

	# 1. Verify Goalkeeper loads gk_save ability from players.json
	var gk_right := m.players_container.get_node_or_null("GoalkeeperRight") as Goalkeeper
	assert_not_null(gk_right, "GoalkeeperRight must exist")
	assert_eq(gk_right.ability_type, "gk_save", "Goalkeeper loads gk_save ability type")
	assert_false(gk_right.ability_name.is_empty(), "Goalkeeper ability_name is populated")

	# 2. 4-Phase Hissatsu Windup -> Impact -> Super Shot -> GK Hissatsu Response
	var striker := m.players_container.get_node_or_null("UserPlayer4") as Player
	assert_not_null(striker, "UserPlayer4 striker must exist")
	striker.load_player("arg_03") # El Diez Eterno ("Tiro Cósmico", type = "shot")
	striker.set_user_controlled(true)
	striker.global_position = Vector2(1420.0, 0.0)
	striker.facing_direction = Vector2.RIGHT
	striker.ability_cooldown = 0.0
	m.ball.global_position = Vector2(1440.0, 0.0)
	m.ball.take_possession(striker)

	var impact_data := {"triggered": false, "hit": false}
	striker.ability_impact.connect(func(_pl: Player, _ab: String, _tp: String, hit_ok: bool):
		impact_data["triggered"] = true
		impact_data["hit"] = hit_ok
	)

	var gk_hissatsu := {"activated": false, "name": ""}
	gk_right.gk_ability_activated.connect(func(_gk: Goalkeeper, ab_n: String, _port: String):
		gk_hissatsu["activated"] = true
		gk_hissatsu["name"] = ab_n
	)

	# Trigger striker Hissatsu
	striker._activate_special_ability()
	assert_true(striker._hissatsu_pending, "Hissatsu enters 0.20s windup phase before firing")
	assert_eq(int(m.skill_fsm.get("current_state")), 1, "SkillStateMachine enters STARTUP in sync")

	# Step past 0.20s windup -> payload fires!
	for _i in range(15):
		striker._physics_process(0.016)
		m.skill_fsm.call("process_step", 0.016)
	assert_true(impact_data["triggered"], "ability_impact fires after 0.20s startup windup")
	assert_true(m.ball.is_super_shot, "Shot Hissatsu marks Ball.is_super_shot = true")
	assert_true(m.vfx_pool.call("get_active_count", "skill_burst") >= 1, "SkillBurstVFX spawned from VFXPool")

	# Step ball & GoalkeeperRight so GK detects incoming Super Shot and activates gk_save Hissatsu!
	gk_right.ability_cooldown = 0.0
	gk_right.global_position = Vector2(1710.0, 0.0)
	for _i in range(25):
		m.ball._physics_process(0.016)
		gk_right._physics_process(0.016)
		if gk_hissatsu["activated"]:
			break
	assert_true(gk_hissatsu["activated"], "Goalkeeper automatically triggers gk_save Hissatsu against incoming Super Shot")
	Engine.time_scale = 1.0

	# 3. Merit Cooldown Reduction on Pass & Clean Steal
	striker.ability_cooldown = 6.0
	m._on_ball_pass_completed(striker)
	assert_almost_eq(striker.ability_cooldown, 4.8, 0.05, "Completed pass reduces team ability cooldown by 1.2s")

	var rival := m.players_container.get_node_or_null("RivalPlayer1") as Player
	m._on_player_ball_stolen(striker, rival)
	assert_almost_eq(striker.ability_cooldown, 3.3, 0.05, "Clean steal reduces tackler ability cooldown by 1.5s")

	# 4. Tournament Target-Score Victory -> Auto-Save -> Reload -> Round 6 Championship
	m._on_goal_right_scored("GoalRight")
	m._on_goal_right_scored("GoalRight")
	m._on_goal_right_scored("GoalRight")
	assert_eq(m.home_score, 3, "Home reaches target_score_to_win = 3")
	m._physics_process(1.6) # Complete celebration -> finishes Round 1
	assert_true(m.is_match_finished, "Reaching 3 goals in Tournament finishes the round")
	assert_eq(m.tournament_round_index, 1, "Winning Round 1 advances tournament_round_index to 1 (Round 2)")
	assert_true(FileAccess.file_exists(TEMP_SAVE_PATH), "Tournament progress auto-saved to disk")

	# Instantiate fresh MatchController and verify save reload
	m.free()
	var m2 := match_packed.instantiate() as MatchController
	m2.tournament_save_path = TEMP_SAVE_PATH
	_active_root().add_child(m2)
	assert_true(m2.load_tournament_progress(), "Fresh MatchController loads saved tournament progress")
	assert_eq(m2.tournament_user_team_index, 4, "Restores saved user team index")
	assert_eq(m2.tournament_round_index, 1, "Restores saved Round 2 index")

	# Jump to Round 6 (Final Boss, index 5) and win Championship!
	m2.start_tournament_round(4, 5, false)
	assert_almost_eq(m2.current_ai_difficulty, 1.40, 0.01, "Round 6 Final Boss AI difficulty modifier is 1.40")
	m2._on_goal_right_scored("GoalRight")
	m2._on_goal_right_scored("GoalRight")
	m2._on_goal_right_scored("GoalRight")
	m2._physics_process(1.6)
	assert_true(m2.is_match_finished, "Final Boss round finishes at 3 goals")
	assert_true(m2.tournament_completed, "Winning Round 6 marks tournament_completed = true")

	m2.free()
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
