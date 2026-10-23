"""Static guardrails for the chess runtime regression suite and legal-move engine."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def test_chess_runtime_regression_suite_covers_legality_undo_and_cpu_safety() -> None:
    suite = read("tests/godot/test_chess_rules.gd")
    for marker in (
        "_test_king_safety_and_pins()",
        "_test_start_position_perft()",
        "_perft(game, 3)",
        "== 8902",
        "== 2812",
        "exact pre-capture position",
        "_test_castling_and_undo()",
        "_test_capture_undo_and_move_counters()",
        "_test_en_passant_and_undo()",
        "_test_promotion_and_undo()",
        "_test_mate_stalemate_and_draw_claims()",
        "_test_cpu_undo()",
        "_test_ai_finds_mate_in_one()",
        "_test_ai_generates_underpromotion_choices()",
        "human cannot claim draw on the CPU turn",
        "CHESS_RULES_TESTS: checks=%d, failures=%d",
    ):
        assert marker in suite, f"Chess regression coverage missing: {marker}"


def test_both_web_workflows_run_and_require_a_clean_godot_chess_test_summary() -> None:
    for relative in (".github/workflows/build-web.yml", ".github/workflows/deploy-web.yml"):
        workflow = read(relative)
        assert "Run chess rules regression tests" in workflow
        assert "res://tests/godot/test_chess_rules.gd" in workflow
        assert "CHESS_RULES_TESTS: .*failures=[1-9][0-9]*" in workflow
        assert "CHESS_RULES_TESTS: checks=[0-9]+, failures=0" in workflow


def test_ai_evaluates_each_underpromotion_as_a_distinct_legal_move() -> None:
    rules = read("games/chess/rules.gd")
    ai = read("games/chess/ai.gd")
    assert "for promotion_type in [5, 4, 3, 2]:" in rules
    assert "func _promotion_type_from_move(move: Array) -> int:" in ai
    assert "var promotion_type: int = int(best[2]) if best.size() >= 3 else 5" in rules
    assert "_chess_make_move(best[0], best[1], promotion_type)" in rules
    assert "score += 8000.0 + float(PIECE_VALUES[promotion_type])" in ai
    assert "return repetitions >= 5" in ai
    assert "return repetitions >= 3" in ai
    assert "return maxf(score, DRAW_SCORE) if side == 2 else minf(score, DRAW_SCORE)" in ai
