class_name Goal
extends Node2D

signal goal_scored(goal_name: String)

@export var is_right_goal: bool = true
@export var goal_width: float = 260.0
@export var goal_depth: float = 80.0
@export var post_radius: float = 9.0

var post_color: Color = Color(0.99, 0.99, 0.97)
var gold_post_ring: Color = Color(0.85, 0.69, 0.20, 0.95)
var net_color: Color = Color(0.96, 0.94, 0.88, 0.52)
var net_flash_timer: float = 0.0
var scoring_enabled: bool = true

@onready var goal_area: Area2D = get_node_or_null("GoalArea")

func _ready() -> void:
	if not is_right_goal:
		var ga = get_node_or_null("GoalArea")
		if ga: ga.position.x = -abs(ga.position.x)
		var nb = get_node_or_null("NetBack")
		if nb: nb.position.x = -abs(nb.position.x)
		var nt = get_node_or_null("NetTop")
		if nt: nt.position.x = -abs(nt.position.x)
		var nbot = get_node_or_null("NetBottom")
		if nbot: nbot.position.x = -abs(nbot.position.x)
	if goal_area and not goal_area.body_entered.is_connected(_on_body_entered):
		goal_area.body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if net_flash_timer > 0.0:
		net_flash_timer -= delta
		queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if not scoring_enabled:
		return
	if body is Ball or body.is_in_group("ball"):
		net_flash_timer = 0.6
		queue_redraw()
		emit_signal("goal_scored", name)

func _draw() -> void:
	var half_w = goal_width / 2.0
	var depth_dir = 1.0 if is_right_goal else -1.0
	var depth = goal_depth * depth_dir

	var current_net_color = Color(0.98, 0.84, 0.22, 0.85) if net_flash_timer > 0.0 else net_color

	# Net grid lines
	for y in range(int(-half_w), int(half_w) + 1, 16):
		draw_line(Vector2(0, y), Vector2(depth, y), current_net_color, 1.5)

	for x in range(0, int(abs(depth)) + 1, 13):
		var cur_x = x * depth_dir
		draw_line(Vector2(cur_x, -half_w), Vector2(cur_x, half_w), current_net_color, 1.5)

	draw_line(Vector2(depth, -half_w), Vector2(depth, half_w), gold_post_ring, 2.8)

	# Goal line
	draw_line(Vector2(0, -half_w), Vector2(0, half_w), Color(1.0, 1.0, 1.0, 0.82), 3.5)

	# Posts
	draw_line(Vector2(0, -half_w), Vector2(depth, -half_w), post_color, 4.0)
	draw_line(Vector2(0, half_w), Vector2(depth, half_w), post_color, 4.0)

	draw_circle(Vector2(0, -half_w), post_radius, post_color)
	draw_circle(Vector2(0, -half_w), post_radius - 2.0, gold_post_ring, false, 1.8)
	draw_circle(Vector2(0, -half_w), post_radius + 1.0, Color(0.08, 0.08, 0.1, 0.75), false, 1.5)

	draw_circle(Vector2(0, half_w), post_radius, post_color)
	draw_circle(Vector2(0, half_w), post_radius - 2.0, gold_post_ring, false, 1.8)
	draw_circle(Vector2(0, half_w), post_radius + 1.0, Color(0.08, 0.08, 0.1, 0.75), false, 1.5)
