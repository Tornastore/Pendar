from pathlib import Path
import re


def test_hokm_is_released_and_not_marked_experimental() -> None:
    root = Path(__file__).resolve().parents[1]
    catalog = (root / "core" / "game_catalog.gd").read_text(encoding="utf-8")
    hokm_entries = [line for line in catalog.splitlines() if '"id": "hokm"' in line]

    assert len(hokm_entries) == 1, "Hokm must have exactly one catalogue entry"
    assert re.search(r'"beta"\s*:\s*false', hokm_entries[0]), (
        "Hokm must be a released game so the menu and mode screen do not show the experimental badge"
    )

    readme = (root / "games" / "hokm" / "README.md").read_text(encoding="utf-8")
    assert "نسخهٔ عمومی و فعال" in readme
