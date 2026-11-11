class_name MatchHUD
extends CanvasLayer

## MatchHUD: Clean, ergonomic CanvasLayer for Inazuma Arcade Mobile.
## Maintains 100% unobstructed view of the top-left quadrant ([0, 460] x [0, 360]).
## Features a Warm Beige, Imperial Crimson Red, Crisp White & Royal Gold visual identity,
## compact bottom-center HUD dock (clearing both bottom thumb zones), Touch-Grid Team Selectors,
## Pause Menu, and Result Overlay.

const VIEWPORT_WIDTH: float = 1280.0
const VIEWPORT_HEIGHT: float = 720.0

const SCOREBOARD_POS: Vector2 = Vector2(460.0, 14.0)
const SCOREBOARD_SIZE: Vector2 = Vector2(360.0, 52.0)
const SCOREBOARD_BG_COLOR: Color = Color(0.08, 0.11, 0.16, 0.75)

# Compact Bottom-Center Dock: keeps [0..290] (left thumb) and [990..1280] (right thumb) 100% clear
const BOTTOM_HUD_Y: float = 628.0
const HOME_CARD_POS: Vector2 = Vector2(296.0, BOTTOM_HUD_Y)
const AWAY_CARD_POS: Vector2 = Vector2(748.0, BOTTOM_HUD_Y)
const PLAYER_CARD_SIZE: Vector2 = Vector2(236.0, 78.0)
const RADAR_POS: Vector2 = Vector2(542.0, BOTTOM_HUD_Y)
const RADAR_SIZE: Vector2 = Vector2(196.0, 80.0)
const STATUS_BADGE_POS: Vector2 = Vector2(500.0, 70.0)
const STATUS_BADGE_SIZE: Vector2 = Vector2(280.0, 24.0)

# Palette: Warm Beige, Imperial Crimson Red, Crisp White & Royal Gold
const THEME_BG_CREAM: Color = Color(0.96, 0.92, 0.84, 0.98)
const THEME_BG_CARD: Color = Color(0.99, 0.97, 0.93, 0.98)
const THEME_BG_BEIGE_SUB: Color = Color(0.91, 0.85, 0.74, 0.96)
const THEME_BACKDROP: Color = Color(0.16, 0.06, 0.06, 0.84)
const THEME_RED_PRIMARY: Color = Color(0.78, 0.14, 0.16, 1.0)
const THEME_RED_DARK: Color = Color(0.52, 0.08, 0.10, 1.0)
const THEME_RED_BRIGHT: Color = Color(0.88, 0.20, 0.20, 1.0)
const THEME_GOLD: Color = Color(0.86, 0.65, 0.14, 1.0)
const THEME_GOLD_BRIGHT: Color = Color(0.98, 0.80, 0.20, 1.0)
const THEME_WHITE: Color = Color(0.99, 0.98, 0.96, 1.0)
const THEME_TEXT_DARK: Color = Color(0.18, 0.09, 0.08, 1.0)
const THEME_TEXT_MUTED: Color = Color(0.44, 0.26, 0.22, 1.0)

const SkillBannerScript = preload("res://scripts/hud/SkillBanner.gd")
const TouchControlsScript = preload("res://scripts/hud/TouchControls.gd")
const MiniRadarScript = preload("res://scripts/hud/MiniRadar.gd")

# Properties
var home_score: int = 0
var away_score: int = 0
var match_time_seconds: float = 0.0
var home_team_name: String = "TRES LEONES"
var away_team_name: String = "FURIA ROJA"
var home_team_color: Color = Color(0.78, 0.14, 0.16)
var away_team_color: Color = Color(0.86, 0.65, 0.14)

var menu_layer: Control = null
var home_team_picker: OptionButton = null
var away_team_picker: OptionButton = null
var tournament_team_picker: OptionButton = null
var selected_quick_duration: float = 90.0

var bottom_home_card: PanelContainer = null
var bottom_away_card: PanelContainer = null
var mini_radar: Control = null
var status_badge: PanelContainer = null
var status_badge_label: Label = null
var pause_layer: Control = null
var result_layer: Control = null
var touch_controls: Control = null

var _icon_cache: Dictionary = {}
var _home_card_refs: Dictionary = {}
var _away_card_refs: Dictionary = {}
var _pause_refs: Dictionary = {}
var _last_time_sec: int = -1
var _last_home_score: int = -1
var _last_away_score: int = -1

signal match_start_requested(home_index: int, away_index: int)
signal quick_match_requested(home_index: int, away_index: int, duration_seconds: float)
signal tournament_round_requested(user_team_index: int, round_index: int, start_new: bool)
signal pause_action_requested(action: String)
signal result_action_requested(action: String)
signal virtual_move_changed(vector: Vector2)
signal touch_action_selected(action: String)
signal field_drag_started(screen_position: Vector2)
signal field_drag_changed(screen_position: Vector2)
signal field_drag_ended(screen_position: Vector2)
signal field_clicked(button: int, screen_position: Vector2)

# Robust node accessors supporting both packed scene tree & dynamic instantiation
var scoreboard_panel: PanelContainer:
	get:
		if _scoreboard_panel == null:
			_scoreboard_panel = get_node_or_null("TopCenterScoreboard")
		return _scoreboard_panel
	set(val):
		_scoreboard_panel = val
var _scoreboard_panel: PanelContainer = null

var home_name_label: Label:
	get:
		if _home_name_label == null:
			_home_name_label = find_child("HomeName", true, false) as Label
		return _home_name_label
	set(val):
		_home_name_label = val
var _home_name_label: Label = null

var home_score_label: Label:
	get:
		if _home_score_label == null:
			_home_score_label = find_child("HomeScore", true, false) as Label
		return _home_score_label
	set(val):
		_home_score_label = val
var _home_score_label: Label = null

var time_label: Label:
	get:
		if _time_label == null:
			_time_label = find_child("TimeLabel", true, false) as Label
		return _time_label
	set(val):
		_time_label = val
var _time_label: Label = null

var away_score_label: Label:
	get:
		if _away_score_label == null:
			_away_score_label = find_child("AwayScore", true, false) as Label
		return _away_score_label
	set(val):
		_away_score_label = val
var _away_score_label: Label = null

var away_name_label: Label:
	get:
		if _away_name_label == null:
			_away_name_label = find_child("AwayName", true, false) as Label
		return _away_name_label
	set(val):
		_away_name_label = val
var _away_name_label: Label = null

var skill_banner: Control:
	get:
		if _skill_banner == null:
			_skill_banner = get_node_or_null("SkillBanner") as Control
		return _skill_banner
	set(val):
		_skill_banner = val
var _skill_banner: Control = null

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui_if_needed()
	_ensure_touch_controls()
	_build_bottom_hud_if_needed()
	_build_status_badge_if_needed()
	_build_pause_menu_if_needed()
	update_all()
	_sync_touch_menu_block()

func _ensure_touch_controls() -> void:
	touch_controls = get_node_or_null("TouchControls") as Control
	if touch_controls == null:
		touch_controls = TouchControlsScript.new()
		touch_controls.name = "TouchControls"
		touch_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		touch_controls.move_changed.connect(func(vector: Vector2): virtual_move_changed.emit(vector))
		touch_controls.action_selected.connect(func(action: String): touch_action_selected.emit(action))
		touch_controls.ability_pressed.connect(func(): touch_action_selected.emit("ability"))
		touch_controls.field_drag_started.connect(func(pos: Vector2): field_drag_started.emit(pos))
		touch_controls.field_drag_changed.connect(func(pos: Vector2): field_drag_changed.emit(pos))
		touch_controls.field_drag_ended.connect(func(pos: Vector2): field_drag_ended.emit(pos))
		touch_controls.field_clicked.connect(func(button: int, pos: Vector2): field_clicked.emit(button, pos))
		if touch_controls.has_signal("pause_pressed"):
			touch_controls.pause_pressed.connect(func(): pause_action_requested.emit("toggle_pause"))
		add_child(touch_controls)
	if DisplayServer.get_name() == "headless" and touch_controls.has_method("set_touch_enabled"):
		touch_controls.call("set_touch_enabled", false)

func _sync_touch_menu_block() -> void:
	if touch_controls == null or not is_instance_valid(touch_controls):
		return
	var any_menu_open: bool = (
		(is_instance_valid(menu_layer) and menu_layer.visible)
		or (is_instance_valid(pause_layer) and pause_layer.visible)
		or (is_instance_valid(result_layer) and result_layer.visible)
	)
	if touch_controls.has_method("set_blocked_by_menu"):
		touch_controls.call("set_blocked_by_menu", any_menu_open)

func set_touch_controls_enabled(enabled: bool) -> void:
	_ensure_touch_controls()
	if touch_controls != null and touch_controls.has_method("set_touch_enabled"):
		touch_controls.call("set_touch_enabled", enabled)
	_sync_touch_menu_block()

func is_touch_controls_enabled() -> bool:
	if touch_controls != null and touch_controls.get("touch_enabled") != null:
		return bool(touch_controls.get("touch_enabled"))
	return false

func _load_cached_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _icon_cache.has(path):
		return _icon_cache[path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		_icon_cache[path] = tex
	return tex

func preload_match_assets(icon_paths: Array, portrait_paths: Array) -> void:
	for p in icon_paths:
		var s := str(p)
		if not s.is_empty():
			_load_cached_texture(s)
	if skill_banner != null and skill_banner.has_method("preload_portrait"):
		for p in portrait_paths:
			var s := str(p)
			if not s.is_empty():
				skill_banner.call("preload_portrait", s)

# ==============================================================================
# BROADCAST BOTTOM-CENTER HUD DOCK & STATUS BADGE
# ==============================================================================

func _build_status_badge_if_needed() -> void:
	status_badge = get_node_or_null("MatchStatusBadge") as PanelContainer
	if status_badge != null:
		status_badge_label = status_badge.find_child("StatusLabel", true, false) as Label
		return

	status_badge = PanelContainer.new()
	status_badge.name = "MatchStatusBadge"
	status_badge.position = STATUS_BADGE_POS
	status_badge.custom_minimum_size = STATUS_BADGE_SIZE
	status_badge.size = STATUS_BADGE_SIZE
	status_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_badge.visible = false

	var st := StyleBoxFlat.new()
	st.bg_color = THEME_RED_PRIMARY
	st.border_color = THEME_GOLD_BRIGHT
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	status_badge.add_theme_stylebox_override("panel", st)

	status_badge_label = Label.new()
	status_badge_label.name = "StatusLabel"
	status_badge_label.text = "GOL DE ORO"
	status_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_badge_label.add_theme_font_size_override("font_size", 11)
	status_badge_label.add_theme_color_override("font_color", THEME_WHITE)
	status_badge.add_child(status_badge_label)
	add_child(status_badge)

func set_status_badge(text_value: String, accent_col: Color = THEME_GOLD_BRIGHT, show_badge: bool = true) -> void:
	_build_status_badge_if_needed()
	if status_badge == null:
		return
	if not show_badge or text_value.strip_edges().is_empty():
		status_badge.visible = false
		return
	status_badge.visible = true
	if status_badge_label != null:
		status_badge_label.text = text_value
		status_badge_label.add_theme_color_override("font_color", THEME_WHITE)
	var st := status_badge.get_theme_stylebox("panel") as StyleBoxFlat
	if st != null:
		st.border_color = Color(accent_col.r, accent_col.g, accent_col.b, 0.95)

func _build_bottom_hud_if_needed() -> void:
	bottom_home_card = get_node_or_null("BottomHomeCard") as PanelContainer
	if bottom_home_card == null:
		var built_home := _create_bottom_player_card("BottomHomeCard", HOME_CARD_POS, true)
		bottom_home_card = built_home["panel"]
		_home_card_refs = built_home
		add_child(bottom_home_card)

	mini_radar = get_node_or_null("MiniRadar") as Control
	if mini_radar == null:
		mini_radar = MiniRadarScript.new()
		mini_radar.name = "MiniRadar"
		mini_radar.position = RADAR_POS
		mini_radar.custom_minimum_size = RADAR_SIZE
		mini_radar.size = RADAR_SIZE
		add_child(mini_radar)

	bottom_away_card = get_node_or_null("BottomAwayCard") as PanelContainer
	if bottom_away_card == null:
		var built_away := _create_bottom_player_card("BottomAwayCard", AWAY_CARD_POS, false)
		bottom_away_card = built_away["panel"]
		_away_card_refs = built_away
		add_child(bottom_away_card)

func _create_bottom_player_card(node_name: String, pos: Vector2, is_home: bool) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.position = pos
	panel.custom_minimum_size = PLAYER_CARD_SIZE
	panel.size = PLAYER_CARD_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.96, 0.92, 0.84, 0.92)
	st.border_width_top = 2
	st.border_width_bottom = 2
	st.border_width_left = 5 if is_home else 2
	st.border_width_right = 2 if is_home else 5
	st.border_color = THEME_RED_PRIMARY if is_home else THEME_GOLD
	st.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", st)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	var icon_frame := PanelContainer.new()
	icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.custom_minimum_size = Vector2(48, 48)
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = THEME_RED_PRIMARY if is_home else THEME_RED_DARK
	icon_style.border_color = THEME_GOLD_BRIGHT
	icon_style.set_border_width_all(2)
	icon_style.set_corner_radius_all(8)
	icon_frame.add_theme_stylebox_override("panel", icon_style)

	var icon_rect := TextureRect.new()
	icon_rect.name = "IconRect"
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.custom_minimum_size = Vector2(44, 44)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_frame.add_child(icon_rect)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)

	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lbl := Label.new()
	name_lbl.name = "PlayerNameLabel"
	name_lbl.text = "JUGADOR"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", THEME_TEXT_DARK)
	top_row.add_child(name_lbl)

	var role_lbl := Label.new()
	role_lbl.name = "RoleBadge"
	role_lbl.text = "[MF]"
	role_lbl.add_theme_font_size_override("font_size", 10)
	role_lbl.add_theme_color_override("font_color", THEME_RED_PRIMARY)
	top_row.add_child(role_lbl)
	vbox.add_child(top_row)

	var status_lbl := Label.new()
	status_lbl.name = "SkillStatusLabel"
	status_lbl.text = "★ HISSATSU LISTO"
	status_lbl.clip_text = true
	status_lbl.add_theme_font_size_override("font_size", 10)
	status_lbl.add_theme_color_override("font_color", THEME_RED_DARK)
	vbox.add_child(status_lbl)

	var bar := ProgressBar.new()
	bar.name = "SkillProgressBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.custom_minimum_size = Vector2(0, 7)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.82, 0.75, 0.64, 0.95)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = THEME_RED_PRIMARY
	bar_fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(bar)

	if is_home:
		hbox.add_child(icon_frame)
		hbox.add_child(vbox)
	else:
		hbox.add_child(vbox)
		hbox.add_child(icon_frame)

	return {
		"panel": panel,
		"style": st,
		"icon": icon_rect,
		"name_lbl": name_lbl,
		"role_lbl": role_lbl,
		"status_lbl": status_lbl,
		"bar": bar,
		"bar_fill": bar_fill,
		"last_icon_path": "",
		"last_name": "",
		"last_role": "",
		"last_status": "",
		"last_status_col": Color(-1.0, -1.0, -1.0, -1.0),
		"last_fill_col": Color(-1.0, -1.0, -1.0, -1.0),
		"last_bar_q": -1
	}

func set_team_colors(home_col: Color, away_col: Color) -> void:
	home_team_color = home_col
	away_team_color = away_col
	if home_name_label != null:
		home_name_label.add_theme_color_override("font_color", home_col.lightened(0.32))
	if away_name_label != null:
		away_name_label.add_theme_color_override("font_color", away_col.lightened(0.32))
	if _home_card_refs.has("style"):
		(_home_card_refs["style"] as StyleBoxFlat).border_color = home_col
	if _away_card_refs.has("style"):
		(_away_card_refs["style"] as StyleBoxFlat).border_color = away_col

func update_bottom_hud(active_home: Node, active_away: Node, all_players: Array, ball_node: Node2D) -> void:
	_build_bottom_hud_if_needed()
	_populate_player_card(_home_card_refs, active_home, true)
	_populate_player_card(_away_card_refs, active_away, false)
	if mini_radar != null and mini_radar.has_method("update_radar"):
		mini_radar.call("update_radar", all_players, ball_node, home_team_color, away_team_color)

func _populate_player_card(refs: Dictionary, p_node: Node, is_home: bool) -> void:
	if refs.is_empty() or not is_instance_valid(p_node):
		return
	var p_name: String = str(p_node.get("player_name")) if p_node.get("player_name") != null else "JUGADOR"
	var p_role: String = str(p_node.get("role")) if p_node.get("role") != null else "MF"
	var ab_name: String = str(p_node.get("ability_name")) if p_node.get("ability_name") != null else "HISSATSU"
	var cd: float = float(p_node.get("ability_cooldown")) if p_node.get("ability_cooldown") != null else 0.0
	var max_cd: float = maxf(0.1, float(p_node.get("ability_max_cooldown")) if p_node.get("ability_max_cooldown") != null else 8.0)
	var is_charging: bool = (true if p_node.get("is_charging_action") else false) and (true if p_node.get("has_ball") else false)
	var charge_t: float = float(p_node.get("pass_press_time")) if p_node.get("pass_press_time") != null else 0.0

	var icon_path: String = str(p_node.get("icon_path")) if p_node.get("icon_path") != null else ""
	if icon_path.is_empty() and p_node.get("portrait_path") != null:
		icon_path = str(p_node.get("portrait_path"))

	var name_lbl := refs["name_lbl"] as Label
	var role_lbl := refs["role_lbl"] as Label
	var status_lbl := refs["status_lbl"] as Label
	var bar := refs["bar"] as ProgressBar
	var bar_fill := refs["bar_fill"] as StyleBoxFlat
	var icon_rect := refs["icon"] as TextureRect

	var upper_name := p_name.to_upper()
	if refs["last_name"] != upper_name:
		refs["last_name"] = upper_name
		name_lbl.text = upper_name

	var role_txt := "[%s]" % p_role.to_upper()
	if refs["last_role"] != role_txt:
		refs["last_role"] = role_txt
		role_lbl.text = role_txt

	if refs["last_icon_path"] != icon_path:
		refs["last_icon_path"] = icon_path
		icon_rect.texture = _load_cached_texture(icon_path)

	var bar_val: float = 100.0
	var fill_col: Color = THEME_GOLD
	var status_txt: String = ""
	var status_col: Color = THEME_TEXT_DARK

	if is_home and is_charging:
		var pct: float = clampf(charge_t / 0.60, 0.0, 1.0)
		var pct_int: int = int(round(pct * 100.0))
		bar_val = float(pct_int)
		fill_col = THEME_RED_PRIMARY
		status_txt = "⚡ CARGANDO TIRO (%d%%)" % pct_int
		status_col = THEME_RED_PRIMARY
	elif cd <= 0.01:
		bar_val = 100.0
		fill_col = THEME_GOLD if is_home else THEME_RED_PRIMARY
		status_txt = "★ %s" % ab_name.to_upper()
		status_col = THEME_RED_DARK if is_home else THEME_TEXT_DARK
	else:
		var ready_pct: float = clampf(1.0 - (cd / max_cd), 0.0, 1.0)
		bar_val = ready_pct * 100.0
		fill_col = Color(0.68, 0.45, 0.22, 0.90)
		var cd_tenths: float = round(cd * 10.0) * 0.1
		status_txt = "%s · %.1fs" % [ab_name, cd_tenths]
		status_col = THEME_TEXT_MUTED

	var bar_q: int = int(round(bar_val * 2.0))
	if refs["last_bar_q"] != bar_q:
		refs["last_bar_q"] = bar_q
		bar.value = bar_val
	if refs["last_fill_col"] != fill_col:
		refs["last_fill_col"] = fill_col
		bar_fill.bg_color = fill_col
	if refs["last_status"] != status_txt:
		refs["last_status"] = status_txt
		status_lbl.text = status_txt
	if refs["last_status_col"] != status_col:
		refs["last_status_col"] = status_col
		status_lbl.add_theme_color_override("font_color", status_col)

# ==============================================================================
# PAUSE MENU OVERLAY (BEIGE / CRIMSON RED / WHITE / ROYAL GOLD)
# ==============================================================================

func _build_pause_menu_if_needed() -> void:
	pause_layer = get_node_or_null("PauseMenu") as Control
	if pause_layer != null:
		return

	pause_layer = Control.new()
	pause_layer.name = "PauseMenu"
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.visible = false
	add_child(pause_layer)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = THEME_BACKDROP
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(340, 68)
	panel.size = Vector2(600, 584)
	var st := StyleBoxFlat.new()
	st.bg_color = THEME_BG_CREAM
	st.border_color = THEME_GOLD
	st.set_border_width_all(3)
	st.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel", st)
	pause_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header_panel := PanelContainer.new()
	var hst := StyleBoxFlat.new()
	hst.bg_color = THEME_RED_PRIMARY
	hst.border_color = THEME_GOLD_BRIGHT
	hst.set_border_width_all(2)
	hst.set_corner_radius_all(10)
	hst.content_margin_top = 8
	hst.content_margin_bottom = 8
	header_panel.add_theme_stylebox_override("panel", hst)
	vbox.add_child(header_panel)

	var title := Label.new()
	title.text = "⚽ PAUSA TÁCTICA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", THEME_WHITE)
	header_panel.add_child(title)

	var controls_card := PanelContainer.new()
	var cst := StyleBoxFlat.new()
	cst.bg_color = THEME_BG_CARD
	cst.border_color = THEME_GOLD
	cst.set_border_width_all(1)
	cst.set_corner_radius_all(10)
	cst.content_margin_left = 14
	cst.content_margin_right = 14
	cst.content_margin_top = 10
	cst.content_margin_bottom = 10
	controls_card.add_theme_stylebox_override("panel", cst)
	vbox.add_child(controls_card)

	var controls_box := Label.new()
	controls_box.text = "GUÍA TÁCTIL MOBILE:\n• Joystick Izquierdo: Mover jugador (inclinar al máximo activa ⚡ SPRINT)\n• Botón Rojo Principal: Mantener para cargar TIRO potente\n• Arco Táctil Derecho: PASE rápido, BARRIDA, CAMBIAR jugador y ★ HISSATSU\n• Toque en Cancha: Toca un compañero para pasar o el arco rival para tirar"
	controls_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_box.add_theme_font_size_override("font_size", 12)
	controls_box.add_theme_color_override("font_color", THEME_TEXT_DARK)
	controls_card.add_child(controls_box)

	var btn_resume := _make_arcade_button("▶ REANUDAR PARTIDO", true)
	btn_resume.custom_minimum_size = Vector2(0, 48)
	btn_resume.pressed.connect(func(): pause_action_requested.emit("resume"))
	vbox.add_child(btn_resume)

	var btn_restart := _make_arcade_button("↻ REINICIAR PARTIDO", false)
	btn_restart.custom_minimum_size = Vector2(0, 44)
	btn_restart.pressed.connect(func(): pause_action_requested.emit("restart"))
	vbox.add_child(btn_restart)

	var btn_touch := _make_arcade_button("CONTROLES TÁCTILES: ON", false)
	btn_touch.custom_minimum_size = Vector2(0, 44)
	btn_touch.pressed.connect(func(): pause_action_requested.emit("toggle_touch"))
	vbox.add_child(btn_touch)

	var audio_row := HBoxContainer.new()
	audio_row.add_theme_constant_override("separation", 12)
	var btn_sfx := _make_arcade_button("SFX: ON", false)
	btn_sfx.custom_minimum_size = Vector2(0, 44)
	btn_sfx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_sfx.pressed.connect(func(): pause_action_requested.emit("toggle_sfx"))
	var btn_music := _make_arcade_button("MÚSICA: ON", false)
	btn_music.custom_minimum_size = Vector2(0, 44)
	btn_music.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_music.pressed.connect(func(): pause_action_requested.emit("toggle_music"))
	audio_row.add_child(btn_sfx)
	audio_row.add_child(btn_music)
	vbox.add_child(audio_row)

	var btn_menu := _make_arcade_button("🏠 VOLVER AL MENÚ PRINCIPAL", false)
	btn_menu.custom_minimum_size = Vector2(0, 46)
	btn_menu.pressed.connect(func(): pause_action_requested.emit("main_menu"))
	vbox.add_child(btn_menu)

	_pause_refs = {
		"resume": btn_resume,
		"touch": btn_touch,
		"sfx": btn_sfx,
		"music": btn_music
	}

func set_pause_menu_visible(show_pause: bool, state: Dictionary = {}) -> void:
	_build_pause_menu_if_needed()
	if pause_layer == null:
		return
	pause_layer.visible = show_pause
	if show_pause:
		pause_layer.move_to_front()
		if _pause_refs.has("touch"):
			(_pause_refs["touch"] as Button).text = "CONTROLES TÁCTILES: %s" % ("ON" if bool(state.get("touch_enabled", false)) else "OFF")
		if _pause_refs.has("sfx"):
			(_pause_refs["sfx"] as Button).text = "EFECTOS SFX: %s" % ("ON" if bool(state.get("sfx_enabled", true)) else "OFF")
		if _pause_refs.has("music"):
			(_pause_refs["music"] as Button).text = "MÚSICA ARCADE: %s" % ("ON" if bool(state.get("music_enabled", true)) else "OFF")
		var resume_btn := _pause_refs.get("resume") as Button
		if is_instance_valid(resume_btn) and resume_btn.is_inside_tree():
			resume_btn.grab_focus()
	_sync_touch_menu_block()

func _make_arcade_button(caption: String, primary: bool = false) -> Button:
	var btn := Button.new()
	btn.text = caption
	btn.custom_minimum_size = Vector2(0, 44)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", 15)

	var st := StyleBoxFlat.new()
	var hover_st := StyleBoxFlat.new()
	var pressed_st := StyleBoxFlat.new()

	if primary:
		st.bg_color = THEME_RED_PRIMARY
		st.border_color = THEME_GOLD_BRIGHT
		st.set_border_width_all(2)
		hover_st.bg_color = THEME_RED_BRIGHT
		hover_st.border_color = THEME_WHITE
		hover_st.set_border_width_all(2)
		pressed_st.bg_color = THEME_RED_DARK
		pressed_st.border_color = THEME_GOLD_BRIGHT
		pressed_st.set_border_width_all(3)
		btn.add_theme_color_override("font_color", THEME_WHITE)
		btn.add_theme_color_override("font_hover_color", THEME_WHITE)
		btn.add_theme_color_override("font_pressed_color", THEME_GOLD_BRIGHT)
		btn.add_theme_color_override("font_focus_color", THEME_WHITE)
	else:
		st.bg_color = THEME_BG_CARD
		st.border_color = THEME_GOLD
		st.set_border_width_all(2)
		hover_st.bg_color = THEME_WHITE
		hover_st.border_color = THEME_RED_PRIMARY
		hover_st.set_border_width_all(2)
		pressed_st.bg_color = THEME_BG_BEIGE_SUB
		pressed_st.border_color = THEME_RED_PRIMARY
		pressed_st.set_border_width_all(2)
		btn.add_theme_color_override("font_color", THEME_TEXT_DARK)
		btn.add_theme_color_override("font_hover_color", THEME_RED_PRIMARY)
		btn.add_theme_color_override("font_pressed_color", THEME_RED_DARK)
		btn.add_theme_color_override("font_focus_color", THEME_TEXT_DARK)

	st.set_corner_radius_all(10)
	hover_st.set_corner_radius_all(10)
	pressed_st.set_corner_radius_all(10)

	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", hover_st)
	btn.add_theme_stylebox_override("pressed", pressed_st)
	btn.add_theme_stylebox_override("focus", hover_st)
	return btn

# ==============================================================================
# MAIN MENU: TOUCH-GRID TEAM SELECTOR (BEIGE / CRIMSON RED / WHITE / GOLD)
# ==============================================================================

func show_match_setup(teams: Array[Dictionary], tournament_info: Dictionary = {}) -> void:
	hide_match_result()
	set_pause_menu_visible(false)
	if is_instance_valid(menu_layer):
		menu_layer.queue_free()
		menu_layer = null

	menu_layer = Control.new()
	menu_layer.name = "MatchSetup"
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(menu_layer)
	menu_layer.move_to_front()

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = THEME_BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.position = Vector2(80, 22)
	panel.size = Vector2(1120, 676)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = THEME_BG_CREAM
	panel_style.border_color = THEME_GOLD
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(20)
	panel.add_theme_stylebox_override("panel", panel_style)
	menu_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	# Championship Crimson & Gold Banner Header
	var header_bar := PanelContainer.new()
	var h_style := StyleBoxFlat.new()
	h_style.bg_color = THEME_RED_PRIMARY
	h_style.border_color = THEME_GOLD_BRIGHT
	h_style.set_border_width_all(2)
	h_style.set_corner_radius_all(12)
	h_style.content_margin_top = 6
	h_style.content_margin_bottom = 6
	header_bar.add_theme_stylebox_override("panel", h_style)
	content.add_child(header_bar)

	var title := Label.new()
	title.text = "⚽ INAZUMA ARCADE MOBILE  •  EDICIÓN CAMPEONATO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", THEME_WHITE)
	title.add_theme_font_size_override("font_size", 22)
	header_bar.add_child(title)

	# Mode switcher tabs
	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 16)
	content.add_child(tab_row)

	var btn_tab_tour := _make_arcade_button("🏆 COPA CONTINENTAL (6 RONDAS)", true)
	btn_tab_tour.custom_minimum_size = Vector2(440, 44)
	var btn_tab_quick := _make_arcade_button("⚡ PARTIDO RÁPIDO (5v5)", false)
	btn_tab_quick.custom_minimum_size = Vector2(440, 44)
	tab_row.add_child(btn_tab_tour)
	tab_row.add_child(btn_tab_quick)

	var tour_container := VBoxContainer.new()
	tour_container.name = "TournamentTab"
	tour_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tour_container.add_theme_constant_override("separation", 10)
	content.add_child(tour_container)

	var quick_container := VBoxContainer.new()
	quick_container.name = "QuickMatchTab"
	quick_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quick_container.add_theme_constant_override("separation", 10)
	quick_container.visible = false
	content.add_child(quick_container)

	_populate_tournament_tab(tour_container, teams, tournament_info)
	_populate_quick_match_tab(quick_container, teams)

	var default_tour: bool = bool(tournament_info.get("prefer_tournament", not tournament_info.is_empty()))
	tour_container.visible = default_tour
	quick_container.visible = not default_tour
	_style_mode_tabs(btn_tab_tour, btn_tab_quick, default_tour)

	btn_tab_tour.pressed.connect(func():
		tour_container.visible = true
		quick_container.visible = false
		_style_mode_tabs(btn_tab_tour, btn_tab_quick, true)
	)
	btn_tab_quick.pressed.connect(func():
		tour_container.visible = false
		quick_container.visible = true
		_style_mode_tabs(btn_tab_tour, btn_tab_quick, false)
	)

	_sync_touch_menu_block()

func _style_mode_tabs(tour_btn: Button, quick_btn: Button, tour_active: bool) -> void:
	var active_st := StyleBoxFlat.new()
	active_st.bg_color = THEME_RED_PRIMARY
	active_st.border_color = THEME_GOLD_BRIGHT
	active_st.set_border_width_all(2)
	active_st.set_corner_radius_all(10)

	var idle_st := StyleBoxFlat.new()
	idle_st.bg_color = THEME_BG_CARD
	idle_st.border_color = THEME_GOLD
	idle_st.set_border_width_all(2)
	idle_st.set_corner_radius_all(10)

	tour_btn.add_theme_stylebox_override("normal", active_st if tour_active else idle_st)
	tour_btn.add_theme_stylebox_override("hover", active_st if tour_active else idle_st)
	tour_btn.add_theme_color_override("font_color", THEME_WHITE if tour_active else THEME_TEXT_DARK)
	tour_btn.add_theme_color_override("font_hover_color", THEME_WHITE if tour_active else THEME_RED_PRIMARY)

	quick_btn.add_theme_stylebox_override("normal", idle_st if tour_active else active_st)
	quick_btn.add_theme_stylebox_override("hover", idle_st if tour_active else active_st)
	quick_btn.add_theme_color_override("font_color", THEME_TEXT_DARK if tour_active else THEME_WHITE)
	quick_btn.add_theme_color_override("font_hover_color", THEME_RED_PRIMARY if tour_active else THEME_WHITE)

func _populate_tournament_tab(container: VBoxContainer, teams: Array[Dictionary], info: Dictionary) -> void:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	container.add_child(body)

	var saved_team: int = clampi(int(info.get("saved_team_index", 4)), 0, maxi(0, teams.size() - 1))

	# Left column: Direct Touch Team Grid (3x2) + Team Details
	var left_col := _create_touch_team_grid_selector("ELIGE TU EQUIPO (TOCA UNA TARJETA)", teams, saved_team, false)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 1.45
	tournament_team_picker = left_col.get_meta("picker") as OptionButton
	body.add_child(left_col)

	# Right column: 6-Round Bracket progression
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	var rp_st := StyleBoxFlat.new()
	rp_st.bg_color = THEME_BG_CARD
	rp_st.border_color = THEME_GOLD
	rp_st.set_border_width_all(2)
	rp_st.set_corner_radius_all(12)
	rp_st.content_margin_left = 14
	rp_st.content_margin_right = 14
	rp_st.content_margin_top = 12
	rp_st.content_margin_bottom = 12
	right_panel.add_theme_stylebox_override("panel", rp_st)
	body.add_child(right_panel)

	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 6)
	right_panel.add_child(right_col)

	var cup_lbl := Label.new()
	cup_lbl.text = str(info.get("title", "CAMINO A LA COPA  •  60s O 3 GOLES")).to_upper()
	cup_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cup_lbl.add_theme_font_size_override("font_size", 13)
	cup_lbl.add_theme_color_override("font_color", THEME_RED_PRIMARY)
	right_col.add_child(cup_lbl)

	var rounds: Array = info.get("rounds", [])
	var cur_round: int = int(info.get("saved_round_index", 0))
	var has_save: bool = bool(info.get("has_save", false))
	var completed: bool = bool(info.get("completed", false))

	for i in range(rounds.size()):
		var r: Dictionary = rounds[i]
		var row_panel := PanelContainer.new()
		row_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var rst := StyleBoxFlat.new()
		var is_current: bool = (i == cur_round and not completed)
		var is_done: bool = completed or (i < cur_round)
		if is_current:
			rst.bg_color = THEME_RED_PRIMARY
			rst.border_color = THEME_GOLD_BRIGHT
			rst.set_border_width_all(2)
		elif is_done:
			rst.bg_color = Color(0.92, 0.88, 0.76, 0.95)
			rst.border_color = THEME_GOLD
			rst.set_border_width_all(1)
		else:
			rst.bg_color = THEME_BG_CREAM
			rst.border_color = Color(0.82, 0.74, 0.62, 0.85)
			rst.set_border_width_all(1)
		rst.set_corner_radius_all(8)
		rst.content_margin_left = 10
		rst.content_margin_right = 10
		rst.content_margin_top = 4
		rst.content_margin_bottom = 4
		row_panel.add_theme_stylebox_override("panel", rst)

		var rl := Label.new()
		var badge := "✓ " if is_done else ("▶ " if is_current else "• ")
		var opp_name: String = str(r.get("opponent_label", r.get("opponent_team", "Rival")))
		rl.text = "%sRonda %d · %s — vs %s" % [badge, i + 1, str(r.get("name", "Fase")), opp_name]
		rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rl.add_theme_font_size_override("font_size", 12)
		rl.add_theme_color_override("font_color", THEME_WHITE if is_current else (THEME_RED_DARK if is_done else THEME_TEXT_DARK))
		row_panel.add_child(rl)
		right_col.add_child(row_panel)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	container.add_child(btn_row)

	if has_save and not completed and cur_round > 0:
		var btn_cont := _make_arcade_button("▶ CONTINUAR RONDA %d" % (cur_round + 1), true)
		btn_cont.custom_minimum_size = Vector2(0, 52)
		btn_cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_cont.pressed.connect(func():
			var t_idx: int = tournament_team_picker.selected if is_instance_valid(tournament_team_picker) else saved_team
			_close_menu_layer()
			tournament_round_requested.emit(t_idx, cur_round, false)
		)
		btn_row.add_child(btn_cont)

		var btn_new := _make_arcade_button("↻ NUEVO TORNEO DESDE RONDA 1", false)
		btn_new.custom_minimum_size = Vector2(0, 52)
		btn_new.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_new.pressed.connect(func():
			var t_idx: int = tournament_team_picker.selected if is_instance_valid(tournament_team_picker) else 0
			_close_menu_layer()
			tournament_round_requested.emit(t_idx, 0, true)
		)
		btn_row.add_child(btn_new)
	else:
		var btn_start_tour := _make_arcade_button("🏆 INICIAR TORNEO CONTINENTAL (RONDA 1)", true)
		btn_start_tour.custom_minimum_size = Vector2(0, 52)
		btn_start_tour.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_start_tour.pressed.connect(func():
			var t_idx: int = tournament_team_picker.selected if is_instance_valid(tournament_team_picker) else 0
			_close_menu_layer()
			tournament_round_requested.emit(t_idx, 0, true)
		)
		btn_row.add_child(btn_start_tour)

func _populate_quick_match_tab(container: VBoxContainer, teams: Array[Dictionary]) -> void:
	var selectors := HBoxContainer.new()
	selectors.alignment = BoxContainer.ALIGNMENT_CENTER
	selectors.size_flags_vertical = Control.SIZE_EXPAND_FILL
	selectors.add_theme_constant_override("separation", 18)
	container.add_child(selectors)

	var def_home: int = 4 if teams.size() > 4 else 0
	var def_away: int = 2 if teams.size() > 2 else maxi(0, teams.size() - 1)

	var home_picker_box := _create_touch_team_grid_selector("🚩 TU EQUIPO (LOCAL)", teams, def_home, true)
	var away_picker_box := _create_touch_team_grid_selector("⚔️ EQUIPO RIVAL (CPU)", teams, def_away, true)
	home_picker_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	away_picker_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	home_team_picker = home_picker_box.get_meta("picker") as OptionButton
	away_team_picker = away_picker_box.get_meta("picker") as OptionButton
	selectors.add_child(home_picker_box)
	selectors.add_child(away_picker_box)

	var bottom_bar := HBoxContainer.new()
	bottom_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_bar.add_theme_constant_override("separation", 14)
	container.add_child(bottom_bar)

	var dur_lbl := Label.new()
	dur_lbl.text = "TIEMPO:"
	dur_lbl.add_theme_font_size_override("font_size", 14)
	dur_lbl.add_theme_color_override("font_color", THEME_RED_PRIMARY)
	bottom_bar.add_child(dur_lbl)

	var dur_buttons: Array[Button] = []
	var durations: Array[Dictionary] = [
		{"sec": 60.0, "label": "60s RELÁMPAGO"},
		{"sec": 90.0, "label": "90s ARCADE"},
		{"sec": 180.0, "label": "180s COMPLETO"}
	]
	for d in durations:
		var sec_val: float = float(d["sec"])
		var b := _make_arcade_button(str(d["label"]), is_equal_approx(sec_val, selected_quick_duration))
		b.custom_minimum_size = Vector2(145, 48)
		b.set_meta("sec", sec_val)
		b.pressed.connect(func():
			selected_quick_duration = sec_val
			for other in dur_buttons:
				var active: bool = is_equal_approx(float(other.get_meta("sec")), selected_quick_duration)
				_style_single_toggle(other, active)
		)
		dur_buttons.append(b)
		bottom_bar.add_child(b)

	var start := _make_arcade_button("⚡ ¡JUGAR PARTIDO RÁPIDO!", true)
	start.custom_minimum_size = Vector2(320, 50)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(_on_start_match_pressed)
	bottom_bar.add_child(start)

func _style_single_toggle(btn: Button, active: bool) -> void:
	var st := StyleBoxFlat.new()
	st.set_corner_radius_all(10)
	if active:
		st.bg_color = THEME_RED_PRIMARY
		st.border_color = THEME_GOLD_BRIGHT
		st.set_border_width_all(2)
		btn.add_theme_color_override("font_color", THEME_WHITE)
		btn.add_theme_color_override("font_hover_color", THEME_WHITE)
	else:
		st.bg_color = THEME_BG_CARD
		st.border_color = THEME_GOLD
		st.set_border_width_all(2)
		btn.add_theme_color_override("font_color", THEME_TEXT_DARK)
		btn.add_theme_color_override("font_hover_color", THEME_RED_PRIMARY)
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", st)

func _create_touch_team_grid_selector(caption: String, teams: Array[Dictionary], default_idx: int, compact: bool) -> VBoxContainer:
	var dense: bool = teams.size() > 6
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6 if dense else 8)

	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", THEME_RED_PRIMARY)
	label.add_theme_font_size_override("font_size", 14)
	box.add_child(label)

	# Keep hidden OptionButton synced for backwards API compatibility
	var picker := OptionButton.new()
	picker.visible = false
	for team in teams:
		picker.add_item(str(team.get("name", "Equipo")))
	box.add_child(picker)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6 if dense else 8)
	box.add_child(grid)

	# Selected Team Info Card below the Grid
	var preview_card := PanelContainer.new()
	var pst := StyleBoxFlat.new()
	pst.bg_color = THEME_BG_CARD
	pst.border_color = THEME_GOLD
	pst.set_border_width_all(2)
	pst.set_corner_radius_all(10)
	pst.content_margin_left = 10
	pst.content_margin_right = 10
	pst.content_margin_top = 5 if dense else 6
	pst.content_margin_bottom = 5 if dense else 6
	preview_card.add_theme_stylebox_override("panel", pst)
	box.add_child(preview_card)

	var card_hbox := HBoxContainer.new()
	card_hbox.add_theme_constant_override("separation", 10)
	preview_card.add_child(card_hbox)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = (Vector2(48, 48) if compact else Vector2(56, 56)) if dense else (Vector2(54, 54) if compact else Vector2(64, 64))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_hbox.add_child(portrait)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	info_vbox.add_theme_constant_override("separation", 2)
	card_hbox.add_child(info_vbox)

	var desc_lbl := Label.new()
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", THEME_RED_PRIMARY)
	info_vbox.add_child(desc_lbl)

	var roster := Label.new()
	roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster.add_theme_color_override("font_color", THEME_TEXT_DARK)
	roster.add_theme_font_size_override("font_size", 11)
	info_vbox.add_child(roster)

	var card_min_size: Vector2
	var port_min_size: Vector2
	if dense:
		card_min_size = Vector2(142, 68) if compact else Vector2(166, 74)
		port_min_size = Vector2(30, 30) if compact else Vector2(34, 34)
	else:
		card_min_size = Vector2(148, 86) if compact else Vector2(172, 102)
		port_min_size = Vector2(36, 36) if compact else Vector2(42, 42)

	var sel_st := StyleBoxFlat.new()
	sel_st.set_corner_radius_all(10)
	sel_st.bg_color = THEME_RED_PRIMARY
	sel_st.border_color = THEME_GOLD_BRIGHT
	sel_st.set_border_width_all(3)
	var sel_hover_st := sel_st.duplicate() as StyleBoxFlat
	sel_hover_st.border_color = THEME_GOLD_BRIGHT

	var idle_st := StyleBoxFlat.new()
	idle_st.set_corner_radius_all(10)
	idle_st.bg_color = THEME_BG_CARD
	idle_st.border_color = THEME_GOLD
	idle_st.set_border_width_all(2)
	var idle_hover_st := idle_st.duplicate() as StyleBoxFlat
	idle_hover_st.border_color = THEME_RED_PRIMARY

	var card_buttons: Array[Button] = []
	for i in range(teams.size()):
		var t: Dictionary = teams[i]
		var card_btn := Button.new()
		card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_btn.custom_minimum_size = card_min_size
		card_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		card_btn.set_meta("team_idx", i)
		card_btn.set_meta("sel_st", sel_st)
		card_btn.set_meta("sel_hover_st", sel_hover_st)
		card_btn.set_meta("idle_st", idle_st)
		card_btn.set_meta("idle_hover_st", idle_hover_st)

		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 6 if dense else 8)
		margin.add_theme_constant_override("margin_right", 6 if dense else 8)
		margin.add_theme_constant_override("margin_top", 4 if dense else 6)
		margin.add_theme_constant_override("margin_bottom", 4 if dense else 6)
		card_btn.add_child(margin)

		var vb := VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 2 if dense else 4)
		margin.add_child(vb)

		var top_hb := HBoxContainer.new()
		top_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_hb.alignment = BoxContainer.ALIGNMENT_CENTER
		top_hb.add_theme_constant_override("separation", 6)
		vb.add_child(top_hb)

		var mini_port := TextureRect.new()
		mini_port.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mini_port.custom_minimum_size = port_min_size
		mini_port.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mini_port.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mini_port.texture = _load_cached_texture(str(t.get("star_portrait", "")))
		top_hb.add_child(mini_port)

		var badge_vb := VBoxContainer.new()
		badge_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge_vb.alignment = BoxContainer.ALIGNMENT_CENTER
		top_hb.add_child(badge_vb)

		var color_swatch := ColorRect.new()
		color_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		color_swatch.custom_minimum_size = Vector2(26, 8) if dense else Vector2(28, 10)
		color_swatch.color = Color.from_string(str(t.get("color", "#EF4444")), THEME_RED_PRIMARY)
		badge_vb.add_child(color_swatch)

		var lvl_lbl := Label.new()
		lvl_lbl.name = "LevelLabel"
		lvl_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lvl_lbl.text = "★ Nv.%d" % int(t.get("level", i + 1))
		lvl_lbl.add_theme_font_size_override("font_size", 10)
		badge_vb.add_child(lvl_lbl)

		var t_name_lbl := Label.new()
		t_name_lbl.name = "TeamNameLabel"
		t_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t_name_lbl.text = str(t.get("name", "Equipo"))
		t_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t_name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t_name_lbl.add_theme_font_size_override("font_size", (10 if compact else 11) if dense else (11 if compact else 12))
		vb.add_child(t_name_lbl)

		card_btn.set_meta("name_lbl", t_name_lbl)
		card_btn.set_meta("lvl_lbl", lvl_lbl)

		var idx_capture: int = i
		card_btn.pressed.connect(func():
			picker.select(idx_capture)
			_on_team_picker_changed(idx_capture, picker)
			_style_team_grid_cards(card_buttons, idx_capture)
		)
		card_buttons.append(card_btn)
		grid.add_child(card_btn)

	box.set_meta("picker", picker)
	picker.set_meta("teams", teams)
	picker.set_meta("roster_label", roster)
	picker.set_meta("desc_label", desc_lbl)
	picker.set_meta("portrait_rect", portrait)
	picker.set_meta("card_style", pst)
	picker.set_meta("card_buttons", card_buttons)
	picker.item_selected.connect(func(idx: int):
		_on_team_picker_changed(idx, picker)
		_style_team_grid_cards(card_buttons, idx)
	)

	var initial_idx: int = clampi(default_idx, 0, maxi(0, teams.size() - 1))
	if not teams.is_empty():
		picker.select(initial_idx)
		_on_team_picker_changed(initial_idx, picker)
		_style_team_grid_cards(card_buttons, initial_idx)
	return box

func _style_team_grid_cards(card_buttons: Array[Button], selected_idx: int) -> void:
	for i in range(card_buttons.size()):
		var btn := card_buttons[i]
		if not is_instance_valid(btn):
			continue
		var is_sel: bool = (i == selected_idx)
		var st: StyleBoxFlat = btn.get_meta("sel_st", null) if is_sel else btn.get_meta("idle_st", null)
		var hover_st: StyleBoxFlat = btn.get_meta("sel_hover_st", null) if is_sel else btn.get_meta("idle_hover_st", null)
		if st == null:
			st = StyleBoxFlat.new()
			st.set_corner_radius_all(10)
			st.bg_color = THEME_RED_PRIMARY if is_sel else THEME_BG_CARD
			st.border_color = THEME_GOLD_BRIGHT if is_sel else THEME_GOLD
			st.set_border_width_all(3 if is_sel else 2)
			hover_st = st.duplicate() as StyleBoxFlat
			hover_st.border_color = THEME_GOLD_BRIGHT if is_sel else THEME_RED_PRIMARY
		btn.add_theme_stylebox_override("normal", st)
		btn.add_theme_stylebox_override("hover", hover_st)
		btn.add_theme_stylebox_override("pressed", st)
		btn.add_theme_stylebox_override("focus", hover_st)

		var name_lbl: Label = btn.get_meta("name_lbl", null) as Label
		if name_lbl == null:
			name_lbl = btn.find_child("TeamNameLabel", true, false) as Label
		if name_lbl != null:
			name_lbl.add_theme_color_override("font_color", THEME_WHITE if is_sel else THEME_TEXT_DARK)
		var lvl_lbl: Label = btn.get_meta("lvl_lbl", null) as Label
		if lvl_lbl == null:
			lvl_lbl = btn.find_child("LevelLabel", true, false) as Label
		if lvl_lbl != null:
			lvl_lbl.add_theme_color_override("font_color", THEME_GOLD_BRIGHT if is_sel else THEME_RED_PRIMARY)

func _on_team_picker_changed(index: int, picker: OptionButton) -> void:
	var teams: Array = picker.get_meta("teams", [])
	var roster := picker.get_meta("roster_label") as Label
	var desc_lbl := picker.get_meta("desc_label") as Label
	var portrait := picker.get_meta("portrait_rect") as TextureRect
	var pst := picker.get_meta("card_style") as StyleBoxFlat
	if index >= 0 and index < teams.size():
		var t: Dictionary = teams[index]
		if is_instance_valid(roster):
			var players_arr: Array = t.get("players", [])
			roster.text = "Plantilla: " + " • ".join(players_arr)
		if is_instance_valid(desc_lbl):
			desc_lbl.text = "%s — %s" % [str(t.get("name", "Equipo")).to_upper(), str(t.get("description", ""))]
		if pst != null:
			pst.border_color = THEME_RED_PRIMARY
		if is_instance_valid(portrait):
			var p_path: String = str(t.get("star_portrait", ""))
			var tex := _load_cached_texture(p_path)
			portrait.texture = tex
			portrait.visible = (tex != null)

func _close_menu_layer() -> void:
	if is_instance_valid(menu_layer):
		menu_layer.visible = false
		menu_layer.queue_free()
		menu_layer = null
	_sync_touch_menu_block()

func _on_start_match_pressed() -> void:
	if not is_instance_valid(home_team_picker) or not is_instance_valid(away_team_picker):
		return
	var h_idx: int = home_team_picker.selected
	var a_idx: int = away_team_picker.selected
	if h_idx == a_idx and away_team_picker.item_count > 1:
		a_idx = (a_idx + 1) % away_team_picker.item_count
		away_team_picker.select(a_idx)
	_close_menu_layer()
	emit_signal("quick_match_requested", h_idx, a_idx, selected_quick_duration)
	emit_signal("match_start_requested", h_idx, a_idx)

# ==============================================================================
# POST-MATCH RESULT OVERLAY (BEIGE / CRIMSON RED / WHITE / ROYAL GOLD)
# ==============================================================================

func hide_match_result() -> void:
	if is_instance_valid(result_layer):
		result_layer.visible = false
		result_layer.queue_free()
		result_layer = null
	_sync_touch_menu_block()

func show_match_result(info: Dictionary) -> void:
	hide_match_result()
	result_layer = Control.new()
	result_layer.name = "MatchResultOverlay"
	result_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(result_layer)
	result_layer.move_to_front()

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = THEME_BACKDROP
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(290, 120)
	panel.size = Vector2(700, 480)
	var st := StyleBoxFlat.new()
	var user_won: bool = bool(info.get("user_won", true))
	st.bg_color = THEME_BG_CREAM
	st.border_color = THEME_GOLD_BRIGHT if user_won else THEME_RED_PRIMARY
	st.set_border_width_all(3)
	st.set_corner_radius_all(20)
	panel.add_theme_stylebox_override("panel", st)
	result_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var banner_panel := PanelContainer.new()
	var bst := StyleBoxFlat.new()
	bst.bg_color = THEME_RED_PRIMARY if user_won else THEME_RED_DARK
	bst.border_color = THEME_GOLD_BRIGHT
	bst.set_border_width_all(2)
	bst.set_corner_radius_all(12)
	bst.content_margin_top = 10
	bst.content_margin_bottom = 10
	banner_panel.add_theme_stylebox_override("panel", bst)
	vbox.add_child(banner_panel)

	var headline := Label.new()
	headline.text = str(info.get("headline", "FINAL DEL PARTIDO"))
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_font_size_override("font_size", 28)
	headline.add_theme_color_override("font_color", THEME_WHITE)
	banner_panel.add_child(headline)

	var score_card := PanelContainer.new()
	var sc_st := StyleBoxFlat.new()
	sc_st.bg_color = THEME_BG_CARD
	sc_st.border_color = THEME_GOLD
	sc_st.set_border_width_all(2)
	sc_st.set_corner_radius_all(10)
	sc_st.content_margin_top = 10
	sc_st.content_margin_bottom = 10
	score_card.add_theme_stylebox_override("panel", sc_st)
	vbox.add_child(score_card)

	var score_line := Label.new()
	score_line.text = "%s   %d  —  %d   %s" % [
		str(info.get("home_name", home_team_name)),
		int(info.get("home_score", home_score)),
		int(info.get("away_score", away_score)),
		str(info.get("away_name", away_team_name))
	]
	score_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_line.add_theme_font_size_override("font_size", 24)
	score_line.add_theme_color_override("font_color", THEME_TEXT_DARK)
	score_card.add_child(score_line)

	var sub := Label.new()
	sub.text = str(info.get("subtitle", ""))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", THEME_RED_PRIMARY)
	vbox.add_child(sub)

	var is_tournament: bool = bool(info.get("is_tournament", false))
	var is_champion: bool = bool(info.get("is_champion", false))

	var primary_btn: Button = null
	if is_tournament:
		if is_champion:
			primary_btn = _make_arcade_button("🏆 JUGAR NUEVO TORNEO", true)
			primary_btn.pressed.connect(func():
				hide_match_result()
				result_action_requested.emit("new_tournament")
			, CONNECT_DEFERRED)
		elif user_won:
			primary_btn = _make_arcade_button("▶ AVANZAR A SIGUIENTE RONDA", true)
			primary_btn.pressed.connect(func():
				hide_match_result()
				result_action_requested.emit("next_round")
			, CONNECT_DEFERRED)
		else:
			primary_btn = _make_arcade_button("↻ REINTENTAR RONDA", true)
			primary_btn.pressed.connect(func():
				hide_match_result()
				result_action_requested.emit("retry_round")
			, CONNECT_DEFERRED)
	else:
		primary_btn = _make_arcade_button("⚡ JUGAR REVANCHA", true)
		primary_btn.pressed.connect(func():
			hide_match_result()
			result_action_requested.emit("rematch")
		, CONNECT_DEFERRED)

	primary_btn.custom_minimum_size = Vector2(0, 50)
	vbox.add_child(primary_btn)

	var menu_btn := _make_arcade_button("🏠 VOLVER AL MENÚ PRINCIPAL", false)
	menu_btn.custom_minimum_size = Vector2(0, 46)
	menu_btn.pressed.connect(func():
		hide_match_result()
		result_action_requested.emit("main_menu")
	, CONNECT_DEFERRED)
	vbox.add_child(menu_btn)

	if primary_btn.is_inside_tree():
		primary_btn.grab_focus()
	_sync_touch_menu_block()

# ==============================================================================
# SCOREBOARD & SKILL BANNER CORE (PRESERVES ALL INVARIANTS)
# ==============================================================================

func _build_ui_if_needed() -> void:
	if scoreboard_panel == null:
		var panel = PanelContainer.new()
		panel.name = "TopCenterScoreboard"
		panel.position = SCOREBOARD_POS
		panel.custom_minimum_size = SCOREBOARD_SIZE
		panel.size = SCOREBOARD_SIZE

		var style = StyleBoxFlat.new()
		style.bg_color = SCOREBOARD_BG_COLOR
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_left = 10
		style.corner_radius_bottom_right = 10
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.98, 0.82, 0.12, 0.45)
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		style.content_margin_left = 12
		style.content_margin_right = 12
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
		scoreboard_panel = panel

		var margin = MarginContainer.new()
		margin.name = "Margin"
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_top", 2)
		margin.add_theme_constant_override("margin_bottom", 2)
		panel.add_child(margin)

		var hbox = HBoxContainer.new()
		hbox.name = "HBox"
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		margin.add_child(hbox)

		var h_name = Label.new()
		h_name.name = "HomeName"
		h_name.text = home_team_name
		h_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h_name.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 1.0))
		h_name.add_theme_font_size_override("font_size", 12)
		hbox.add_child(h_name)
		home_name_label = h_name

		var spacer1 = Control.new()
		spacer1.custom_minimum_size = Vector2(6, 0)
		hbox.add_child(spacer1)

		var h_score = Label.new()
		h_score.name = "HomeScore"
		h_score.text = str(home_score)
		h_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h_score.add_theme_color_override("font_color", Color(1.0, 0.90, 0.20, 1.0))
		h_score.add_theme_font_size_override("font_size", 14)
		hbox.add_child(h_score)
		home_score_label = h_score

		var spacer_mid1 = Control.new()
		spacer_mid1.custom_minimum_size = Vector2(8, 0)
		hbox.add_child(spacer_mid1)

		var time_container = PanelContainer.new()
		time_container.name = "TimeContainer"
		var time_style = StyleBoxFlat.new()
		time_style.bg_color = Color(0.58, 0.10, 0.12, 0.92)
		time_style.corner_radius_top_left = 6
		time_style.corner_radius_top_right = 6
		time_style.corner_radius_bottom_left = 6
		time_style.corner_radius_bottom_right = 6
		time_style.content_margin_left = 6
		time_style.content_margin_right = 6
		time_style.content_margin_top = 1
		time_style.content_margin_bottom = 1
		time_container.add_theme_stylebox_override("panel", time_style)

		var time_margin = MarginContainer.new()
		time_margin.name = "TimeMargin"
		time_container.add_child(time_margin)

		var t_lbl = Label.new()
		t_lbl.name = "TimeLabel"
		t_lbl.text = "00:00"
		t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		t_lbl.add_theme_color_override("font_color", THEME_WHITE)
		t_lbl.add_theme_font_size_override("font_size", 12)
		time_margin.add_child(t_lbl)
		time_label = t_lbl

		hbox.add_child(time_container)

		var spacer_mid2 = Control.new()
		spacer_mid2.custom_minimum_size = Vector2(8, 0)
		hbox.add_child(spacer_mid2)

		var a_score = Label.new()
		a_score.name = "AwayScore"
		a_score.text = str(away_score)
		a_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		a_score.add_theme_color_override("font_color", Color(1.0, 0.90, 0.20, 1.0))
		a_score.add_theme_font_size_override("font_size", 14)
		hbox.add_child(a_score)
		away_score_label = a_score

		var spacer2 = Control.new()
		spacer2.custom_minimum_size = Vector2(6, 0)
		hbox.add_child(spacer2)

		var a_name = Label.new()
		a_name.name = "AwayName"
		a_name.text = away_team_name
		a_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		a_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		a_name.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98, 1.0))
		a_name.add_theme_font_size_override("font_size", 12)
		hbox.add_child(a_name)
		away_name_label = a_name

	if skill_banner == null:
		var banner = SkillBannerScript.new()
		banner.name = "SkillBanner"
		add_child(banner)
		skill_banner = banner

## Updates the score display for home and away teams
func set_score(home: int, away: int) -> void:
	home_score = maxi(0, home)
	away_score = maxi(0, away)
	var h_lbl := home_score_label
	if h_lbl != null and _last_home_score != home_score:
		_last_home_score = home_score
		h_lbl.text = str(home_score)
	var a_lbl := away_score_label
	if a_lbl != null and _last_away_score != away_score:
		_last_away_score = away_score
		a_lbl.text = str(away_score)

## Formats and updates the match timer in MM:SS format
func set_time(seconds: float) -> void:
	match_time_seconds = maxf(0.0, seconds)
	var total_sec: int = int(match_time_seconds)
	var t_lbl := time_label
	if t_lbl != null and _last_time_sec != total_sec:
		_last_time_sec = total_sec
		var mins: int = total_sec / 60
		var secs: int = total_sec % 60
		t_lbl.text = "%02d:%02d" % [mins, secs]

## Updates the display names of both teams
func set_team_names(home: String, away: String) -> void:
	home_team_name = home
	away_team_name = away
	var hn_lbl := home_name_label
	if hn_lbl != null and hn_lbl.text != home_team_name:
		hn_lbl.text = home_team_name
	var an_lbl := away_name_label
	if an_lbl != null and an_lbl.text != away_team_name:
		an_lbl.text = away_team_name

## Triggers the transient skill announcement banner outside the action corridor
func display_skill_banner(player_name: String, skill_name: String, element: String = "FIRE", portrait_path: String = "") -> void:
	if skill_banner != null and skill_banner.has_method("display_skill"):
		skill_banner.display_skill(player_name, skill_name, element, portrait_path)

func get_skill_banner() -> Control:
	return skill_banner

func get_scoreboard_rect() -> Rect2:
	if scoreboard_panel != null:
		return Rect2(scoreboard_panel.position, scoreboard_panel.size)
	return Rect2(SCOREBOARD_POS, SCOREBOARD_SIZE)

## Refreshes all labels from stored variables
func update_all() -> void:
	set_score(home_score, away_score)
	set_time(match_time_seconds)
	set_team_names(home_team_name, away_team_name)

## Verifies that the primary top-left playfield vision quadrant ([0, 460] x [0, 360]) is 100% clear
func is_top_left_unobstructed() -> bool:
	var top_left_rect = Rect2(0, 0, 460, 360)
	for child in get_children():
		if child is Control and child.visible:
			var c_rect = Rect2(child.position, child.size)
			if top_left_rect.intersects(c_rect):
				return false
	return true
