#!/usr/bin/env python3
"""
test_mutations.py - Adversarial Mutation Testing for verify_roster.py
====================================================================
Synthesizes mutated, corrupt versions of players_roster.json and passes them
to verify_roster.py's verification functions to verify that every corruption is caught.
"""

import copy
import json
import os
import sys
import unittest
import verify_roster

with open("players_roster.json", "r", encoding="utf-8") as f:
    CLEAN_ROSTER = json.load(f)


class TestVerifyRosterMutationSurvival(unittest.TestCase):
    """Ensure verify_roster catches any data corruption or specification violation."""

    def run_suite_on_roster(self, data):
        suite = verify_roster.TestSuite(verbose=False)
        verify_roster.run_tier_1_schema(suite, data, "synthetic.json", ".")
        verify_roster.run_tier_2_boundaries(suite, data, ".")
        verify_roster.run_tier_3_transparency_and_cross(suite, data, ".")
        verify_roster.run_tier_4_simulations(suite, data, ".")
        failed = sum(1 for a in suite.assertions if not a.passed)
        return failed, suite.assertions

    def test_clean_roster_has_zero_failures(self):
        failed, _ = self.run_suite_on_roster(CLEAN_ROSTER)
        self.assertEqual(failed, 0, "Clean roster must produce exactly 0 failures")

    def test_mutation_stat_exceeds_100(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        corrupt["players"][0]["estadisticas"]["nivel_99"]["tiro"] = 101
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("tiro=101 outside" in (a.details or "") for a in assertions))

    def test_mutation_stat_below_15(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        corrupt["players"][0]["estadisticas"]["base"]["defensa"] = 14
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("defensa=14 outside" in (a.details or "") for a in assertions))

    def test_mutation_inverted_monotonic_growth(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        # Invert base and lv50
        corrupt["players"][0]["estadisticas"]["base"]["rapidez"] = 70
        corrupt["players"][0]["estadisticas"]["nivel_50"]["rapidez"] = 65
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("violated" in (a.details or "") for a in assertions))

    def test_mutation_move_pt_exceeds_75(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        corrupt["players"][0]["supertecnicas"][0]["costo_pt"] = 76
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("T2.4_move_pt_bound" in a.name and not a.passed for a in assertions))

    def test_mutation_move_pt_below_10(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        corrupt["players"][0]["supertecnicas"][0]["costo_pt"] = 9
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("T2.4_move_pt_bound" in a.name and not a.passed for a in assertions))

    def test_mutation_move_power_exceeds_135(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        corrupt["players"][0]["supertecnicas"][0]["potencia"] = 136
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("T2.5_move_power_bound" in a.name and not a.passed for a in assertions))

    def test_mutation_gk_catch_has_foul(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        # Find goalkeeper and add foul to catch move
        for p in corrupt["players"]:
            if p["posicion"] == "PR":
                p["supertecnicas"][0]["tasa_falta"] = 15
                break
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("T2.6_move_foul_bound" in a.name and not a.passed for a in assertions))

    def test_mutation_invalid_position_enum(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        corrupt["players"][0]["posicion"] = "CF"
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("T1.7_player_pos_enum" in a.name and not a.passed for a in assertions))

    def test_mutation_invalid_element_enum(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        corrupt["players"][0]["elemento"] = "Agua"
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("T1.8_player_element_enum" in a.name and not a.passed for a in assertions))

    def test_mutation_wrong_player_count(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        corrupt["players"].pop()  # 9 players
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("T1.4_exact_10_players_count" in a.name and not a.passed for a in assertions))

    def test_mutation_wrong_move_count(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        corrupt["players"][0]["supertecnicas"].pop()  # 3 moves
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("T1.10_player_moves_count" in a.name and not a.passed for a in assertions))

    def test_mutation_dl_without_shot(self):
        corrupt = copy.deepcopy(CLEAN_ROSTER)
        # Turn all shots of Haaland into Bloqueo
        for m in corrupt["players"][0]["supertecnicas"]:
            if m["tipo"] == "Tiro":
                m["tipo"] = "Bloqueo"
        failed, assertions = self.run_suite_on_roster(corrupt)
        self.assertGreater(failed, 0)
        self.assertTrue(any("T3.1_positional_suitability" in a.name and not a.passed for a in assertions))


if __name__ == "__main__":
    unittest.main(verbosity=2)
