from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_result_page_and_popup_delegate_to_result_presenter():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    result = (ROOT / "ui/screens/result_screen.gd").read_text(encoding="utf-8")

    assert 'preload("res://ui/screens/result_screen.gd")' in main
    assert "var _result_screen = ResultScreenScript.new()" in main
    assert "_result_screen.build_buttons(self, _ui_screen_theme)" in main
    assert "_result_screen.render(self, _ui_screen_theme)" in main
    assert "_result_screen.render_popup(self, _ui_screen_theme)" in main
    assert "func build_buttons(host, theme: Dictionary) -> void:" in result
    assert "func render(host, theme: Dictionary) -> void:" in result
    assert "func render_popup(host, theme: Dictionary) -> void:" in result
    assert "امتیاز رتبه‌ای ثبت نشد" in result
    assert "لیگ ماهانه" in result


def test_result_logic_and_scoring_ownership_stay_in_controller():
    main = (ROOT / "main.gd").read_text(encoding="utf-8")
    result = (ROOT / "ui/screens/result_screen.gd").read_text(encoding="utf-8")

    assert "func _result_info() -> Dictionary:" in main
    assert "func _go_result(_won: bool = false) -> void:" in main
    assert "scoring_service.record_result" in main
    assert "host.scoring_service.record_result" not in result
    assert "host.state =" not in result
    assert "host._result_delta =" not in result
    assert "host._result_logged =" not in result
