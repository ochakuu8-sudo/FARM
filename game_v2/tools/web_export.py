"""ブラウザ版の書き出し（build/web/）。順に：
  1. 見た目の焼き込み（looks_bake.gd、WebP 品質0.9）… キャラの素材を登録・差し替えたあとに必要
  2. 日本語フォントの部分集合（web_fonts.py）… 文言を足したあとに必要
  3. Godot の Web 書き出し（export_presets.cfg の "Web"：スレッドなし＝スマホ向け）
  4. 計測用のページ bench.html（web_bench.py が使う）

    python game_v2/tools/web_export.py [--skip-bake] [--skip-fonts]

packs（動作データ）は焼き込み（bake.gd）のたびに作り直されるので、ここでは作らない。
ツールや Godot の起動中は焼き込みと同じく避ける。
"""
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT = r"C:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe"
PYTHON = sys.executable
OUT = os.path.join(ROOT, "build", "web")


def run(args, label):
    print("==", label)
    r = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env=dict(os.environ, PYTHONIOENCODING="utf-8"))
    tail = [l for l in (r.stdout + r.stderr).splitlines() if l.strip() and not l.startswith("Godot Engine")]
    for line in tail[-4:]:
        print("   ", line)
    if r.returncode != 0:
        print("失敗:", label)
        sys.exit(1)


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    os.makedirs(OUT, exist_ok=True)
    gdignore = os.path.join(ROOT, "build", ".gdignore")
    if not os.path.exists(gdignore):
        open(gdignore, "w").close()
    if "--skip-bake" not in sys.argv:
        run([GODOT, "--headless", "--path", ".", "--script", "res://game_v2/tools/looks_bake.gd", "--", "--quality=0.9"], "見た目の焼き込み")
    if "--skip-fonts" not in sys.argv:
        run([PYTHON, "game_v2/tools/web_fonts.py"], "日本語フォントの部分集合")
    run([GODOT, "--headless", "--path", ".", "--export-release", "Web", "build/web/index.html"], "Web 書き出し")
    html = open(os.path.join(OUT, "index.html"), encoding="utf-8").read()
    bench = html.replace('"args":[]', '"args":["--","--debug=bench","--setup=mid"]')
    open(os.path.join(OUT, "bench.html"), "w", encoding="utf-8").write(bench)
    for name in ["index.pck", "index.wasm"]:
        print("   %s %.1fMB" % (name, os.path.getsize(os.path.join(OUT, name)) / 1048576.0))
    print("WEB_EXPORT ok  → build/web/index.html（計測は python game_v2/tools/web_bench.py --mobile）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
