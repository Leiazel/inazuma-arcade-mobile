class_name BaseTest
extends SceneTree

var suite_name: String = "BaseTest"
var total_assertions: int = 0
var passed_assertions: int = 0
var failed_assertions: int = 0
var failures: Array[String] = []

var tier_counts: Dictionary = {
	1: {"total": 0, "passed": 0, "failed": 0},
	2: {"total": 0, "passed": 0, "failed": 0},
	3: {"total": 0, "passed": 0, "failed": 0},
	4: {"total": 0, "passed": 0, "failed": 0}
}
var current_tier: int = 1

func _init() -> void:
	var script_file = ""
	if get_script() != null:
		script_file = get_script().resource_path.get_file()
	
	var is_standalone = false
	for arg in OS.get_cmdline_args():
		if not script_file.is_empty() and arg.ends_with(script_file):
			is_standalone = true
			break
	
	if is_standalone:
		call_deferred("_run_standalone")

func _run_standalone() -> void:
	if has_method("run_all"):
		call("run_all")
	print_summary()
	if failed_assertions > 0:
		quit(1)
	else:
		quit(0)

func set_tier(tier: int) -> void:
	current_tier = tier

func assert_true(condition: bool, msg: String = "") -> bool:
	total_assertions += 1
	tier_counts[current_tier]["total"] += 1
	if condition:
		passed_assertions += 1
		tier_counts[current_tier]["passed"] += 1
		return true
	else:
		failed_assertions += 1
		tier_counts[current_tier]["failed"] += 1
		var err = "[FAIL] [%s] [Tier %d] %s" % [suite_name, current_tier, msg]
		failures.append(err)
		printerr(err)
		return false

func assert_false(condition: bool, msg: String = "") -> bool:
	return assert_true(not condition, msg if not msg.is_empty() else "Expected false, got true")

func assert_eq(actual, expected, msg: String = "") -> bool:
	var ok = (actual == expected)
	var detail = "%s (Expected %s, got %s)" % [msg, str(expected), str(actual)]
	return assert_true(ok, detail)

func assert_ne(actual, expected, msg: String = "") -> bool:
	var ok = (actual != expected)
	var detail = "%s (Expected not %s, got %s)" % [msg, str(expected), str(actual)]
	return assert_true(ok, detail)

func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.001, msg: String = "") -> bool:
	var diff = absf(actual - expected)
	var ok = diff <= tolerance
	var detail = "%s (Expected %.5f ± %.5f, got %.5f, diff=%.5f)" % [msg, expected, tolerance, actual, diff]
	return assert_true(ok, detail)

func assert_vector_almost_eq(actual: Vector2, expected: Vector2, tolerance: float = 0.001, msg: String = "") -> bool:
	var diff = actual.distance_to(expected)
	var ok = diff <= tolerance
	var detail = "%s (Expected %s ± %.4f, got %s, dist=%.4f)" % [msg, str(expected), tolerance, str(actual), diff]
	return assert_true(ok, detail)

func assert_color_almost_eq(actual: Color, expected: Color, tolerance: float = 0.01, msg: String = "") -> bool:
	var dr = absf(actual.r - expected.r)
	var dg = absf(actual.g - expected.g)
	var db = absf(actual.b - expected.b)
	var da = absf(actual.a - expected.a)
	var ok = dr <= tolerance and dg <= tolerance and db <= tolerance and da <= tolerance
	var detail = "%s (Expected %s ± %.3f, got %s)" % [msg, str(expected), tolerance, str(actual)]
	return assert_true(ok, detail)

func assert_in_range(val: float, min_val: float, max_val: float, msg: String = "") -> bool:
	var ok = (val >= min_val and val <= max_val)
	var detail = "%s (Value %.4f should be in [%.4f, %.4f])" % [msg, val, min_val, max_val]
	return assert_true(ok, detail)

func assert_not_null(obj, msg: String = "") -> bool:
	var ok = (obj != null)
	return assert_true(ok, msg if not msg.is_empty() else "Expected non-null object")

func assert_null(obj, msg: String = "") -> bool:
	var ok = (obj == null)
	return assert_true(ok, msg if not msg.is_empty() else "Expected null object")

func print_summary() -> void:
	print("==================================================================")
	print("Suite: %s" % suite_name)
	print("Assertions: Total %d | Passed %d | Failed %d" % [total_assertions, passed_assertions, failed_assertions])
	for t in [1, 2, 3, 4]:
		var tc = tier_counts[t]
		if tc["total"] > 0:
			print("  Tier %d: %d/%d passed (%d failed)" % [t, tc["passed"], tc["total"], tc["failed"]])
	if failed_assertions > 0:
		print("Failures:")
		for f in failures:
			print("  ", f)
	print("==================================================================")
