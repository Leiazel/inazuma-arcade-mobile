class_name MiniRadar
extends Control

## Tactical bottom-center mini-map radar showing all 10 players and the ball in real time.
## Positioned safely at y >= 624 outside the top-left sightline corridor.

const FIELD_HALF_W: float = 1800.0
const FIELD_HALF_H: float = 1080.0

var home_color: Color = Color(0.98, 0.80, 0.15)
var away_color: Color = Color(0.22, 0.74, 0.98)
var _player_dots: Array[Dictionary] = []
var _ball_norm: Vector2 = Vector2(0.5, 0.5)
var _has_ball_pos: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(196.0, 80.0)
	if size == Vector2.ZERO:
		size = custom_minimum_size
	queue_redraw()

func update_radar(players: Array, ball: Node2D, home_col: Color, away_col: Color) -> void:
	home_color = home_col
	away_color = away_col
	_player_dots.clear()

	for node in players:
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		var n2d := node as Node2D
		var nx: float = clampf((n2d.global_position.x + FIELD_HALF_W) / (FIELD_HALF_W * 2.0), 0.02, 0.98)
		var ny: float = clampf((n2d.global_position.y + FIELD_HALF_H) / (FIELD_HALF_H * 2.0), 0.04, 0.96)
		var is_home: bool = str(n2d.get("team_id")) == "team_user"
		var controlled: bool = true if n2d.get("is_user_controlled") else false
		var is_gk: bool = n2d.is_in_group("goalkeepers") or str(n2d.get("role")) == "GK"
		_player_dots.append({
			"uv": Vector2(nx, ny),
			"is_home": is_home,
			"controlled": controlled,
			"is_gk": is_gk
		})

	if is_instance_valid(ball):
		_has_ball_pos = true
		_ball_norm = Vector2(
			clampf((ball.global_position.x + FIELD_HALF_W) / (FIELD_HALF_W * 2.0), 0.01, 0.99),
			clampf((ball.global_position.y + FIELD_HALF_H) / (FIELD_HALF_H * 2.0), 0.02, 0.98)
		)
	else:
		_has_ball_pos = false

	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.11, 0.08, 0.82)
	bg.border_color = Color(0.95, 0.82, 0.25, 0.55)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	draw_style_box(bg, rect)

	var pad := Vector2(8.0, 6.0)
	var pitch_rect := Rect2(pad, size - pad * 2.0)
	var line_col := Color(0.85, 0.96, 0.88, 0.34)

	# Pitch markings
	draw_rect(pitch_rect, line_col, false, 1.0)
	var mid_x: float = pitch_rect.position.x + pitch_rect.size.x * 0.5
	var mid_y: float = pitch_rect.position.y + pitch_rect.size.y * 0.5
	draw_line(Vector2(mid_x, pitch_rect.position.y), Vector2(mid_x, pitch_rect.end.y), line_col, 1.0)
	draw_arc(Vector2(mid_x, mid_y), pitch_rect.size.y * 0.22, 0.0, TAU, 20, line_col, 1.0)

	var box_w: float = pitch_rect.size.x * 0.13
	var box_h: float = pitch_rect.size.y * 0.44
	draw_rect(Rect2(pitch_rect.position.x, mid_y - box_h * 0.5, box_w, box_h), line_col, false, 1.0)
	draw_rect(Rect2(pitch_rect.end.x - box_w, mid_y - box_h * 0.5, box_w, box_h), line_col, false, 1.0)

	# Players
	for d in _player_dots:
		var uv: Vector2 = d["uv"]
		var pt := pitch_rect.position + Vector2(uv.x * pitch_rect.size.x, uv.y * pitch_rect.size.y)
		var col: Color = home_color if d["is_home"] else away_color
		var radius: float = 3.2 if d["is_gk"] else 3.8
		if d["controlled"]:
			draw_circle(pt, radius + 2.4, Color(1.0, 1.0, 1.0, 0.95))
		else:
			draw_circle(pt, radius + 1.0, Color(0.02, 0.03, 0.05, 0.90))
		draw_circle(pt, radius, col)

	# Ball
	if _has_ball_pos:
		var bpt := pitch_rect.position + Vector2(_ball_norm.x * pitch_rect.size.x, _ball_norm.y * pitch_rect.size.y)
		draw_circle(bpt, 4.4, Color(0.05, 0.05, 0.08, 0.95))
		draw_circle(bpt, 3.1, Color(1.0, 0.96, 0.55, 1.0))
