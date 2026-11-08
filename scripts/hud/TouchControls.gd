class_name TouchControls
extends Control

## Virtual touch overlay for mobile / touch devices (or optional toggle from Pause Menu).
## Styled in Warm Beige, Imperial Crimson Red, Crisp White, and Royal Gold.
## Features an ergonomic Arc/Diamond right-hand button layout, dynamic floating joystick
## with auto-sprint threshold indicator, hold-to-charge shot integration, and multi-touch tracking.

signal move_changed(vector: Vector2)
signal action_selected(action: String)
signal ability_pressed()
signal switch_pressed()
signal pause_pressed()
signal field_drag_started(screen_position: Vector2)
signal field_drag_changed(screen_position: Vector2)
signal field_drag_ended(screen_position: Vector2)
signal field_clicked(button: int, screen_position: Vector2)

const JOYSTICK_MAX_RADIUS: float = 64.0
const ACTION_PAD_RADIUS: float = 56.0
const ARC_BTN_RADIUS: float = 40.0
const ABILITY_BTN_RADIUS: float = 46.0
const SPRINT_THRESHOLD: float = 0.78

# Palette: Warm Beige, Imperial Red, Crisp White & Royal Gold
const COL_BEIGE_LIGHT := Color(0.97, 0.93, 0.86, 0.92)
const COL_BEIGE_BASE := Color(0.92, 0.86, 0.75, 0.88)
const COL_RED_PRIMARY := Color(0.78, 0.14, 0.16, 0.94)
const COL_RED_ACTIVE := Color(0.92, 0.22, 0.22, 0.98)
const COL_RED_DARK := Color(0.48, 0.08, 0.10, 0.92)
const COL_GOLD := Color(0.90, 0.70, 0.16, 0.95)
const COL_GOLD_BRIGHT := Color(1.0, 0.84, 0.24, 0.98)
const COL_WHITE := Color(0.99, 0.98, 0.96, 0.98)
const COL_TEXT_DARK := Color(0.20, 0.09, 0.08, 0.98)

var touch_enabled: bool = false
var blocked_by_menu: bool = false
var move_origin := Vector2(132.0, 560.0)
var action_origin := Vector2.ZERO
var move_dragging := false
var action_dragging := false
var move_vector := Vector2.ZERO
var action_vector := Vector2.ZERO
var ability_button_down := false
var pass_button_down := false
var switch_button_down := false
var slide_button_down := false
var pause_button_down := false
var _shot_hold_time: float = 0.0

# Multi-touch pointer tracking: assigns specific finger ID to each control
var _move_pointer_id: int = -1
var _action_pointer_id: int = -1
var _ability_pointer_id: int = -1
var _pass_pointer_id: int = -1
var _switch_pointer_id: int = -1
var _slide_pointer_id: int = -1
var _pause_pointer_id: int = -1
var _field_pointer_id: int = -1
var _pause_style_idle: StyleBoxFlat = null
var _pause_style_down: StyleBoxFlat = null

func _ensure_styles() -> void:
	if _pause_style_idle == null:
		_pause_style_idle = StyleBoxFlat.new()
		_pause_style_idle.bg_color = COL_BEIGE_LIGHT
		_pause_style_idle.border_color = COL_GOLD_BRIGHT
		_pause_style_idle.set_border_width_all(2)
		_pause_style_idle.set_corner_radius_all(10)
	if _pause_style_down == null:
		_pause_style_down = StyleBoxFlat.new()
		_pause_style_down.bg_color = COL_RED_PRIMARY
		_pause_style_down.border_color = COL_GOLD_BRIGHT
		_pause_style_down.set_border_width_all(2)
		_pause_style_down.set_corner_radius_all(10)

func _ready() -> void:
	_ensure_styles()
	var is_mobile := OS.get_name() == "Android" or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	set_touch_enabled(is_mobile and DisplayServer.get_name() != "headless")
	set_process(false)

func _process(delta: float) -> void:
	if action_dragging:
		_shot_hold_time = minf(1.0, _shot_hold_time + delta)
		queue_redraw()
	elif _shot_hold_time > 0.0:
		_shot_hold_time = 0.0
		set_process(false)
		queue_redraw()
	else:
		set_process(false)

func set_touch_enabled(enabled: bool) -> void:
	touch_enabled = enabled
	_update_interactivity()

func set_blocked_by_menu(blocked: bool) -> void:
	blocked_by_menu = blocked
	_update_interactivity()

func _update_interactivity() -> void:
	var active := touch_enabled and not blocked_by_menu
	visible = active
	mouse_filter = Control.MOUSE_FILTER_PASS if active else Control.MOUSE_FILTER_IGNORE
	if not active:
		_reset_all_touch_states()
	queue_redraw()

func _reset_all_touch_states() -> void:
	if action_dragging and InputMap.has_action("action_shot"):
		Input.action_release("action_shot")
	move_dragging = false
	action_dragging = false
	set_process(false)
	ability_button_down = false
	pass_button_down = false
	switch_button_down = false
	slide_button_down = false
	pause_button_down = false
	_shot_hold_time = 0.0
	_move_pointer_id = -1
	_action_pointer_id = -1
	_ability_pointer_id = -1
	_pass_pointer_id = -1
	_switch_pointer_id = -1
	_slide_pointer_id = -1
	_pause_pointer_id = -1
	_field_pointer_id = -1
	if move_vector != Vector2.ZERO:
		move_vector = Vector2.ZERO
		move_changed.emit(Vector2.ZERO)
	action_vector = Vector2.ZERO
	move_origin = _get_default_joystick_center()

func _vibrate(_duration_ms: int) -> void:
	# Virtual buttons do not vibrate to prevent OS interruptions and excessive haptics.
	pass

func _gui_input(event: InputEvent) -> void:
	if not touch_enabled or blocked_by_menu:
		return
	# When running on a real touchscreen with emulate_mouse_from_touch=true,
	# ignore synthesized mouse events so touches are not processed twice.
	if DisplayServer.is_touchscreen_available() and (event is InputEventMouseButton or event is InputEventMouseMotion):
		accept_event()
		return

	var pointer := _pointer_position(event)
	if pointer == Vector2.INF:
		return
	var pid := _pointer_id(event)

	if _is_pointer_press(event):
		if _get_pause_rect().has_point(pointer):
			_pause_pointer_id = pid
			pause_button_down = true
			pause_pressed.emit()
			accept_event()
			queue_redraw()
			return

		if pointer.distance_to(_get_ability_center()) <= ABILITY_BTN_RADIUS + 8.0 or _get_ability_rect().has_point(pointer):
			_ability_pointer_id = pid
			ability_button_down = true
			ability_pressed.emit()
			action_selected.emit("ability")
			accept_event()
			queue_redraw()
			return

		if pointer.distance_to(_get_pass_center()) <= ARC_BTN_RADIUS + 8.0 or _get_pass_rect().has_point(pointer):
			_pass_pointer_id = pid
			pass_button_down = true
			action_selected.emit("pass")
			accept_event()
			queue_redraw()
			return

		if pointer.distance_to(_get_switch_center()) <= ARC_BTN_RADIUS + 8.0 or _get_switch_rect().has_point(pointer):
			_switch_pointer_id = pid
			switch_button_down = true
			switch_pressed.emit()
			action_selected.emit("switch")
			accept_event()
			queue_redraw()
			return

		if pointer.distance_to(_get_slide_center()) <= ARC_BTN_RADIUS + 8.0 or _get_slide_rect().has_point(pointer):
			_slide_pointer_id = pid
			slide_button_down = true
			action_selected.emit("slide")
			accept_event()
			queue_redraw()
			return

		var act_center := _get_action_center()
		if pointer.distance_to(act_center) <= ACTION_PAD_RADIUS + 14.0:
			_action_pointer_id = pid
			action_dragging = true
			_shot_hold_time = 0.0
			set_process(true)
			action_origin = act_center
			action_vector = _clamped_vector(pointer - action_origin, ACTION_PAD_RADIUS)
			if InputMap.has_action("action_shot"):
				Input.action_press("action_shot")
			accept_event()
			queue_redraw()
			return

		var w := size.x if size.x > 0.0 else 1280.0
		if pointer.x <= w * 0.42 and pointer.y >= 240.0:
			_move_pointer_id = pid
			move_dragging = true
			move_origin = pointer
			move_vector = Vector2.ZERO
			move_changed.emit(move_vector)
			accept_event()
			queue_redraw()
			return

		_field_pointer_id = pid
		field_drag_started.emit(pointer)
		queue_redraw()
		return

	if _is_pointer_motion(event):
		if pid == _move_pointer_id and move_dragging:
			move_vector = _clamped_vector(pointer - move_origin, JOYSTICK_MAX_RADIUS)
			move_changed.emit(move_vector)
			accept_event()
			queue_redraw()
		elif pid == _action_pointer_id and action_dragging:
			action_vector = _clamped_vector(pointer - action_origin, ACTION_PAD_RADIUS)
			accept_event()
			queue_redraw()
		elif pid == _field_pointer_id:
			field_drag_changed.emit(pointer)
			queue_redraw()
		return

	if _is_pointer_release(event):
		if pid == _pause_pointer_id:
			_pause_pointer_id = -1
			pause_button_down = false
			accept_event()
			queue_redraw()
			return

		if pid == _ability_pointer_id:
			_ability_pointer_id = -1
			ability_button_down = false
			accept_event()
			queue_redraw()
			return

		if pid == _pass_pointer_id:
			_pass_pointer_id = -1
			pass_button_down = false
			accept_event()
			queue_redraw()
			return

		if pid == _switch_pointer_id:
			_switch_pointer_id = -1
			switch_button_down = false
			accept_event()
			queue_redraw()
			return

		if pid == _slide_pointer_id:
			_slide_pointer_id = -1
			slide_button_down = false
			accept_event()
			queue_redraw()
			return

		if pid == _action_pointer_id:
			_action_pointer_id = -1
			action_dragging = false
			_shot_hold_time = 0.0
			if InputMap.has_action("action_shot"):
				Input.action_release("action_shot")
			var chosen := _action_from_vector(action_vector)
			action_vector = Vector2.ZERO
			action_selected.emit(chosen)
			accept_event()
			queue_redraw()
			return

		if pid == _move_pointer_id:
			_move_pointer_id = -1
			move_dragging = false
			move_vector = Vector2.ZERO
			move_changed.emit(move_vector)
			move_origin = _get_default_joystick_center()
			accept_event()
			queue_redraw()
			return

		if pid == _field_pointer_id:
			_field_pointer_id = -1
			field_drag_ended.emit(pointer)
			field_clicked.emit(_pointer_button(event), pointer)
			queue_redraw()
			return

func _pointer_id(event: InputEvent) -> int:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return event.index
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		return 0
	return -1

func _pointer_position(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		return event.position
	if event is InputEventMouseMotion:
		return event.position
	if event is InputEventScreenTouch:
		return event.position
	if event is InputEventScreenDrag:
		return event.position
	return Vector2.INF

func _is_pointer_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	return false

func _is_pointer_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return not event.pressed
	if event is InputEventMouseButton:
		return not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	return false

func _is_pointer_motion(event: InputEvent) -> bool:
	return event is InputEventMouseMotion or event is InputEventScreenDrag

func _pointer_button(event: InputEvent) -> int:
	if event is InputEventScreenTouch:
		return MOUSE_BUTTON_LEFT
	if event is InputEventMouseButton:
		return event.button_index
	return MOUSE_BUTTON_LEFT

func _clamped_vector(delta: Vector2, radius: float) -> Vector2:
	return delta.limit_length(radius) / maxf(1.0, radius)

func _action_from_vector(vector: Vector2) -> String:
	if vector.length() < 0.30:
		return "shot"
	if vector.x < -0.35:
		return "pass"
	return "shot"

func _get_safe_margin_left() -> float:
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0 and safe.position.x > 0:
		return minf(64.0, float(safe.position.x))
	return 0.0

func _get_safe_margin_right() -> float:
	var safe := DisplayServer.get_display_safe_area()
	var screen_w := float(DisplayServer.window_get_size().x)
	if safe.size.x > 0 and screen_w > 0:
		var r_offset := screen_w - float(safe.position.x + safe.size.x)
		return clampf(r_offset, 0.0, 64.0)
	return 0.0

# ==============================================================================
# ERGONOMIC ARC / DIAMOND GEOMETRY (CLEAR OF BOTTOM-CENTER HUD DOCK)
# ==============================================================================

func _get_default_joystick_center() -> Vector2:
	var h := size.y if size.y > 0.0 else 720.0
	return Vector2(132.0 + _get_safe_margin_left(), maxf(480.0, h - 148.0))

func _get_joystick_center() -> Vector2:
	if move_dragging:
		return move_origin
	return _get_default_joystick_center()

func _get_action_center() -> Vector2:
	var w := size.x if size.x > 0.0 else 1280.0
	var h := size.y if size.y > 0.0 else 720.0
	return Vector2(w - 94.0 - _get_safe_margin_right(), h - 98.0)

func _get_pass_center() -> Vector2:
	var act := _get_action_center()
	return act + Vector2(-128.0, 14.0)

func _get_slide_center() -> Vector2:
	var act := _get_action_center()
	return act + Vector2(-106.0, -82.0)

func _get_switch_center() -> Vector2:
	var act := _get_action_center()
	return act + Vector2(-18.0, -124.0)

func _get_ability_center() -> Vector2:
	var act := _get_action_center()
	return act + Vector2(-124.0, -178.0)

func _get_ability_rect() -> Rect2:
	var c := _get_ability_center()
	return Rect2(c - Vector2(ABILITY_BTN_RADIUS, ABILITY_BTN_RADIUS), Vector2(ABILITY_BTN_RADIUS * 2.0, ABILITY_BTN_RADIUS * 2.0))

func _get_pass_rect() -> Rect2:
	var c := _get_pass_center()
	return Rect2(c - Vector2(ARC_BTN_RADIUS, ARC_BTN_RADIUS), Vector2(ARC_BTN_RADIUS * 2.0, ARC_BTN_RADIUS * 2.0))

func _get_switch_rect() -> Rect2:
	var c := _get_switch_center()
	return Rect2(c - Vector2(ARC_BTN_RADIUS, ARC_BTN_RADIUS), Vector2(ARC_BTN_RADIUS * 2.0, ARC_BTN_RADIUS * 2.0))

func _get_slide_rect() -> Rect2:
	var c := _get_slide_center()
	return Rect2(c - Vector2(ARC_BTN_RADIUS, ARC_BTN_RADIUS), Vector2(ARC_BTN_RADIUS * 2.0, ARC_BTN_RADIUS * 2.0))

func _get_pause_rect() -> Rect2:
	var w := size.x if size.x > 0.0 else 1280.0
	return Rect2(Vector2(w - 76.0 - _get_safe_margin_right(), 14.0), Vector2(60.0, 42.0))

# ==============================================================================
# CUSTOM RENDERING (BEIGE / CRIMSON RED / WHITE / ROYAL GOLD)
# ==============================================================================

func _draw() -> void:
	if not touch_enabled or blocked_by_menu:
		return
	_draw_joystick(_get_joystick_center())
	_draw_arc_Guide()
	_draw_action_pad(_get_action_center())
	_draw_circle_button(_get_pass_center(), ARC_BTN_RADIUS, "PASE", "TOCAR", pass_button_down, false)
	_draw_circle_button(_get_slide_center(), ARC_BTN_RADIUS, "BARRIDA", "ROBAR", slide_button_down, false)
	_draw_circle_button(_get_switch_center(), ARC_BTN_RADIUS - 2.0, "CAMBIAR", "DEFENSA", switch_button_down, false)
	_draw_circle_button(_get_ability_center(), ABILITY_BTN_RADIUS, "HISSATSU", "★ TÉCNICA", ability_button_down, true)
	_draw_pause_button(_get_pause_rect(), pause_button_down)

func _draw_arc_Guide() -> void:
	var act := _get_action_center()
	draw_arc(act, 126.0, deg_to_rad(165.0), deg_to_rad(268.0), 28, Color(0.90, 0.70, 0.16, 0.28), 2.0)

func _draw_joystick(center: Vector2) -> void:
	var is_sprint := move_vector.length() >= SPRINT_THRESHOLD
	# Outer warm beige translucent base
	draw_circle(center, JOYSTICK_MAX_RADIUS, Color(0.96, 0.92, 0.84, 0.34))
	draw_circle(center, JOYSTICK_MAX_RADIUS * 0.78, Color(0.78, 0.14, 0.16, 0.14))
	# Rim: glows bright gold + crimson when sprinting
	var rim_col := COL_GOLD_BRIGHT if is_sprint else Color(0.90, 0.70, 0.16, 0.78)
	draw_arc(center, JOYSTICK_MAX_RADIUS, 0.0, TAU, 40, rim_col, 3.5 if is_sprint else 2.5)
	if is_sprint:
		draw_arc(center, JOYSTICK_MAX_RADIUS + 5.0, 0.0, TAU, 40, COL_RED_ACTIVE, 2.0)
		draw_string(ThemeDB.fallback_font, center + Vector2(-44.0, -JOYSTICK_MAX_RADIUS - 10.0), "⚡ SPRINT", HORIZONTAL_ALIGNMENT_CENTER, 88.0, 12, COL_GOLD_BRIGHT)

	# Crosshair subtle lines
	draw_line(center + Vector2(-18, 0), center + Vector2(18, 0), Color(0.48, 0.08, 0.10, 0.28), 1.5)
	draw_line(center + Vector2(0, -18), center + Vector2(0, 18), Color(0.48, 0.08, 0.10, 0.28), 1.5)

	# Thumb Knob: Crimson Red core + Gold & White rings
	var knob := center + move_vector * (JOYSTICK_MAX_RADIUS * 0.74)
	draw_circle(knob, 26.0, COL_RED_ACTIVE if is_sprint else COL_RED_PRIMARY)
	draw_arc(knob, 26.0, 0.0, TAU, 28, COL_GOLD_BRIGHT, 3.0)
	draw_circle(knob, 10.0, COL_WHITE)

func _draw_action_pad(center: Vector2) -> void:
	var r := ACTION_PAD_RADIUS * (0.94 if action_dragging else 1.0)
	# Outer shadow & Gold halo
	draw_circle(center + Vector2(0, 3), r + 2.0, Color(0.12, 0.04, 0.04, 0.45))
	draw_circle(center, r, COL_RED_ACTIVE if action_dragging else COL_RED_PRIMARY)
	draw_arc(center, r, 0.0, TAU, 40, COL_GOLD_BRIGHT, 3.5)
	draw_arc(center, r - 5.0, 0.0, TAU, 36, Color(1.0, 1.0, 1.0, 0.35), 1.5)

	# Charge progress arc when holding TIRO
	if action_dragging and _shot_hold_time > 0.02:
		var pct := clampf(_shot_hold_time / 0.60, 0.0, 1.0)
		draw_arc(center, r + 6.0, -PI * 0.5, -PI * 0.5 + TAU * pct, 36, COL_GOLD_BRIGHT, 4.5)

	draw_string(ThemeDB.fallback_font, center + Vector2(-48.0, -2.0), "TIRO", HORIZONTAL_ALIGNMENT_CENTER, 96.0, 16, COL_WHITE)
	draw_string(ThemeDB.fallback_font, center + Vector2(-48.0, 15.0), "CARGAR", HORIZONTAL_ALIGNMENT_CENTER, 96.0, 10, COL_BEIGE_LIGHT)

func _draw_circle_button(center: Vector2, radius: float, title_txt: String, sub_txt: String, is_down: bool, is_gold_special: bool) -> void:
	var r := radius * (0.93 if is_down else 1.0)
	draw_circle(center + Vector2(0, 2), r + 1.5, Color(0.12, 0.04, 0.04, 0.40))

	if is_gold_special:
		var fill := COL_RED_ACTIVE if is_down else COL_GOLD
		draw_circle(center, r, fill)
		draw_arc(center, r, 0.0, TAU, 36, COL_WHITE if is_down else COL_RED_PRIMARY, 3.0)
		draw_arc(center, r - 4.0, 0.0, TAU, 32, COL_GOLD_BRIGHT, 1.5)
		var txt_col := COL_WHITE if is_down else COL_TEXT_DARK
		draw_string(ThemeDB.fallback_font, center + Vector2(-r, -1.0), title_txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 12, txt_col)
		draw_string(ThemeDB.fallback_font, center + Vector2(-r, 13.0), sub_txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 9, COL_WHITE if is_down else COL_RED_DARK)
	else:
		var fill := COL_RED_PRIMARY if is_down else COL_BEIGE_LIGHT
		draw_circle(center, r, fill)
		draw_arc(center, r, 0.0, TAU, 32, COL_GOLD_BRIGHT if is_down else COL_GOLD, 2.5)
		draw_arc(center, r - 3.5, 0.0, TAU, 28, COL_RED_PRIMARY, 1.2)
		var main_col := COL_WHITE if is_down else COL_RED_PRIMARY
		var sub_col := COL_BEIGE_LIGHT if is_down else COL_TEXT_DARK
		draw_string(ThemeDB.fallback_font, center + Vector2(-r, -1.0), title_txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 12, main_col)
		draw_string(ThemeDB.fallback_font, center + Vector2(-r, 12.0), sub_txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 9, sub_col)

func _draw_pause_button(rect: Rect2, is_down: bool) -> void:
	_ensure_styles()
	var style: StyleBoxFlat = _pause_style_down if is_down else _pause_style_idle
	draw_style_box(style, rect)
	var col := COL_WHITE if is_down else COL_RED_PRIMARY
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(0.0, rect.size.y * 0.68), "❚❚", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, col)
