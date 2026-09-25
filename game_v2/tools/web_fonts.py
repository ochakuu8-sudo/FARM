"""ブラウザ版の日本語フォント（ブラウザでは OS のフォントを使えないので同梱する）。

Windows に入っている Noto Sans JP / Noto Serif JP（SIL Open Font License 1.1、再配布可）を、
ゲームで使う文字（ゲームのコードと文言データに出てくる文字）＋かな・英数・記号だけに絞って game/ui/fonts/ へ書き出す。
文言を足したら書き出し直す（web_export.py が書き出しの前に自動で回す）。

    python game_v2/tools/web_fonts.py
"""
import glob
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "ui", "fonts")
FONTS = {
    "NotoSansJP-sub.ttf": r"C:\Windows\Fonts\NotoSansJP-VF.ttf",
    "NotoSerifJP-sub.ttf": r"C:\Windows\Fonts\NotoSerifJP-VF.ttf",
}
# 文言が入っているファイル
SOURCES = [
    "game/**/*.gd", "game/data/*.json",
    "game_v2/content/*.json", "game_v2/content/pair_scenes/*.json",
    "game_v2/animation/*.gd", "mini/layered2d/data/catalog.gd",
]
SKIP = ("game/tests/",)


def used_chars() -> set:
    chars = set()
    for pattern in SOURCES:
        for path in glob.glob(os.path.join(ROOT, pattern), recursive=True):
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            if rel.startswith(SKIP):
                continue
            with open(path, encoding="utf-8", errors="ignore") as f:
                chars.update(f.read())
    # かな・英数・記号は全部（名前の組み立てや数字の表示で使う）
    for lo, hi in [(0x20, 0x7E), (0xA0, 0xFF), (0x2000, 0x206F), (0x2190, 0x21FF), (0x2460, 0x24FF),
                   (0x25A0, 0x25FF), (0x2600, 0x26FF), (0x3000, 0x303F), (0x3040, 0x309F),
                   (0x30A0, 0x30FF), (0xFF00, 0xFFEF)]:
        chars.update(chr(c) for c in range(lo, hi + 1))
    return {c for c in chars if ord(c) >= 0x20}


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    os.makedirs(OUT, exist_ok=True)
    chars = used_chars()
    text = "".join(sorted(chars))
    for name, src in FONTS.items():
        if not os.path.exists(src):
            print("フォントがない:", src)
            return 1
        options = subset.Options()
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        options.notdef_outline = True
        font = TTFont(src)
        sub = subset.Subsetter(options)
        sub.populate(text=text)
        sub.subset(font)
        dst = os.path.join(OUT, name)
        font.save(dst)
        print("%s  %d文字  %.0fKB" % (name, len(chars), os.path.getsize(dst) / 1024))
    # 著作権表示と使用許諾はフォント自身の名前表（0 著作権・13 使用許諾・14 その URL）から写す
    lines = []
    for name, src in FONTS.items():
        names = TTFont(src)["name"]
        lines.append("%s（元: %s）" % (name, os.path.basename(src)))
        for nid in (0, 13, 14):
            rec = names.getDebugName(nid)
            if rec:
                lines.append("  " + rec)
    lines.append("このフォルダのフォントは、ゲームで使う文字だけに絞った部分集合です（game_v2/tools/web_fonts.py）。")
    with open(os.path.join(OUT, "OFL.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
