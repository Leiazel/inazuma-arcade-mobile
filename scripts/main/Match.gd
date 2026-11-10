class_name MatchController
extends Node2D

## MatchController: Orchestrates the integrated 5v5 match scene in Godot 4.3.
## Coordinates Pitch, DynamicCamera, Ball, 5v5 Players & Goalkeepers, KitData,
## ColorClashDetector, SkillStateMachine, SkillBurstVFX (NodePool), WarmUpManager,
## ArcadeAudioManager, Countdown + Golden Goal rules, and the 6-Round Continental Tournament.

const ColorClashDetectorScript = preload("res://scripts/kits/ColorClashDetector.gd")
const SkillStateMachineScript = preload("res://scripts/skills/SkillStateMachine.gd")
const NodePoolScript = preload("res://scripts/performance/NodePool.gd")
const WarmUpManagerScript = preload("res://scripts/performance/WarmUpManager.gd")
const ArcadeAudioManagerScript = preload("res://scripts/audio/ArcadeAudioManager.gd")
const SkillBurstVFXScript = preload("res://scripts/vfx/SkillBurstVFX.gd")

const DEFAULT_QUICK_DURATION: float = 90.0
const GOAL_CELEBRATION_DURATION: float = 1.5
const PASS_COOLDOWN_REDUCTION: float = 1.2
const STEAL_COOLDOWN_REDUCTION: float = 1.5

@export var home_team_name: String = "TRES LEONES"
@export var away_team_name: String = "FURIA ROJA"
@export var match_duration_seconds: float = 90.0

var home_score: int = 0
var away_score: int = 0
var elapsed_time: float = 0.0
var is_match_active: bool = true
var is_paused: bool = false
var is_in_menu: bool = false
var is_match_finished: bool = false
var is_golden_goal: bool = false
var goal_reset_timer: float = 0.0

# Tournament & Mode state
var is_tournament_mode: bool = false
var target_score_to_win: int = 0
var current_ai_difficulty: float = 1.0
var tournament_config: Dictionary = {}
var tournament_rounds: Array[Dictionary] = []
var tournament_user_team_index: int = 4
var tournament_round_index: int = 0
var tournament_completed: bool = false
var tournament_has_save: bool = false
var tournament_save_path: String = "user://tournament_save.json"

var last_quick_home_index: int = 4
var last_quick_away_index: int = 2
var resolved_home_color: Color = Color(0.98, 0.80, 0.15)
var resolved_away_color: Color = Color(0.22, 0.74, 0.98)

var skill_fsm: Node = null
var vfx_pool: Node = null
var warmup_manager: Node = null
var audio_manager: Node = null

var _all_match_actors: Array = []
var _user_players: Array[Player] = []
var _opp_players: Array[Player] = []
var _goalkeepers: Array = []

# 5v5 Matchup presets (preserved for backwards compatibility)
var matchups: Array[Dictionary] = [
	{
		"user_team_name": "VERDEAMARELA",
		"user_ids": ["bra_05", "bra_03", "bra_01", "bra_02"],
		"user_gk": "gk_bra",
		"user_color": "#FACC15",
		"opp_team_name": "ESTRELLAS",
		"opp_ids": ["star_04", "star_03", "star_02", "star_01"],
		"opp_gk": "gk_star",
		"opp_color": "#EF4444"
	},
	{
		"user_team_name": "CELESTE",
		"user_ids": ["arg_04", "arg_02", "arg_01", "arg_03"],
		"user_gk": "gk_arg",
		"user_color": "#38BDF8",
		"opp_team_name": "AZZURRA",
		"opp_ids": ["ita_02", "ita_04", "ita_01", "ita_03"],
		"opp_gk": "gk_ita",
		"opp_color": "#2563EB"
	},
	{
		"user_team_name": "CLÁSICOS",
		"user_ids": ["vet_03", "vet_01", "vet_04", "vet_02"],
		"user_gk": "gk_vet",
		"user_color": "#A855F7",
		"opp_team_name": "DESAFIANTES",
		"opp_ids": ["leg_02", "leg_03", "leg_01", "bra_04"],
		"opp_gk": "gk_leg",
		"opp_color": "#FF6B1A"
	}
]
var current_matchup_index: int = 0
var team_catalog: Array[Dictionary] = []
var dragged_player: Player = null

# Robust node accessors
var pitch: Node2D:
	get:
		if _pitch == null:
			_pitch = get_node_or_null("Pitch")
		return _pitch
	set(val):
		_pitch = val
var _pitch: Node2D = null

var camera: DynamicCamera2D:
	get:
		if _camera == null:
			_camera = get_node_or_null("DynamicCamera") as DynamicCamera2D
		return _camera
	set(val):
		_camera = val
var _camera: DynamicCamera2D = null

var ball: Ball:
	get:
		if _ball == null:
			_ball = get_node_or_null("Ball") as Ball
		return _ball
	set(val):
		_ball = val
var _ball: Ball = null

var hud: CanvasLayer:
	get:
		if _hud == null:
			_hud = get_node_or_null("HUD") as CanvasLayer
		return _hud
	set(val):
		_hud = val
var _hud: CanvasLayer = null

var players_container: Node2D:
	get:
		if _players_container == null:
			_players_container = get_node_or_null("Players") as Node2D
		return _players_container
	set(val):
		_players_container = val
var _players_container: Node2D = null

func _ready() -> void:
	_setup_performance_and_skill_systems()
	_connect_goals()
	_connect_ball()
	_connect_players_and_goalkeepers()
	_load_team_catalog()
	_load_tournament_config()
	load_tournament_progress()
	_apply_matchup(0)
	_connect_hud_signals()

	# In interactive display mode, open the Main Menu on boot;
	# in headless mode, stay active immediately so automated physics & integration suites step cleanly.
	var is_headless: bool = (DisplayServer.get_name() == "headless")
	if not is_headless:
		open_main_menu()
	else:
		is_in_menu = false
		is_paused = false
		is_match_finished = false
		is_match_active = true
		_set_match_process_enabled(true)
		_refresh_hud_full()

func _exit_tree() -> void:
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	_all_match_actors.clear()
	_user_players.clear()
	_opp_players.clear()
	_goalkeepers.clear()

func _connect_hud_signals() -> void:
	if hud == null:
		return
	if hud.has_signal("match_start_requested") and not hud.match_start_requested.is_connected(_on_match_start_requested):
		hud.match_start_requested.connect(_on_match_start_requested)
	if hud.has_signal("tournament_round_requested") and not hud.tournament_round_requested.is_connected(_on_tournament_round_requested):
		hud.tournament_round_requested.connect(_on_tournament_round_requested)
	if hud.has_signal("pause_action_requested") and not hud.pause_action_requested.is_connected(_on_pause_action_requested):
		hud.pause_action_requested.connect(_on_pause_action_requested)
	if hud.has_signal("result_action_requested") and not hud.result_action_requested.is_connected(_on_result_action_requested):
		hud.result_action_requested.connect(_on_result_action_requested)
	if hud.has_signal("virtual_move_changed") and not hud.virtual_move_changed.is_connected(_on_virtual_move_changed):
		hud.virtual_move_changed.connect(_on_virtual_move_changed)
	if hud.has_signal("touch_action_selected") and not hud.touch_action_selected.is_connected(_on_touch_action_selected):
		hud.touch_action_selected.connect(_on_touch_action_selected)
	if hud.has_signal("field_drag_started") and not hud.field_drag_started.is_connected(_on_field_drag_started):
		hud.field_drag_started.connect(_on_field_drag_started)
	if hud.has_signal("field_drag_changed") and not hud.field_drag_changed.is_connected(_on_field_drag_changed):
		hud.field_drag_changed.connect(_on_field_drag_changed)
	if hud.has_signal("field_drag_ended") and not hud.field_drag_ended.is_connected(_on_field_drag_ended):
		hud.field_drag_ended.connect(_on_field_drag_ended)
	if hud.has_signal("field_clicked") and not hud.field_clicked.is_connected(_on_field_clicked):
		hud.field_clicked.connect(_on_field_clicked)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		if not is_in_menu and not is_match_finished:
			toggle_pause()
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			if is_match_active and not is_paused and not is_in_menu:
				set_paused_state(true)
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if is_in_menu:
				pass
			elif is_paused:
				set_paused_state(false)
			elif is_match_active and not is_match_finished:
				set_paused_state(true)

func _vibrate(duration_ms: int = 80) -> void:
	if duration_ms <= 0 or is_paused:
		return
	if Input.has_method("vibrate_handheld"):
		Input.vibrate_handheld(duration_ms)

# ==============================================================================
# MENU, PAUSE, QUICK MATCH & 6-ROUND TOURNAMENT FLOW
# ==============================================================================

func open_main_menu(prefer_tournament: bool = true) -> void:
	is_in_menu = true
	is_paused = false
	is_match_active = false
	is_match_finished = false
	is_golden_goal = false
	if skill_fsm != null and skill_fsm.has_method("cancel"):
		skill_fsm.call("cancel")
	_set_match_process_enabled(false)

	if hud != null:
		if hud.has_method("set_pause_menu_visible"):
			hud.call("set_pause_menu_visible", false)
		if hud.has_method("hide_match_result"):
			hud.call("hide_match_result")
		if hud.has_method("set_status_badge"):
			hud.call("set_status_badge", "", Color.WHITE, false)
		if hud.has_method("show_match_setup"):
			hud.call("show_match_setup", team_catalog, _build_tournament_ui_info(prefer_tournament))

func toggle_pause() -> void:
	if is_in_menu or is_match_finished:
		return
	set_paused_state(not is_paused)

func set_paused_state(paused_flag: bool) -> void:
	is_paused = paused_flag
	is_match_active = not is_paused
	if is_paused and Engine.time_scale != 1.0:
		if skill_fsm != null and skill_fsm.has_method("cancel"):
			skill_fsm.call("cancel")
		else:
			Engine.time_scale = 1.0
	_set_match_process_enabled(not is_paused)
	if audio_manager != null and audio_manager.has_method("play_sfx"):
		audio_manager.call("play_sfx", "ui_click")
	if hud != null and hud.has_method("set_pause_menu_visible"):
		hud.call("set_pause_menu_visible", is_paused, _get_pause_ui_state())

func _get_pause_ui_state() -> Dictionary:
	return {
		"touch_enabled": hud.call("is_touch_controls_enabled") if (hud != null and hud.has_method("is_touch_controls_enabled")) else false,
		"sfx_enabled": bool(audio_manager.get("sfx_enabled")) if audio_manager != null else true,
		"music_enabled": bool(audio_manager.get("music_enabled")) if audio_manager != null else true
	}

func _on_pause_action_requested(action: String) -> void:
	match action:
		"pause", "toggle_pause":
			toggle_pause()
		"resume":
			set_paused_state(false)
		"restart":
			set_paused_state(false)
			if is_tournament_mode:
				start_tournament_round(tournament_user_team_index, tournament_round_index, false)
			else:
				start_quick_match(last_quick_home_index, last_quick_away_index, match_duration_seconds)
		"toggle_touch":
			if hud != null and hud.has_method("is_touch_controls_enabled") and hud.has_method("set_touch_controls_enabled"):
				var next_touch: bool = not bool(hud.call("is_touch_controls_enabled"))
				hud.call("set_touch_controls_enabled", next_touch)
				hud.call("set_pause_menu_visible", true, _get_pause_ui_state())
			if audio_manager != null:
				audio_manager.call("play_sfx", "ui_click")
		"toggle_sfx":
			if audio_manager != null:
				var next_sfx: bool = not bool(audio_manager.get("sfx_enabled"))
				audio_manager.call("set_sfx_enabled", next_sfx)
				if next_sfx:
					audio_manager.call("play_sfx", "ui_click")
			if hud != null and hud.has_method("set_pause_menu_visible"):
				hud.call("set_pause_menu_visible", true, _get_pause_ui_state())
		"toggle_music":
			if audio_manager != null:
				var next_mus: bool = not bool(audio_manager.get("music_enabled"))
				audio_manager.call("set_music_enabled", next_mus)
				audio_manager.call("play_sfx", "ui_click")
			if hud != null and hud.has_method("set_pause_menu_visible"):
				hud.call("set_pause_menu_visible", true, _get_pause_ui_state())
		"main_menu":
			open_main_menu(is_tournament_mode)

func _on_result_action_requested(action: String) -> void:
	if audio_manager != null:
		audio_manager.call("play_sfx", "ui_click")
	match action:
		"next_round":
			start_tournament_round(tournament_user_team_index, tournament_round_index, false)
		"retry_round":
			start_tournament_round(tournament_user_team_index, tournament_round_index, false)
		"new_tournament":
			start_tournament_round(tournament_user_team_index, 0, true)
		"rematch":
			start_quick_match(last_quick_home_index, last_quick_away_index, match_duration_seconds)
		"main_menu":
			open_main_menu(is_tournament_mode)

func _on_match_start_requested(home_index: int, away_index: int) -> void:
	if team_catalog.is_empty():
		return
	var dur: float = DEFAULT_QUICK_DURATION
	if hud != null and hud.get("selected_quick_duration") != null:
		dur = float(hud.get("selected_quick_duration"))
	var safe_away: int = away_index
	if home_index == safe_away and team_catalog.size() > 1:
		safe_away = (home_index + 1) % team_catalog.size()
	start_quick_match(home_index, safe_away, dur)

func start_quick_match(home_index: int, away_index: int, duration_sec: float = DEFAULT_QUICK_DURATION) -> void:
	if team_catalog.is_empty():
		_load_team_catalog()
	is_tournament_mode = false
	target_score_to_win = 0
	current_ai_difficulty = 1.0
	match_duration_seconds = maxf(15.0, duration_sec)
	last_quick_home_index = clampi(home_index, 0, maxi(0, team_catalog.size() - 1))
	last_quick_away_index = clampi(away_index, 0, maxi(0, team_catalog.size() - 1))

	matchups = [_build_matchup(last_quick_home_index, last_quick_away_index)]
	_begin_configured_match("")

func _on_tournament_round_requested(user_team_idx: int, round_idx: int, start_new: bool) -> void:
	start_tournament_round(user_team_idx, round_idx, start_new)

func start_tournament_round(user_team_idx: int, round_idx: int = 0, start_new: bool = false) -> void:
	if team_catalog.is_empty():
		_load_team_catalog()
	if tournament_rounds.is_empty():
		_load_tournament_config()

	is_tournament_mode = true
	tournament_user_team_index = clampi(user_team_idx, 0, maxi(0, team_catalog.size() - 1))
	if start_new:
		tournament_round_index = 0
		tournament_completed = false
	else:
		tournament_round_index = clampi(round_idx, 0, maxi(0, tournament_rounds.size() - 1))

	save_tournament_progress()

	var r_data: Dictionary = tournament_rounds[tournament_round_index] if not tournament_rounds.is_empty() else {}
	var opp_team_id: String = str(r_data.get("opponent_team", "team_desafiantes"))
	var opp_idx: int = _find_team_index_by_id(opp_team_id)
	var is_mirror: bool = (opp_idx == tournament_user_team_index)

	current_ai_difficulty = clampf(float(r_data.get("difficulty_modifier", 1.0)), 0.80, 1.50)
	match_duration_seconds = maxf(20.0, float(tournament_config.get("match_duration_seconds", 60.0)))
	target_score_to_win = maxi(1, int(tournament_config.get("target_score_to_win", 3)))

	var m := _build_matchup(tournament_user_team_index, opp_idx, is_mirror)
	matchups = [m]
	var round_title: String = "RONDA %d/%d · %s (META: %d GOLES)" % [
		tournament_round_index + 1,
		maxi(1, tournament_rounds.size()),
		str(r_data.get("name", "Fase")).to_upper(),
		target_score_to_win
	]
	_begin_configured_match(round_title)

func _begin_configured_match(badge_text: String) -> void:
	is_in_menu = false
	is_paused = false
	is_match_finished = false
	is_golden_goal = false
	home_score = 0
	away_score = 0
	elapsed_time = 0.0
	goal_reset_timer = 0.0

	_apply_matchup(0)
	_set_goals_scoring_enabled(true)
	_set_match_process_enabled(true)
	is_match_active = true

	if hud != null:
		if hud.has_method("hide_match_result"):
			hud.call("hide_match_result")
		if hud.has_method("set_pause_menu_visible"):
			hud.call("set_pause_menu_visible", false)
		if hud.has_method("set_status_badge"):
			hud.call("set_status_badge", badge_text, Color(0.38, 0.82, 1.0), not badge_text.is_empty())
	_refresh_hud_full()

	if audio_manager != null:
		audio_manager.call("start_music")
		audio_manager.call("play_sfx", "whistle_kickoff")

# ==============================================================================
# TOURNAMENT DATA & PERSISTENCE
# ==============================================================================

func _load_tournament_config() -> void:
	tournament_config.clear()
	tournament_rounds.clear()
	if not FileAccess.file_exists("res://data/tournament.json"):
		return
	var file := FileAccess.open("res://data/tournament.json", FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file else null
	if parsed is Dictionary and parsed.has("tournament"):
		tournament_config = parsed["tournament"]
		var raw_rounds: Array = tournament_config.get("rounds", [])
		for r in raw_rounds:
			if r is Dictionary:
				var r_copy: Dictionary = r.duplicate(true)
				var opp_idx: int = _find_team_index_by_id(str(r_copy.get("opponent_team", "")))
				if opp_idx >= 0 and opp_idx < team_catalog.size():
					r_copy["opponent_label"] = str(team_catalog[opp_idx].get("name", r_copy.get("opponent_team", "")))
				tournament_rounds.append(r_copy)

func _find_team_index_by_id(team_id_str: String) -> int:
	for i in range(team_catalog.size()):
		if str(team_catalog[i].get("id", "")) == team_id_str:
			return i
	return 0

func save_tournament_progress() -> void:
	var payload := {
		"user_team_index": tournament_user_team_index,
		"current_round_index": tournament_round_index,
		"completed": tournament_completed
	}
	var file := FileAccess.open(tournament_save_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload))
		tournament_has_save = true

func load_tournament_progress() -> bool:
	if not FileAccess.file_exists(tournament_save_path):
		tournament_has_save = false
		return false
	var file := FileAccess.open(tournament_save_path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		tournament_user_team_index = clampi(int(parsed.get("user_team_index", 4)), 0, maxi(0, team_catalog.size() - 1))
		tournament_round_index = clampi(int(parsed.get("current_round_index", 0)), 0, maxi(0, tournament_rounds.size() - 1))
		tournament_completed = bool(parsed.get("completed", false))
		tournament_has_save = true
		return true
	return false

func _build_tournament_ui_info(prefer_tournament: bool = true) -> Dictionary:
	return {
		"title": "%s  •  %ds O PRIMERO A %d GOLES" % [
			str(tournament_config.get("title", "Torneo Continental")),
			int(tournament_config.get("match_duration_seconds", 60)),
			int(tournament_config.get("target_score_to_win", 3))
		],
		"rounds": tournament_rounds,
		"saved_team_index": tournament_user_team_index,
		"saved_round_index": tournament_round_index,
		"has_save": tournament_has_save,
		"completed": tournament_completed,
		"prefer_tournament": prefer_tournament
	}

# ==============================================================================
# TOUCH, MOUSE & FIELD INPUT BRIDGES
# ==============================================================================

func _get_active_player() -> Player:
	for p in _user_players:
		if is_instance_valid(p) and p.is_user_controlled:
			return p
	if players_container == null:
		return null
	for node in players_container.get_children():
		if node is Player and node.team_id == "team_user" and node.is_user_controlled:
			return node
	return null

func _get_featured_away_player() -> Node:
	if ball != null and ball.current_state == Ball.State.CONTROLADA and is_instance_valid(ball.carrier):
		if str(ball.carrier.get("team_id")) == "team_opp":
			return ball.carrier
	var best_rival: Node = null
	var best_dist_sq: float = INF
	var ref_pos: Vector2 = ball.global_position if ball != null else Vector2.ZERO
	if not _opp_players.is_empty():
		for p in _opp_players:
			if is_instance_valid(p):
				var d_sq: float = p.global_position.distance_squared_to(ref_pos)
				if d_sq < best_dist_sq:
					best_dist_sq = d_sq
					best_rival = p
		return best_rival
	if players_container == null:
		return null
	for node in players_container.get_children():
		if node is Player and node.team_id == "team_opp":
			var d_sq: float = node.global_position.distance_squared_to(ref_pos)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_rival = node
	return best_rival

func _on_virtual_move_changed(vector: Vector2) -> void:
	var player := _get_active_player()
	if player != null:
		player.set_virtual_move(vector)

func _on_touch_action_selected(action: String) -> void:
	var player := _get_active_player()
	if player != null:
		if action == "slide":
			if player.has_method("can_slide_tackle") and player.can_slide_tackle():
				player.call("_start_slide_tackle")
			else:
				player.execute_basic_command(action)
		else:
			player.execute_basic_command(action)

func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position

func _find_player_at_world(world_position: Vector2) -> Player:
	var nearest: Player = null
	var nearest_dist_sq: float = 92.0 * 92.0
	if not _user_players.is_empty():
		for p in _user_players:
			if is_instance_valid(p) and not p.is_ai:
				var d_sq: float = p.global_position.distance_squared_to(world_position)
				if d_sq < nearest_dist_sq:
					nearest = p
					nearest_dist_sq = d_sq
		return nearest
	if players_container == null:
		return null
	for node in players_container.get_children():
		if node is Player and node.team_id == "team_user" and not node.is_ai:
			var d_sq: float = node.global_position.distance_squared_to(world_position)
			if d_sq < nearest_dist_sq:
				nearest = node
				nearest_dist_sq = d_sq
	return nearest

func _on_field_drag_started(_screen_position: Vector2) -> void:
	return

func _on_field_clicked(button: int, screen_position: Vector2) -> void:
	if not is_match_active or players_container == null:
		return
	var world_position := _screen_to_world(screen_position)
	var active_player := _get_active_player()
	if active_player == null:
		return
	var clicked_player := _find_player_at_world(world_position)
	if clicked_player != null and clicked_player != active_player and clicked_player.team_id == active_player.team_id:
		active_player.execute_pass_at_position(clicked_player)
	elif active_player.has_ball and (button == MOUSE_BUTTON_RIGHT or world_position.x > 0.0):
		active_player.execute_shot_at_position(world_position)

func _on_field_drag_changed(_screen_position: Vector2) -> void:
	return

func _on_field_drag_ended(_screen_position: Vector2) -> void:
	return

# ==============================================================================
# TEAM CATALOG, KIT ARBITRATION & MATCHUP SETUP
# ==============================================================================

func _load_team_catalog() -> void:
	team_catalog.clear()
	var players_data: Dictionary = Player.get_cached_players_db()

	if FileAccess.file_exists("res://data/teams.json"):
		var file := FileAccess.open("res://data/teams.json", FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text()) if file else null
		if parsed is Dictionary and parsed.has("teams"):
			for team in parsed["teams"].values():
				if team is Dictionary and team.has("formation") and team.has("gk_id"):
					var team_copy: Dictionary = team.duplicate(true)
					var form: Array = team_copy.get("formation", [])
					team_copy["players"] = _get_roster_names_from_dict(form, str(team_copy.get("gk_id", "")), players_data)
					team_copy["star_portrait"] = _find_star_portrait(form, players_data)
					team_catalog.append(team_copy)

	if team_catalog.is_empty():
		team_catalog = [
			{"id": "team_brasil", "name": "Selección Verdeamarela", "formation": ["bra_05", "bra_03", "bra_01", "bra_02"], "gk_id": "gk_bra", "color": "#FACC15", "secondary_color": "#16A34A", "alt_color": "#22C55E"},
			{"id": "team_estrellas", "name": "Estrellas Mundiales", "formation": ["star_04", "star_03", "star_02", "star_01"], "gk_id": "gk_star", "color": "#EF4444", "secondary_color": "#FFFFFF", "alt_color": "#F97316"}
		]

func _find_star_portrait(formation: Array, players_data: Dictionary) -> String:
	for idx in range(formation.size() - 1, -1, -1):
		var pid: String = str(formation[idx])
		var pdata: Dictionary = players_data.get(pid, {})
		var p_path: String = str(pdata.get("portrait", ""))
		if p_path.is_empty():
			var vis: Dictionary = pdata.get("visuals", {})
			p_path = str(vis.get("portrait_sprite", ""))
		if not p_path.is_empty() and (ResourceLoader.exists(p_path) or FileAccess.file_exists(p_path)):
			return p_path
	return ""

func _get_roster_names_from_dict(formation: Array, goalkeeper_id: String, players_data: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for player_id in formation:
		var data: Dictionary = players_data.get(str(player_id), {})
		var ab: Dictionary = data.get("ability", {})
		var ab_txt: String = str(ab.get("name", ""))
		result.append("%s (%s)%s" % [
			str(data.get("name", player_id)),
			str(data.get("role", "MF")),
			(" · " + ab_txt) if not ab_txt.is_empty() else ""
		])
	var gk_data: Dictionary = players_data.get(str(goalkeeper_id), {})
	var gk_ab: Dictionary = gk_data.get("ability", {})
	var gk_ab_txt: String = str(gk_ab.get("name", ""))
	result.append("%s (GK)%s" % [
		str(gk_data.get("name", goalkeeper_id)),
		(" · " + gk_ab_txt) if not gk_ab_txt.is_empty() else ""
	])
	return result

func _build_matchup(home_index: int, away_index: int, is_mirror_elite: bool = false) -> Dictionary:
	var home: Dictionary = team_catalog[clampi(home_index, 0, team_catalog.size() - 1)]
	var away: Dictionary = team_catalog[clampi(away_index, 0, team_catalog.size() - 1)]
	var opp_label: String = str(away.get("name", "VISITANTE")).to_upper()
	if is_mirror_elite:
		opp_label += " ÉLITE"
	return {
		"user_team_name": str(home.get("name", "LOCAL")).to_upper(),
		"user_ids": home.get("formation", []),
		"user_gk": home.get("gk_id", "gk_bra"),
		"user_color": home.get("color", "#FACC15"),
		"user_secondary": home.get("secondary_color", "#16A34A"),
		"opp_team_name": opp_label,
		"opp_ids": away.get("formation", []),
		"opp_gk": away.get("gk_id", "gk_star"),
		"opp_color": away.get("alt_color", "#E11D48") if is_mirror_elite else away.get("color", "#EF4444"),
		"opp_secondary": away.get("secondary_color", "#FFFFFF"),
		"opp_alt_color": away.get("alt_color", "#06B6D4")
	}

func _set_match_process_enabled(enabled: bool) -> void:
	var target_mode := Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	if not _all_match_actors.is_empty():
		for node in _all_match_actors:
			if is_instance_valid(node):
				node.process_mode = target_mode
	elif players_container != null:
		for node in players_container.get_children():
			node.process_mode = target_mode
	if ball != null:
		ball.process_mode = target_mode

func _set_goals_scoring_enabled(enabled: bool) -> void:
	if pitch == null:
		return
	var gl = pitch.get_node_or_null("GoalLeft")
	var gr = pitch.get_node_or_null("GoalRight")
	if gl != null and gl.get("scoring_enabled") != null:
		gl.set("scoring_enabled", enabled)
	if gr != null and gr.get("scoring_enabled") != null:
		gr.set("scoring_enabled", enabled)

func _setup_performance_and_skill_systems() -> void:
	if camera != null and camera.has_method("set_managed_externally"):
		camera.set_managed_externally(true)

	if skill_fsm == null:
		skill_fsm = get_node_or_null("SkillStateMachine")
		if skill_fsm == null:
			skill_fsm = SkillStateMachineScript.new()
			skill_fsm.name = "SkillStateMachine"
			add_child(skill_fsm)
	skill_fsm.set("camera", camera)

	if vfx_pool == null:
		vfx_pool = get_node_or_null("VFXPool")
		if vfx_pool == null:
			vfx_pool = NodePoolScript.new()
			vfx_pool.name = "VFXPool"
			add_child(vfx_pool)
	if vfx_pool != null and vfx_pool.has_method("has_pool") and not bool(vfx_pool.call("has_pool", "skill_burst")):
		var burst_proto := SkillBurstVFXScript.new()
		var burst_scene := PackedScene.new()
		burst_scene.pack(burst_proto)
		burst_proto.free()
		vfx_pool.call("register_prefab", "skill_burst", burst_scene, 10, 24)

	if warmup_manager == null:
		warmup_manager = get_node_or_null("WarmUpManager")
		if warmup_manager == null:
			warmup_manager = WarmUpManagerScript.new()
			warmup_manager.name = "WarmUpManager"
			add_child(warmup_manager)
	if warmup_manager != null:
		var kit_mat := ShaderMaterial.new()
		kit_mat.shader = Player.KitColorSwapShader
		var warm_mats: Array[Material] = [kit_mat]
		warmup_manager.set("materials_to_warm", warm_mats)
		if DisplayServer.get_name() != "headless" and warmup_manager.has_method("run_warm_up_routine"):
			warmup_manager.call_deferred("run_warm_up_routine")

	if audio_manager == null:
		audio_manager = get_node_or_null("AudioManager")
		if audio_manager == null:
			audio_manager = ArcadeAudioManagerScript.new()
			audio_manager.name = "AudioManager"
			add_child(audio_manager)

func _spawn_vfx_burst(pos: Vector2, col: Color, scale_mult: float = 1.0, dur: float = 0.38) -> void:
	if vfx_pool == null or not vfx_pool.has_method("acquire"):
		return
	var node: Node = vfx_pool.call("acquire", "skill_burst", pos)
	if node == null:
		return
	if not node.has_method("play_burst"):
		node.set_script(SkillBurstVFXScript)
	node.set("pool_ref", vfx_pool)
	node.call("play_burst", col, scale_mult, dur)

func _connect_goals() -> void:
	if pitch == null:
		return
	var goal_left = pitch.get_node_or_null("GoalLeft")
	var goal_right = pitch.get_node_or_null("GoalRight")
	if goal_left and goal_left.has_signal("goal_scored") and not goal_left.goal_scored.is_connected(_on_goal_left_scored):
		goal_left.goal_scored.connect(_on_goal_left_scored)
	if goal_right and goal_right.has_signal("goal_scored") and not goal_right.goal_scored.is_connected(_on_goal_right_scored):
		goal_right.goal_scored.connect(_on_goal_right_scored)

func _connect_ball() -> void:
	if ball == null:
		return
	if ball.has_signal("pass_completed") and not ball.pass_completed.is_connected(_on_ball_pass_completed):
		ball.pass_completed.connect(_on_ball_pass_completed)

func _refresh_actor_caches() -> void:
	_all_match_actors.clear()
	_user_players.clear()
	_opp_players.clear()
	_goalkeepers.clear()
	if players_container == null:
		return
	for node in players_container.get_children():
		_all_match_actors.append(node)
		if node is Player:
			var p := node as Player
			if p.team_id == "team_user":
				_user_players.append(p)
			elif p.team_id == "team_opp":
				_opp_players.append(p)
		elif node is CharacterBody2D:
			_goalkeepers.append(node)
	for node in _all_match_actors:
		if node is Player:
			var p := node as Player
			p.match_players_ref = _all_match_actors
			p.match_gks_ref = _goalkeepers
			if ball != null:
				p.current_ball = ball
		elif node is CharacterBody2D:
			node.set("match_players_ref", _all_match_actors)
			if ball != null:
				node.set("ball", ball)
	if ball != null:
		ball.match_players_ref = _all_match_actors

func _connect_players_and_goalkeepers() -> void:
	if players_container == null:
		return
	for node in players_container.get_children():
		if node is Player:
			var p := node as Player
			if not p.ability_activated.is_connected(_on_player_ability_activated):
				p.ability_activated.connect(_on_player_ability_activated)
			if p.has_signal("ability_impact") and not p.ability_impact.is_connected(_on_player_ability_impact):
				p.ability_impact.connect(_on_player_ability_impact)
			if not p.ball_stolen.is_connected(_on_player_ball_stolen):
				p.ball_stolen.connect(_on_player_ball_stolen)
			if not p.pass_initiated.is_connected(_on_player_pass_initiated):
				p.pass_initiated.connect(_on_player_pass_initiated)
			if not p.shot_charge_started.is_connected(_on_player_shot_charge_started):
				p.shot_charge_started.connect(_on_player_shot_charge_started)
			if not p.shot_executed.is_connected(_on_player_shot_executed):
				p.shot_executed.connect(_on_player_shot_executed)
			if not p.slide_tackle_executed.is_connected(_on_player_slide_tackle_executed):
				p.slide_tackle_executed.connect(_on_player_slide_tackle_executed)
		else:
			if node.has_signal("shot_saved") and not node.shot_saved.is_connected(_on_goalkeeper_shot_saved):
				node.shot_saved.connect(_on_goalkeeper_shot_saved)
			if node.has_signal("gk_ability_activated") and not node.gk_ability_activated.is_connected(_on_goalkeeper_ability_activated):
				node.gk_ability_activated.connect(_on_goalkeeper_ability_activated)
	_refresh_actor_caches()

func _arbitrate_team_colors(m: Dictionary) -> void:
	var h_prim := Color.from_string(str(m.get("user_color", "#FACC15")), Color(0.98, 0.80, 0.15))
	var h_sec := Color.from_string(str(m.get("user_secondary", "#16A34A")), Color(0.10, 0.60, 0.25))
	var a_prim := Color.from_string(str(m.get("opp_color", "#EF4444")), Color(0.94, 0.27, 0.27))
	var a_sec := Color.from_string(str(m.get("opp_secondary", "#FFFFFF")), Color.WHITE)
	var a_alt := Color.from_string(str(m.get("opp_alt_color", "#06B6D4")), Color(0.02, 0.71, 0.83))

	var home_kit := KitData.new()
	home_kit.team_name = str(m.get("user_team_name", "LOCAL"))
	home_kit.primary_color = h_prim
	home_kit.secondary_color = h_sec

	var away_kit := KitData.new()
	away_kit.team_name = str(m.get("opp_team_name", "RIVAL"))
	away_kit.primary_color = a_prim
	away_kit.secondary_color = a_sec

	var away_alt_kit := KitData.new()
	away_alt_kit.team_name = away_kit.team_name + "_ALT"
	away_alt_kit.is_away = true
	away_alt_kit.primary_color = a_alt
	away_alt_kit.secondary_color = Color.WHITE

	var arb: Dictionary = ColorClashDetectorScript.arbitrate_kits(home_kit, away_kit, away_alt_kit)
	var chosen_away: KitData = arb.get("away_kit", away_kit)
	var final_away_col: Color = chosen_away.primary_color

	# Guaranteed contrast safety fallback if primary + alt still clash
	if ColorClashDetectorScript.calculate_color_distance(h_prim, final_away_col) < ColorClashDetectorScript.CLASH_THRESHOLD:
		var cand_crimson := Color("#E11D48")
		var cand_cyan := Color("#06B6D4")
		var d_crim: float = ColorClashDetectorScript.calculate_color_distance(h_prim, cand_crimson)
		var d_cyan: float = ColorClashDetectorScript.calculate_color_distance(h_prim, cand_cyan)
		final_away_col = cand_crimson if d_crim >= d_cyan else cand_cyan

	resolved_home_color = h_prim
	resolved_away_color = final_away_col

func _apply_matchup(idx: int) -> void:
	if matchups.is_empty() or players_container == null:
		return
	current_matchup_index = posmod(idx, matchups.size())
	var m: Dictionary = matchups[current_matchup_index]
	home_team_name = str(m["user_team_name"])
	away_team_name = str(m["opp_team_name"])

	_arbitrate_team_colors(m)

	if hud != null:
		if hud.has_method("set_team_names"):
			hud.set_team_names(home_team_name, away_team_name)
		if hud.has_method("set_team_colors"):
			hud.call("set_team_colors", resolved_home_color, resolved_away_color)

	var roles: Array[String] = ["DF", "MF", "MF", "FW"]
	var user_ids: Array = m["user_ids"]
	var opp_ids: Array = m["opp_ids"]

	for i in range(4):
		var up = players_container.get_node_or_null("UserPlayer%d" % (i + 1)) as Player
		if up:
			up.team_id = "team_user"
			up.is_ai = false
			up.ai_difficulty = 1.0
			up.target_goal_x = 1800.0
			up.load_player(user_ids[i])
			up.role = roles[i]
			up.set_user_controlled(i == 1)
			if is_instance_valid(up.base_indicator):
				up.base_indicator.set_team_color(resolved_home_color)

		var rp = players_container.get_node_or_null("RivalPlayer%d" % (i + 1)) as Player
		if rp:
			rp.team_id = "team_opp"
			rp.is_ai = true
			rp.ai_difficulty = current_ai_difficulty
			rp.target_goal_x = -1800.0
			rp.load_player(opp_ids[i])
			rp.role = roles[i]
			rp.set_user_controlled(false)
			if is_instance_valid(rp.base_indicator):
				rp.base_indicator.set_team_color(resolved_away_color)

	var gk_l = players_container.get_node_or_null("GoalkeeperLeft")
	if gk_l:
		gk_l.set("team_id", "team_user")
		gk_l.set("ai_difficulty", 1.0)
		if gk_l.has_method("load_goalkeeper"):
			gk_l.call("load_goalkeeper", m["user_gk"])
		var gk_home_ind = gk_l.get("base_indicator") as BaseIndicator2D
		if is_instance_valid(gk_home_ind):
			gk_home_ind.set_team_color(resolved_home_color)

	var gk_r = players_container.get_node_or_null("GoalkeeperRight")
	if gk_r:
		gk_r.set("team_id", "team_opp")
		gk_r.set("ai_difficulty", current_ai_difficulty)
		if gk_r.has_method("load_goalkeeper"):
			gk_r.call("load_goalkeeper", m["opp_gk"])
		var gk_away_ind = gk_r.get("base_indicator") as BaseIndicator2D
		if is_instance_valid(gk_away_ind):
			gk_away_ind.set_team_color(resolved_away_color)

	_refresh_actor_caches()

	if hud != null and hud.has_method("preload_match_assets"):
		var icon_paths: Array[String] = []
		var portrait_paths: Array[String] = []
		for actor in _all_match_actors:
			if is_instance_valid(actor):
				var ic: String = str(actor.get("icon_path")) if actor.get("icon_path") != null else ""
				if not ic.is_empty() and not icon_paths.has(ic):
					icon_paths.append(ic)
				var pt: String = str(actor.get("portrait_path")) if actor.get("portrait_path") != null else ""
				if not pt.is_empty() and not portrait_paths.has(pt):
					portrait_paths.append(pt)
		hud.call("preload_match_assets", icon_paths, portrait_paths)

	_reset_formation()

func _reset_formation() -> void:
	if players_container == null:
		return

	var up1 = players_container.get_node_or_null("UserPlayer1") as Player
	var up2 = players_container.get_node_or_null("UserPlayer2") as Player
	var up3 = players_container.get_node_or_null("UserPlayer3") as Player
	var up4 = players_container.get_node_or_null("UserPlayer4") as Player

	if up1: up1.set_home_position(Vector2(-920, 0))
	if up2: up2.set_home_position(Vector2(-420, -300))
	if up3: up3.set_home_position(Vector2(-420, 300))
	if up4:
		up4.set_home_position(Vector2(500, 100))
		up4.global_position = Vector2(-150, 70)

	var rp1 = players_container.get_node_or_null("RivalPlayer1") as Player
	var rp2 = players_container.get_node_or_null("RivalPlayer2") as Player
	var rp3 = players_container.get_node_or_null("RivalPlayer3") as Player
	var rp4 = players_container.get_node_or_null("RivalPlayer4") as Player

	if rp1: rp1.set_home_position(Vector2(920, 0))
	if rp2: rp2.set_home_position(Vector2(420, -300))
	if rp3: rp3.set_home_position(Vector2(420, 300))
	if rp4:
		rp4.set_home_position(Vector2(-500, -100))
		rp4.global_position = Vector2(170, -70)

	var actors_list: Array = _all_match_actors if not _all_match_actors.is_empty() else players_container.get_children()
	for node in actors_list:
		if node is CharacterBody2D:
			(node as CharacterBody2D).velocity = Vector2.ZERO
			node.set("has_ball", false)
			node.set("is_charging_action", false)
			node.set("pass_press_time", 0.0)

	var gk_l = players_container.get_node_or_null("GoalkeeperLeft") as Node2D
	var gk_r = players_container.get_node_or_null("GoalkeeperRight") as Node2D
	if gk_l:
		gk_l.global_position = Vector2(-1710, 0)
		gk_l.set("current_state", 0)
	if gk_r:
		gk_r.global_position = Vector2(1710, 0)
		gk_r.set("current_state", 0)

	if ball != null:
		ball.global_position = Vector2.ZERO
		ball.set_libre(Vector2.ZERO)

	_set_goals_scoring_enabled(true)

func _refresh_hud_full() -> void:
	if hud == null:
		return
	if hud.has_method("set_team_names"):
		hud.set_team_names(home_team_name, away_team_name)
	if hud.has_method("set_score"):
		hud.set_score(home_score, away_score)
	_update_hud_clock()
	_update_bottom_hud()

func _update_hud_clock() -> void:
	if hud == null or not hud.has_method("set_time"):
		return
	if is_golden_goal:
		var ot_elapsed: float = maxf(0.0, elapsed_time - match_duration_seconds)
		hud.set_time(ot_elapsed)
	else:
		var remaining: float = maxf(0.0, match_duration_seconds - elapsed_time)
		hud.set_time(remaining)

func _update_bottom_hud() -> void:
	if hud == null or not hud.has_method("update_bottom_hud"):
		return
	var all_p: Array = _all_match_actors if not _all_match_actors.is_empty() else (players_container.get_children() if players_container != null else [])
	hud.call("update_bottom_hud", _get_active_player(), _get_featured_away_player(), all_p, ball)

# ==============================================================================
# PHYSICS TICK, COUNTDOWN, GOLDEN GOAL & MATCH COMPLETION
# ==============================================================================

func _physics_process(delta: float) -> void:
	if not is_match_active:
		return

	elapsed_time += delta
	_update_hud_clock()
	_update_bottom_hud()

	if goal_reset_timer > 0.0:
		goal_reset_timer -= delta
		if goal_reset_timer <= 0.0:
			goal_reset_timer = 0.0
			if _check_post_goal_match_end():
				return
			_reset_formation()
			if audio_manager != null:
				audio_manager.call("play_sfx", "whistle_kickoff")
	else:
		_check_regulation_clock_end()

	if Input.is_key_pressed(KEY_R) and goal_reset_timer <= 0.0:
		_reset_formation()

	_update_camera_tracking(delta)

func _check_post_goal_match_end() -> bool:
	if is_golden_goal and home_score != away_score:
		_finish_match()
		return true
	if target_score_to_win > 0 and (home_score >= target_score_to_win or away_score >= target_score_to_win):
		_finish_match()
		return true
	if elapsed_time >= match_duration_seconds and home_score != away_score:
		_finish_match()
		return true
	return false

func _check_regulation_clock_end() -> void:
	if is_golden_goal or is_match_finished:
		return
	if elapsed_time < match_duration_seconds:
		return

	if home_score == away_score:
		# Enter Golden Goal sudden-death tiebreaker!
		is_golden_goal = true
		if audio_manager != null:
			audio_manager.call("play_sfx", "whistle_golden")
		if hud != null:
			if hud.has_method("set_status_badge"):
				hud.call("set_status_badge", "⚡ GOL DE ORO — ¡PRÓXIMO GOL GANA! ⚡", Color(1.0, 0.78, 0.16), true)
			if hud.has_method("display_skill_banner"):
				hud.call("display_skill_banner", "TIEMPO CUMPLIDO", "¡GOL DE ORO · MUERTE SÚBITA!", "FIRE")
	else:
		_finish_match()

func _finish_match() -> void:
	if is_match_finished:
		return
	is_match_finished = true
	is_match_active = false
	if skill_fsm != null and skill_fsm.has_method("cancel"):
		skill_fsm.call("cancel")
	_set_match_process_enabled(false)

	if audio_manager != null:
		audio_manager.call("play_sfx", "whistle_end")

	var user_won: bool = home_score > away_score
	var headline: String = "¡VICTORIA!" if user_won else "DERROTA"
	var subtitle: String = "Partido Rápido completado."
	var is_champion: bool = false

	if is_tournament_mode:
		var total_rounds: int = maxi(1, tournament_rounds.size())
		var round_num: int = tournament_round_index + 1
		if user_won:
			if round_num >= total_rounds:
				is_champion = true
				tournament_completed = true
				headline = "🏆 ¡CAMPEÓN CONTINENTAL! 🏆"
				subtitle = "¡Has vencido a las 6 leyendas continentales y conquistado la Copa!"
			else:
				tournament_round_index += 1
				var next_r: Dictionary = tournament_rounds[tournament_round_index] if tournament_round_index < tournament_rounds.size() else {}
				headline = "¡RONDA %d SUPERADA!" % round_num
				subtitle = "Próximo desafío: Ronda %d — %s vs %s" % [
					tournament_round_index + 1,
					str(next_r.get("name", "Siguiente Fase")),
					str(next_r.get("opponent_label", next_r.get("opponent_team", "Rival")))
				]
			save_tournament_progress()
		else:
			headline = "CAÍSTE EN LA RONDA %d" % round_num
			subtitle = "Tu progreso en el Torneo está guardado. ¡Ajusta tu táctica y reintenta la ronda!"
	else:
		if is_golden_goal:
			subtitle = ("¡Definición épica en Gol de Oro!" if user_won else "El rival se llevó el duelo en Gol de Oro.")

	if hud != null and hud.has_method("show_match_result"):
		hud.call("show_match_result", {
			"user_won": user_won,
			"is_tournament": is_tournament_mode,
			"is_champion": is_champion,
			"headline": headline,
			"subtitle": subtitle,
			"home_name": home_team_name,
			"away_name": away_team_name,
			"home_score": home_score,
			"away_score": away_score
		})

func _update_camera_tracking(delta: float) -> void:
	if camera == null:
		return
	var carrier: CharacterBody2D = null
	if ball != null and ball.current_state == Ball.State.CONTROLADA:
		carrier = ball.carrier

	var active_player: CharacterBody2D = _get_active_player()
	if active_player == null:
		if not _user_players.is_empty() and is_instance_valid(_user_players[0]):
			active_player = _user_players[0]
		elif not _all_match_actors.is_empty():
			for p in _all_match_actors:
				if p is CharacterBody2D:
					active_player = p as CharacterBody2D
					break
		elif players_container != null:
			for p in players_container.get_children():
				if p is CharacterBody2D:
					active_player = p as CharacterBody2D
					break

	camera.update_camera(delta, ball, carrier, active_player)

# ==============================================================================
# GOALS, 4-PHASE HISSATSU, GK DUELS, COOLDOWN MERIT & AUDIO/VFX
# ==============================================================================

func _on_goal_right_scored(_goal_name: String) -> void:
	home_score += 1
	goal_reset_timer = GOAL_CELEBRATION_DURATION
	_set_goals_scoring_enabled(false)
	_vibrate(250)
	if audio_manager != null:
		audio_manager.call("play_sfx", "goal")
	if ball != null:
		_spawn_vfx_burst(ball.global_position, Color(1.0, 0.84, 0.18), 1.75, 0.55)
	if hud != null:
		if hud.has_method("set_score"):
			hud.set_score(home_score, away_score)
		if hud.has_method("display_skill_banner"):
			var msg := "¡GOL DE ORO · VICTORIA!" if is_golden_goal else "¡¡¡ GOOOOOL !!!"
			hud.display_skill_banner(home_team_name, msg, "FIRE")
	if camera != null:
		camera.add_trauma(0.65)

func _on_goal_left_scored(_goal_name: String) -> void:
	away_score += 1
	goal_reset_timer = GOAL_CELEBRATION_DURATION
	_set_goals_scoring_enabled(false)
	_vibrate(200)
	if audio_manager != null:
		audio_manager.call("play_sfx", "goal", 0.88)
	if ball != null:
		_spawn_vfx_burst(ball.global_position, Color(0.95, 0.35, 0.25), 1.65, 0.55)
	if hud != null:
		if hud.has_method("set_score"):
			hud.set_score(home_score, away_score)
		if hud.has_method("display_skill_banner"):
			var msg := "¡GOL DE ORO RIVAL!" if is_golden_goal else "¡¡¡ GOL RIVAL !!!"
			hud.display_skill_banner(away_team_name, msg, "EARTH")
	if camera != null:
		camera.add_trauma(0.65)

func _element_for_ability_type(ab_type: String) -> String:
	match ab_type:
		"shot": return "FIRE"
		"dribble": return "AIR"
		"pass": return "WOOD"
		"defense", "gk_save": return "EARTH"
	return "FIRE"

func _color_for_ability_type(ab_type: String) -> Color:
	match ab_type:
		"shot": return Color(1.0, 0.42, 0.12)
		"dribble": return Color(0.24, 0.78, 1.0)
		"pass": return Color(0.25, 0.92, 0.52)
		"defense", "gk_save": return Color(1.0, 0.84, 0.22)
	return Color(1.0, 0.75, 0.20)

func _on_player_ability_activated(p: Player, ab_name: String, ab_type: String) -> void:
	var elem := _element_for_ability_type(ab_type)
	_vibrate(150)
	if audio_manager != null:
		audio_manager.call("play_sfx", "hissatsu_start")
	_spawn_vfx_burst(p.global_position, _color_for_ability_type(ab_type), 0.90, 0.28)
	if skill_fsm != null and int(skill_fsm.get("current_state")) == 0:
		if skill_fsm.has_method("execute"):
			skill_fsm.call("execute", ab_name, true)
	trigger_hissatsu_banner(p.player_name.to_upper(), ab_name.to_upper(), elem, p.portrait_path)

func _on_player_ability_impact(p: Player, _ab_name: String, ab_type: String, hit_connected: bool) -> void:
	if audio_manager != null:
		audio_manager.call("play_sfx", "hissatsu_hit" if hit_connected else "shot")
	var vfx_pos: Vector2 = p.global_position
	if (ab_type == "shot" or ab_type == "pass") and ball != null:
		vfx_pos = ball.global_position
	_spawn_vfx_burst(vfx_pos, _color_for_ability_type(ab_type), 1.50 if hit_connected else 1.0, 0.44)
	if camera != null:
		camera.add_trauma(0.55 if hit_connected else 0.28)

func _on_goalkeeper_ability_activated(gk: CharacterBody2D, ab_name: String, portrait_path: String) -> void:
	_vibrate(120)
	if audio_manager != null:
		audio_manager.call("play_sfx", "gk_save")
	_spawn_vfx_burst(gk.global_position, Color(1.0, 0.85, 0.22), 1.40, 0.45)
	var gk_name: String = str(gk.get("player_name")) if gk.get("player_name") != null else "ARQUERO"
	trigger_hissatsu_banner(gk_name.to_upper(), ab_name.to_upper(), "EARTH", portrait_path)

func _on_goalkeeper_shot_saved(gk: CharacterBody2D) -> void:
	_vibrate(80)
	if audio_manager != null:
		audio_manager.call("play_sfx", "gk_save", 1.08)
	_spawn_vfx_burst(gk.global_position, Color(0.98, 0.88, 0.35), 1.0, 0.34)
	if camera != null:
		camera.add_trauma(0.35)
	var used_hissatsu: bool = bool(gk.get("dive_using_hissatsu")) if gk.get("dive_using_hissatsu") != null else false
	if not used_hissatsu and hud != null and hud.has_method("display_skill_banner"):
		var gk_name: String = str(gk.get("player_name")) if gk.get("player_name") != null else "ARQUERO"
		var gk_port: String = str(gk.get("portrait_path")) if gk.get("portrait_path") != null else ""
		hud.call("display_skill_banner", gk_name.to_upper(), "¡ATAJADA ESPECTACULAR!", "EARTH", gk_port)

func _on_ball_pass_completed(receiver: CharacterBody2D) -> void:
	if not is_instance_valid(receiver):
		return
	if audio_manager != null:
		audio_manager.call("play_sfx", "pass", 1.14)
	_spawn_vfx_burst(receiver.global_position, Color(0.35, 0.95, 0.62), 0.65, 0.24)
	var recv_team: String = str(receiver.get("team_id"))
	if not _all_match_actors.is_empty():
		for node in _all_match_actors:
			if is_instance_valid(node) and str(node.get("team_id")) == recv_team and node.has_method("reduce_ability_cooldown"):
				node.call("reduce_ability_cooldown", PASS_COOLDOWN_REDUCTION)
	elif players_container != null:
		for node in players_container.get_children():
			if str(node.get("team_id")) == recv_team and node.has_method("reduce_ability_cooldown"):
				node.call("reduce_ability_cooldown", PASS_COOLDOWN_REDUCTION)

func _on_player_ball_stolen(tackler: Player, _victim: Player) -> void:
	if audio_manager != null:
		audio_manager.call("play_sfx", "steal")
	if tackler.has_method("reduce_ability_cooldown"):
		tackler.reduce_ability_cooldown(STEAL_COOLDOWN_REDUCTION)
	_spawn_vfx_burst(tackler.global_position, Color(0.28, 0.86, 1.0), 0.85, 0.30)
	if camera != null:
		camera.add_trauma(0.22)
	if tackler.team_id == "team_user" and hud != null and hud.has_method("display_skill_banner"):
		hud.call("display_skill_banner", tackler.player_name.to_upper(), "¡ROBO LIMPIO!", "AIR", tackler.portrait_path)

func _on_player_pass_initiated(_from: Player, _to: Player, _power: float) -> void:
	if audio_manager != null:
		audio_manager.call("play_sfx", "pass")

func _on_player_shot_charge_started(_p: Player) -> void:
	if audio_manager != null:
		audio_manager.call("play_sfx", "charge")

func _on_player_shot_executed(_p: Player, _speed: float, charge_factor: float) -> void:
	if audio_manager != null:
		audio_manager.call("play_sfx", "shot", lerpf(0.92, 1.18, charge_factor))

func _on_player_slide_tackle_executed(_p: Player, _success: bool) -> void:
	if audio_manager != null:
		audio_manager.call("play_sfx", "slide")

func trigger_hissatsu_banner(player_name: String, skill_name: String, element: String = "FIRE", portrait_path: String = "") -> void:
	if hud != null and hud.has_method("display_skill_banner"):
		hud.call("display_skill_banner", player_name, skill_name, element, portrait_path)
	if camera != null:
		camera.add_trauma(0.40)
