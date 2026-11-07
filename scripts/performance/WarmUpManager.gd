class_name WarmUpManager
extends Node

## Pre-match off-screen GPU shader and particle pipeline warm-up manager.
## Renders heavy materials and particle systems in an off-screen SubViewport for 2 frames
## prior to kickoff to eliminate driver shader compilation stutters.
## Also provides stutter-free cinematic-to-gameplay transition hooks.

signal warm_up_started
signal warm_up_completed
signal cinematic_transition_started(participants: Array)
signal cinematic_transition_completed

@export var viewport_size: Vector2i = Vector2i(128, 128)
@export var warm_up_viewport: SubViewport = null
@export var materials_to_warm: Array[Material] = []
@export var particles_to_warm: Array[PackedScene] = []

var is_completed: bool = false
var materials_count: int = 0
var particles_count: int = 0
var _staging_container: Node2D = null
var _saved_gameplay_state: Dictionary = {}

## Prepares and returns the off-screen SubViewport and staging container
func setup_staging(mats: int = 0, particles: int = 0) -> Dictionary:
	materials_count = mats
	particles_count = particles

	var vp = SubViewport.new()
	vp.size = viewport_size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var container = Node2D.new()
	container.position = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.5)
	vp.add_child(container)

	return {
		"viewport": vp,
		"container": container
	}

## Executes the full 2-frame pre-match warm-up pass
func run_warm_up_routine() -> void:
	emit_signal("warm_up_started")
	is_completed = false

	var stage = setup_staging(materials_to_warm.size(), particles_to_warm.size())
	var vp = stage["viewport"] as SubViewport
	var container = stage["container"] as Node2D
	_staging_container = container
	add_child(vp)

	# 1. Instantiate material test quads to warm up shaders
	for mat in materials_to_warm:
		if mat == null:
			continue
		var sprite = Sprite2D.new()
		sprite.texture = PlaceholderTexture2D.new()
		sprite.material = mat
		container.add_child(sprite)

	# 2. Instantiate and emit particle scenes for GPU pipeline compile
	for ps_scene in particles_to_warm:
		if ps_scene == null:
			continue
		var p_inst = ps_scene.instantiate()
		if p_inst is GPUParticles2D:
			p_inst.emitting = true
			p_inst.one_shot = true
		container.add_child(p_inst)

	# 3. Wait 2 frames to force GPU pipeline state object (PSO) compilation
	if is_inside_tree():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

	# 4. Clean up off-screen staging nodes
	if is_instance_valid(container):
		container.queue_free()
	if is_instance_valid(vp):
		vp.queue_free()

	is_completed = true
	emit_signal("warm_up_completed")

# ==============================================================================
# CINEMATIC-TO-GAMEPLAY TRANSITION HOOKS
# ==============================================================================

## Saves ball and player kinematics before entering a skill cutscene
func save_gameplay_state(ball: Node2D = null, players: Array = []) -> Dictionary:
	var state = {
		"ball_velocity": Vector2.ZERO,
		"players_velocities": {}
	}

	if is_instance_valid(ball) and ball is CharacterBody2D:
		state["ball_velocity"] = (ball as CharacterBody2D).velocity

	for p in players:
		if is_instance_valid(p) and p is CharacterBody2D:
			state["players_velocities"][p] = (p as CharacterBody2D).velocity

	_saved_gameplay_state = state
	return state

## Restores saved velocities cleanly upon exiting a cutscene
func restore_gameplay_state(state: Dictionary = {}) -> void:
	var target_state = state if not state.is_empty() else _saved_gameplay_state

	if target_state.has("players_velocities"):
		var pv: Dictionary = target_state["players_velocities"]
		for p in pv.keys():
			if is_instance_valid(p) and p is CharacterBody2D:
				(p as CharacterBody2D).velocity = pv[p]
				p.set_physics_process(true)

	_saved_gameplay_state.clear()

## Starts cinematic transition: soft-freezes non-participants and tweens camera
func start_cinematic_transition(
	camera: Camera2D,
	participants: Array,
	duration_in: float = 0.22,
	target_zoom: float = 0.85
) -> Tween:
	if is_inside_tree():
		var all_players = get_tree().get_nodes_in_group("players")
		for p in all_players:
			if p not in participants and is_instance_valid(p) and p is CharacterBody2D:
				(p as CharacterBody2D).set_physics_process(false)

	var tween: Tween = null
	if is_instance_valid(camera):
		tween = create_tween().set_parallel(true)
		tween.tween_property(camera, "zoom", Vector2(target_zoom, target_zoom), duration_in).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	emit_signal("cinematic_transition_started", participants)
	return tween

## Ends cinematic transition: tweens camera back to gameplay framing and unfreezes players
func end_cinematic_transition(
	camera: Camera2D,
	duration_out: float = 0.26,
	target_zoom: float = 0.68
) -> Tween:
	var tween: Tween = null
	if is_instance_valid(camera):
		tween = create_tween().set_parallel(true)
		tween.tween_property(camera, "zoom", Vector2(target_zoom, target_zoom), duration_out).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	if is_inside_tree():
		var all_players = get_tree().get_nodes_in_group("players")
		for p in all_players:
			if is_instance_valid(p) and p is CharacterBody2D:
				(p as CharacterBody2D).set_physics_process(true)

	emit_signal("cinematic_transition_completed")
	return tween
