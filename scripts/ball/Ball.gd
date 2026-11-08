class_name Ball
extends CharacterBody2D

## 3-State FSM Ball Physics Engine for Inazuma Inspired Arcade Soccer.
## Preserves authoritative ball handling, drag, friction, bouncing, and passing invariants.

enum State {
	LIBRE = 0,
	CONTROLADA = 1,
	EN_VUELO = 2
}

@export var current_state: State = State.LIBRE
@export var pickup_radius: float = 36.0
@export var base_friction: float = 340.0 # px/s^2

# Scaled pitch boundaries (3600 x 2160 px)
@export var field_half_width: float = 1800.0
@export var field_half_height: float = 1080.0
@export var goal_half_mouth: float = 130.0

@export var bounce_restitution: float = 0.72
@export var wall_restitution: float = 0.78

var carrier: CharacterBody2D = null
var kick_cooldown: float = 0.0
var last_kicker: CharacterBody2D = null
var target_receiver: CharacterBody2D = null
var match_players_ref: Array = []

# Super skill visual trail, aura, and duel metadata
var super_effect_timer: float = 0.0
var super_effect_color: Color = Color(1.0, 0.84, 0.18, 0.95)
var is_super_shot: bool = false
var shot_power_rating: float = 0.0

# Visual nodes
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var shadow: Sprite2D = get_node_or_null("Shadow")

signal state_changed(new_state: State)
signal possession_changed(new_carrier: CharacterBody2D)
signal pass_completed(receiver: CharacterBody2D)

func _ready() -> void:
	add_to_group("ball")
	collision_layer = 2
	collision_mask = 4

func activate_super_effect(duration: float = 1.2, col: Color = Color(1.0, 0.84, 0.18, 0.95), super_shot_flag: bool = false, power_rating: float = 85.0) -> void:
	super_effect_timer = duration
	super_effect_color = col
	is_super_shot = super_shot_flag
	shot_power_rating = power_rating
	queue_redraw()

func _physics_process(delta: float) -> void:
	if kick_cooldown > 0.0:
		kick_cooldown -= delta
		if kick_cooldown <= 0.0:
			last_kicker = null

	if super_effect_timer > 0.0:
		super_effect_timer -= delta
		if super_effect_timer <= 0.0:
			is_super_shot = false
		queue_redraw()

	match current_state:
		State.LIBRE:
			_process_libre(delta)
		State.CONTROLADA:
			_process_controlada(delta)
		State.EN_VUELO:
			_process_en_vuelo(delta)

func _process_libre(delta: float) -> void:
	if velocity.length() > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, base_friction * delta)
		_move_with_bounce(delta)
		if is_instance_valid(sprite):
			sprite.rotation += velocity.length() * 0.028 * delta * (1.0 if velocity.x >= 0.0 else -1.0)

	_keep_inside_pitch_bounds()
	_check_for_pickup()

func _process_controlada(delta: float) -> void:
	if not is_instance_valid(carrier):
		set_libre(Vector2.ZERO)
		return

	var facing = carrier.get("facing_direction")
	if facing == null or facing == Vector2.ZERO:
		facing = Vector2.DOWN

	var control_stat: float = 75.0
	if carrier.get("stats") and carrier.stats.has("control"):
		control_stat = float(carrier.stats["control"])

	var t: float = clampf(control_stat / 100.0, 0.0, 1.0)
	var ball_distance: float = lerp(28.0, 18.0, t)
	var lerp_weight: float = lerp(20.0, 34.0, t)

	var target_pos: Vector2 = carrier.global_position + facing.normalized() * ball_distance

	if carrier.get("is_moving") and is_instance_valid(sprite):
		sprite.rotation += carrier.velocity.length() * 0.025 * delta * (1.0 if facing.x >= 0.0 else -1.0)

	global_position = global_position.lerp(target_pos, clampf(lerp_weight * delta, 0.0, 1.0))
	velocity = carrier.velocity

func _process_en_vuelo(delta: float) -> void:
	# Directed pass homing towards teammate
	if is_instance_valid(target_receiver):
		var to_target = target_receiver.global_position - global_position
		var dist_to_target = to_target.length()
		if dist_to_target <= (pickup_radius + 22.0):
			var recv = target_receiver
			target_receiver = null
			take_possession(recv)
			emit_signal("pass_completed", recv)
			return
		elif velocity.length() > 120.0:
			var desired_dir = to_target.normalized()
			var current_speed = velocity.length()
			var new_dir = velocity.normalized().lerp(desired_dir, clampf(6.5 * delta, 0.0, 1.0)).normalized()
			velocity = new_dir * current_speed

	_move_with_bounce(delta)
	_keep_inside_pitch_bounds()
	if is_instance_valid(sprite):
		sprite.rotation += velocity.length() * 0.032 * delta * (1.0 if velocity.x >= 0.0 else -1.0)

	# Air drag: (base_friction * 0.42) = 142.8 px/s^2
	velocity = velocity.move_toward(Vector2.ZERO, (base_friction * 0.42) * delta)

	if velocity.length() < 95.0:
		target_receiver = null
		super_effect_timer = 0.0
		is_super_shot = false
		shot_power_rating = 0.0
		current_state = State.LIBRE
		emit_signal("state_changed", current_state)
		queue_redraw()
	else:
		_check_for_pickup()

func _move_with_bounce(delta: float) -> void:
	var collision = move_and_collide(velocity * delta)
	if collision:
		var normal = collision.get_normal()
		velocity = velocity.bounce(normal) * bounce_restitution
		target_receiver = null

func _keep_inside_pitch_bounds() -> void:
	var margin: float = 14.0
	# Rebound on touchlines (top and bottom)
	if global_position.y < -field_half_height + margin:
		global_position.y = -field_half_height + margin
		if velocity.y < 0.0:
			velocity.y = -velocity.y * wall_restitution
			target_receiver = null
	elif global_position.y > field_half_height - margin:
		global_position.y = field_half_height - margin
		if velocity.y > 0.0:
			velocity.y = -velocity.y * wall_restitution
			target_receiver = null

	# Rebound on goal lines (outside goal mouth opening)
	var in_goal_mouth = abs(global_position.y) <= goal_half_mouth
	if not in_goal_mouth:
		if global_position.x < -field_half_width + margin:
			global_position.x = -field_half_width + margin
			if velocity.x < 0.0:
				velocity.x = -velocity.x * wall_restitution
				target_receiver = null
		elif global_position.x > field_half_width - margin:
			global_position.x = field_half_width - margin
			if velocity.x > 0.0:
				velocity.x = -velocity.x * wall_restitution
				target_receiver = null
	else:
		# Net back depth limit inside goal
		var max_goal_depth = field_half_width + 80.0
		global_position.x = clampf(global_position.x, -max_goal_depth, max_goal_depth)

func _check_for_pickup() -> void:
	if not is_inside_tree():
		return

	# If goalkeeper is carrying the ball, opposing players cannot pick it up
	if current_state == State.CONTROLADA and is_instance_valid(carrier) and carrier.is_in_group("goalkeepers"):
		return

	var players: Array = match_players_ref if not match_players_ref.is_empty() else get_tree().get_nodes_in_group("players")
	var best_player: CharacterBody2D = null
	var best_dist_sq: float = pickup_radius * pickup_radius
	var fast_super_shot: bool = is_super_shot and velocity.length_squared() > 1102500.0 # 1050^2
	var gk_just_cleared: bool = is_instance_valid(last_kicker) and kick_cooldown > 0.0 and last_kicker.is_in_group("goalkeepers")

	for player in players:
		if not is_instance_valid(player):
			continue
		if player == last_kicker and kick_cooldown > 0.0:
			continue

		# Pass interception radius penalties: friendly 19.8 px, opponent 30.6 px
		var eff_radius := pickup_radius
		if is_instance_valid(target_receiver) and player != target_receiver:
			if player.get("team_id") == target_receiver.get("team_id"):
				eff_radius = pickup_radius * 0.55
			else:
				eff_radius = pickup_radius * 0.85

		var dist_sq: float = global_position.distance_squared_to(player.global_position)
		if dist_sq > eff_radius * eff_radius or dist_sq > best_dist_sq:
			continue

		# Super shots flying above 1050 px/s cannot be casually trapped by field players point-blank unless GK
		if fast_super_shot and not player.is_in_group("goalkeepers"):
			if is_instance_valid(last_kicker) and player.get("team_id") != last_kicker.get("team_id"):
				continue
		# If goalkeeper just cleared, opposing team cannot immediately intercept at point blank
		if gk_just_cleared and player.get("team_id") != last_kicker.get("team_id"):
			continue
		if player.get("pickup_lock_timer") != null and player.pickup_lock_timer > 0.0:
			continue
		if player.get("slide_recovery_timer") != null and player.slide_recovery_timer > 0.0:
			continue

		best_dist_sq = dist_sq
		best_player = player

	if is_instance_valid(best_player):
		take_possession(best_player)

func take_possession(player: CharacterBody2D) -> void:
	var received_pass := is_instance_valid(target_receiver) and target_receiver == player
	if is_instance_valid(carrier) and carrier != player and carrier.has_method("on_ball_lost"):
		carrier.on_ball_lost(self)
	carrier = player
	target_receiver = null
	super_effect_timer = 0.0
	is_super_shot = false
	shot_power_rating = 0.0
	current_state = State.CONTROLADA
	if player.has_method("on_ball_possessed"):
		player.on_ball_possessed(self)
	if received_pass and player.has_method("on_pass_received"):
		player.on_pass_received()
	emit_signal("possession_changed", carrier)
	emit_signal("state_changed", current_state)
	queue_redraw()

func set_libre(initial_velocity: Vector2 = Vector2.ZERO) -> void:
	if is_instance_valid(carrier) and carrier.has_method("on_ball_lost"):
		carrier.on_ball_lost(self)
	carrier = null
	target_receiver = null
	super_effect_timer = 0.0
	is_super_shot = false
	shot_power_rating = 0.0
	velocity = initial_velocity
	current_state = State.LIBRE
	emit_signal("possession_changed", null)
	emit_signal("state_changed", current_state)
	queue_redraw()

func kick(direction: Vector2, power: float, kicker: CharacterBody2D) -> void:
	last_kicker = kicker
	kick_cooldown = 0.35
	target_receiver = null
	if is_instance_valid(carrier) and carrier.has_method("on_ball_lost"):
		carrier.on_ball_lost(self)
	carrier = null
	velocity = direction.normalized() * power
	current_state = State.EN_VUELO
	emit_signal("possession_changed", null)
	emit_signal("state_changed", current_state)

func pass_to(target: CharacterBody2D, power: float, kicker: CharacterBody2D) -> void:
	last_kicker = kicker
	kick_cooldown = 0.30
	target_receiver = target
	is_super_shot = false
	if is_instance_valid(carrier) and carrier.has_method("on_ball_lost"):
		carrier.on_ball_lost(self)
	carrier = null

	var dir_to_target = (target.global_position - global_position).normalized()
	velocity = dir_to_target * power
	current_state = State.EN_VUELO
	emit_signal("possession_changed", null)
	emit_signal("state_changed", current_state)

func _draw() -> void:
	if super_effect_timer > 0.0 and current_state == State.EN_VUELO:
		var dir = -velocity.normalized() if velocity.length() > 10.0 else Vector2.LEFT
		var outer_tail = PackedVector2Array([
			dir * 6.0 + dir.orthogonal() * 14.0,
			dir * 68.0,
			dir * 6.0 - dir.orthogonal() * 14.0
		])
		var inner_tail = PackedVector2Array([
			dir * 8.0 + dir.orthogonal() * 7.5,
			dir * 44.0,
			dir * 8.0 - dir.orthogonal() * 7.5
		])
		draw_colored_polygon(outer_tail, Color(super_effect_color.r, super_effect_color.g, super_effect_color.b, 0.52))
		draw_colored_polygon(inner_tail, Color(1.0, 0.98, 0.85, 0.72))
		draw_circle(Vector2.ZERO, 17.5, Color(super_effect_color.r, super_effect_color.g, super_effect_color.b, 0.44))
		draw_arc(Vector2.ZERO, 19.5, 0.0, TAU, 24, Color(1.0, 0.96, 0.75, 0.92), 2.6)
