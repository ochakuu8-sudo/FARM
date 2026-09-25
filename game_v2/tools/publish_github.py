"""GitHub（ochakuu8-sudo/FARM）へゲームを載せる。作業フォルダは Git にせず、隣の FARM_publish/ に写してからコミットする。
  main      … ゲームのコードと、ゲームが読むデータ（動作データ packs・焼いた見た目 looks・フォント）
  gh-pages  … ブラウザ版（build/web）。GitHub Pages はこのブランチから配信する

    python game_v2/tools/publish_github.py [--message=コミットの説明] [--no-pages]

先に python game_v2/tools/web_export.py でブラウザ版を書き出しておく。
原画・プレビュー画像・old/・docs/・管理ツールは載せない（原画が無いので、見た目の焼き直しはこの作業フォルダで行う）。
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PUB = os.path.join(os.path.dirname(ROOT), "FARM_publish")
REMOTE = "https://github.com/ochakuu8-sudo/FARM.git"
PAGES_URL = "https://ochakuu8-sudo.github.io/FARM/"
TRAILER = "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"

# 載せるもの（ROOT からの相対パス。フォルダは中身ごと）
INCLUDE = [
    "project.godot", "export_presets.cfg", "icon.svg", "icon.svg.import", "ゲームを起動.cmd",
    "game", "game_v2/animation", "game_v2/content",
    "game_v2/assets/bakes/packs", "game_v2/assets/looks",
    "game_v2/tools/web_export.py", "game_v2/tools/web_bench.py", "game_v2/tools/web_fonts.py",
    "game_v2/tools/looks_bake.gd", "game_v2/tools/publish_github.py",
    "mini",
]
SKIP_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bin", ".tmp")
SKIP_DIRS = ("game/tests/out", "mini/layered2d/examples/", "mini/layered2d/tests/", "mini/layered2d/tools/")


def skip(rel: str) -> bool:
    low = rel.lower()
    if low.endswith(".import"):
        # 元の画像を載せないものの import 設定は載せない（フォント・アイコンは載せる）
        return low[:-len(".import")].endswith(SKIP_EXT)
    if rel.startswith("mini/") and low.endswith(".md"):   # 制作メモ（手元のパスが入っている）
        return True
    return low.endswith(SKIP_EXT) or rel.startswith(SKIP_DIRS)


README = """# 魔王の娘の魔物牧場（仮）

Godot 4.7.1（Compatibility / GLES3）で作っているゲームの本体です。

- **ブラウザで遊ぶ**：%s（スマホのブラウザにも対応中。タッチ操作はまだ）
- ゲームのコード：`game/`（画面・戦闘・牧場・データ）、アニメーション：`game_v2/animation/`、描画：`mini/layered2d/`
- ゲームが読むデータ：動作 `game_v2/assets/bakes/packs/`、焼いた見た目 `game_v2/assets/looks/`、フォント `game/ui/fonts/`（Noto Sans/Serif JP の部分集合、OFL）

原画・制作ツールはこのリポジトリには入れていません。ブラウザ版は `gh-pages` ブランチにあります。
""" % PAGES_URL

GITIGNORE = ".godot/\nbuild/\n*.tmp\n"


def git(args, cwd, check=True):
    r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if check and r.returncode != 0:
        print(r.stdout + r.stderr)
        raise SystemExit("git %s に失敗" % " ".join(args))
    return r.stdout.strip()


def sync_main() -> int:
    if not os.path.isdir(os.path.join(PUB, ".git")):
        os.makedirs(PUB, exist_ok=True)
        git(["init", "-b", "main"], PUB)
        git(["remote", "add", "origin", REMOTE], PUB)
    # 前に写したものを消してから写し直す（消したファイルもコミットに反映する）
    for name in os.listdir(PUB):
        if name == ".git":
            continue
        p = os.path.join(PUB, name)
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    count = 0
    for item in INCLUDE:
        src = os.path.join(ROOT, item)
        if os.path.isfile(src):
            files = [item]
        else:
            files = []
            for d, _, names in os.walk(src):
                for n in names:
                    files.append(os.path.relpath(os.path.join(d, n), ROOT).replace("\\", "/"))
        for rel in files:
            if skip(rel):
                continue
            dst = os.path.join(PUB, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(os.path.join(ROOT, rel), dst)
            count += 1
    open(os.path.join(PUB, "README.md"), "w", encoding="utf-8").write(README)
    open(os.path.join(PUB, ".gitignore"), "w", encoding="utf-8").write(GITIGNORE)
    return count


def publish_pages(message: str) -> None:
    web = os.path.join(ROOT, "build", "web")
    if not os.path.exists(os.path.join(web, "index.html")):
        raise SystemExit("build/web が無い。先に python game_v2/tools/web_export.py")
    tmp = tempfile.mkdtemp(prefix="farm_pages_")
    try:
        for n in os.listdir(web):
            if n == "bench.html":   # 計測用のページは載せない
                continue
            shutil.copy2(os.path.join(web, n), os.path.join(tmp, n))
        open(os.path.join(tmp, ".nojekyll"), "w").close()
        git(["init", "-b", "gh-pages"], tmp)
        git(["add", "-A"], tmp)
        git(["commit", "-m", message + TRAILER], tmp)
        # ブラウザ版は毎回まるごと差し替える（履歴を積まない）
        git(["push", "--force", REMOTE, "gh-pages"], tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    message = "ゲーム本体を更新"
    for a in sys.argv[1:]:
        if a.startswith("--message="):
            message = a.split("=", 1)[1]
    n = sync_main()
    git(["add", "-A"], PUB)
    if git(["status", "--porcelain"], PUB):
        git(["commit", "-m", message + TRAILER], PUB)
        git(["push", "-u", "origin", "main"], PUB)
        print("main: %d ファイルを載せた" % n)
    else:
        print("main: 変更なし")
    if "--no-pages" not in sys.argv:
        publish_pages("ブラウザ版を更新（%s）" % message)
        print("gh-pages: ブラウザ版を載せた → %s" % PAGES_URL)
    return 0


if __name__ == "__main__":
    sys.exit(main())
