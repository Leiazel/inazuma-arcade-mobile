class_name ColorClashDetector
extends RefCounted

## Utility implementing perceptual color difference algorithms (Redmean)
## to detect chromatic clashes between team kits and automatically arbitrate selection.

## Perceptual clash threshold tau. Values below this trigger kit switching.
const CLASH_THRESHOLD: float = 0.38

## Weight factors for total kit chromatic distance (70% primary, 30% secondary)
const PRIMARY_WEIGHT: float = 0.70
const SECONDARY_WEIGHT: float = 0.30

## Computes the normalized perceptual Redmean distance between two colors in [0.0, 1.0].
## Formula: delta_C = sqrt((2.0 + r_mean) * dR^2 + 4.0 * dG^2 + (3.0 - r_mean) * dB^2) / 3.0
static func calculate_color_distance(c1: Color, c2: Color) -> float:
	if is_nan(c1.r) or is_nan(c1.g) or is_nan(c1.b) or is_nan(c2.r) or is_nan(c2.g) or is_nan(c2.b):
		return NAN
	var r1: float = clampf(c1.r, 0.0, 1.0)
	var g1: float = clampf(c1.g, 0.0, 1.0)
	var b1: float = clampf(c1.b, 0.0, 1.0)
	var r2: float = clampf(c2.r, 0.0, 1.0)
	var g2: float = clampf(c2.g, 0.0, 1.0)
	var b2: float = clampf(c2.b, 0.0, 1.0)
	
	var r_mean: float = 0.5 * (r1 + r2)
	var dr: float = r1 - r2
	var dg: float = g1 - g2
	var db: float = b1 - b2
	
	var weight_r: float = 2.0 + r_mean
	var weight_g: float = 4.0
	var weight_b: float = 3.0 - r_mean
	
	var delta_sq: float = maxf(0.0, (weight_r * dr * dr) + (weight_g * dg * dg) + (weight_b * db * db))
	return sqrt(delta_sq) / 3.0

## Alias for calculate_color_distance
static func calculate_distance(c1: Color, c2: Color) -> float:
	return calculate_color_distance(c1, c2)

## Alias for compute_color_distance
static func compute_color_distance(c1: Color, c2: Color) -> float:
	return calculate_color_distance(c1, c2)

## Computes total chromatic distance between two KitData resources
static func calculate_kit_distance(kit_a: KitData, kit_b: KitData) -> float:
	if kit_a == null or kit_b == null:
		return 1.0
	var dist_prim: float = calculate_color_distance(kit_a.primary_color, kit_b.primary_color)
	var dist_sec: float = calculate_color_distance(kit_a.secondary_color, kit_b.secondary_color)
	if is_nan(dist_prim) or is_nan(dist_sec):
		return NAN
	return (dist_prim * PRIMARY_WEIGHT) + (dist_sec * SECONDARY_WEIGHT)

## Alias for compute_kit_clash
static func compute_kit_clash(kit_a: KitData, kit_b: KitData) -> float:
	return calculate_kit_distance(kit_a, kit_b)

## Returns true if the chromatic distance between two kits is below the clash threshold
static func is_clashing(kit_a: KitData, kit_b: KitData, threshold: float = CLASH_THRESHOLD) -> bool:
	if kit_a == null or kit_b == null:
		return false
	var distance: float = calculate_kit_distance(kit_a, kit_b)
	if is_nan(distance):
		return true
	return (distance < threshold) and not is_equal_approx(distance, threshold)

## Resolves kit selection: if away_candidate clashes with home, selects away_alt if it provides better contrast
static func resolve_kit_selection(home: KitData, away_candidate: KitData, away_alt: KitData) -> KitData:
	if home == null:
		return away_candidate
	if away_candidate == null:
		return away_alt
	
	# If candidate does not clash, use it directly
	if not is_clashing(home, away_candidate):
		return away_candidate
	
	# If candidate clashes and no alternative is given, keep candidate
	if away_alt == null:
		return away_candidate
	
	var clash_candidate: float = calculate_kit_distance(home, away_candidate)
	var clash_alt: float = calculate_kit_distance(home, away_alt)
	
	if is_nan(clash_candidate) and not is_nan(clash_alt):
		return away_alt
	
	# Select the alternative if it provides higher chromatic distance from home
	if clash_alt > clash_candidate:
		return away_alt
	
	return away_candidate

## Detailed kit arbitration returning a structured dictionary
static func arbitrate_kits(home: KitData, away_candidate: KitData, away_alt: KitData) -> Dictionary:
	var clash_score: float = calculate_kit_distance(home, away_candidate)
	var has_clash: bool = is_nan(clash_score) or ((clash_score < CLASH_THRESHOLD) and not is_equal_approx(clash_score, CLASH_THRESHOLD))
	var selected_away: KitData = resolve_kit_selection(home, away_candidate, away_alt)
	var was_swapped: bool = selected_away != away_candidate
	
	return {
		"home_kit": home,
		"away_kit": selected_away,
		"clash_detected": has_clash,
		"clash_score": clash_score,
		"swapped": was_swapped
	}
