extends SceneTree

# ==============================================================================
# Automated Headless E2E Test Runner for Inazuma Inspired Arcade Soccer
# Target: Godot Engine 4.3 Stable CLI
# Usage: /home/damian/.local/bin/godot --headless --script tests/test_runner.gd
# ==============================================================================

const SUITE_PATHS: Array[String] = [
	"res://tests/test_kits_differentiation.gd",
	"res://tests/test_pitch_camera.gd",
	"res://tests/test_skills_hitstop.gd",
	"res://tests/test_pooling_warmup.gd",
	"res://tests/test_physics_invariants.gd",
	"res://tests/test_hud_hierarchy.gd",
	"res://tests/test_arcade_improvements.gd"
]

func _init() -> void:
	call_deferred("_run_test_harness")

func _run_test_harness() -> void:
	var start_usec = Time.get_ticks_usec()
	
	print("================================================================================")
	print("       INAZUMA INSPIRED ARCADE SOCCER — 4-TIER E2E AUTOMATED TEST RUNNER        ")
	print("================================================================================")
	print("Godot Engine Version : ", Engine.get_version_info().string)
	print("Operating Mode       : Headless CLI (GL Compatibility / Mobile)")
	print("Project Root         : res://")
	print("Time (UTC)           : ", Time.get_datetime_string_from_system(true, true))
	print("================================================================================")
	print("")
	
	var total_assertions = 0
	var total_passed = 0
	var total_failed = 0
	var all_failures: Array[String] = []
	
	var tier_totals: Dictionary = {
		1: {"total": 0, "passed": 0, "failed": 0},
		2: {"total": 0, "passed": 0, "failed": 0},
		3: {"total": 0, "passed": 0, "failed": 0},
		4: {"total": 0, "passed": 0, "failed": 0}
	}
	
	var suite_reports: Array[Dictionary] = []
	
	for suite_path in SUITE_PATHS:
		var suite_name = suite_path.get_file().get_basename()
		print("[RUNNING] %s ..." % suite_name)
		
		if not FileAccess.file_exists(suite_path):
			printerr("[ERROR] Test suite file missing: %s" % suite_path)
			total_failed += 1
			all_failures.append("Suite file missing: " + suite_path)
			continue
		
		var SuiteScript = load(suite_path)
		if SuiteScript == null:
			printerr("[ERROR] Failed to compile/load test suite: %s" % suite_path)
			total_failed += 1
			all_failures.append("Compilation failure: " + suite_path)
			continue
		
		var suite_instance = SuiteScript.new()
		if not suite_instance.has_method("run_all"):
			printerr("[ERROR] Test suite lacks 'run_all()' method: %s" % suite_path)
			total_failed += 1
			all_failures.append("Missing run_all in: " + suite_path)
			continue
		
		suite_instance.run_all()
		
		total_assertions += suite_instance.total_assertions
		total_passed += suite_instance.passed_assertions
		total_failed += suite_instance.failed_assertions
		all_failures.append_array(suite_instance.failures)
		
		for t in [1, 2, 3, 4]:
			tier_totals[t]["total"] += suite_instance.tier_counts[t]["total"]
			tier_totals[t]["passed"] += suite_instance.tier_counts[t]["passed"]
			tier_totals[t]["failed"] += suite_instance.tier_counts[t]["failed"]
		
		suite_reports.append({
			"name": suite_instance.suite_name,
			"path": suite_path.get_file(),
			"total": suite_instance.total_assertions,
			"passed": suite_instance.passed_assertions,
			"failed": suite_instance.failed_assertions,
			"tier_counts": suite_instance.tier_counts.duplicate(true)
		})
		
		var status_badge = "[PASS]" if suite_instance.failed_assertions == 0 else "[FAIL]"
		print("  %s %s: %d assertions passed (%d failed)" % [
			status_badge,
			suite_instance.suite_name,
			suite_instance.passed_assertions,
			suite_instance.failed_assertions
		])
		suite_instance.free()
	
	var elapsed_ms = (Time.get_ticks_usec() - start_usec) / 1000.0
	
	print("")
	print("================================================================================")
	print("                             E2E SUITE SUMMARY TABLE                            ")
	print("================================================================================")
	print("%-28s | %-6s | %-6s | %-6s | %-6s | %-6s" % [
		"Test Suite", "Tier 1", "Tier 2", "Tier 3", "Passed", "Failed"
	])
	print("--------------------------------------------------------------------------------")
	for rep in suite_reports:
		var t1 = rep["tier_counts"][1]["passed"]
		var t2 = rep["tier_counts"][2]["passed"]
		var t3 = rep["tier_counts"][3]["passed"]
		print("%-28s | %-6d | %-6d | %-6d | %-6d | %-6d" % [
			rep["name"], t1, t2, t3, rep["passed"], rep["failed"]
		])
	print("--------------------------------------------------------------------------------")
	print("%-28s | %-6d | %-6d | %-6d | %-6d | %-6d" % [
		"TOTALS",
		tier_totals[1]["passed"],
		tier_totals[2]["passed"],
		tier_totals[3]["passed"],
		total_passed,
		total_failed
	])
	print("================================================================================")
	print("")
	print("TIER COVERAGE SUMMARY:")
	print("  Tier 1 (Feature Coverage)        : %d assertions" % tier_totals[1]["passed"])
	print("  Tier 2 (Boundary & Corner Cases) : %d assertions" % tier_totals[2]["passed"])
	print("  Tier 3 (Cross-Feature Integrat.) : %d assertions" % tier_totals[3]["passed"])
	print("  TOTAL ASSERTIONS VERIFIED        : %d" % total_assertions)
	print("  EXECUTION TIME                   : %.2f ms" % elapsed_ms)
	print("")
	
	if total_failed == 0:
		print("================================================================================")
		print("           OVERALL RESULT: [PASS] ALL ASSERTIONS COMPLETED CLEANLY              ")
		print("================================================================================")
		quit(0)
	else:
		print("================================================================================")
		print("           OVERALL RESULT: [FAIL] %d ASSERTION(S) FAILED                        " % total_failed)
		print("================================================================================")
		print("Failures:")
		for f in all_failures:
			print("  ", f)
		quit(1)
