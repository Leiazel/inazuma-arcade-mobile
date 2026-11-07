class_name SkillStateMachine
extends Node

## Deterministic 4-Phase Hissatsu Skill Finite State Machine.
## Lifecycle: STARTUP -> ACTIVE -> HITSTOP -> RECOVERY -> IDLE.
## Features deterministic cone targeting and unscaled hitstop micro-pauses.

enum State {
	IDLE = 0,
	STARTUP = 1,
	ACTIVE = 2,
	HITSTOP = 3,
	RECOVERY = 4
}

# Signal interface
signal skill_started(skill_name: String)
signal skill_hit(target: Node2D)
signal hitstop_entered()
signal hitstop_exited()
signal skill_finished(skill_name: String, hit_connected: bool)
signal state_changed(old_state: State, new_state: State)

# Default architectural timings & invariants
const DEFAULT_CONE_ANGLE_DEG: float = 60.0
const DEFAULT_CONE_RANGE: float = 120.0
const DEFAULT_STARTUP_DURATION: float = 0.20   # ~12 frames @ 60 FPS (0.166s - 0.233s)
const DEFAULT_ACTIVE_DURATION: float = 0.08    # ~5 frames @ 60 FPS (0.066s - 0.100s)
const DEFAULT_HITSTOP_DURATION: float = 0.05   # ~3 frames @ 60 FPS (0.033s - 0.066s)
const DEFAULT_RECOVERY_DURATION: float = 0.25  # ~15 frames @ 60 FPS (0.200s - 0.300s)
const DEFAULT_HITSTOP_TIME_SCALE: float = 0.04 # Micro-pause slowdown
const DEFAULT_TRAUMA_AMOUNT: float = 0.65      # Procedural camera shake intensity

@export_group("Timing Configuration")
@export var startup_duration: float = DEFAULT_STARTUP_DURATION
@export var active_duration: float = DEFAULT_ACTIVE_DURATION
@export var hitstop_duration: float = DEFAULT_HITSTOP_DURATION
@export var recovery_duration: float = DEFAULT_RECOVERY_DURATION

@export_group("Targeting Sector")
@export var cone_range: float = DEFAULT_CONE_RANGE
@export var cone_angle_deg: float = DEFAULT_CONE_ANGLE_DEG

@export_group("Hitstop & Feel")
@export var hitstop_time_scale: float = DEFAULT_HITSTOP_TIME_SCALE
@export var hitstop_trauma: float = DEFAULT_TRAUMA_AMOUNT
@export var camera: DynamicCamera2D = null

# Active runtime state
var current_state: State = State.IDLE
var current_skill_name: String = ""
var phase_timer: float = 0.0
var hit_connected: bool = false
var user_player: Node2D = null
var target_entity: Node2D = null
var history: Array[int] = [State.IDLE]
var unscaled_timer: SceneTreeTimer = null

func _init() -> void:
	current_state = State.IDLE
	phase_timer = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Safety restoration of time_scale on node destruction
		if Engine.time_scale != 1.0:
			Engine.time_scale = 1.0

## Infallible deterministic sector targeting query
static func is_target_in_action_sector(
	source_pos: Vector2,
	facing_dir: Vector2,
	target_pos: Vector2,
	max_range: float = DEFAULT_CONE_RANGE,
	max_half_angle_deg: float = DEFAULT_CONE_ANGLE_DEG
) -> bool:
	var to_target = target_pos - source_pos
	var dist = to_target.length()
	if dist > max_range:
		return false
	if dist < 0.0001:
		return true

	var forward = facing_dir.normalized()
	var dir_to_target = to_target.normalized()
	var dot_val = forward.dot(dir_to_target)
	var min_dot = cos(deg_to_rad(max_half_angle_deg))
	return dot_val >= (min_dot - 0.00001)

## Public execution entrypoint for explicit hit flag (e.g. testing or scripted play)
func execute(skill_name: String, hit: bool = false) -> void:
	current_skill_name = skill_name
	hit_connected = hit
	target_entity = null
	history = [State.IDLE]
	_transition_to(State.STARTUP)
	emit_signal("skill_started", current_skill_name)

## Public execution with deterministic collision detection against target
func execute_skill(skill_name: String, source: Node2D = null, target: Node2D = null) -> bool:
	if current_state != State.IDLE:
		return false

	current_skill_name = skill_name
	if source != null:
		user_player = source

	target_entity = target
	hit_connected = false

	if is_instance_valid(user_player) and is_instance_valid(target_entity):
		var facing: Vector2 = Vector2.RIGHT
		if user_player.get("facing_direction") != null:
			facing = user_player.get("facing_direction")
		hit_connected = is_target_in_action_sector(
			user_player.global_position,
			facing,
			target_entity.global_position,
			cone_range,
			cone_angle_deg
		)

	history = [State.IDLE]
	_transition_to(State.STARTUP)
	emit_signal("skill_started", current_skill_name)
	return true

## Discrete simulation step for test suites and deterministic physics processing
func process_step(delta: float) -> void:
	if current_state == State.IDLE:
		return

	phase_timer -= delta
	if phase_timer <= 0.0:
		match current_state:
			State.STARTUP:
				_transition_to(State.ACTIVE)
			State.ACTIVE:
				if hit_connected:
					_transition_to(State.HITSTOP)
				else:
					_transition_to(State.RECOVERY)
			State.HITSTOP:
				_end_hitstop()
				_transition_to(State.RECOVERY)
			State.RECOVERY:
				_transition_to(State.IDLE)
				emit_signal("skill_finished", current_skill_name, hit_connected)

func _process(delta: float) -> void:
	if current_state != State.IDLE:
		process_step(delta)

func _transition_to(new_state: State) -> void:
	var old_state = current_state
	current_state = new_state
	history.append(int(new_state))

	match new_state:
		State.STARTUP:
			phase_timer = startup_duration
		State.ACTIVE:
			phase_timer = active_duration
		State.HITSTOP:
			phase_timer = hitstop_duration
			_on_hitstop_enter()
		State.RECOVERY:
			phase_timer = recovery_duration
		State.IDLE:
			phase_timer = 0.0

	emit_signal("state_changed", old_state, new_state)

func _on_hitstop_enter() -> void:
	emit_signal("hitstop_entered")
	if is_instance_valid(target_entity):
		emit_signal("skill_hit", target_entity)

	_trigger_camera_shake(hitstop_trauma)

	if is_inside_tree() and get_tree() != null:
		Engine.time_scale = hitstop_time_scale
		unscaled_timer = get_tree().create_timer(hitstop_duration, true, false, true)
		unscaled_timer.timeout.connect(_on_unscaled_hitstop_timeout)

func _on_unscaled_hitstop_timeout() -> void:
	if current_state == State.HITSTOP:
		_end_hitstop()
		_transition_to(State.RECOVERY)

func _end_hitstop() -> void:
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
	emit_signal("hitstop_exited")

func _trigger_camera_shake(trauma_amount: float) -> void:
	if is_instance_valid(camera) and camera.has_method("add_trauma"):
		camera.call("add_trauma", trauma_amount)
		return

	if is_inside_tree():
		var vp = get_viewport()
		if vp != null:
			var cam = vp.get_camera_2d()
			if is_instance_valid(cam) and cam.has_method("add_trauma"):
				cam.call("add_trauma", trauma_amount)
				return

		var cameras = get_tree().get_nodes_in_group("camera")
		for cam_node in cameras:
			if is_instance_valid(cam_node) and cam_node.has_method("add_trauma"):
				cam_node.call("add_trauma", trauma_amount)
				return

func cancel() -> void:
	if current_state == State.HITSTOP:
		_end_hitstop()
	current_state = State.IDLE
	phase_timer = 0.0
	hit_connected = false
	target_entity = null
