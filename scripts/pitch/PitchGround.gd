class_name PitchGround
extends Node2D

## Scaled pitch dimensions for Inazuma Inspired Arcade Soccer (3600 x 2160 px).
## Provides vector drawing of grass turf, lines, zones, and manages boundary colliders.

@export_group("Field Dimensions")
@export var field_width: float = 3600.0
@export var field_height: float = 2160.0
@export var field_half_width: float = 1800.0
@export var field_half_height: float = 1080.0
@export var line_width: float = 4.5

@export_group("Pitch Markings")
@export var center_circle_radius: float = 185.0
@export var penalty_box_width: float = 480.0
@export var penalty_box_height: float = 880.0
@export var goal_area_width: float = 180.0
@export var goal_area_height: float = 440.0
@export var penalty_spot_dist: float = 330.0

@export_group("Goal Dimensions")
@export var goal_width: float = 260.0
@export var goal_half_mouth: float = 130.0
@export var goal_depth: float = 80.0
@export var post_radius: float = 9.0

@export_group("Physics Invariants")
@export var wall_restitution: float = 0.78

var grass_outer: Color = Color(0.11, 0.36, 0.16)
var grass_dark: Color = Color(0.16, 0.49, 0.21)
var grass_light: Color = Color(0.20, 0.55, 0.25)
var line_color: Color = Color(0.98, 0.98, 0.96, 0.92)
var gold_accent: Color = Color(0.85, 0.69, 0.22, 0.55)

var boundary_colliders: Dictionary = {}

func _init() -> void:
	z_index = -10

func _ready() -> void:
	z_index = -10
	_ensure_boundary_colliders()

## Generates or finds the 6 physical StaticBody2D boundaries on Layer 4
func _ensure_boundary_colliders() -> void:
	var boundaries_node = get_node_or_null("PitchBoundaries")
	if not boundaries_node:
		boundaries_node = Node2D.new()
		boundaries_node.name = "PitchBoundaries"
		add_child(boundaries_node)

	var defs = [
		{"name": "TopTouchline", "pos": Vector2(0, -1100), "size": Vector2(3800, 40)},
		{"name": "BottomTouchline", "pos": Vector2(0, 1100), "size": Vector2(3800, 40)},
		{"name": "LeftGoalLineTop", "pos": Vector2(-1820, -605), "size": Vector2(40, 950)},
		{"name": "LeftGoalLineBottom", "pos": Vector2(-1820, 605), "size": Vector2(40, 950)},
		{"name": "RightGoalLineTop", "pos": Vector2(1820, -605), "size": Vector2(40, 950)},
		{"name": "RightGoalLineBottom", "pos": Vector2(1820, 605), "size": Vector2(40, 950)}
	]

	var phys_mat = PhysicsMaterial.new()
	phys_mat.bounce = wall_restitution
	phys_mat.friction = 0.0

	for def in defs:
		var body = boundaries_node.get_node_or_null(def["name"]) as StaticBody2D
		if not body:
			body = StaticBody2D.new()
			body.name = def["name"]
			body.position = def["pos"]
			body.collision_layer = 4
			body.collision_mask = 3
			body.physics_material_override = phys_mat

			var cshape = CollisionShape2D.new()
			var rect = RectangleShape2D.new()
			rect.size = def["size"]
			cshape.shape = rect
			body.add_child(cshape)
			boundaries_node.add_child(body)
		boundary_colliders[def["name"]] = body

func _draw() -> void:
	var half_w = field_half_width
	var half_h = field_half_height

	# 1. Outer grass and gold tournament border
	var rect_outer = Rect2(-half_w - 320, -half_h - 240, field_width + 640, field_height + 480)
	draw_rect(rect_outer, grass_outer, true)
	draw_rect(Rect2(-half_w - 18, -half_h - 18, field_width + 36, field_height + 36), gold_accent, false, 2.5)
	draw_rect(Rect2(-half_w, -half_h, field_width, field_height), grass_dark, true)

	# 2. Alternating grass stripes
	var stripe_w = 180.0
	var start_x = -half_w
	var stripe_count = int(field_width / stripe_w)
	for i in range(stripe_count):
		if i % 2 == 0:
			draw_rect(Rect2(start_x + i * stripe_w, -half_h, stripe_w, field_height), grass_light, true)

	# 3. Outer field boundaries
	draw_rect(Rect2(-half_w, -half_h, field_width, field_height), line_color, false, line_width)

	# 4. Halfway line
	draw_line(Vector2(0, -half_h), Vector2(0, half_h), line_color, line_width)

	# 5. Center circle and kickoff spot
	draw_arc(Vector2.ZERO, center_circle_radius + 7.0, 0, TAU, 64, gold_accent, 2.0)
	draw_arc(Vector2.ZERO, center_circle_radius, 0, TAU, 64, line_color, line_width)
	draw_circle(Vector2.ZERO, 8.5, gold_accent)
	draw_circle(Vector2.ZERO, 6.0, line_color)

	# 6. Penalty boxes (left and right)
	draw_rect(Rect2(-half_w, -penalty_box_height / 2.0, penalty_box_width, penalty_box_height), line_color, false, line_width)
	draw_rect(Rect2(half_w - penalty_box_width, -penalty_box_height / 2.0, penalty_box_width, penalty_box_height), line_color, false, line_width)

	# 7. Goal areas (left and right)
	draw_rect(Rect2(-half_w, -goal_area_height / 2.0, goal_area_width, goal_area_height), line_color, false, line_width)
	draw_rect(Rect2(half_w - goal_area_width, -goal_area_height / 2.0, goal_area_width, goal_area_height), line_color, false, line_width)

	# 8. Penalty spots and arcs
	draw_circle(Vector2(-half_w + penalty_spot_dist, 0), 5.5, line_color)
	draw_circle(Vector2(half_w - penalty_spot_dist, 0), 5.5, line_color)
	draw_arc(Vector2(-half_w + penalty_spot_dist, 0), 140.0, -0.92, 0.92, 32, line_color, line_width)
	draw_arc(Vector2(half_w - penalty_spot_dist, 0), 140.0, PI - 0.92, PI + 0.92, 32, line_color, line_width)

	# 9. Corner arcs
	var corner_r = 36.0
	draw_arc(Vector2(-half_w, -half_h), corner_r, 0, PI * 0.5, 16, line_color, line_width)
	draw_arc(Vector2(half_w, -half_h), corner_r, PI * 0.5, PI, 16, line_color, line_width)
	draw_arc(Vector2(half_w, half_h), corner_r, PI, PI * 1.5, 16, line_color, line_width)
	draw_arc(Vector2(-half_w, half_h), corner_r, PI * 1.5, TAU, 16, line_color, line_width)
