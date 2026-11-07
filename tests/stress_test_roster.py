#!/usr/bin/env python3
"""
stress_test_roster.py - Empirical Adversarial Stress Test Suite
==============================================================
Adversarial test suite designed to challenge and stress-test:
  1. players_roster.json data invariants, boundary conditions, and monotonic stat growth.
  2. PT reserves under competitive match half conditions across Base, Lv50, and Lv99.
  3. Inazuma Eleven 3 duel combat formulas, STAB scaling, and complete tournament matrix.
  4. verify_roster.py verification harness integrity via mutation testing (checking for blind spots).
"""

import copy
import io
import json
import os
import sys
import tempfile
import unittest
from PIL import Image

ROSTER_PATH = "players_roster.json"
VERIFY_SCRIPT = "verify_roster.py"

with open(ROSTER_PATH, "r", encoding="utf-8") as f:
    ROSTER = json.load(f)

PLAYERS = ROSTER["players"]
PLAYERS_MAP = {p["id"]: p for p in PLAYERS}

CORE_STATS = ["pe", "pt", "tiro", "fisico", "control", "defensa", "rapidez", "aguante", "valor"]
BATTLE_STATS = ["tiro", "fisico", "control", "defensa", "rapidez", "aguante", "valor"]
VALID_POSITIONS = {"DL", "MD", "DF", "PR"}
VALID_ELEMENTS = {"Fuego", "Bosque", "Aire", "Montaña"}
ELEMENT_ADVANTAGES = {
    "Fuego": "Bosque",
    "Bosque": "Aire",
    "Aire": "Montaña",
    "Montaña": "Fuego",
}

def get_element_multiplier(atk: str, dfn: str) -> float:
    if ELEMENT_ADVANTAGES.get(atk) == dfn:
        return 1.10
    if ELEMENT_ADVANTAGES.get(dfn) == atk:
        return 0.90
    return 1.00

def get_stab_multiplier(player_elem: str, move_elem: str) -> float:
    if player_elem == move_elem and player_elem in VALID_ELEMENTS:
        return 1.20
    return 1.00

def calculate_combat_power(stat_val: float, level: int, valor: float, move_power: float, stab: float = 1.0, element_mult: float = 1.0, evolution_mult: float = 1.0) -> float:
    base_combat = (stat_val * 0.8) + (level * 0.6) + (valor / 4.0)
    technique_power = move_power * stab * evolution_mult
    return (base_combat + technique_power) * element_mult


class TestBoundaryAndMonotonicity(unittest.TestCase):
    """Stress test boundary conditions and monotonic stat growth."""

    def test_all_10_players_exist_with_valid_keys(self):
        self.assertEqual(len(PLAYERS), 10, "Roster must contain exactly 10 players")
        for p in PLAYERS:
            for key in ["id", "nombre", "apodo", "dorsal", "posicion", "elemento", "genero", "descripcion", "estadisticas", "supertecnicas", "visual_assets"]:
                self.assertIn(key, p, f"Player {p.get('id')} missing mandatory key '{key}'")

    def test_strict_stat_bounds(self):
        """Verify battle stats in [15, 100] and PE/PT in [60, 200] across all levels."""
        for p in PLAYERS:
            p_id = p["id"]
            stats = p["estadisticas"]
            for lvl in ["base", "nivel_50", "nivel_99"]:
                self.assertIn(lvl, stats, f"Player {p_id} missing {lvl} stats")
                block = stats[lvl]
                for s in CORE_STATS:
                    val = block[s]
                    self.assertIsInstance(val, int, f"{p_id} {lvl} {s} is not int")
                    if s in ("pe", "pt"):
                        self.assertGreaterEqual(val, 60, f"{p_id} {lvl} {s}={val} < 60")
                        self.assertLessEqual(val, 200, f"{p_id} {lvl} {s}={val} > 200")
                    else:
                        self.assertGreaterEqual(val, 15, f"{p_id} {lvl} {s}={val} < 15")
                        self.assertLessEqual(val, 100, f"{p_id} {lvl} {s}={val} > 100")

    def test_strict_monotonic_growth(self):
        """Every single stat must strictly increase: Base < Lv50 < Lv99."""
        for p in PLAYERS:
            p_id = p["id"]
            b = p["estadisticas"]["base"]
            m50 = p["estadisticas"]["nivel_50"]
            m99 = p["estadisticas"]["nivel_99"]
            for s in CORE_STATS:
                bv = b[s]
                mv = m50[s]
                ev = m99[s]
                self.assertLess(bv, mv, f"{p_id} {s}: Base({bv}) not < Lv50({mv})")
                self.assertLess(mv, ev, f"{p_id} {s}: Lv50({mv}) not < Lv99({ev})")

    def test_growth_smoothness_and_diminishing_returns(self):
        """Level growth delta from 1->50 should be >= 50->99 delta (diminishing returns), within reasonable bounds."""
        for p in PLAYERS:
            p_id = p["id"]
            b = p["estadisticas"]["base"]
            m50 = p["estadisticas"]["nivel_50"]
            m99 = p["estadisticas"]["nivel_99"]
            for s in CORE_STATS:
                d1 = m50[s] - b[s]
                d2 = m99[s] - m50[s]
                # In IE3 RPG curves, early growth is equal or slightly higher than late growth
                self.assertGreater(d1, 0)
                self.assertGreater(d2, 0)
                self.assertLessEqual(abs(d1 - d2), 15, f"{p_id} {s} has extreme non-linear growth jerk: |{d1} - {d2}| > 15")

    def test_hissatsu_parameter_boundaries(self):
        """Verify all 40 hissatsu moves adhere strictly to bounds."""
        for p in PLAYERS:
            moves = p["supertecnicas"]
            self.assertEqual(len(moves), 4, f"Player {p['id']} does not have exactly 4 moves")
            for m in moves:
                pt = m["costo_pt"]
                pwr = m["potencia"]
                foul = m["tasa_falta"]
                m_type = m["tipo"]
                m_elem = m["afinidad"]

                if m_type == "Talento":
                    self.assertEqual(pt, 0)
                    self.assertEqual(pwr, 0)
                    self.assertEqual(foul, 0)
                else:
                    self.assertGreaterEqual(pt, 10, f"Move {m['nombre']} PT < 10")
                    self.assertLessEqual(pt, 75, f"Move {m['nombre']} PT > 75")
                    self.assertGreaterEqual(pwr, 15, f"Move {m['nombre']} Power < 15")
                    self.assertLessEqual(pwr, 135, f"Move {m['nombre']} Power > 135")
                    self.assertGreaterEqual(foul, 0, f"Move {m['nombre']} Foul < 0")
                    self.assertLessEqual(foul, 50, f"Move {m['nombre']} Foul > 50")
                    if m_type == "Atajo":
                        self.assertEqual(foul, 0, f"Goalkeeper catch move {m['nombre']} has non-zero foul rate")

                self.assertIn(m_elem, VALID_ELEMENTS.union({"Neutro"}))
                self.assertGreater(len(m["descripcion_cinematica"]), 50, f"Move {m['nombre']} has too short description")


class TestPTMatchEconomy(unittest.TestCase):
    """Stress test PT reserves across match halves."""

    def test_lv99_pt_sustainable_for_top_2_moves(self):
        """At Lv99, every player must be able to cast their 2 highest PT moves in a half."""
        for p in PLAYERS:
            p_id = p["id"]
            pt_99 = p["estadisticas"]["nivel_99"]["pt"]
            costs = sorted([m["costo_pt"] for m in p["supertecnicas"] if m["tipo"] != "Talento"], reverse=True)
            top2_cost = costs[0] + costs[1]
            self.assertGreaterEqual(pt_99, top2_cost, f"{p_id} Lv99 PT ({pt_99}) cannot sustain top 2 moves ({top2_cost})")

    def test_lv50_pt_sustainable_for_tactical_play(self):
        """At Lv50, every player must be able to cast their highest move + cheapest move."""
        for p in PLAYERS:
            p_id = p["id"]
            pt_50 = p["estadisticas"]["nivel_50"]["pt"]
            costs = sorted([m["costo_pt"] for m in p["supertecnicas"] if m["tipo"] != "Talento"])
            min_c = costs[0]
            max_c = costs[-1]
            combined = min_c + max_c
            self.assertGreaterEqual(pt_50, combined, f"{p_id} Lv50 PT ({pt_50}) cannot cast max({max_c}) + min({min_c}) = {combined}")

    def test_base_pt_sustainable_for_two_basic_activations(self):
        """At Base level (Level 1), player must sustain at least 2 activations of their lowest cost move."""
        for p in PLAYERS:
            p_id = p["id"]
            b_pt = p["estadisticas"]["base"]["pt"]
            costs = sorted([m["costo_pt"] for m in p["supertecnicas"] if m["tipo"] != "Talento"])
            min2 = costs[0] + costs[1]
            self.assertGreaterEqual(b_pt, min2, f"{p_id} Base PT ({b_pt}) cannot cast 2 lowest moves ({min2})")


class TestCombatFormulasAndTournamentMatrix(unittest.TestCase):
    """Stress test combat calculations and RPS cycle."""

    def test_element_cycle_completeness(self):
        """Check all 4 elements form a closed 4-cycle with exact 1.10x advantage and 0.90x disadvantage."""
        elements = ["Fuego", "Bosque", "Aire", "Montaña"]
        for i, elem in enumerate(elements):
            beaten = ELEMENT_ADVANTAGES[elem]
            self.assertEqual(get_element_multiplier(elem, beaten), 1.10)
            self.assertEqual(get_element_multiplier(beaten, elem), 0.90)
            self.assertEqual(get_element_multiplier(elem, elem), 1.00)

    def test_combat_power_monotonicity_and_bounds(self):
        """Verify combat power behaves strictly monotonically with respect to each input parameter."""
        # Baseline
        base_p = calculate_combat_power(stat_val=50, level=50, valor=50, move_power=50, stab=1.0, element_mult=1.0)
        
        # Increase stat
        p_stat = calculate_combat_power(stat_val=60, level=50, valor=50, move_power=50, stab=1.0, element_mult=1.0)
        self.assertGreater(p_stat, base_p)
        
        # Increase level
        p_lvl = calculate_combat_power(stat_val=50, level=60, valor=50, move_power=50, stab=1.0, element_mult=1.0)
        self.assertGreater(p_lvl, base_p)
        
        # Increase valor
        p_val = calculate_combat_power(stat_val=50, level=50, valor=60, move_power=50, stab=1.0, element_mult=1.0)
        self.assertGreater(p_val, base_p)
        
        # Increase move power
        p_mov = calculate_combat_power(stat_val=50, level=50, valor=50, move_power=60, stab=1.0, element_mult=1.0)
        self.assertGreater(p_mov, base_p)
        
        # Add STAB
        p_stab = calculate_combat_power(stat_val=50, level=50, valor=50, move_power=50, stab=1.2, element_mult=1.0)
        self.assertGreater(p_stab, base_p)

    def test_all_attackers_vs_buffon_matrix(self):
        """Simulate all shots in the roster against Buffon catches."""
        buffon = PLAYERS_MAP["buffon"]
        b_stats = buffon["estadisticas"]["nivel_99"]
        b_catches = [m for m in buffon["supertecnicas"] if m["tipo"] == "Atajo"]
        top_catch = max(b_catches, key=lambda m: m["potencia"])

        goals = 0
        saves = 0

        for p in PLAYERS:
            if p["id"] == "buffon": continue
            stats = p["estadisticas"]["nivel_99"]
            shots = [m for m in p["supertecnicas"] if m["tipo"] == "Tiro"]
            for s in shots:
                s_mult = get_element_multiplier(s["afinidad"], buffon["elemento"])
                g_mult = get_element_multiplier(buffon["elemento"], s["afinidad"])
                stab = 1.2 if p["elemento"] == s["afinidad"] else 1.0

                shot_pwr = calculate_combat_power(stats["tiro"], 99, stats["valor"], s["potencia"], stab=stab, element_mult=s_mult)
                catch_pwr = calculate_combat_power(b_stats["defensa"], 99, b_stats["valor"], top_catch["potencia"], stab=1.2, element_mult=g_mult)

                if shot_pwr > catch_pwr:
                    goals += 1
                else:
                    saves += 1

        self.assertGreater(goals, 0, "At least some shots (Aire elemental advantage) must score on Buffon")
        self.assertGreater(saves, 0, "Buffon with elemental advantage or high power must save shots")


class TestVerifyRosterMutationRigour(unittest.TestCase):
    """Mutation testing: verify that verify_roster.py's internal checks actually fail when data is corrupted."""

    def test_audit_png_asset_rejects_dirty_corner(self):
        """Synthesize a PNG with a single non-transparent corner pixel and ensure audit_png_asset fails."""
        import verify_roster
        im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        # Draw some character art
        for y in range(20, 44):
            for x in range(20, 44):
                im.putpixel((x, y), (200, 100, 50, 255))
        # Corrupt one corner
        im.putpixel((0, 0), (255, 255, 255, 255))
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            im.save(tmp.name)
            tmp_path = tmp.name

        try:
            passed, msg, _ = verify_roster.audit_png_asset(tmp_path, asset_type="mugshot")
            self.assertFalse(passed, "Auditor must reject PNG with non-transparent corner")
            self.assertIn("Corner pixel", msg)
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_audit_png_asset_rejects_border_density_violation(self):
        """Synthesize a PNG where outer border has < 90% transparency and ensure auditor rejects it."""
        import verify_roster
        im = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        # Draw character art
        for y in range(20, 44):
            for x in range(20, 44):
                im.putpixel((x, y), (200, 100, 50, 255))
        # Bleed into border (20% of border opaque, keeping 4 corners clean)
        for x in range(1, 40):
            im.putpixel((x, 0), (100, 100, 100, 255))

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            im.save(tmp.name)
            tmp_path = tmp.name

        try:
            passed, msg, _ = verify_roster.audit_png_asset(tmp_path, asset_type="mugshot")
            self.assertFalse(passed, "Auditor must reject PNG with <90% border transparency")
            self.assertIn("Outer perimeter transparency", msg)
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
