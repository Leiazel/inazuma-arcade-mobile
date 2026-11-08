class_name Player
extends CharacterBody2D

## Player controller and physics engine for Inazuma Inspired Arcade Soccer.
## Preserves authoritative movement, sprint multipliers, dribbling control curves,
## slide tackle kinematics, pass/shot charging, and integrates BaseIndicator2D + KitData.

const BASE_SPRITE_SCALE := Vector2(0.78, 0.78)
const BASE_SPRITE_OFFSET := Vector2(0, -42)
const PASS_SHOT_HOLD_THRESHOLD: float = 0.26 # seconds (<0.26s = Pass, >=0.26s = Power Shot)
const HISSATSU_STARTUP_TIME: float = 0.20
const KitColorSwapShader: Shader = preload("res://shaders/kit_color_swap.gdshader")

static var _extra_inputs_registered: bool = false
static var _players_db_cache: Dictionary = {}
static var _players_db_loaded: bool = false
static var _roster_fallback_cache: Array = []
static var _roster_fallback_loaded: bool = false
static var _anim_json_cache: Dictionary = {}
static var _sprite_frames_pool: Dictionary = {}
static var _live_actor_count: int = 0

@export_group("Identity")
@export var player_id: String = "bra_01"
@export var team_id: String = "team_user"
@export var is_user_controlled: bool = true
@export var is_ai: bool = false
@export var target_goal_x: float = 1800.0 # Attack direction target (+1800 or -1800)

@export_group("Field Invariants")
@export var field_half_width: float = 1800.0
@export var field_half_height: float = 1080.0

# Player attributes (Scale 1-100)
var player_name: String = "Jugador"
var role: String = "FW" # "DF", "MF", "FW"
var portrait_path: String = ""
var icon_path: String = ""
var ai_difficulty: float = 1.0
var stats: Dictionary = {
	"velocidad": 80,
	"control": 80,
	"pase": 80,
	"tiro": 80,
	"defensa": 80
}

# Special Ability / Hissatsu
var ability_name: String = "Impulso Dorado"
var ability_type: String = "dribble" # "shot", "dribble", "pass", "defense"
var ability_max_cooldown: float = 8.0
var ability_desc: String = ""
var ability_cooldown: float = 0.0
var ability_active_timer: float = 0.0
var hissatsu_windup_timer: float = 0.0
var _hissatsu_pending: bool = false

# Kinematics and orientation
var facing_direction: Vector2 = Vector2.DOWN
var last_anim_dir: String = "down"
var last_flip_h: bool = false
var is_moving: bool = false
var is_sprinting: bool = false
var is_kicking: bool = false
var kick_anim_timer: float = 0.0

var has_ball: bool = false
var current_ball: CharacterBody2D = null
var match_players_ref: Array = []
var match_gks_ref: Array = []

# Passing and shooting
var pass_press_time: float = 0.0
var is_charging_action: bool = false
var _shot_rearm_required: bool = false
var _prev_action_pressed: Dictionary = {}
var _consumed_action_frame: Dictionary = {}
var _overlay_dirty_active: bool = false
var current_pass_target: Player = null
var is_targeted_for_pass: bool = false

# Tackles, collision, stumble
var tackle_cooldown: float = 0.0
var stumble_timer: float = 0.0
var pickup_lock_timer: float = 0.0
var pass_receive_grace_timer: float = 0.0
var virtual_move_vector := Vector2.ZERO
var manual_drag_active := false
var manual_drag_target := Vector2.ZERO
var command_move_active := false
var command_move_target := Vector2.ZERO

# Slide tackle kinematics
var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_recovery_timer: float = 0.0
var slide_max_recovery: float = 0.85
var slide_cooldown: float = 0.0
var slide_max_cooldown: float = 3.5
var slide_direction: Vector2 = Vector2.RIGHT
var slide_hit_done: bool = false

# AI States
enum AIState {
	GUARDAR_POSICION,
	BUSCAR_PELOTA,
	DESMARCARSE,
	CORTAR,
	APOYAR
}
var ai_state: AIState = AIState.GUARDAR_POSICION
var home_position: Vector2 = Vector2.ZERO
var ai_decision_timer: float = 0.0
var aurora_time: float = 0.0

# Child node references
@onready var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var shadow: Sprite2D = get_node_or_null("Shadow")
@onready var base_indicator: BaseIndicator2D = get_node_or_null("BaseIndicator2D")

signal player_loaded(player_data: Dictionary)
signal pass_initiated(from_player: Player, to_player: Player, power: float)
signal shot_charge_started(player: Player)
signal shot_executed(player: Player, speed: float, charge_factor: float)
signal ball_stolen(tackler: Player, victim: Player)
signal slide_tackle_executed(player: Player, success: bool)
signal ability_activated(player: Player, ability_name: String, ability_type: String)
signal ability_impact(player: Player, ability_name: String, ability_type: String, hit_connected: bool)

static func register_actor_instance() -> void:
	_live_actor_count += 1

static func unregister_actor_instance() -> void:
	_live_actor_count = maxi(0, _live_actor_count - 1)
	if _live_actor_count == 0:
		_sprite_frames_pool.clear()

static func get_cached_players_db() -> Dictionary:
	if not _players_db_loaded:
		_players_db_loaded = true
		if FileAccess.file_exists("res://data/players.json"):
			var file := FileAccess.open("res://data/players.json", FileAccess.READ)
			if file:
				var parsed = JSON.parse_string(file.get_as_text())
				if parsed is Dictionary and parsed.has("players") and parsed["players"] is Dictionary:
					_players_db_cache = parsed["players"]
	return _players_db_cache

static func get_or_build_sprite_frames(anim_json_path: String, sheet_path: String, fallback_sheet_path: String) -> SpriteFrames:
	var cache_key := anim_json_path + "|" + sheet_path
	if _sprite_frames_pool.has(cache_key):
		return _sprite_frames_pool[cache_key] as SpriteFrames

	var a_data: Dictionary = {}
	if _anim_json_cache.has(anim_json_path):
		a_data = _anim_json_cache[anim_json_path]
	else:
		if not FileAccess.file_exists(anim_json_path):
			return null
		var a_file := FileAccess.open(anim_json_path, FileAccess.READ)
		if not a_file:
			return null
		var parsed_anim = JSON.parse_string(a_file.get_as_text())
		if not (parsed_anim is Dictionary) or not parsed_anim.has("animations"):
			return null
		a_data = parsed_anim
		_anim_json_cache[anim_json_path] = a_data

	var sheet_texture: Texture2D = null
	if ResourceLoader.exists(sheet_path):
		sheet_texture = load(sheet_path) as Texture2D
	elif FileAccess.file_exists(sheet_path):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(sheet_path)) == OK:
			sheet_texture = ImageTexture.create_from_image(img)
	if not sheet_texture:
		sheet_texture = load(sheet_path) as Texture2D
	if not sheet_texture and not fallback_sheet_path.is_empty():
		sheet_texture = load(fallback_sheet_path) as Texture2D
	if not sheet_texture:
		return null

	var sf := SpriteFrames.new()
	for existing_anim in sf.get_animation_names():
		sf.remove_animation(existing_anim)

	var anims_dict: Dictionary = a_data["animations"]
	for anim_name in anims_dict.keys():
		var anim_info: Dictionary = anims_dict[anim_name]
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, float(anim_info.get("fps", 8)))
		sf.set_animation_loop(anim_name, bool(anim_info.get("loop", true)))

		for f in anim_info["frames"]:
			var rect_info: Dictionary = f["rect"]
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet_texture
			atlas.region = Rect2(rect_info["x"], rect_info["y"], rect_info["w"], rect_info["h"])
			sf.add_frame(anim_name, atlas)

	if _live_actor_count > 0:
		_sprite_frames_pool[cache_key] = sf
	return sf

func _init() -> void:
	register_actor_instance()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		unregister_actor_instance()

func _ready() -> void:
	add_to_group("players")
	collision_layer = 1
	collision_mask = 4
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.05
	home_position = global_position
	_ensure_extra_inputs()
	_ensure_base_indicator()
	load_player(player_id)

func _get_match_players() -> Array:
	if not match_players_ref.is_empty():
		return match_players_ref
	var tree := get_tree()
	return tree.get_nodes_in_group("players") if tree != null else []

func _get_match_goalkeepers() -> Array:
	if not match_gks_ref.is_empty():
		return match_gks_ref
	var tree := get_tree()
	return tree.get_nodes_in_group("goalkeepers") if tree != null else []

func _needs_overlay_draw() -> bool:
	return (
		ability_cooldown > 0.0
		or _hissatsu_pending
		or ability_active_timer > 0.0
		or is_sliding
		or slide_recovery_timer > 0.0
		or (is_charging_action and pass_press_time > 0.04)
	)

func _refresh_overlay_redraw() -> void:
	var active := _needs_overlay_draw()
	if active or _overlay_dirty_active:
		_overlay_dirty_active = active
		queue_redraw()

func _ensure_base_indicator() -> void:
	if not is_instance_valid(base_indicator):
		base_indicator = get_node_or_null("BaseIndicator2D") as BaseIndicator2D
	if not is_instance_valid(base_indicator):
		base_indicator = BaseIndicator2D.new()
		base_indicator.name = "BaseIndicator2D"
		add_child(base_indicator)
	base_indicator.set_selection_state(is_user_controlled, is_targeted_for_pass)

## Binds team KitData colors to the palette swap shader and foot base indicator
func apply_kit(kit: KitData) -> void:
	if kit == null:
		return
	_ensure_base_indicator()
	if is_instance_valid(base_indicator):
		base_indicator.set_team_color(kit.get_effective_indicator_color())

	if not is_instance_valid(anim_sprite):
		anim_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if is_instance_valid(anim_sprite):
		var mat = anim_sprite.material as ShaderMaterial
		if mat == null and KitColorSwapShader != null:
			mat = ShaderMaterial.new()
			mat.shader = KitColorSwapShader
			anim_sprite.material = mat
		if mat:
			kit.apply_to_material(mat)

## Alias for apply_kit
func set_kit_data(kit: KitData) -> void:
	apply_kit(kit)

func reduce_ability_cooldown(amount: float) -> void:
	if ability_cooldown > 0.0:
		ability_cooldown = maxf(0.0, ability_cooldown - amount)
		_refresh_overlay_redraw()

static func _bind_key(action: String, physical_kc: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_kc
	InputMap.action_add_event(action, ev)

static func _bind_joy_button(action: String, btn: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	InputMap.action_add_event(action, ev)

static func _bind_joy_axis(action: String, axis: JoyAxis, axis_val: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = axis_val
	InputMap.action_add_event(action, ev)

func _ensure_extra_inputs() -> void:
	for act in ["move_left", "move_right", "move_up", "move_down", "sprint", "switch_player", "action_ability", "action_shot", "action_pass", "action_slide", "action_primary", "action_secondary", "pause_game"]:
		if not InputMap.has_action(act):
			InputMap.add_action(act)

	if _extra_inputs_registered:
		return
	_extra_inputs_registered = true

	# Ergonomic Keyboard Two-Hand Layouts (WASD + J/K/L/U & Arrows + Z/X/C/Q)
	_bind_key("action_pass", KEY_J)
	_bind_key("action_pass", KEY_Z)
	_bind_key("action_shot", KEY_K)
	_bind_key("action_shot", KEY_X)
	_bind_key("action_slide", KEY_K)
	_bind_key("action_slide", KEY_X)
	_bind_key("action_ability", KEY_L)
	_bind_key("action_ability", KEY_C)
	_bind_key("switch_player", KEY_TAB)
	_bind_key("switch_player", KEY_U)
	_bind_key("switch_player", KEY_Q)
	_bind_key("pause_game", KEY_ESCAPE)
	_bind_key("pause_game", KEY_P)

	# Full Gamepad Support (Left Stick + D-Pad + Face & Shoulder Buttons)
	_bind_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_bind_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_bind_joy_button("move_left", JOY_BUTTON_DPAD_LEFT)
	_bind_joy_button("move_right", JOY_BUTTON_DPAD_RIGHT)
	_bind_joy_button("move_up", JOY_BUTTON_DPAD_UP)
	_bind_joy_button("move_down", JOY_BUTTON_DPAD_DOWN)

	_bind_joy_button("action_pass", JOY_BUTTON_A)
	_bind_joy_button("action_shot", JOY_BUTTON_X)
	_bind_joy_button("action_shot", JOY_BUTTON_B)
	_bind_joy_button("action_slide", JOY_BUTTON_X)
	_bind_joy_button("action_slide", JOY_BUTTON_B)
	_bind_joy_button("action_ability", JOY_BUTTON_Y)
	_bind_joy_button("switch_player", JOY_BUTTON_LEFT_SHOULDER)
	_bind_joy_button("sprint", JOY_BUTTON_RIGHT_SHOULDER)
	_bind_joy_button("pause_game", JOY_BUTTON_START)

func set_home_position(pos: Vector2) -> void:
	home_position = pos
	global_position = pos
	velocity = Vector2.ZERO
	is_sliding = false
	slide_timer = 0.0
	slide_recovery_timer = 0.0
	is_charging_action = false
	pass_press_time = 0.0
	_hissatsu_pending = false
	hissatsu_windup_timer = 0.0
	if is_instance_valid(anim_sprite):
		anim_sprite.rotation = 0.0
		anim_sprite.position = BASE_SPRITE_OFFSET
		anim_sprite.scale = BASE_SPRITE_SCALE

func load_player(p_id: String) -> void:
	player_id = p_id
	var p_data: Dictionary = {}

	# 1. Check cached data/players.json
	var players_db := get_cached_players_db()
	if players_db.has(player_id):
		p_data = players_db[player_id]

	# 2. Check players_roster.json if not found
	if p_data.is_empty():
		if not _roster_fallback_loaded:
			_roster_fallback_loaded = true
			if FileAccess.file_exists("res://players_roster.json"):
				var file_r := FileAccess.open("res://players_roster.json", FileAccess.READ)
				if file_r:
					var parsed_r = JSON.parse_string(file_r.get_as_text())
					if parsed_r is Dictionary and parsed_r.has("players") and parsed_r["players"] is Array:
						_roster_fallback_cache = parsed_r["players"]
		for cand in _roster_fallback_cache:
			if cand.get("id") == player_id:
				p_data = {
					"name": cand.get("nombre", "Jugador"),
					"role": cand.get("posicion", "FW"),
					"stats": {
						"velocidad": cand.get("estadisticas", {}).get("base", {}).get("rapidez", 80),
						"control": cand.get("estadisticas", {}).get("base", {}).get("control", 80),
						"pase": cand.get("estadisticas", {}).get("base", {}).get("control", 80),
						"tiro": cand.get("estadisticas", {}).get("base", {}).get("tiro", 80),
						"defensa": cand.get("estadisticas", {}).get("base", {}).get("defensa", 80)
					}
				}
				break

	# 3. Fallback to default player if still not found
	if p_data.is_empty():
		var is_gk: bool = player_id.contains("gk") or role == "GK"
		var is_away_id: bool = player_id.contains("away") or player_id.contains("opp") or player_id.contains("rival") or team_id == "team_opp" or team_id == "team_away"
		var fallback_id: String = ("gk_star" if is_away_id else "gk_bra") if is_gk else ("star_01" if is_away_id else "bra_01")
		if players_db.has(fallback_id):
			p_data = players_db[fallback_id]
			player_id = fallback_id

	if not p_data.is_empty():
		player_name = p_data.get("name", "Jugador")
		role = p_data.get("role", "FW")
		portrait_path = str(p_data.get("portrait", "res://assets/sprites/" + player_id + "_portrait.png"))
		icon_path = str(p_data.get("icon", "res://assets/sprites/" + player_id + "_icon.png"))
		if p_data.has("stats"):
			stats = p_data["stats"].duplicate(true)

		if p_data.has("ability") and p_data["ability"] is Dictionary:
			var ab: Dictionary = p_data["ability"]
			ability_name = ab.get("name", "Impulso Dorado")
			ability_type = ab.get("type", "dribble")
			ability_max_cooldown = float(ab.get("cooldown", 8.0))
			ability_desc = ab.get("description", "")
		else:
			ability_name = "Impulso Dorado"
			ability_type = "dribble"
			ability_max_cooldown = 8.0
			ability_desc = ""

		_build_sprite_frames(p_data)
		emit_signal("player_loaded", p_data)

	ability_cooldown = 0.0
	ability_active_timer = 0.0
	_hissatsu_pending = false
	hissatsu_windup_timer = 0.0
	_overlay_dirty_active = true
	_refresh_overlay_redraw()

func _build_sprite_frames(p_data: Dictionary) -> void:
	if not is_instance_valid(anim_sprite):
		anim_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if not is_instance_valid(shadow):
		shadow = get_node_or_null("Shadow") as Sprite2D
	if not is_instance_valid(anim_sprite):
		return

	var anim_json_path: String = p_data.get("anims", "res://data/anims/" + player_id + ".json")
	var sheet_path: String = p_data.get("sheet", "res://assets/sprites/" + player_id + "_aligned.png")

	if not _anim_json_cache.has(anim_json_path) and not FileAccess.file_exists(anim_json_path):
		var is_gk: bool = player_id.contains("gk") or role == "GK"
		var fb_prefix: String = "gk_bra" if is_gk else "bra_01"
		anim_json_path = "res://data/anims/" + fb_prefix + ".json"
		sheet_path = "res://assets/sprites/" + fb_prefix + "_aligned.png"

	var sf := get_or_build_sprite_frames(anim_json_path, sheet_path, "res://assets/sprites/bra_01_aligned.png")
	if sf == null:
		return

	anim_sprite.sprite_frames = sf
	if sf.has_animation("idle_down"):
		anim_sprite.play("idle_down")
	elif sf.get_animation_names().size() > 0:
		anim_sprite.play(sf.get_animation_names()[0])
	anim_sprite.position = BASE_SPRITE_OFFSET
	anim_sprite.scale = BASE_SPRITE_SCALE
	anim_sprite.visible = true
	anim_sprite.rotation = 0.0
	if is_instance_valid(shadow):
		shadow.scale = BASE_SPRITE_SCALE

func set_user_controlled(controlled: bool) -> void:
	is_user_controlled = controlled
	if not is_user_controlled:
		is_charging_action = false
		pass_press_time = 0.0
		_set_target_receiver(null)
	else:
		_shot_rearm_required = Input.is_action_pressed("action_shot") or Input.is_action_pressed("action_primary")
	_ensure_base_indicator()
	if is_instance_valid(base_indicator):
		base_indicator.set_selection_state(is_user_controlled, is_targeted_for_pass)
	_refresh_overlay_redraw()

func _is_gk_holding_ball() -> bool:
	if not is_instance_valid(current_ball):
		return false
	if current_ball.get("current_state") != null and int(current_ball.get("current_state")) != 1:
		return false
	var c = current_ball.get("carrier")
	return is_instance_valid(c) and c.is_in_group("goalkeepers")

func _physics_process(delta: float) -> void:
	aurora_time += delta

	if not is_instance_valid(current_ball):
		var tree := get_tree()
		if tree != null:
			var balls := tree.get_nodes_in_group("ball")
			if not balls.is_empty():
				current_ball = balls[0] as CharacterBody2D

	if tackle_cooldown > 0.0:
		tackle_cooldown -= delta
	if stumble_timer > 0.0:
		stumble_timer -= delta
	if pickup_lock_timer > 0.0:
		pickup_lock_timer -= delta
	if pass_receive_grace_timer > 0.0:
		pass_receive_grace_timer -= delta
	if slide_cooldown > 0.0:
		slide_cooldown -= delta
	if ability_cooldown > 0.0:
		ability_cooldown = maxf(0.0, ability_cooldown - delta)
	if ability_active_timer > 0.0:
		ability_active_timer = maxf(0.0, ability_active_timer - delta)

	# Process Hissatsu STARTUP -> ACTIVE phase completion
	if _hissatsu_pending:
		hissatsu_windup_timer -= delta
		velocity = velocity.move_toward(facing_direction * (_get_base_speed() * 0.45), 1400.0 * delta)
		move_and_slide()
		_clamp_inside_field()
		if hissatsu_windup_timer <= 0.0:
			_hissatsu_pending = false
			_execute_hissatsu_payload()
		_refresh_overlay_redraw()
		return

	if is_kicking:
		kick_anim_timer -= delta
		if kick_anim_timer <= 0.0:
			is_kicking = false

	# Process active slide or recovery state
	if is_sliding:
		_process_sliding(delta)
		_clamp_inside_field()
		_refresh_overlay_redraw()
		return
	elif slide_recovery_timer > 0.0:
		_process_slide_recovery(delta)
		_clamp_inside_field()
		_refresh_overlay_redraw()
		return

	# Proximity tackle check
	_check_tackle_attempt()

	if is_user_controlled and not is_ai:
		_process_user_controlled(delta)
	else:
		_process_positional_ai(delta)

	# Soft player separation
	_apply_soft_player_collisions(delta)
	_clamp_inside_field()

	_update_animation()
	_refresh_overlay_redraw()

# ==============================================================================
# SLIDE TACKLE MECHANICS
# ==============================================================================
func can_slide_tackle() -> bool:
	return (
		not has_ball
		and not is_sliding
		and not _hissatsu_pending
		and slide_recovery_timer <= 0.0
		and slide_cooldown <= 0.0
		and stumble_timer <= 0.0
		and not is_kicking
	)

func _start_slide_tackle() -> void:
	if not can_slide_tackle():
		return

	is_sliding = true
	slide_timer = 0.32
	slide_cooldown = slide_max_cooldown
	slide_hit_done = false
	is_moving = true

	var dir := facing_direction.normalized()
	if dir.length() < 0.1:
		dir = Vector2.RIGHT if target_goal_x > 0 else Vector2.LEFT

	if velocity.length() < 30.0 and is_instance_valid(current_ball) and not _is_gk_holding_ball():
		var to_ball = current_ball.global_position - global_position
		if to_ball.length() < 200.0 and to_ball.length() > 5.0:
			dir = to_ball.normalized()
			facing_direction = dir

	slide_direction = dir
	velocity = slide_direction * (_get_base_speed() * 1.72)

	if is_instance_valid(anim_sprite):
		var tilt_sign := -1.0 if slide_direction.x < 0.0 else 1.0
		anim_sprite.rotation = deg_to_rad(68.0 * tilt_sign)
		anim_sprite.position = BASE_SPRITE_OFFSET + Vector2(0, 15)
		anim_sprite.scale = Vector2(BASE_SPRITE_SCALE.x * 1.15, BASE_SPRITE_SCALE.y * 0.82)

	_check_slide_tackle_hit()

func _process_sliding(delta: float) -> void:
	slide_timer -= delta
	velocity = velocity.move_toward(slide_direction * (_get_base_speed() * 0.65), 750.0 * delta)
	move_and_slide()

	if not slide_hit_done:
		_check_slide_tackle_hit()

	if slide_timer <= 0.0:
		is_sliding = false
		slide_max_recovery = 0.52 if slide_hit_done else 0.92
		slide_recovery_timer = slide_max_recovery
		velocity = Vector2.ZERO
		if not slide_hit_done:
			emit_signal("slide_tackle_executed", self, false)

func _process_slide_recovery(delta: float) -> void:
	slide_recovery_timer -= delta
	velocity = velocity.move_toward(Vector2.ZERO, 1400.0 * delta)
	move_and_slide()

	if is_instance_valid(anim_sprite):
		var t := 1.0 - clampf(slide_recovery_timer / maxf(0.01, slide_max_recovery), 0.0, 1.0)
		if t > 0.55:
			anim_sprite.rotation = lerp_angle(anim_sprite.rotation, 0.0, 10.0 * delta)
			anim_sprite.position = anim_sprite.position.lerp(BASE_SPRITE_OFFSET, 10.0 * delta)
			anim_sprite.scale = anim_sprite.scale.lerp(BASE_SPRITE_SCALE, 10.0 * delta)

	if slide_recovery_timer <= 0.0:
		slide_recovery_timer = 0.0
		if is_instance_valid(anim_sprite):
			anim_sprite.rotation = 0.0
			anim_sprite.position = BASE_SPRITE_OFFSET
			anim_sprite.scale = BASE_SPRITE_SCALE

func _check_slide_tackle_hit() -> void:
	if not is_instance_valid(current_ball):
		return

	if _is_gk_holding_ball():
		return

	var ball_state = current_ball.get("current_state")
	if ball_state != null and int(ball_state) == 1: # CONTROLADA
		var carrier = current_ball.get("carrier") as Player
		if not is_instance_valid(carrier) or carrier.team_id == self.team_id:
			return
		if carrier._hissatsu_pending or (carrier.ability_active_timer > 0.0 and carrier.ability_type in ["dribble", "defense"]):
			return

		var dist = global_position.distance_to(carrier.global_position)
		if dist <= 50.0:
			slide_hit_done = true
			var def_stat = float(stats.get("defensa", 60))
			var ctrl_stat = float(carrier.stats.get("control", 60))
			var steal_chance = clampf(0.72 + (def_stat - ctrl_stat) * 0.008, 0.38, 0.94)

			if randf() < steal_chance:
				var push_away = (carrier.global_position - global_position).normalized()
				if push_away.length() < 0.1:
					push_away = slide_direction
				carrier.stumble(push_away, 0.82)
				current_ball.call("take_possession", self)
				emit_signal("ball_stolen", self, carrier)
				emit_signal("slide_tackle_executed", self, true)
			else:
				tackle_cooldown = 0.75
				emit_signal("slide_tackle_executed", self, false)

	elif ball_state != null and int(ball_state) == 0: # LIBRE
		var dist_ball = global_position.distance_to(current_ball.global_position)
		if dist_ball <= 46.0 and pickup_lock_timer <= 0.0:
			slide_hit_done = true
			current_ball.call("take_possession", self)
			emit_signal("slide_tackle_executed", self, true)

# ==============================================================================
# HISSATSU SPECIAL ABILITY (4-PHASE SYNCED)
# ==============================================================================
func can_use_ability() -> bool:
	return (
		ability_cooldown <= 0.0
		and not _hissatsu_pending
		and not is_sliding
		and slide_recovery_timer <= 0.0
		and stumble_timer <= 0.0
		and not is_kicking
	)

func _activate_special_ability() -> void:
	if not can_use_ability():
		return

	is_charging_action = false
	pass_press_time = 0.0
	ability_cooldown = ability_max_cooldown
	ability_active_timer = 2.6
	_hissatsu_pending = true
	hissatsu_windup_timer = HISSATSU_STARTUP_TIME

	# Orient player toward tactical target during STARTUP windup
	match ability_type:
		"shot":
			if has_ball:
				facing_direction = (Vector2(target_goal_x, 0.0) - global_position).normalized()
			elif is_instance_valid(current_ball) and not _is_gk_holding_ball():
				facing_direction = (current_ball.global_position - global_position).normalized()
		"pass":
			if has_ball:
				var mate := _find_best_pass_target()
				if is_instance_valid(mate):
					facing_direction = (mate.global_position - global_position).normalized()
		"defense":
			if not has_ball and is_instance_valid(current_ball) and not _is_gk_holding_ball():
				var diff := current_ball.global_position - global_position
				if diff.length() > 2.0:
					facing_direction = diff.normalized()

	emit_signal("ability_activated", self, ability_name, ability_type)
	_refresh_overlay_redraw()

func _execute_hissatsu_payload() -> void:
	var connected: bool = false

	match ability_type:
		"shot":
			if has_ball and is_instance_valid(current_ball):
				is_kicking = true
				kick_anim_timer = 0.38
				if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("kick"):
					anim_sprite.flip_h = (target_goal_x < 0.0)
					anim_sprite.play("kick")

				var aim_y: float = randf_range(-78.0, 78.0)
				for gk in _get_match_goalkeepers():
					if is_instance_valid(gk) and gk.get("team_id") != self.team_id:
						aim_y = -82.0 if gk.global_position.y >= 0.0 else 82.0
						break

				var goal_pt := Vector2(target_goal_x, aim_y)
				var shot_dir := (goal_pt - global_position).normalized()
				facing_direction = shot_dir

				var tiro_stat = float(stats.get("tiro", 85))
				var super_speed = lerp(1280.0, 1520.0, clampf(tiro_stat / 100.0, 0.0, 1.0))
				current_ball.call("activate_super_effect", 1.5, Color(1.0, 0.42, 0.14, 0.96), true, tiro_stat)
				current_ball.call("kick", shot_dir, super_speed, self)
				connected = true
			else:
				ability_active_timer = 2.4
				if is_instance_valid(current_ball) and not _is_gk_holding_ball():
					facing_direction = (current_ball.global_position - global_position).normalized()
					velocity = facing_direction * (_get_base_speed() * 1.55)

		"dribble":
			ability_active_timer = 2.6
			for p in _get_match_players():
				if p is Player and p.team_id != self.team_id:
					var opp := p as Player
					var in_cone := SkillStateMachine.is_target_in_action_sector(global_position, facing_direction, opp.global_position, 130.0, 75.0)
					if in_cone or global_position.distance_squared_to(opp.global_position) < 9216.0:
						var push_dir := (opp.global_position - global_position).normalized()
						opp.stumble(push_dir, 0.78)
						connected = true
			velocity = facing_direction * (_get_base_speed() * 1.52)
			if has_ball:
				connected = true

		"pass":
			if has_ball and is_instance_valid(current_ball):
				var mate := _find_best_pass_target()
				var dist_goal := global_position.distance_to(Vector2(target_goal_x, 0.0))
				if is_instance_valid(mate) and dist_goal > 520.0:
					is_kicking = true
					kick_anim_timer = 0.30
					facing_direction = (mate.global_position - global_position).normalized()
					if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("kick"):
						anim_sprite.flip_h = facing_direction.x < -0.05
						anim_sprite.play("kick")
					current_ball.call("activate_super_effect", 1.25, Color(0.28, 0.92, 0.45, 0.95), false, 80.0)
					current_ball.call("pass_to", mate, 1140.0, self)
					mate.ability_active_timer = maxf(mate.ability_active_timer, 1.6)
					if is_user_controlled and not is_ai:
						mate.set_user_controlled(true)
						set_user_controlled(false)
					connected = true
				else:
					var aim_y := -75.0 if global_position.y >= 0.0 else 75.0
					var shot_dir := (Vector2(target_goal_x, aim_y) - global_position).normalized()
					facing_direction = shot_dir
					var tiro_stat := float(stats.get("tiro", 82))
					current_ball.call("activate_super_effect", 1.35, Color(1.0, 0.88, 0.28, 0.95), true, tiro_stat)
					current_ball.call("kick", shot_dir, 1280.0, self)
					connected = true
			else:
				ability_active_timer = 2.5
				velocity = facing_direction * (_get_base_speed() * 1.42)

		"defense":
			ability_active_timer = 2.5
			if not has_ball and is_instance_valid(current_ball) and not _is_gk_holding_ball():
				var ball_state = current_ball.get("current_state")
				if ball_state != null and int(ball_state) == 1:
					var carrier = current_ball.get("carrier") as Player
					if is_instance_valid(carrier) and carrier.team_id != self.team_id:
						var in_sector := SkillStateMachine.is_target_in_action_sector(global_position, facing_direction, carrier.global_position, 145.0, 70.0)
						if in_sector or global_position.distance_squared_to(carrier.global_position) <= 15625.0:
							var push_away = (carrier.global_position - global_position).normalized()
							carrier.stumble(push_away, 0.90)
							current_ball.call("take_possession", self)
							emit_signal("ball_stolen", self, carrier)
							connected = true
				elif ball_state != null and int(ball_state) == 0:
					if global_position.distance_squared_to(current_ball.global_position) <= 15625.0:
						current_ball.call("take_possession", self)
						connected = true

	emit_signal("ability_impact", self, ability_name, ability_type, connected)
	_refresh_overlay_redraw()

# ==============================================================================
# SOFT COLLISION AND NORMAL TACKLE
# ==============================================================================
func _apply_soft_player_collisions(delta: float) -> void:
	var push_vec := Vector2.ZERO
	var min_dist: float = 28.0
	var gk_holding := _is_gk_holding_ball()
	var gk_carrier: Object = current_ball.get("carrier") if (gk_holding and is_instance_valid(current_ball)) else null

	for node in _get_match_players():
		if node == self or not is_instance_valid(node):
			continue
		var other := node as Node2D
		if not other:
			continue

		var eff_min_dist := 115.0 if (gk_holding and other == gk_carrier) else min_dist
		var diff := global_position - other.global_position
		var dist_sq := diff.length_squared()
		if dist_sq < eff_min_dist * eff_min_dist:
			var dist := sqrt(dist_sq)
			var dir := (diff / dist) if dist > 0.01 else Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			var overlap := eff_min_dist - dist
			push_vec += dir * (overlap * 16.0)

	if push_vec.length_squared() > 0.0001:
		global_position += push_vec * delta

func _clamp_inside_field() -> void:
	var margin_x: float = 18.0
	var margin_y: float = 18.0
	global_position.x = clampf(global_position.x, -field_half_width + margin_x, field_half_width - margin_x)
	global_position.y = clampf(global_position.y, -field_half_height + margin_y, field_half_height - margin_y)

func _check_tackle_attempt() -> void:
	if tackle_cooldown > 0.0 or has_ball or stumble_timer > 0.0 or pickup_lock_timer > 0.0:
		return

	if not is_instance_valid(current_ball):
		return
	var ball_state = current_ball.get("current_state")
	if ball_state == null or int(ball_state) != 1:
		return

	if _is_gk_holding_ball():
		return

	var carrier = current_ball.get("carrier") as Player
	if not is_instance_valid(carrier) or carrier.team_id == self.team_id:
		return

	if carrier._hissatsu_pending or (carrier.ability_active_timer > 0.0 and carrier.ability_type in ["dribble", "defense"]):
		return

	if global_position.distance_squared_to(carrier.global_position) <= 1156.0: # 34^2
		tackle_cooldown = 0.75
		_execute_tackle(carrier)

func _execute_tackle(carrier: Player) -> void:
	var def_stat = float(stats.get("defensa", 50))
	var ctrl_stat = float(carrier.stats.get("control", 50))

	# Authoritative steal probability: P(steal) = clamp(0.50 + (def - ctrl) * 0.008, 0.18, 0.85)
	var steal_chance = clampf(0.50 + (def_stat - ctrl_stat) * 0.008, 0.18, 0.85)

	if randf() < steal_chance:
		var push_away = (carrier.global_position - global_position).normalized()
		if push_away.length() < 0.1:
			push_away = -facing_direction
		carrier.stumble(push_away)
		current_ball.call("take_possession", self)
		emit_signal("ball_stolen", self, carrier)
	else:
		tackle_cooldown = 0.55

func stumble(push_dir: Vector2 = Vector2.ZERO, custom_duration: float = 0.42) -> void:
	stumble_timer = custom_duration
	pickup_lock_timer = custom_duration + 0.15 # 0.57s lock
	is_charging_action = false
	pass_press_time = 0.0
	if push_dir.length() > 0.05:
		velocity = push_dir.normalized() * 145.0
	else:
		velocity = velocity * 0.25

func _get_base_speed() -> float:
	var vel_stat = float(stats.get("velocidad", 75))
	var speed = lerp(235.0, 325.0, clampf(vel_stat / 100.0, 0.0, 1.0))
	if has_ball:
		var ctrl_stat = float(stats.get("control", 75))
		speed *= lerp(0.95, 1.0, clampf(ctrl_stat / 100.0, 0.0, 1.0))
	if is_ai and ai_difficulty != 1.0:
		# Fair difficulty speed scaling: soft range [0.92, 1.06] so Boss feels sharp without unfair speed cheats
		speed *= clampf(1.0 + (ai_difficulty - 1.0) * 0.15, 0.92, 1.06)
	if ability_active_timer > 0.0:
		speed *= 1.38
	return speed

func _poll_action_edge(act: String) -> bool:
	var pressed_now: bool = Input.is_action_pressed(act)
	var was_pressed: bool = bool(_prev_action_pressed.get(act, false))
	_prev_action_pressed[act] = pressed_now
	var cur_frame: int = Engine.get_process_frames()
	if pressed_now and not was_pressed:
		_consumed_action_frame[act] = cur_frame
		return true
	if not pressed_now and not was_pressed and Input.is_action_just_pressed(act):
		var last_consumed: int = int(_consumed_action_frame.get(act, -1))
		if cur_frame > last_consumed:
			_consumed_action_frame[act] = cur_frame
			return true
	return false

func _process_user_controlled(delta: float) -> void:
	if has_ball and is_instance_valid(current_ball):
		var target = _find_best_pass_target()
		_set_target_receiver(target)
	else:
		is_charging_action = false
		pass_press_time = 0.0
		_set_target_receiver(null)

	var secondary_pressed := _poll_action_edge("action_secondary")
	var switch_just_pressed := _poll_action_edge("switch_player")
	var ability_just_pressed := _poll_action_edge("action_ability")
	var primary_just_pressed := _poll_action_edge("action_primary")
	var shot_just_pressed := _poll_action_edge("action_shot")
	var slide_just_pressed := _poll_action_edge("action_slide")
	var pass_pressed := _poll_action_edge("action_pass")
	var shot_held := Input.is_action_pressed("action_shot") or Input.is_action_pressed("action_primary")
	if not shot_held:
		_shot_rearm_required = false

	if (secondary_pressed or switch_just_pressed) and not has_ball:
		_switch_to_next_teammate()
		return

	# A receiver must not interpret the same pass input as a slide tackle.
	if pass_receive_grace_timer > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 1500.0 * delta)
		move_and_slide()
		return

	if ability_just_pressed:
		_activate_special_ability()
		return

	if manual_drag_active:
		var to_target := manual_drag_target - global_position
		is_moving = to_target.length() > 14.0
		is_sprinting = false
		if is_moving:
			facing_direction = to_target.normalized()
			velocity = velocity.move_toward(facing_direction * (_get_base_speed() * 1.18), 1800.0 * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, 1800.0 * delta)
		move_and_slide()
		return

	if command_move_active:
		var to_target := command_move_target - global_position
		is_moving = to_target.length() > 18.0
		is_sprinting = false
		if is_moving:
			facing_direction = to_target.normalized()
			velocity = velocity.move_toward(facing_direction * (_get_base_speed() * 1.18), 1800.0 * delta)
			move_and_slide()
		else:
			command_move_active = false
			velocity = Vector2.ZERO
		return

	# Pass takes immediate priority and cancels any active shot charge
	if (secondary_pressed or pass_pressed) and has_ball and is_instance_valid(current_ball):
		is_charging_action = false
		pass_press_time = 0.0
		_perform_pass()
	elif not has_ball and (primary_just_pressed or slide_just_pressed or shot_just_pressed):
		if can_slide_tackle():
			_start_slide_tackle()
			return
	elif has_ball and is_instance_valid(current_ball):
		if not is_charging_action and not _shot_rearm_required and (primary_just_pressed or shot_just_pressed or shot_held):
			is_charging_action = true
			pass_press_time = 0.0
			_consumed_action_frame["action_shot"] = Engine.get_process_frames()
			_consumed_action_frame["action_primary"] = Engine.get_process_frames()
			emit_signal("shot_charge_started", self)
		elif is_charging_action:
			if shot_held and pass_press_time < 0.78:
				pass_press_time += delta
			else:
				_perform_power_kick()
				is_charging_action = false
				pass_press_time = 0.0
				_shot_rearm_required = shot_held
				_consumed_action_frame["action_shot"] = Engine.get_process_frames()
				_consumed_action_frame["action_primary"] = Engine.get_process_frames()

	if is_kicking or stumble_timer > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		return

	var keyboard_vec := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var input_vec := virtual_move_vector if virtual_move_vector.length() > 0.05 else keyboard_vec
	is_moving = input_vec.length() > 0.05
	is_sprinting = (Input.is_action_pressed("sprint") or virtual_move_vector.length() >= 0.78) and not is_charging_action

	if is_moving:
		facing_direction = input_vec.normalized()

	var base_speed = _get_base_speed() * 1.12 # User +12% bonus
	var charge_pace := 0.88 if is_charging_action else 1.0
	var target_speed = base_speed * (1.28 if is_sprinting else 1.0) * charge_pace

	if is_moving:
		velocity = velocity.move_toward(facing_direction * target_speed, 1800.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 1500.0 * delta)

	move_and_slide()

func set_virtual_move(vector: Vector2) -> void:
	virtual_move_vector = vector.limit_length(1.0)
	if virtual_move_vector.length() > 0.05:
		facing_direction = virtual_move_vector.normalized()

func begin_manual_drag(target: Vector2) -> void:
	manual_drag_active = true
	manual_drag_target = target
	virtual_move_vector = Vector2.ZERO

func command_move_to(target: Vector2) -> void:
	command_move_target = Vector2(
		clampf(target.x, -field_half_width + 40.0, field_half_width - 40.0),
		clampf(target.y, -field_half_height + 40.0, field_half_height - 40.0)
	)
	command_move_active = true
	manual_drag_active = false
	virtual_move_vector = Vector2.ZERO

func execute_command_at_position(target: Vector2) -> void:
	if not has_ball or not is_instance_valid(current_ball):
		return
	var teammate := _find_teammate_near(target)
	if teammate != null:
		facing_direction = (teammate.global_position - global_position).normalized()
		_perform_pass_to(teammate)
		return
	var goal_x := target_goal_x
	if absf(target.x - goal_x) < 520.0 and absf(target.y) <= 190.0:
		facing_direction = (target - global_position).normalized()
		pass_press_time = 0.42
		_perform_power_kick()
		pass_press_time = 0.0

func execute_pass_at_position(target: Player) -> void:
	if not is_user_controlled or is_ai or not is_instance_valid(target):
		return
	if target == self or target.team_id != team_id:
		return
	_perform_pass_to(target)

func execute_shot_at_position(target: Vector2) -> void:
	if not is_user_controlled or is_ai or not has_ball or not is_instance_valid(current_ball):
		return
	var goal_target := Vector2(target_goal_x, clampf(target.y, -120.0, 120.0))
	facing_direction = (goal_target - global_position).normalized()
	pass_press_time = 0.45
	_perform_power_kick()
	pass_press_time = 0.0

func _find_teammate_near(target: Vector2) -> Player:
	var nearest: Player = null
	var nearest_dist_sq := 13225.0 # 115^2
	for node in _get_match_players():
		if node is Player and node != self and node.team_id == team_id:
			var dist_sq: float = node.global_position.distance_squared_to(target)
			if dist_sq < nearest_dist_sq:
				nearest = node
				nearest_dist_sq = dist_sq
	return nearest

func _perform_pass_to(target: Player) -> void:
	if not has_ball or not is_instance_valid(current_ball):
		return
	is_kicking = true
	kick_anim_timer = 0.28
	var pase_stat := float(stats.get("pase", 80))
	var distance := global_position.distance_to(target.global_position)
	var pass_speed := clampf(maxf(lerp(580.0, 880.0, pase_stat / 100.0), distance * 1.15), 560.0, 1020.0)
	emit_signal("pass_initiated", self, target, pass_speed)
	current_ball.call("pass_to", target, pass_speed, self)
	if is_user_controlled and not is_ai:
		target.set_user_controlled(true)
		set_user_controlled(false)

func update_manual_drag(target: Vector2) -> void:
	manual_drag_target = Vector2(
		clampf(target.x, -field_half_width + 40.0, field_half_width - 40.0),
		clampf(target.y, -field_half_height + 40.0, field_half_height - 40.0)
	)

func end_manual_drag(target: Vector2) -> void:
	update_manual_drag(target)
	manual_drag_active = false

func execute_basic_command(command: String) -> void:
	if not is_user_controlled or is_ai:
		return
	match command:
		"ability":
			_activate_special_ability()
		"switch":
			if not has_ball:
				_switch_to_next_teammate()
		"pass":
			if has_ball and is_instance_valid(current_ball):
				_perform_pass()
		"shot":
			if has_ball and is_instance_valid(current_ball):
				if not is_charging_action or pass_press_time < 0.05:
					pass_press_time = 0.42
				_perform_power_kick()
				is_charging_action = false
				pass_press_time = 0.0
			elif can_slide_tackle():
				_start_slide_tackle()
		"slide":
			if can_slide_tackle():
				_start_slide_tackle()

# ==============================================================================
# TACTICAL AI LOGIC (TEAMMATES & DIFFICULTY-SCALED RIVALS)
# ==============================================================================
func _process_positional_ai(delta: float) -> void:
	ai_decision_timer -= delta
	_set_target_receiver(null)

	if is_kicking or stumble_timer > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		return

	if not is_instance_valid(current_ball):
		is_moving = false
		velocity = velocity.move_toward(Vector2.ZERO, 1000.0 * delta)
		move_and_slide()
		return

	if has_ball and not is_ai and not is_user_controlled:
		_promote_self_to_user_controlled()
		_process_user_controlled(delta)
		return

	if has_ball:
		_process_ai_with_ball(delta)
		move_and_slide()
		return

	var speed = _get_base_speed()
	var ball_pos = current_ball.global_position
	var dist_to_ball = global_position.distance_to(ball_pos)
	var attack_dir_x: float = 1.0 if target_goal_x > 0.0 else -1.0
	var own_goal_pos := Vector2(-target_goal_x, 0.0)
	var enemy_goal_pos := Vector2(target_goal_x, 0.0)

	if _is_gk_holding_ball():
		ai_state = AIState.GUARDAR_POSICION
		var safe_pos := home_position
		var to_safe := safe_pos - global_position
		if to_safe.length() > 28.0:
			var dir_safe := to_safe.normalized()
			facing_direction = facing_direction.lerp(dir_safe, clampf(10.0 * delta, 0.0, 1.0)).normalized()
			is_moving = true
			is_sprinting = false
			velocity = velocity.move_toward(dir_safe * (speed * 0.90), 1300.0 * delta)
		else:
			is_moving = false
			is_sprinting = false
			velocity = velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
			facing_direction = (ball_pos - global_position).normalized()
		move_and_slide()
		return

	var carrier = current_ball.get("carrier")
	var team_has_ball: bool = is_instance_valid(carrier) and carrier.get("team_id") == self.team_id
	var opp_has_ball: bool = is_instance_valid(carrier) and carrier.get("team_id") != self.team_id
	var ball_state = current_ball.get("current_state")
	var ball_is_loose: bool = ball_state != null and int(ball_state) == 0

	# Rival off-ball tactical actions: Defense Hissatsu & Slide Tackle
	if is_ai and opp_has_ball and is_instance_valid(carrier) and ai_decision_timer <= 0.0:
		var carrier_2d := carrier as Node2D
		var carrier_gp: Vector2 = carrier_2d.global_position if carrier_2d != null else ball_pos
		var dist_carrier: float = global_position.distance_to(carrier_gp)
		var to_carrier: Vector2 = carrier_gp - global_position
		var facing_ok: bool = to_carrier.length() > 1.0 and facing_direction.dot(to_carrier.normalized()) > 0.35
		var decision_cd: float = clampf(0.48 / maxf(0.5, ai_difficulty), 0.24, 0.65)

		if ability_type == "defense" and can_use_ability() and dist_carrier <= 115.0:
			var def_hissatsu_prob := clampf(0.28 * ai_difficulty, 0.18, 0.55)
			if randf() < def_hissatsu_prob:
				ai_decision_timer = decision_cd
				_activate_special_ability()
				return

		if can_slide_tackle() and facing_ok and dist_carrier >= 36.0 and dist_carrier <= 74.0:
			var slide_prob := clampf(0.24 * ai_difficulty, 0.12, 0.46)
			ai_decision_timer = decision_cd
			if randf() < slide_prob:
				_start_slide_tackle()
				return

	var is_closest_to_ball := _is_closest_ai_on_team_to(ball_pos)
	var target_pos: Vector2 = _compute_role_base_position(ball_pos, own_goal_pos, enemy_goal_pos, attack_dir_x)
	var move_mult: float = 0.92

	match role:
		"GK":
			ai_state = AIState.GUARDAR_POSICION
			var gk_x = own_goal_pos.x + attack_dir_x * 80.0
			var gk_y = clampf(ball_pos.y * 0.42, -115.0, 115.0)
			target_pos = Vector2(gk_x, gk_y)
			move_mult = 1.15
			if ball_is_loose and dist_to_ball < 85.0 and absf(ball_pos.x - own_goal_pos.x) < 260.0:
				current_ball.call("take_possession", self)
		"DF":
			var ball_in_def_zone = (ball_pos.x * attack_dir_x) < 220.0
			var dist_own_goal_ball = own_goal_pos.distance_to(ball_pos)
			if team_has_ball:
				ai_state = AIState.APOYAR
				var support_x = clampf(ball_pos.x - attack_dir_x * 500.0, -field_half_width + 320.0, field_half_width - 320.0)
				target_pos = Vector2(support_x, lerpf(home_position.y, ball_pos.y, 0.35))
				move_mult = 0.88
			elif (opp_has_ball or ball_is_loose) and (ball_in_def_zone or dist_own_goal_ball < 980.0 or (ball_is_loose and is_closest_to_ball and dist_to_ball < 520.0)):
				ai_state = AIState.CORTAR
				target_pos = carrier.global_position if (opp_has_ball and is_instance_valid(carrier)) else ball_pos
				move_mult = 1.12
			else:
				ai_state = AIState.GUARDAR_POSICION
				move_mult = 0.88
		"FW":
			if team_has_ball:
				ai_state = AIState.DESMARCARSE
				var carrier_2d := carrier as Node2D
				var carrier_pos: Vector2 = carrier_2d.global_position if (is_instance_valid(carrier) and carrier_2d != null) else ball_pos
				var desired_x: float = carrier_pos.x + attack_dir_x * 540.0
				var lane_y: float = lerpf(home_position.y, -carrier_pos.y * 0.45, 0.45)
				target_pos = Vector2(clampf(desired_x, -field_half_width + 260.0, field_half_width - 260.0), clampf(lane_y, -field_half_height + 160.0, field_half_height - 160.0))
				move_mult = 1.06
			elif (opp_has_ball and is_closest_to_ball and dist_to_ball < 520.0) or (ball_is_loose and dist_to_ball < 650.0):
				ai_state = AIState.BUSCAR_PELOTA
				target_pos = carrier.global_position if (opp_has_ball and is_instance_valid(carrier)) else ball_pos
				move_mult = 1.14
			else:
				ai_state = AIState.GUARDAR_POSICION
				move_mult = 0.88
		_:
			if team_has_ball:
				ai_state = AIState.DESMARCARSE
				var lane_offset_y := home_position.y + sin(aurora_time * 1.4) * 75.0
				target_pos = Vector2(clampf(ball_pos.x + attack_dir_x * 320.0, -field_half_width + 280.0, field_half_width - 280.0), clampf(lane_offset_y, -field_half_height + 150.0, field_half_height - 150.0))
				move_mult = 1.00
			elif (ball_is_loose and is_closest_to_ball) or dist_to_ball < 600.0:
				ai_state = AIState.BUSCAR_PELOTA
				target_pos = carrier.global_position if (opp_has_ball and is_instance_valid(carrier)) else ball_pos
				move_mult = 1.10
			else:
				ai_state = AIState.GUARDAR_POSICION
				move_mult = 0.90

	var to_dest = target_pos - global_position
	if to_dest.length() > 26.0:
		var desired_dir = to_dest.normalized()
		facing_direction = facing_direction.lerp(desired_dir, clampf(10.0 * delta, 0.0, 1.0)).normalized()
		is_moving = true
		is_sprinting = move_mult > 1.08
		velocity = velocity.move_toward(desired_dir * (speed * move_mult), 1400.0 * delta)
	else:
		is_moving = false
		is_sprinting = false
		velocity = velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
		if (ball_pos - global_position).length() > 10.0:
			facing_direction = (ball_pos - global_position).normalized()

	move_and_slide()

func _compute_role_base_position(ball_pos: Vector2, own_goal_pos: Vector2, _enemy_goal_pos: Vector2, attack_dir_x: float) -> Vector2:
	var base_x: float = home_position.x
	match role:
		"GK":
			base_x = own_goal_pos.x + attack_dir_x * 80.0
			var gk_y = clampf(ball_pos.y * 0.42, -115.0, 115.0)
			return Vector2(base_x, gk_y)
		"DF":
			base_x = lerpf(own_goal_pos.x + attack_dir_x * 560.0, ball_pos.x - attack_dir_x * 460.0, 0.35)
		"MF":
			base_x = lerpf(home_position.x * 0.5, ball_pos.x, 0.45)
		"FW":
			base_x = lerpf(attack_dir_x * 440.0, ball_pos.x + attack_dir_x * 400.0, 0.40)

	var base_y: float = clampf(lerpf(home_position.y, ball_pos.y, 0.36), -field_half_height + 140.0, field_half_height - 140.0)
	return Vector2(base_x, base_y)

func _is_closest_ai_on_team_to(pos: Vector2) -> bool:
	var threshold := global_position.distance_to(pos) - 15.0
	if threshold <= 0.0:
		return true
	var threshold_sq := threshold * threshold
	for p in _get_match_players():
		if p != self and p is Player and p.team_id == self.team_id and not p.is_user_controlled:
			if p.global_position.distance_squared_to(pos) < threshold_sq:
				return false
	return true

func _count_nearby_opponents(radius: float) -> int:
	var count := 0
	var r_sq := radius * radius
	for p in _get_match_players():
		if p is Player and p.team_id != self.team_id:
			if global_position.distance_squared_to(p.global_position) <= r_sq:
				count += 1
	return count

func _find_open_forward_teammate(attack_dir_x: float) -> Player:
	var best: Player = null
	var best_score: float = -9999.0
	var players_list := _get_match_players()
	for p in players_list:
		if p != self and p is Player and p.team_id == self.team_id:
			var mate := p as Player
			var advance := (mate.global_position.x - global_position.x) * attack_dir_x
			if advance < 75.0:
				continue
			var dist_sq := global_position.distance_squared_to(mate.global_position)
			if dist_sq < 14400.0 or dist_sq > 1322500.0: # [120^2, 1150^2]
				continue
			var dist := sqrt(dist_sq)
			var opp_near_mate := mate._count_nearby_opponents(135.0)
			var score := advance * 0.65 - float(opp_near_mate) * 140.0 - dist * 0.08
			if score > best_score:
				best_score = score
				best = mate
	return best if best_score > 10.0 else null

func _process_ai_with_ball(delta: float) -> void:
	var speed = _get_base_speed()
	var attack_dir_x: float = 1.0 if target_goal_x > 0.0 else -1.0
	var goal_target := Vector2(target_goal_x, clampf(global_position.y * 0.35, -78.0, 78.0))
	var dist_to_goal := global_position.distance_to(goal_target)
	var decision_cd := clampf(0.50 / maxf(0.5, ai_difficulty), 0.22, 0.68)

	if ai_decision_timer <= 0.0:
		var pressure := _count_nearby_opponents(110.0)

		# 1. Shooting zone: Super Shot Hissatsu or Charged Power Kick
		var shoot_range: float = 610.0 if role != "DF" else 440.0
		if dist_to_goal < shoot_range:
			if ability_type == "shot" and can_use_ability() and randf() < clampf(0.45 * ai_difficulty, 0.25, 0.78):
				ai_decision_timer = decision_cd
				_activate_special_ability()
				return
			facing_direction = (goal_target - global_position).normalized()
			pass_press_time = clampf(lerpf(0.28, 0.58, clampf((ai_difficulty - 0.8) / 0.6, 0.0, 1.0)), 0.20, 0.60)
			_perform_power_kick()
			pass_press_time = 0.0
			ai_decision_timer = decision_cd
			return

		# 2. Under pressure: Dribble/Pass Hissatsu or tactical pass to open teammate
		if pressure > 0:
			if ability_type in ["dribble", "pass"] and can_use_ability() and randf() < clampf(0.36 * ai_difficulty, 0.18, 0.62):
				ai_decision_timer = decision_cd
				_activate_special_ability()
				return

			var open_mate := _find_open_forward_teammate(attack_dir_x)
			if is_instance_valid(open_mate) and randf() < clampf(0.52 * ai_difficulty, 0.28, 0.82):
				facing_direction = (open_mate.global_position - global_position).normalized()
				_perform_pass_to(open_mate)
				ai_decision_timer = decision_cd
				return
		else:
			# Proactive build-up pass from DF/MF to unmarked FW ahead
			if role in ["DF", "MF"]:
				var forward_mate := _find_open_forward_teammate(attack_dir_x)
				if is_instance_valid(forward_mate) and randf() < clampf(0.22 * ai_difficulty, 0.10, 0.40):
					facing_direction = (forward_mate.global_position - global_position).normalized()
					_perform_pass_to(forward_mate)
					ai_decision_timer = decision_cd + 0.15
					return

		ai_decision_timer = decision_cd * 0.55

	# Evasive dribble angle around defenders directly ahead
	var move_dir := (goal_target - global_position).normalized()
	for p in _get_match_players():
		if p is Player and p.team_id != self.team_id:
			var to_opp: Vector2 = p.global_position - global_position
			var d_sq := to_opp.length_squared()
			if d_sq > 25.0 and d_sq < 19600.0: # (5^2, 140^2)
				var d := sqrt(d_sq)
				if move_dir.dot(to_opp / d) > 0.55:
					var sidestep := Vector2(0.0, -1.0 if to_opp.y >= 0.0 else 1.0)
					if absf(global_position.y) > field_half_height - 220.0:
						sidestep.y = -signf(global_position.y)
					move_dir = (move_dir + sidestep * 0.55).normalized()
					break

	facing_direction = facing_direction.lerp(move_dir, clampf(10.0 * delta, 0.0, 1.0)).normalized()
	is_moving = true
	is_sprinting = true
	velocity = velocity.move_toward(facing_direction * speed, 1400.0 * delta)

func _find_best_pass_target() -> Player:
	var best_target: Player = null
	var best_score: float = -9999.0
	var players_list := _get_match_players()
	var has_teammate := false

	for p in players_list:
		if p != self and p is Player and p.team_id == self.team_id:
			has_teammate = true
			var mate := p as Player
			var to_mate := mate.global_position - global_position
			var dist_sq := to_mate.length_squared()
			if dist_sq < 2025.0 or dist_sq > 2722500.0: # [45^2, 1650^2]
				continue
			var dist := sqrt(dist_sq)
			var dot := facing_direction.dot(to_mate / dist)
			if dot >= 0.15:
				var score := (dot * 120.0) - (dist * 0.04)
				if score > best_score:
					best_score = score
					best_target = mate

	if best_target == null and has_teammate:
		var attack_dir_x: float = 1.0 if target_goal_x > 0.0 else -1.0
		for p in players_list:
			if p != self and p is Player and p.team_id == self.team_id:
				var mate := p as Player
				var dist := global_position.distance_to(mate.global_position)
				var forward_bonus := (mate.global_position.x - global_position.x) * attack_dir_x * 0.15
				var score := forward_bonus - dist * 0.1
				if score > best_score:
					best_score = score
					best_target = mate

	return best_target

func _set_target_receiver(target: Player) -> void:
	if current_pass_target == target:
		return

	if is_instance_valid(current_pass_target):
		current_pass_target.is_targeted_for_pass = false
		if is_instance_valid(current_pass_target.base_indicator):
			current_pass_target.base_indicator.set_selection_state(current_pass_target.is_user_controlled, false)
		current_pass_target._refresh_overlay_redraw()

	current_pass_target = target

	if is_instance_valid(current_pass_target):
		current_pass_target.is_targeted_for_pass = true
		if is_instance_valid(current_pass_target.base_indicator):
			current_pass_target.base_indicator.set_selection_state(current_pass_target.is_user_controlled, true)
		current_pass_target._refresh_overlay_redraw()

func _perform_pass() -> void:
	if not has_ball or not is_instance_valid(current_ball):
		return

	var target = current_pass_target
	if not is_instance_valid(target):
		target = _find_best_pass_target()
	if not is_instance_valid(target):
		_perform_soft_pass()
		return

	var to_target_dir = (target.global_position - global_position).normalized()
	if to_target_dir.length() > 0.05:
		facing_direction = to_target_dir

	is_kicking = true
	kick_anim_timer = 0.28
	if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.flip_h = facing_direction.x < -0.05
		anim_sprite.play("kick")

	var pase_stat = float(stats.get("pase", 80))
	var dist = global_position.distance_to(target.global_position)
	var base_pass_speed = lerp(580.0, 880.0, clampf(pase_stat / 100.0, 0.0, 1.0))
	var pass_speed = clampf(maxf(base_pass_speed, dist * 1.15), 560.0, 1020.0)

	emit_signal("pass_initiated", self, target, pass_speed)
	current_ball.call("pass_to", target, pass_speed, self)

	if is_user_controlled and not is_ai:
		target.set_user_controlled(true)
		set_user_controlled(false)

func _perform_soft_pass() -> void:
	is_kicking = true
	kick_anim_timer = 0.26
	if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.flip_h = facing_direction.x < -0.05
		anim_sprite.play("kick")

	var pase_stat = float(stats.get("pase", 75))
	var pass_speed = lerp(460.0, 680.0, clampf(pase_stat / 100.0, 0.0, 1.0))
	current_ball.call("kick", facing_direction, pass_speed, self)

func _perform_power_kick() -> void:
	if not has_ball or not is_instance_valid(current_ball):
		return

	is_kicking = true
	kick_anim_timer = 0.32
	if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("kick"):
		anim_sprite.flip_h = facing_direction.x < -0.05
		anim_sprite.play("kick")

	var tiro_stat = float(stats.get("tiro", 75))
	var charge_factor = clampf(pass_press_time / 0.60, 0.45, 1.0)
	var base_speed = lerp(660.0, 1060.0, clampf(tiro_stat / 100.0, 0.0, 1.0))
	var kick_speed = base_speed * (0.82 + 0.35 * charge_factor)

	var shot_dir = facing_direction.normalized()
	if (target_goal_x > 0 and shot_dir.x > 0.1) or (target_goal_x < 0 and shot_dir.x < -0.1):
		shot_dir.y += clampf(velocity.y * 0.0008, -0.22, 0.22)
		shot_dir = shot_dir.normalized()

	if charge_factor >= 0.82:
		current_ball.call("activate_super_effect", 0.75, Color(1.0, 0.86, 0.26, 0.88), false, tiro_stat)

	current_ball.call("kick", shot_dir, kick_speed, self)
	emit_signal("shot_executed", self, kick_speed, charge_factor)

func _switch_to_next_teammate() -> void:
	var best_mate: Player = null
	var best_dist_sq: float = INF
	var ref_pos := current_ball.global_position if is_instance_valid(current_ball) else global_position

	for p in _get_match_players():
		if p != self and p is Player and p.team_id == self.team_id:
			var d_sq: float = p.global_position.distance_squared_to(ref_pos)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_mate = p as Player

	if is_instance_valid(best_mate):
		best_mate.set_user_controlled(true)
		set_user_controlled(false)

func _promote_self_to_user_controlled() -> void:
	for p in _get_match_players():
		if p is Player and p.team_id == self.team_id:
			p.set_user_controlled(p == self)

func _update_animation() -> void:
	if is_kicking or not anim_sprite or not anim_sprite.sprite_frames:
		return

	if velocity.length() > 16.0 or is_moving:
		last_anim_dir = _get_direction_name(facing_direction)
		if facing_direction.x < -0.18:
			last_flip_h = true
		elif facing_direction.x > 0.18:
			last_flip_h = false

	var dir_name := last_anim_dir
	var sf := anim_sprite.sprite_frames
	var target_anim := "idle_down"
	var use_flip := false

	if is_moving and velocity.length() > 12.0:
		var is_fast := is_sprinting or velocity.length() > 210.0
		var prefix := "run_" if is_fast else "walk_"

		if dir_name == "up":
			target_anim = "run_up" if sf.has_animation("run_up") else "idle_down"
			use_flip = false
		elif dir_name == "down":
			target_anim = "run_down" if sf.has_animation("run_down") else "idle_down"
			use_flip = false
		elif dir_name == "side":
			if last_flip_h and sf.has_animation(prefix + "left"):
				target_anim = prefix + "left"
				use_flip = false
			else:
				target_anim = (prefix + "side") if sf.has_animation(prefix + "side") else ("run_side" if sf.has_animation("run_side") else "idle_down")
				use_flip = last_flip_h
		elif dir_name == "down_side":
			target_anim = (prefix + "down_side") if sf.has_animation(prefix + "down_side") else ("run_down_side" if sf.has_animation("run_down_side") else "idle_down")
			use_flip = last_flip_h
		elif dir_name == "up_side":
			target_anim = (prefix + "up_side") if sf.has_animation(prefix + "up_side") else ("run_up_side" if sf.has_animation("run_up_side") else "idle_down")
			use_flip = last_flip_h
	else:
		if dir_name == "up" and sf.has_animation("idle_up"):
			target_anim = "idle_up"
		else:
			target_anim = "idle_down" if sf.has_animation("idle_down") else sf.get_animation_names()[0] if sf.get_animation_names().size() > 0 else ""

	anim_sprite.flip_h = use_flip
	if target_anim != "" and (anim_sprite.animation != target_anim or not anim_sprite.is_playing()):
		anim_sprite.play(target_anim)

func _get_direction_name(dir: Vector2) -> String:
	var n := dir.normalized()
	var abs_x := absf(n.x)
	var y := n.y

	if y < -0.68 and abs_x < 0.48:
		return "up"
	elif y > 0.68 and abs_x < 0.48:
		return "down"
	elif abs_x >= 0.68 and absf(y) < 0.42:
		return "side"
	elif y >= 0.25 and abs_x >= 0.38:
		return "down_side"
	elif y <= -0.25 and abs_x >= 0.38:
		return "up_side"

	return last_anim_dir if last_anim_dir != "" else "down"

func on_ball_possessed(b: CharacterBody2D) -> void:
	has_ball = true
	current_ball = b
	if not is_ai and team_id == "team_user" and not is_user_controlled:
		_promote_self_to_user_controlled()

func on_pass_received() -> void:
	pass_receive_grace_timer = 0.14
	is_sliding = false
	slide_timer = 0.0
	slide_recovery_timer = 0.0
	is_kicking = false
	kick_anim_timer = 0.0
	is_charging_action = false
	pass_press_time = 0.0
	if is_instance_valid(anim_sprite):
		anim_sprite.rotation = 0.0
		anim_sprite.position = BASE_SPRITE_OFFSET
		anim_sprite.scale = BASE_SPRITE_SCALE

func on_ball_lost(_b: CharacterBody2D) -> void:
	has_ball = false
	is_charging_action = false
	pass_press_time = 0.0
	_set_target_receiver(null)

func _draw() -> void:
	# Cooldown indicator keeps the special ability readable during play.
	if ability_cooldown > 0.0:
		var cooldown_pct := clampf(ability_cooldown / maxf(0.1, ability_max_cooldown), 0.0, 1.0)
		var cooldown_rect := Rect2(-22.0, -103.0, 44.0, 4.0)
		draw_rect(cooldown_rect, Color(0.04, 0.05, 0.08, 0.9), true)
		draw_rect(Rect2(cooldown_rect.position, Vector2(cooldown_rect.size.x * (1.0 - cooldown_pct), cooldown_rect.size.y)), Color(0.35, 0.72, 0.98, 0.95), true)

	# Hissatsu STARTUP windup intense ring
	if _hissatsu_pending:
		var windup_pct := 1.0 - clampf(hissatsu_windup_timer / maxf(0.01, HISSATSU_STARTUP_TIME), 0.0, 1.0)
		var r_in := lerpf(42.0, 18.0, windup_pct)
		draw_arc(Vector2(0, -18), r_in, 0.0, TAU, 28, Color(1.0, 0.92, 0.35, 0.95), 3.2)
		draw_circle(Vector2(0, -18), 22.0, Color(1.0, 0.72, 0.18, 0.30))

	# Active Hissatsu / Special ability golden aura
	if ability_active_timer > 0.0:
		var pulse_ab = 0.65 + 0.35 * sin(aurora_time * 12.0)
		draw_circle(Vector2(0, -18), 28.0, Color(1.0, 0.85, 0.20, 0.22 * pulse_ab))
		draw_arc(Vector2(0, 0), 25.0, 0.0, TAU, 32, Color(1.0, 0.88, 0.25, 0.95), 3.0)
		draw_arc(Vector2(0, 0), 30.0, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.70 * pulse_ab), 1.8)

	# Slide tackle dust trail
	if is_sliding:
		var trail_dir = -slide_direction.normalized()
		draw_line(Vector2.ZERO, trail_dir * 34.0, Color(1.0, 0.96, 0.82, 0.75), 8.0)
		draw_line(Vector2(0, 4), trail_dir * 26.0 + Vector2(0, 4), Color(0.85, 0.68, 0.22, 0.80), 4.0)

	# Slide recovery gauge
	if slide_recovery_timer > 0.0:
		var pct_rec: float = 1.0 - clampf(slide_recovery_timer / maxf(0.01, slide_max_recovery), 0.0, 1.0)
		var bw: float = 34.0
		var bh: float = 5.0
		var bpos: Vector2 = Vector2(-bw / 2.0, -90.0)
		draw_rect(Rect2(bpos, Vector2(bw, bh)), Color(0.08, 0.08, 0.10, 0.9), true)
		draw_rect(Rect2(bpos, Vector2(bw * pct_rec, bh)), Color(0.92, 0.75, 0.22, 0.95), true)
		draw_rect(Rect2(bpos, Vector2(bw, bh)), Color(1.0, 0.98, 0.92, 0.9), false, 1.0)

	# Shot power charge gauge
	if is_charging_action and pass_press_time > 0.04:
		var max_charge: float = 0.60
		var pct: float = clampf(pass_press_time / max_charge, 0.0, 1.0)
		var bar_w: float = 38.0
		var bar_h: float = 6.0
		var bar_pos: Vector2 = Vector2(-bar_w / 2.0, -96.0)

		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0.08, 0.08, 0.10, 0.92), true)
		var fill_color = Color(0.98, 0.92, 0.35).lerp(Color(1.0, 0.32, 0.12), pct)
		draw_rect(Rect2(bar_pos, Vector2(bar_w * pct, bar_h)), fill_color, true)
		draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(1.0, 0.88, 0.32, 0.95), false, 1.2)
