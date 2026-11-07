class_name Goalkeeper
extends CharacterBody2D

const BASE_SPRITE_SCALE := Vector2(0.78, 0.78)
const BASE_SPRITE_OFFSET := Vector2(0, -42)

@export var player_id: String = "gk_bra"
@export var team_id: String = "team_user"
@export var goal_center: Vector2 = Vector2(1800, 0)
@export var goal_half_height: float = 120.0
@export var patrol_x: float = 1710.0

enum GKState {
	GUARD,
	DIVING,
	RECOVERING,
	HOLDING
}

var current_state: GKState = GKState.GUARD
var player_name: String = "El Guardián"
var role: String = "GK"
var portrait_path: String = ""
var icon_path: String = ""
var stats: Dictionary = {
	"reflejos": 88,
	"velocidad": 76,
	"control": 76,
	"pase": 80,
	"defensa": 90
}

# Goalkeeper Hissatsu ("gk_save")
var ability_name: String = "Mano Celestial"
var ability_type: String = "gk_save"
var ability_max_cooldown: float = 10.0
var ability_cooldown: float = 0.0
var ability_active_timer: float = 0.0
var dive_using_hissatsu: bool = false
var ai_difficulty: float = 1.0
var aurora_time: float = 0.0

var ball: Ball = null
var dive_timer: float = 0.0
var hold_timer: float = 0.0
var pickup_lock_timer: float = 0.0
var has_ball: bool = false
var is_user_controlled: bool = false
var facing_direction: Vector2 = Vector2.LEFT

@onready var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var shadow: Sprite2D = get_node_or_null("Shadow")
@onready var base_indicator: BaseIndicator2D = get_node_or_null("BaseIndicator2D")

signal shot_saved(gk: Goalkeeper)
signal gk_ability_activated(gk: Goalkeeper, ability_name: String, portrait_path: String)

func _ready() -> void:
	add_to_group("players")
	add_to_group("goalkeepers")
	collision_layer = 1
	collision_mask = 4
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.05
	_ensure_base_indicator()
	load_goalkeeper(player_id)

func _ensure_base_indicator() -> void:
	if not is_instance_valid(base_indicator):
		base_indicator = get_node_or_null("BaseIndicator2D") as BaseIndicator2D
	if not is_instance_valid(base_indicator):
		base_indicator = BaseIndicator2D.new()
		base_indicator.name = "BaseIndicator2D"
		add_child(base_indicator)
	base_indicator.set_selection_state(false, false)

func apply_kit(kit: KitData) -> void:
	if kit == null:
		return
	_ensure_base_indicator()
	if is_instance_valid(base_indicator):
		base_indicator.set_team_color(kit.get_effective_indicator_color())

func set_team_indicator_color(col: Color) -> void:
	_ensure_base_indicator()
	if is_instance_valid(base_indicator):
		base_indicator.set_team_color(col)

func reduce_ability_cooldown(amount: float) -> void:
	if ability_cooldown > 0.0:
		ability_cooldown = maxf(0.0, ability_cooldown - amount)
		queue_redraw()

func load_goalkeeper(p_id: String) -> void:
	player_id = p_id
	var file = FileAccess.open("res://data/players.json", FileAccess.READ)
	if not file:
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed or not parsed.has("players"):
		return

	var target_id := player_id
	if not parsed["players"].has(target_id):
		target_id = "gk_bra" if team_id == "team_user" else "gk_star"

	if not parsed["players"].has(target_id):
		return

	var p_data: Dictionary = parsed["players"][target_id]
	player_name = p_data.get("name", "Arquero")
	portrait_path = str(p_data.get("portrait", "res://assets/sprites/" + target_id + "_portrait.png"))
	icon_path = str(p_data.get("icon", "res://assets/sprites/" + target_id + "_icon.png"))
	if p_data.has("stats"):
		stats = p_data["stats"].duplicate(true)

	if p_data.has("ability") and p_data["ability"] is Dictionary:
		var ab: Dictionary = p_data["ability"]
		ability_name = str(ab.get("name", "Parada Suprema"))
		ability_type = str(ab.get("type", "gk_save"))
		ability_max_cooldown = float(ab.get("cooldown", 10.0))
	else:
		ability_name = "Parada Suprema"
		ability_type = "gk_save"
		ability_max_cooldown = 10.0

	ability_cooldown = 0.0
	ability_active_timer = 0.0
	dive_using_hissatsu = false
	_build_sprite_frames(p_data, target_id)
	queue_redraw()

func _build_sprite_frames(p_data: Dictionary, resolved_id: String) -> void:
	if not is_instance_valid(anim_sprite):
		anim_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if not is_instance_valid(shadow):
		shadow = get_node_or_null("Shadow") as Sprite2D
	if not is_instance_valid(anim_sprite):
		return

	var anim_json_path: String = p_data.get("anims", "res://data/anims/" + resolved_id + ".json")
	var sheet_path: String = p_data.get("sheet", "res://assets/sprites/" + resolved_id + "_aligned.png")

	if not FileAccess.file_exists(anim_json_path):
		return

	var a_file = FileAccess.open(anim_json_path, FileAccess.READ)
	var a_data = JSON.parse_string(a_file.get_as_text())
	var sheet_texture: Texture2D = null
	if ResourceLoader.exists(sheet_path):
		sheet_texture = load(sheet_path) as Texture2D
	elif FileAccess.file_exists(sheet_path):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(sheet_path)) == OK:
			sheet_texture = ImageTexture.create_from_image(img)
	if not sheet_texture:
		sheet_texture = load(sheet_path) as Texture2D
	if not sheet_texture:
		sheet_texture = load("res://assets/sprites/gk_bra_aligned.png") as Texture2D
	if not sheet_texture:
		return

	var sf = SpriteFrames.new()
	for existing in sf.get_animation_names():
		sf.remove_animation(existing)

	for anim_name in a_data["animations"].keys():
		var anim_info = a_data["animations"][anim_name]
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, float(anim_info.get("fps", 8)))
		sf.set_animation_loop(anim_name, bool(anim_info.get("loop", true)))

		for f in anim_info["frames"]:
			var rect_info = f["rect"]
			var atlas = AtlasTexture.new()
			atlas.atlas = sheet_texture
			atlas.region = Rect2(rect_info["x"], rect_info["y"], rect_info["w"], rect_info["h"])
			sf.add_frame(anim_name, atlas)

	anim_sprite.sprite_frames = sf
	anim_sprite.play("idle_down")
	anim_sprite.position = BASE_SPRITE_OFFSET
	anim_sprite.scale = BASE_SPRITE_SCALE
	if is_instance_valid(shadow):
		shadow.scale = BASE_SPRITE_SCALE
	anim_sprite.flip_h = false

func _physics_process(delta: float) -> void:
	aurora_time += delta
	if pickup_lock_timer > 0.0:
		pickup_lock_timer -= delta
	if ability_cooldown > 0.0:
		ability_cooldown = maxf(0.0, ability_cooldown - delta)
		queue_redraw()
	if ability_active_timer > 0.0:
		ability_active_timer = maxf(0.0, ability_active_timer - delta)
		queue_redraw()

	if not is_instance_valid(ball):
		var balls = get_tree().get_nodes_in_group("ball") if get_tree() != null else []
		if not balls.is_empty():
			ball = balls[0] as Ball

	match current_state:
		GKState.GUARD:
			_process_guard(delta)
		GKState.DIVING:
			_process_diving(delta)
		GKState.RECOVERING:
			_process_recovering(delta)
		GKState.HOLDING:
			_process_holding(delta)

func _get_effective_reflejos() -> float:
	var base_refl := float(stats.get("reflejos", 85))
	var bonus := clampf((ai_difficulty - 1.0) * 14.0, -4.0, 6.0)
	return clampf(base_refl + bonus, 15.0, 100.0)

func _process_guard(delta: float) -> void:
	if not is_instance_valid(ball):
		return

	var to_ball = ball.global_position - goal_center
	var target_y = 0.0
	var is_right_side = (patrol_x > 0)

	if (is_right_side and to_ball.x < -10.0) or (!is_right_side and to_ball.x > 10.0):
		var slope = to_ball.y / to_ball.x
		target_y = clampf((patrol_x - goal_center.x) * slope, -goal_half_height, goal_half_height)
	else:
		target_y = clampf(ball.global_position.y, -goal_half_height, goal_half_height)

	var target_x = patrol_x
	if ball.current_state == Ball.State.LIBRE and global_position.distance_to(ball.global_position) < 165.0:
		target_x = clampf(ball.global_position.x, patrol_x - 95.0, patrol_x + 95.0)
		target_y = clampf(ball.global_position.y, -goal_half_height * 1.25, goal_half_height * 1.25)

	var target_pos = Vector2(target_x, target_y)
	var move_diff = target_pos.y - global_position.y

	var refl = _get_effective_reflejos()
	var max_gk_speed = lerp(210.0, 340.0, clampf(refl / 100.0, 0.0, 1.0))

	if absf(move_diff) > 4.0:
		velocity.y = move_toward(velocity.y, signf(move_diff) * max_gk_speed, 1400.0 * delta)
	else:
		velocity.y = move_toward(velocity.y, 0.0, 1200.0 * delta)

	velocity.x = move_toward(velocity.x, (target_x - global_position.x) * 5.0, 1000.0 * delta)
	move_and_slide()

	facing_direction = Vector2.LEFT if is_right_side else Vector2.RIGHT

	if is_instance_valid(anim_sprite) and anim_sprite.sprite_frames:
		if absf(velocity.y) > 22.0:
			var side_anim = "walk_left" if (is_right_side and anim_sprite.sprite_frames.has_animation("walk_left")) else "walk_side"
			if anim_sprite.sprite_frames.has_animation(side_anim):
				anim_sprite.flip_h = (is_right_side and side_anim == "walk_side")
				anim_sprite.play(side_anim)
			elif anim_sprite.sprite_frames.has_animation("run_down"):
				anim_sprite.flip_h = false
				anim_sprite.play("run_down")
		elif anim_sprite.sprite_frames.has_animation("idle_down"):
			anim_sprite.flip_h = false
			anim_sprite.play("idle_down")

	var is_ball_threatening = false
	if ball.current_state == Ball.State.EN_VUELO:
		if is_right_side and ball.velocity.x > 160.0 and ball.global_position.x < patrol_x + 35.0:
			is_ball_threatening = true
		elif !is_right_side and ball.velocity.x < -160.0 and ball.global_position.x > patrol_x - 35.0:
			is_ball_threatening = true

	if is_ball_threatening:
		var dist_to_ball = global_position.distance_to(ball.global_position)
		var trigger_dist: float = 175.0 + refl * 0.85 if ball.is_super_shot else (160.0 + refl * 0.7)
		if dist_to_ball < trigger_dist:
			var wants_hissatsu: bool = ability_cooldown <= 0.0 and (ball.is_super_shot or ball.velocity.length() >= 960.0)
			_perform_dive(wants_hissatsu)

func _perform_dive(use_hissatsu: bool = false) -> void:
	current_state = GKState.DIVING
	dive_timer = 0.48 if use_hissatsu else 0.45
	dive_using_hissatsu = use_hissatsu

	if use_hissatsu:
		ability_cooldown = ability_max_cooldown
		ability_active_timer = 1.5
		emit_signal("gk_ability_activated", self, ability_name, portrait_path)
		queue_redraw()

	var is_right_side = (patrol_x > 0)
	var dive_up = ball.global_position.y < global_position.y
	var angle = deg_to_rad(-38.0 if dive_up else 38.0)
	if not is_right_side:
		angle = -angle

	if is_instance_valid(anim_sprite):
		anim_sprite.rotation = angle
		anim_sprite.scale = Vector2(BASE_SPRITE_SCALE.x * 1.25, BASE_SPRITE_SCALE.y * 0.78)

	var dir_x = -0.25 if is_right_side else 0.25
	var dive_dir = Vector2(dir_x, -1.0 if dive_up else 1.0).normalized()
	var dive_speed: float = 365.0 if use_hissatsu else 310.0
	velocity = dive_dir * dive_speed

func _process_diving(delta: float) -> void:
	dive_timer -= delta
	move_and_slide()

	if is_instance_valid(ball) and ball.current_state == Ball.State.EN_VUELO:
		var dist: float = global_position.distance_to(ball.global_position)
		var refl: float = _get_effective_reflejos()
		var base_save_reach: float = 46.0 + clampf(refl / 100.0, 0.0, 1.0) * 20.0
		var save_reach: float = base_save_reach * (1.38 if dive_using_hissatsu else 1.0)

		if dist <= save_reach:
			if ball.is_super_shot:
				var def_stat: float = float(stats.get("defensa", 88))
				var gk_power: float = refl * 0.65 + def_stat * 0.35 + (14.0 if dive_using_hissatsu else -28.0)
				var shot_pwr: float = ball.shot_power_rating if ball.shot_power_rating > 0.0 else 90.0
				var save_prob: float = clampf(0.55 + (gk_power - shot_pwr) * 0.014, 0.16, 0.86)
				if not dive_using_hissatsu:
					save_prob = minf(save_prob, 0.24)
				if randf() <= save_prob:
					_on_save_successful()
					return
				else:
					# Duel lost: prevent re-rolling on subsequent frames of the same dive
					dive_timer = 0.0
					current_state = GKState.RECOVERING
					return
			else:
				_on_save_successful()
				return

	if dive_timer <= 0.0:
		dive_using_hissatsu = false
		current_state = GKState.RECOVERING

func _on_save_successful() -> void:
	current_state = GKState.HOLDING
	hold_timer = 0.75
	has_ball = true
	dive_using_hissatsu = false
	ball.take_possession(self)
	emit_signal("shot_saved", self)

func _process_holding(delta: float) -> void:
	hold_timer -= delta
	velocity = Vector2.ZERO
	if is_instance_valid(anim_sprite):
		anim_sprite.rotation = rotate_toward(anim_sprite.rotation, 0.0, 8.0 * delta)
		anim_sprite.scale = anim_sprite.scale.move_toward(BASE_SPRITE_SCALE, 3.0 * delta)
	move_and_slide()

	if hold_timer <= 0.0:
		_clear_ball()

func _clear_ball() -> void:
	has_ball = false
	pickup_lock_timer = 0.55
	current_state = GKState.RECOVERING
	var is_right_side = (patrol_x > 0)
	var dir_x = -1.0 if is_right_side else 1.0

	var best_mate: Player = null
	var best_score: float = -9999.0
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p is Player and p.team_id == self.team_id:
			var dist = global_position.distance_to(p.global_position)
			var score = -dist * 0.35 + (120.0 if p.role == "DF" else (90.0 if p.role == "MF" else 20.0))
			if score > best_score:
				best_score = score
				best_mate = p

	if is_instance_valid(best_mate):
		facing_direction = (best_mate.global_position - global_position).normalized()
		ball.pass_to(best_mate, 780.0, self)
		ball.kick_cooldown = 0.45
		if team_id == "team_user" and not best_mate.is_ai:
			for p in get_tree().get_nodes_in_group("players"):
				if p is Player and p.team_id == "team_user":
					p.set_user_controlled(p == best_mate)
	else:
		var clear_dir = Vector2(dir_x, randf_range(-0.4, 0.4)).normalized()
		ball.kick(clear_dir, 740.0, self)
		ball.kick_cooldown = 0.45

func _process_recovering(delta: float) -> void:
	if is_instance_valid(anim_sprite):
		anim_sprite.rotation = rotate_toward(anim_sprite.rotation, 0.0, 6.0 * delta)
		anim_sprite.scale = anim_sprite.scale.move_toward(BASE_SPRITE_SCALE, 2.5 * delta)
	velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
	move_and_slide()

	if not is_instance_valid(anim_sprite) or (absf(anim_sprite.rotation) < 0.05 and anim_sprite.scale.distance_to(BASE_SPRITE_SCALE) < 0.03):
		if is_instance_valid(anim_sprite):
			anim_sprite.rotation = 0.0
			anim_sprite.scale = BASE_SPRITE_SCALE
		current_state = GKState.GUARD

func on_ball_possessed(_b: CharacterBody2D) -> void:
	has_ball = true
	if current_state != GKState.HOLDING:
		current_state = GKState.HOLDING
		hold_timer = 0.70

func on_ball_lost(_b: CharacterBody2D) -> void:
	has_ball = false

func _draw() -> void:
	if ability_cooldown > 0.0:
		var pct := clampf(ability_cooldown / maxf(0.1, ability_max_cooldown), 0.0, 1.0)
		var rect := Rect2(-20.0, -102.0, 40.0, 4.0)
		draw_rect(rect, Color(0.04, 0.05, 0.08, 0.88), true)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * (1.0 - pct), rect.size.y)), Color(0.95, 0.76, 0.22, 0.95), true)

	if ability_active_timer > 0.0:
		var pulse := 0.7 + 0.3 * sin(aurora_time * 14.0)
		draw_circle(Vector2(0, -18), 32.0, Color(0.98, 0.80, 0.20, 0.26 * pulse))
		draw_arc(Vector2(0, -12), 30.0, 0.0, TAU, 32, Color(1.0, 0.88, 0.30, 0.95), 3.2)
