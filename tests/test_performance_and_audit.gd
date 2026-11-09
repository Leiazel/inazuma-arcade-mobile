class_name TestPerformanceAndAudit
extends "res://tests/base_test.gd"

# ==============================================================================
# Mobile Fluidity Audit, Anti-Stutter Caching, 9-Team Roster Integrity,
# Edge-Case Bug Regressions & 3,600-Frame (60s) 5v5 Match Benchmark Suite
# ==============================================================================

const MATCH_SCENE_PATH: String = "res://scenes/main/Match.tscn"
const TEMP_SAVE_PATH: String = "user://test_perf_audit_save.json"

func _init() -> void:
	super()
	suite_name = "PerformanceAndAudit"

func run_all() -> void:
	test_tier_1_anti_stutter_caches_redraw_gating_and_single_clock()
	test_tier_2_input_edge_hitstop_safety_and_9_team_catalog_integrity()
	test_tier_3_3600_frame_match_stress_and_latency_benchmark()

func _active_root() -> Window:
	var ml := Engine.get_main_loop() as SceneTree
	if ml != null and ml.root != null:
		return ml.root
	return root

# ------------------------------------------------------------------------------
# TIER 1: Zero-Allocation Caches, Redraw Gating & Single-Clock Camera
# ------------------------------------------------------------------------------
func test_tier_1_anti_stutter_caches_redraw_gating_and_single_clock() -> void:
	set_tier(1)

	var match_packed := load(MATCH_SCENE_PATH) as PackedScene
	assert_not_null(match_packed, "Match.tscn must load cleanly")
	var m := match_packed.instantiate() as MatchController
	m.tournament_save_path = TEMP_SAVE_PATH
	_active_root().add_child(m)

	# 1. MatchController zero-allocation actor caches & injected references
	assert_eq(m._all_match_actors.size(), 10, "MatchController caches all 10 field & GK actors")
	assert_eq(m._user_players.size(), 4, "MatchController caches 4 user outfield players")
	assert_eq(m._opp_players.size(), 4, "MatchController caches 4 opponent outfield players")
	assert_eq(m._goalkeepers.size(), 2, "MatchController caches 2 goalkeepers")
	assert_eq(m.ball.match_players_ref.size(), 10, "Ball receives shared match_players_ref without group queries")

	for p in m._user_players:
		assert_eq(p.match_players_ref.size(), 10, "User player receives shared match_players_ref")
		assert_eq(p.match_gks_ref.size(), 2, "User player receives shared match_gks_ref")
		assert_eq(p.current_ball, m.ball, "User player receives direct Ball reference")

	# 2. Single-clock DynamicCamera2D invariant (no double-stepping across _process + _physics_process)
	assert_not_null(m.camera, "DynamicCamera2D must exist in Match")
	assert_true(m.camera.managed_externally, "DynamicCamera2D is managed_externally by MatchController")
	assert_false(m.camera.is_processing(), "DynamicCamera2D _process is disabled to prevent frame/physics jitter")

	# 3. Player & Goalkeeper idle overlay redraw gating
	var active_p := m._get_active_player()
	assert_not_null(active_p, "Active user player exists")
	active_p.ability_cooldown = 0.0
	active_p.ability_active_timer = 0.0
	active_p._hissatsu_pending = false
	active_p.is_sliding = false
	active_p.slide_recovery_timer = 0.0
	active_p.is_charging_action = false
	active_p._refresh_overlay_redraw()
	assert_false(active_p._needs_overlay_draw(), "Idle Player does not request 60Hz CanvasItem overlay draw")
	assert_false(active_p._overlay_dirty_active, "Idle Player _overlay_dirty_active stays false")

	active_p.ability_cooldown = 4.0
	active_p._refresh_overlay_redraw()
	assert_true(active_p._needs_overlay_draw(), "Player on ability cooldown activates overlay draw")
	assert_true(active_p._overlay_dirty_active, "Player _overlay_dirty_active tracks active gauge")

	active_p.ability_cooldown = 0.0
	active_p._refresh_overlay_redraw()
	assert_false(active_p._overlay_dirty_active, "Player _overlay_dirty_active clears cleanly after 1 transition redraw")

	# 4. BaseIndicator2D idle _process gating (8 of 10 actors idle -> zero _process overhead)
	var processing_indicators: int = 0
	for actor in m._all_match_actors:
		var ind := actor.get("base_indicator") as BaseIndicator2D
		if is_instance_valid(ind) and ind.is_processing():
			processing_indicators += 1
	assert_eq(processing_indicators, 1, "Only the single controlled player's BaseIndicator2D runs _process when no pass target is active")
	assert_eq(BaseIndicator2D._unit_circle_32.size(), 33, "BaseIndicator2D precomputes 33-point static unit circle trig lookup")

	# 5. Pooled SkillBurstVFX idle _process gating
	var vfx_node: Node = m.vfx_pool.call("acquire", "skill_burst", Vector2.ZERO)
	assert_not_null(vfx_node, "VFXPool acquires SkillBurstVFX cleanly")
	vfx_node.set("pool_ref", m.vfx_pool)
	vfx_node.call("play_burst", Color.ORANGE, 1.0, 0.10)
	assert_true(vfx_node.is_processing(), "Active SkillBurstVFX enables _process during burst")
	vfx_node.call("_process", 0.25)
	assert_false(vfx_node.is_processing(), "Expired SkillBurstVFX disables _process when returned to pool")

	# 6. MiniRadar & TouchControls zero-allocation cached StyleBoxFlat & buffer reuse
	var hud := m.hud as MatchHUD
	var radar := hud.mini_radar as MiniRadar
	assert_not_null(radar._bg_style, "MiniRadar pre-allocates _bg_style once")
	var bg_ref: StyleBoxFlat = radar._bg_style
	m._update_bottom_hud()
	var hash_before: int = radar._last_hash
	m._update_bottom_hud()
	assert_eq(radar._bg_style, bg_ref, "MiniRadar reuses identical StyleBoxFlat instance across frames")
	assert_eq(radar._last_hash, hash_before, "MiniRadar quantized state hash skips redundant redraw when positions unchanged")
	assert_eq(radar._dot_count, 10, "MiniRadar packs all 10 actors into PackedVector2Array/PackedByteArray")

	var tc := hud.touch_controls as TouchControls
	assert_not_null(tc._pause_style_idle, "TouchControls caches _pause_style_idle StyleBoxFlat")
	assert_not_null(tc._pause_style_down, "TouchControls caches _pause_style_down StyleBoxFlat")
	assert_false(tc.is_processing(), "TouchControls _process stays disabled while shot button is not held")

	# 7. Shared PCM cache & HUD texture pre-warming
	assert_eq(ArcadeAudioManager._shared_pcm_cache.size(), 14, "ArcadeAudioManager caches all 14 synthesized PCM buffers statically")
	assert_true(hud._icon_cache.size() >= 6, "Match startup pre-warms HUD player icons into _icon_cache")
	var banner := hud.get_skill_banner() as SkillBanner
	assert_true(banner._portrait_cache.size() >= 6, "Match startup pre-warms SkillBanner portraits into _portrait_cache")

	m.free()

# ------------------------------------------------------------------------------
# TIER 2: Sub-Frame Input Edge Fix, Hitstop Safety & 9-Team Asset/Contrast Audit
# ------------------------------------------------------------------------------
func test_tier_2_input_edge_hitstop_safety_and_9_team_catalog_integrity() -> void:
	set_tier(2)

	var match_packed := load(MATCH_SCENE_PATH) as PackedScene
	var m := match_packed.instantiate() as MatchController
	m.tournament_save_path = TEMP_SAVE_PATH
	_active_root().add_child(m)

	# 1. Regression test for Godot 4.3 sub-frame Input.is_action_just_pressed("action_shot"):
	# Releasing a charged shot and tilting joystick in the same process frame MUST NOT trigger a slide tackle!
	var p := m._get_active_player()
	m.ball.take_possession(p)
	p.pass_receive_grace_timer = 0.0
	p.slide_cooldown = 0.0
	p.is_sliding = false

	Input.action_press("action_shot")
	for _i in range(20):
		p._physics_process(0.016)
	assert_true(p.is_charging_action, "Player is charging shot before release")

	# Release shot AND immediately move at sprint tilt within the exact same engine frame
	Input.action_release("action_shot")
	p._physics_process(0.016)
	assert_false(p.has_ball, "Releasing charged shot launches ball")
	assert_false(p.is_sliding, "Releasing shot does NOT trigger slide tackle")

	p.is_kicking = false
	p.kick_anim_timer = 0.0
	p.set_virtual_move(Vector2(1.0, 0.0))
	p._physics_process(0.016)
	assert_false(p.is_sliding, "Sub-frame move after shot release MUST NOT phantom-slide")
	assert_true(p.is_sprinting, "Player immediately enters Auto-Sprint cleanly after shot release")
	p.set_virtual_move(Vector2.ZERO)

	# 2. Rapid consecutive SkillStateMachine hitstops + mid-hitstop pause safety
	var fsm := m.skill_fsm as SkillStateMachine
	assert_not_null(fsm, "SkillStateMachine exists")
	var gen_initial: int = fsm._hitstop_generation
	fsm.execute("Tornado de Fuego", true)
	fsm.process_step(0.21) # -> ACTIVE
	fsm.process_step(0.09) # -> HITSTOP
	assert_eq(int(fsm.current_state), int(SkillStateMachine.State.HITSTOP), "FSM enters HITSTOP")
	assert_true(Engine.time_scale < 0.2, "Engine.time_scale slows down during HITSTOP")
	assert_true(fsm._hitstop_generation > gen_initial, "Hitstop increments _hitstop_generation token")

	# Pausing match mid-hitstop MUST restore Engine.time_scale = 1.0 immediately so pause UI isn't frozen!
	m.set_paused_state(true)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "Pausing match mid-hitstop immediately restores Engine.time_scale = 1.0")
	assert_eq(int(fsm.current_state), int(SkillStateMachine.State.IDLE), "Pausing cancels active SkillStateMachine hitstop cleanly")
	m.set_paused_state(false)

	# 3. Full 9-Team & 40-Player JSON Schema + Asset Existence + 81-Matchup Contrast Audit
	var expected_team_ids: Array[String] = [
		"team_desafiantes", "team_veteranos", "team_estrellas",
		"team_italia", "team_brasil", "team_argentina",
		"team_inglaterra", "team_espana", "team_francia"
	]
	assert_eq(m.team_catalog.size(), 9, "Catalog contains all 9 playable teams")
	for idx in range(expected_team_ids.size()):
		assert_eq(str(m.team_catalog[idx].get("id", "")), expected_team_ids[idx], "Team slot %d matches '%s'" % [idx, expected_team_ids[idx]])

	var players_db: Dictionary = Player.get_cached_players_db()
	assert_true(players_db.size() >= 38, "Players DB contains full expanded roster (>= 38 entries)")

	# Verify every single player entry in players.json has existing anims, sheet, portrait & icon files
	var valid_roles := ["DF", "MF", "FW", "GK"]
	var valid_ab_types := ["shot", "dribble", "pass", "defense", "gk_save"]
	var all_assets_exist: bool = true
	for pid in players_db.keys():
		var pdata: Dictionary = players_db[pid]
		var role_str := str(pdata.get("role", ""))
		var ab: Dictionary = pdata.get("ability", {})
		var ab_type := str(ab.get("type", ""))
		if not valid_roles.has(role_str) or not valid_ab_types.has(ab_type):
			all_assets_exist = false
		for asset_key in ["anims", "sheet", "portrait", "icon"]:
			var path := str(pdata.get(asset_key, ""))
			if path.is_empty() or (not FileAccess.file_exists(path) and not ResourceLoader.exists(path)):
				printerr("Missing asset '%s' (%s) for player '%s'" % [asset_key, path, str(pid)])
				all_assets_exist = false
	assert_true(all_assets_exist, "Every player in data/players.json has valid role, ability type, and verified disk assets")

	# Verify all 3 new teams load into a live match without fallbacks and build valid SpriteFrames
	for new_team_idx in [6, 7, 8]:
		var opp_idx: int = (new_team_idx + 1) % 9
		m.start_quick_match(new_team_idx, opp_idx, 60.0)
		var team_entry: Dictionary = m.team_catalog[new_team_idx]
		var expected_form: Array = team_entry.get("formation", [])
		assert_eq(expected_form.size(), 4, "Team %s has 4 outfield players" % str(team_entry.get("id")))
		for slot_i in range(4):
			var up := m._user_players[slot_i]
			assert_eq(up.player_id, str(expected_form[slot_i]), "UserPlayer%d loads exact player_id '%s' without fallback" % [slot_i + 1, str(expected_form[slot_i])])
			assert_not_null(up.anim_sprite.sprite_frames, "SpriteFrames built cleanly for '%s'" % up.player_id)
			assert_true(up.anim_sprite.sprite_frames.get_frame_count("idle_down") > 0, "idle_down has frames for '%s'" % up.player_id)

	# Verify 3x3 touch grid geometry stays compact inside the 1280x720 menu container
	var hud := m.hud as MatchHUD
	hud.show_match_setup(m.team_catalog, m._build_tournament_ui_info())
	var card_btns: Array = hud.tournament_team_picker.get_meta("card_buttons", [])
	assert_eq(card_btns.size(), 9, "Tournament 3x3 selector creates 9 direct-tap card buttons")
	var grid := (card_btns[0] as Control).get_parent() as GridContainer
	assert_not_null(grid, "Tournament 3x3 GridContainer exists")
	assert_eq(grid.columns, 3, "Tournament Team Grid uses 3 columns for 3x3 symmetry")
	var min_grid_size: Vector2 = grid.get_combined_minimum_size()
	assert_true(min_grid_size.y <= 250.0, "Dense 3x3 team grid minimum height (%.1f px) fits comfortably inside 720p menu" % min_grid_size.y)
	hud._close_menu_layer()

	# Verify 8-directional animation orientation, flip_h state, and zero static/backwards frames
	var test_p := m._get_active_player()
	assert_not_null(test_p, "Active user player exists for directional animation verification")
	if test_p != null:
		test_p.is_kicking = false
		test_p.is_moving = true
		test_p.is_sprinting = true

		# 1. Pure Right (+X): must play run_side with flip_h == false
		test_p.facing_direction = Vector2.RIGHT
		test_p.velocity = Vector2(300.0, 0.0)
		test_p._update_animation()
		assert_eq(String(test_p.anim_sprite.animation), "run_side", "Moving right (+X) plays 'run_side'")
		assert_false(test_p.anim_sprite.flip_h, "Moving right (+X) keeps flip_h == false (facing right)")

		# 2. Slight angle Right (joystick slightly tilted, e.g. y = 0.28): must STILL play run_side facing right
		test_p.facing_direction = Vector2(0.96, 0.28).normalized()
		test_p.velocity = test_p.facing_direction * 300.0
		test_p._update_animation()
		assert_eq(String(test_p.anim_sprite.animation), "run_side", "Slight joystick angle right plays 'run_side' without deadzone lock")
		assert_false(test_p.anim_sprite.flip_h, "Slight joystick angle right keeps flip_h == false")

		# 3. Pure Left (-X): must play native run_left with flip_h == false
		test_p.facing_direction = Vector2.LEFT
		test_p.velocity = Vector2(-300.0, 0.0)
		test_p._update_animation()
		assert_eq(String(test_p.anim_sprite.animation), "run_left", "Moving left (-X) plays native 'run_left'")
		assert_false(test_p.anim_sprite.flip_h, "Moving left (-X) with native 'run_left' keeps flip_h == false")

		# 4. Diagonal Down-Right (+X, +Y): must play run_down_side with flip_h == false
		test_p.facing_direction = Vector2(0.75, 0.66).normalized()
		test_p.velocity = test_p.facing_direction * 300.0
		test_p._update_animation()
		assert_eq(String(test_p.anim_sprite.animation), "run_down_side", "Moving down-right (+X, +Y) plays 'run_down_side'")
		assert_false(test_p.anim_sprite.flip_h, "Moving down-right (+X, +Y) keeps flip_h == false")

		# 5. Diagonal Down-Left (-X, +Y): must play native run_down_left with flip_h == false
		test_p.facing_direction = Vector2(-0.75, 0.66).normalized()
		test_p.velocity = test_p.facing_direction * 300.0
		test_p._update_animation()
		assert_eq(String(test_p.anim_sprite.animation), "run_down_left", "Moving down-left (-X, +Y) plays native 'run_down_left'")
		assert_false(test_p.anim_sprite.flip_h, "Moving down-left (-X, +Y) with native 'run_down_left' keeps flip_h == false")

		# 6. Diagonal Up-Right (+X, -Y): must play run_up_side with flip_h == false
		test_p.facing_direction = Vector2(0.75, -0.66).normalized()
		test_p.velocity = test_p.facing_direction * 300.0
		test_p._update_animation()
		assert_eq(String(test_p.anim_sprite.animation), "run_up_side", "Moving up-right (+X, -Y) plays 'run_up_side'")
		assert_false(test_p.anim_sprite.flip_h, "Moving up-right (+X, -Y) keeps flip_h == false")

		# 7. Diagonal Up-Left (-X, -Y): must play run_up_side with flip_h == true
		test_p.facing_direction = Vector2(-0.75, -0.66).normalized()
		test_p.velocity = test_p.facing_direction * 300.0
		test_p._update_animation()
		assert_eq(String(test_p.anim_sprite.animation), "run_up_side", "Moving up-left (-X, -Y) plays 'run_up_side'")
		assert_true(test_p.anim_sprite.flip_h, "Moving up-left (-X, -Y) sets flip_h == true")

		# 8. Verify run_side frames never include the standing cell (col 2, row 2 -> x=256, y=256) or back-facing cell (col 4, row 2 -> x=512, y=256)
		var sf_check := test_p.anim_sprite.sprite_frames
		var bad_side_frame_found := false
		for fi in range(sf_check.get_frame_count("run_side")):
			var tex := sf_check.get_frame_texture("run_side", fi) as AtlasTexture
			if tex != null:
				if tex.region.position == Vector2(256, 256) or tex.region.position == Vector2(512, 256):
					bad_side_frame_found = true
		assert_false(bad_side_frame_found, "run_side excludes static standing frame (#22) and back-number frame (#24)")

	m.free()

# ------------------------------------------------------------------------------
# TIER 3: 3,600-Frame (60s @ 60Hz) Full 5v5 Match Stress & Frame-Time Benchmark
# ------------------------------------------------------------------------------
func test_tier_3_3600_frame_match_stress_and_latency_benchmark() -> void:
	set_tier(3)

	var baseline_actors: int = Player._live_actor_count
	var match_packed := load(MATCH_SCENE_PATH) as PackedScene
	var m := match_packed.instantiate() as MatchController
	m.tournament_save_path = TEMP_SAVE_PATH
	_active_root().add_child(m)
	assert_eq(Player._live_actor_count, baseline_actors + 10, "Instantiating Match increments live actor refcount by 10")

	# Run Selección Tres Leones (index 6) vs Selección de los Galos (index 8) for 3,600 physics frames (60s)
	m.start_quick_match(6, 8, 90.0)
	var dt: float = 1.0 / 60.0
	var frame_times_usec := PackedInt64Array()
	frame_times_usec.resize(3600)
	var total_usec: int = 0
	var nan_detected: bool = false
	var out_of_bounds_detected: bool = false

	for frame in range(3600):
		var t0: int = Time.get_ticks_usec()

		# Drive synthetic user gameplay inputs across phases (dribbling, passing, charging shots, Hissatsu)
		var active_p := m._get_active_player()
		if active_p != null:
			var angle: float = float(frame) * 0.035
			var move_dir := Vector2(cos(angle), sin(angle * 1.3) * 0.75)
			active_p.set_virtual_move(move_dir)

			if frame % 240 == 60 and active_p.has_ball:
				active_p.execute_basic_command("pass")
			elif frame % 240 == 140 and active_p.has_ball:
				active_p.execute_basic_command("shot")
			elif frame % 300 == 180 and active_p.ability_cooldown <= 0.0:
				active_p.execute_basic_command("ability")

		# Step authoritative physics across Match, Ball, 8 Players, 2 Goalkeepers & SkillStateMachine
		m._physics_process(dt)
		m.ball._physics_process(dt)
		for actor in m._all_match_actors:
			if actor.process_mode != Node.PROCESS_MODE_DISABLED:
				actor._physics_process(dt)
		if m.skill_fsm != null and m.skill_fsm.is_processing():
			m.skill_fsm.call("process_step", dt)

		var elapsed_u: int = Time.get_ticks_usec() - t0
		frame_times_usec[frame] = elapsed_u
		total_usec += elapsed_u

		# Check numerical stability every 30 frames
		if frame % 30 == 0:
			var bp := m.ball.global_position
			if is_nan(bp.x) or is_nan(bp.y) or is_inf(bp.x) or is_inf(bp.y):
				nan_detected = true
			for actor in m._all_match_actors:
				var ap: Vector2 = (actor as Node2D).global_position
				if is_nan(ap.x) or is_nan(ap.y) or is_inf(ap.x) or is_inf(ap.y):
					nan_detected = true
				if absf(ap.x) > 1950.0 or absf(ap.y) > 1200.0:
					out_of_bounds_detected = true

	var avg_ms: float = (float(total_usec) / 3600.0) / 1000.0
	var sorted_times := Array(frame_times_usec)
	sorted_times.sort()
	var p99_ms: float = float(sorted_times[int(3600 * 0.99)]) / 1000.0

	print("    [BENCHMARK 3600 FRAMES] Avg step: %.3f ms | P99 step: %.3f ms (Budget 60FPS = 16.67 ms)" % [avg_ms, p99_ms])

	assert_false(nan_detected, "Zero NaN/Inf positions across 3,600 simulated 5v5 match frames")
	assert_false(out_of_bounds_detected, "All 10 actors remain clamped inside pitch boundaries across 3,600 frames")
	assert_true(avg_ms < 1.5, "Average 5v5 match physics+HUD step (%.3f ms) is well under 1.5 ms (<9%% of 60FPS budget)" % avg_ms)
	assert_true(p99_ms < 5.0, "P99 5v5 match step (%.3f ms) exhibits zero GC/allocation stutter spikes (< 5.0 ms)" % p99_ms)

	Engine.time_scale = 1.0
	m.free()
	assert_eq(Player._live_actor_count, baseline_actors, "All 10 Player/Goalkeeper actor instances cleanly unregistered on free")
	if baseline_actors == 0:
		assert_eq(Player._sprite_frames_pool.size(), 0, "Static SpriteFrames pool auto-releases RefCounted textures when actor count hits 0")

	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
