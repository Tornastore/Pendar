from pathlib import Path
import subprocess
import sys


def test_pendar_brand_is_consistent_in_project_and_exports():
    root = Path(__file__).resolve().parents[1]
    project = (root / "project.godot").read_text(encoding="utf-8")
    presets = (root / "export_presets.cfg").read_text(encoding="utf-8")
    main = (root / "main.gd").read_text(encoding="utf-8")
    assert 'config/name="PENDAR | پندار"' in project
    assert 'config/icon="res://icon.png"' in project
    assert 'package/name="PENDAR"' in presets
    assert 'export_path="build/android/Pendar.apk"' in presets
    assert 'res://branding/pendar_logo.png' in main
    menu = (root / "ui" / "screens" / "menu_screen.gd").read_text(encoding="utf-8")
    assert 'draw_texture_rect(host._brand_logo' in menu
    assert (root / "branding" / "pendar_logo.png").is_file()
    assert (root / "branding" / "pendar_emblem.png").is_file()
    assert (root / "favicon.png").is_file()
    assert (root / "favicon.ico").is_file()


def test_web_export_hook_sets_title_and_favicon(tmp_path):
    root = Path(__file__).resolve().parents[1]
    (tmp_path / "index.html").write_text('<!doctype html><html><head><title>Godot</title></head><body></body></html>', encoding="utf-8")
    result = subprocess.run([sys.executable, str(root / "tools" / "brand_web_export.py"), str(tmp_path)], text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    html = (tmp_path / "index.html").read_text(encoding="utf-8")
    assert '<title>PENDAR | پندار — بازی‌های فکری و رقابتی</title>' in html
    assert 'href="./favicon.png"' in html
    assert 'href="./favicon.ico"' in html
    assert (tmp_path / "favicon.png").is_file()
    assert (tmp_path / "favicon.ico").is_file()
    assert (tmp_path / "branding" / "pendar_logo.png").is_file()
