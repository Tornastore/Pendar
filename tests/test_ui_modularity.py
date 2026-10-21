from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_ui_content_is_externalized_from_main_controller():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    content = (ROOT / "core" / "ui_content.gd").read_text(encoding="utf-8")
    assert 'preload("res://core/ui_content.gd")' in main
    assert '"quarto": [' in content
    assert 'const GENERAL_HELP :=' in content
    assert 'const MM_COLORS :=' in content
    assert 'const RULES :=' not in main


def test_rendering_wrappers_remain_available_for_game_modules():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    illustration = (ROOT / "ui" / "illustration_renderer.gd").read_text(encoding="utf-8")
    tabletop = (ROOT / "ui" / "tabletop_art_renderer.gd").read_text(encoding="utf-8")

    assert 'preload("res://ui/illustration_renderer.gd")' in main
    assert 'preload("res://ui/tabletop_art_renderer.gd")' in main
    for method in ("_draw_icon", "_draw_game_art", "_draw_disc", "_draw_card", "_draw_dom_tile", "_draw_chess_piece"):
        assert f"func {method}(" in main
    assert "func draw_game_art(" in illustration
    assert "func draw_card(" in tabletop
    assert "func draw_chess_piece(" in tabletop
    assert "_canvas.draw_circle(" in tabletop


def test_existing_python_install_fix_is_preserved_in_both_web_workflows():
    for relative in (".github/workflows/build-web.yml", ".github/workflows/deploy-web.yml"):
        workflow = (ROOT / relative).read_text(encoding="utf-8")
        assert "Install Python 3" in workflow
        assert "python3 --version" in workflow
