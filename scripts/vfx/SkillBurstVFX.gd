class_name SkillBurstVFX
extends Node2D

## Lightweight pooled 2D particle & shockwave burst node managed by NodePool.
## Zero runtime allocations: resets state on visibility activation and recycles back to pool on completion.

var pool_ref: Node = null
var burst_color: Color = Color(1.0, 0.72, 0.18, 1.0)
var burst_scale: float = 1.0
var duration: float = 0.40
var elapsed: float = 0.0
var is_playing: bool = false

var _dirs: Array[Vector2] = []
var _speeds: Array[float] = []

func _ready() -> void:
	z_index = 5
	_init_rays()

func _init_rays() -> void:
	if not _dirs.is_empty():
		return
	var ray_count: int = 12
	for i in range(ray_count):
		var ang: float = (TAU * float(i) / float(ray_count)) + (0.13 if i % 2 == 1 else 0.0)
		_dirs.append(Vector2(cos(ang), sin(ang)))
		_speeds.append(95.0 + float((i * 37) % 65))

func play_burst(col: Color, scale_mult: float = 1.0, dur: float = 0.38) -> void:
	_init_rays()
	burst_color = col
	burst_scale = clampf(scale_mult, 0.4, 2.5)
	duration = maxf(0.12, dur)
	elapsed = 0.0
	is_playing = true
	visible = true
	queue_redraw()

func _process(delta: float) -> void:
	if not visible or not is_playing:
		return
	# Use unscaled delta approximation during hitstop so impact flash still animates crisply
	var eff_delta: float = delta
	if Engine.time_scale > 0.001 and Engine.time_scale < 0.25:
		eff_delta = delta / Engine.time_scale
	elapsed += eff_delta
	if elapsed >= duration:
		is_playing = false
		if is_instance_valid(pool_ref) and pool_ref.has_method("release"):
			pool_ref.call("release", self)
		else:
			visible = false
		return
	queue_redraw()

func _draw() -> void:
	if not is_playing:
		return
	var t: float = clampf(elapsed / maxf(0.01, duration), 0.0, 1.0)
	var inv_t: float = 1.0 - t
	var ease_out: float = 1.0 - pow(inv_t, 2.4)

	# Expanding shockwave ring
	var ring_r: float = lerpf(10.0, 68.0 * burst_scale, ease_out)
	var ring_col := Color(burst_color.r, burst_color.g, burst_color.b, 0.88 * inv_t)
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 28, ring_col, maxf(1.2, 4.5 * inv_t * burst_scale))

	# Core flash
	if t < 0.35:
		var flash_a: float = (1.0 - t / 0.35) * 0.72
		draw_circle(Vector2.ZERO, 20.0 * burst_scale * (1.0 - t), Color(1.0, 0.98, 0.88, flash_a))

	# Radial sparks
	for i in range(_dirs.size()):
		var d: Vector2 = _dirs[i]
		var spd: float = _speeds[i] * burst_scale
		var head: Vector2 = d * (spd * ease_out)
		var tail: Vector2 = d * (spd * maxf(0.0, ease_out - 0.28))
		var spark_col := Color(1.0, 0.96, 0.80, 0.92 * inv_t) if i % 3 == 0 else Color(burst_color.r, burst_color.g, burst_color.b, 0.90 * inv_t)
		draw_line(tail, head, spark_col, maxf(1.2, 3.0 * inv_t))
