#!/usr/bin/env python3
"""Apply PENDAR branding to the generated Godot Web export."""
from pathlib import Path
import re, shutil, sys
project = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]) if len(sys.argv) > 1 else project / "build" / "web"
index = out / "index.html"
if not index.is_file():
    raise SystemExit(f"Missing Web export entry point: {index}")
for favicon_name in ("favicon.png", "favicon.ico"):
    source_icon = project / favicon_name
    if source_icon.is_file():
        shutil.copy2(source_icon, out / favicon_name)
branding_out = out / "branding"
branding_out.mkdir(exist_ok=True)
logo = project / "branding" / "pendar_logo.png"
if logo.is_file():
    shutil.copy2(logo, branding_out / "pendar_logo.png")
html = index.read_text(encoding="utf-8")
title = "<title>PENDAR | پندار — بازی‌های فکری و رقابتی</title>"
title_pattern = r"<title\b[^>]*>.*?</title>"
if re.search(title_pattern, html, flags=re.I | re.S):
    html = re.sub(title_pattern, title, html, count=1, flags=re.I | re.S)
else:
    html = re.sub(r"<head\b[^>]*>", lambda m: m.group(0) + "\n" + title, html, count=1, flags=re.I)
head_tags = (
    '\n<meta name="application-name" content="PENDAR">\n'
    '<meta name="theme-color" content="#030b1b">\n'
    '<meta property="og:site_name" content="PENDAR | پندار">\n'
    '<link rel="icon" href="./favicon.ico" sizes="any">\n'
    '<link rel="icon" type="image/png" sizes="256x256" href="./favicon.png">\n'
    '<link rel="apple-touch-icon" href="./branding/pendar_logo.png">\n'
)
if 'href="./favicon.png"' not in html:
    html = re.sub(r"</head>", head_tags + "</head>", html, count=1, flags=re.I)
index.write_text(html, encoding="utf-8")
print("PENDAR branding applied: browser title, favicon and app metadata.")
