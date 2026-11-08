class_name BaseIndicator2D
extends Node2D

## Visual indicator component placed under player's feet.
## Renders clean, antialiased team-colored rings or ground ellipses for high-speed match readability.

@export_group("Colors")
@export var team_color: Color = Color(0.95, 0.80, 0.25, 0.85)
@export var inner_color: Color = Color(1.0, 1.0, 1.0, 0.65)

@export_group("Geometry")
@export var outer_radius: float = 14.0
@export var inner_radius: float = 10.0
@export var ring_width: float = 2.4
@export var is_ellipse: bool = true
## Vertical foreshortening factor for top-down oblique perspective
@export var ellipse_ratio_y: float = 0.62
@export var antialiased: bool = true

@export_group("States")
@export var is_controlled: bool = false
@export var is_pass_target: bool = false

const DEFAULT_RING_SEGMENTS: int = 32

static var ARROW_FILL_PTS: PackedVector2Array = PackedVector2Array([
	Vector2(-10, -82),
	Vector2(10, -82),
	Vector2(0, -68)
])
static var ARROW_OUTLINE_PTS: PackedVector2Array = PackedVector2Array([
	Vector2(-10, -82), Vector2(10, -82), Vector2(0, -68), Vector2(-10, -82)
])
static var DIAMOND_FILL_PTS: PackedVector2Array = PackedVector2Array([
	Vector2(0, -74), Vector2(5, -69), Vector2(0, -64), Vector2(-5, -69)
])
static var DIAMOND_OUTLINE_PTS: PackedVector2Array = PackedVector2Array([
	Vector2(0, -74), Vector2(5, -69), Vector2(0, -64), Vector2(-5, -69), Vector2(0, -74)
])
static var _unit_circle_32: PackedVector2Array = PackedVector2Array()

var pulse_time: float = 0.0
var _ring_buffer: PackedVector2Array = PackedVector2Array()

static func _ensure_unit_circle() -> void:
	if _unit_circle_32.size() == DEFAULT_RING_SEGMENTS + 1:
		return
	_unit_circle_32.resize(DEFAULT_RING_SEGMENTS + 1)
	for i in range(DEFAULT_RING_SEGMENTS + 1):
		var angle := (float(i) / float(DEFAULT_RING_SEGMENTS)) * TAU
		_unit_circle_32[i] = Vector2(cos(angle), sin(angle))

func _init() -> void:
	z_index = -1
	_ensure_unit_circle()
	_ring_buffer.resize(DEFAULT_RING_SEGMENTS + 1)

func _ready() -> void:
	# Ensure indicator renders underneath character sprite and above pitch turf
	z_index = -1
	set_process(is_controlled or is_pass_target)
	queue_redraw()

## Updates the primary team color and triggers redraw
func set_team_color(color: Color) -> void:
	if team_color == color:
		return
	team_color = color
	queue_redraw()

## Updates both team and inner highlight colors
func set_ring_color(team_col: Color, inner_col: Color = Color.WHITE) -> void:
	if team_color == team_col and inner_color == inner_col:
		return
	team_color = team_col
	inner_color = inner_col
	queue_redraw()

## Configures the dimensions of the indicator ring
func set_indicator_radii(outer: float, inner: float) -> void:
	if is_equal_approx(outer_radius, outer) and is_equal_approx(inner_radius, inner):
		return
	outer_radius = outer
	inner_radius = inner
	queue_redraw()

## Updates selection status (user active player or designated pass receiver)
func set_selection_state(user_controlled: bool, pass_target: bool) -> void:
	var changed := (is_controlled != user_controlled or is_pass_target != pass_target)
	is_controlled = user_controlled
	is_pass_target = pass_target
	set_process(is_controlled or is_pass_target)
	if changed:
		queue_redraw()

func _process(delta: float) -> void:
	if is_controlled or is_pass_target:
		pulse_time += delta * 6.0
		queue_redraw()
	else:
		set_process(false)

func _draw() -> void:
	var center := Vector2.ZERO

	if is_controlled:
		# Dynamic pulse effect for currently controlled player
		var pulse: float = 1.0 + 0.12 * sin(pulse_time)
		var rx := outer_radius * pulse
		var ry := (outer_radius * ellipse_ratio_y) * pulse if is_ellipse else rx

		_draw_ring_shape(center, rx + 7.0, ry + 4.0, Color(1.0, 0.95, 0.38, 0.24), 4.0)
		draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.96, 0.45, 0.9))
		_draw_ring_shape(center, rx, ry, team_color, ring_width + 0.8)
		if inner_radius > 0.0:
			_draw_ring_shape(center, rx * 0.75, ry * 0.75, inner_color, 1.4)

		# User overhead arrow indicator for direction / selection
		var arrow_color := Color(team_color.r, team_color.g, team_color.b, 0.95)
		draw_colored_polygon(ARROW_FILL_PTS, arrow_color)
		draw_polyline(ARROW_OUTLINE_PTS, Color(0.04, 0.05, 0.08, 0.95), 2.0, antialiased)
		draw_line(Vector2(0, -68), Vector2(0, -58), Color(1.0, 1.0, 1.0, 0.9), 2.0, antialiased)

	elif is_pass_target:
		# Target receiver visual indicator (bright ring with subtle pulse)
		var pulse: float = 1.0 + 0.08 * sin(pulse_time * 1.2)
		var rx := (outer_radius + 2.0) * pulse
		var ry := ((outer_radius + 2.0) * ellipse_ratio_y) * pulse if is_ellipse else rx

		_draw_ring_shape(center, rx, ry, Color(1.0, 1.0, 1.0, 0.92), ring_width)
		_draw_ring_shape(center, rx + 2.0, ry + 1.5, team_color, 1.4)

		# Overhead pass target diamond
		var diamond_color := Color(1.0, 0.98, 0.92, 0.95)
		draw_colored_polygon(DIAMOND_FILL_PTS, diamond_color)
		draw_polyline(DIAMOND_OUTLINE_PTS, team_color, 1.2, antialiased)

	else:
		# Passive player indicator: clean, subtle ring under feet
		var rx := outer_radius
		var ry := outer_radius * ellipse_ratio_y if is_ellipse else rx
		_draw_ring_shape(center, rx, ry, team_color, ring_width)

		if inner_radius > 0.0 and inner_radius < outer_radius:
			var irx := inner_radius
			var iry := inner_radius * ellipse_ratio_y if is_ellipse else irx
			_draw_ring_shape(center, irx, iry, inner_color, 1.0)

## Helper to draw an antialiased circular or elliptical ring with zero per-frame allocations
func _draw_ring_shape(pos: Vector2, rx: float, ry: float, col: Color, width: float, segments: int = DEFAULT_RING_SEGMENTS) -> void:
	if not is_ellipse or absf(rx - ry) < 0.01:
		draw_arc(pos, rx, 0.0, TAU, segments, col, width, antialiased)
		return

	if segments == DEFAULT_RING_SEGMENTS:
		_ensure_unit_circle()
		if _ring_buffer.size() != DEFAULT_RING_SEGMENTS + 1:
			_ring_buffer.resize(DEFAULT_RING_SEGMENTS + 1)
		for i in range(DEFAULT_RING_SEGMENTS + 1):
			var u := _unit_circle_32[i]
			_ring_buffer[i] = Vector2(pos.x + u.x * rx, pos.y + u.y * ry)
		draw_polyline(_ring_buffer, col, width, antialiased)
		return

	var pts := PackedVector2Array()
	pts.resize(segments + 1)
	for i in range(segments + 1):
		var angle := (float(i) / float(segments)) * TAU
		pts[i] = pos + Vector2(cos(angle) * rx, sin(angle) * ry)
	draw_polyline(pts, col, width, antialiased)
