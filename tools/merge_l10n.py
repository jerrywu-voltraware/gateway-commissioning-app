"""把 lib/l10n/parts/<area>_<lang>.arb 合併成 lib/l10n/app_<lang>.arb。

規範見 docs/i18n.md。無第三方依賴：

    py -3 -X utf8 tools/merge_l10n.py           # 合併並寫出 app_zh.arb、app_en.arb
    py -3 -X utf8 tools/merge_l10n.py --check   # 只比對；與現有檔不同或有錯就 exit 1

規則（任一違反就 exit 1 並列出全部問題，不寫檔）：
- 分區檔名 `<area>_<lang>.arb`；area 為 lowerCamelCase（不可含底線），lang 為 zh／en。
- 每個 key 必須以 `<area>_` 開頭（area＝所在分區檔名），且為合法 Dart 識別字。
- 同一語言內 key 重複（跨分區）→ 失敗。
- 每個分區 zh 與 en 的 key 集合必須相同（en 缺 key 或多 key 都失敗）。
- `@key` metadata（description、placeholders）跟著 key 走；`@key` 沒有對應 key → 失敗。
  metadata 以 zh（template）為準，en 可省略 `@key`。
- 輸出：`@@locale` 在最前，其後依 key 字母序，每個 key 後接它的 `@key`；
  兩格縮排、UTF-8（無 BOM）、LF、結尾換行；輸出穩定（同輸入同輸出）。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L10N_DIR = os.path.join(ROOT, "lib", "l10n")
PARTS_DIR = os.path.join(L10N_DIR, "parts")
LANGS = ("zh", "en")
TEMPLATE = "zh"

PART_NAME = re.compile(r"^([a-z][A-Za-z0-9]*)_([a-z]{2})\.arb$")
DART_IDENT = re.compile(r"^[a-z][A-Za-z0-9_]*$")
DART_RESERVED = {
    "abstract", "as", "assert", "async", "await", "break", "case", "catch",
    "class", "const", "continue", "default", "do", "else", "enum", "export",
    "extends", "false", "final", "finally", "for", "if", "import", "in", "is",
    "new", "null", "return", "super", "switch", "this", "throw", "true", "try",
    "var", "void", "while", "with",
}


def load_part(path: str, errors: list[str]) -> OrderedDict | None:
    try:
        with open(path, encoding="utf-8-sig") as f:
            data = json.load(f, object_pairs_hook=_no_dup_pairs(path, errors))
    except (OSError, ValueError) as e:
        errors.append(f"{_rel(path)}: 無法解析 JSON：{e}")
        return None
    if not isinstance(data, dict):
        errors.append(f"{_rel(path)}: 最外層必須是物件")
        return None
    return data


def _no_dup_pairs(path: str, errors: list[str]):
    def hook(pairs):
        seen = OrderedDict()
        for k, v in pairs:
            if k in seen:
                errors.append(f"{_rel(path)}: 檔內 key 重複：{k}")
            seen[k] = v
        return seen

    return hook


def _rel(path: str) -> str:
    try:
        path = os.path.relpath(path, ROOT)
    except ValueError:  # 不同磁碟（例如暫存目錄）就用絕對路徑
        pass
    return path.replace("\\", "/")


def collect(parts_dir: str = PARTS_DIR):
    """回傳 ({lang: {key: (value, meta|None, part)}}, errors)。"""
    errors: list[str] = []
    areas: dict[str, dict[str, str]] = {}
    if not os.path.isdir(parts_dir):
        return {}, [f"找不到分區目錄 {_rel(parts_dir)}"]
    for name in sorted(os.listdir(parts_dir)):
        if not name.endswith(".arb"):
            continue
        m = PART_NAME.match(name)
        if not m:
            errors.append(f"{name}: 檔名須為 <area>_<lang>.arb（area 為 lowerCamelCase、不含底線）")
            continue
        area, lang = m.groups()
        if lang not in LANGS:
            errors.append(f"{name}: 不支援的語言 {lang}（只允許 {', '.join(LANGS)}）")
            continue
        areas.setdefault(area, {})[lang] = os.path.join(parts_dir, name)

    merged: dict[str, dict] = {lang: {} for lang in LANGS}
    for area, files in sorted(areas.items()):
        for lang in LANGS:
            if lang not in files:
                errors.append(f"分區 {area}: 缺少 {area}_{lang}.arb")
        loaded = {}
        for lang, path in files.items():
            data = load_part(path, errors)
            if data is None:
                continue
            loaded[lang] = data
            entries = merged[lang]
            for key, value in data.items():
                if key.startswith("@@"):
                    continue  # 分區檔的 @@locale 等全域屬性忽略，由輸出決定
                if key.startswith("@"):
                    base = key[1:]
                    if base not in data:
                        errors.append(f"{_rel(path)}: {key} 沒有對應的 key {base}")
                    continue
                if not key.startswith(area + "_"):
                    errors.append(f"{_rel(path)}: key {key} 必須以 {area}_ 開頭")
                if not DART_IDENT.match(key) or key in DART_RESERVED:
                    errors.append(f"{_rel(path)}: key {key} 不是合法的 Dart 識別字")
                if not isinstance(value, str):
                    errors.append(f"{_rel(path)}: key {key} 的值必須是字串")
                    continue
                if key in entries:
                    errors.append(
                        f"key 重複（{lang}）：{key} 同時在 {entries[key][2]} 與 {_rel(path)}"
                    )
                    continue
                meta = data.get("@" + key)
                if meta is not None and not isinstance(meta, dict):
                    errors.append(f"{_rel(path)}: @{key} 必須是物件")
                    meta = None
                entries[key] = (value, meta, _rel(path))
        if TEMPLATE in loaded:
            zh_keys = {k for k in loaded[TEMPLATE] if not k.startswith("@")}
            for lang, data in loaded.items():
                if lang == TEMPLATE:
                    continue
                keys = {k for k in data if not k.startswith("@")}
                for k in sorted(zh_keys - keys):
                    errors.append(f"分區 {area}: {lang} 缺 key {k}")
                for k in sorted(keys - zh_keys):
                    errors.append(f"分區 {area}: {lang} 多出 key {k}（zh 沒有）")
    return merged, errors


def render(lang: str, entries: dict, template: dict) -> str:
    out = OrderedDict()
    out["@@locale"] = lang
    for key in sorted(entries):
        value, meta, _ = entries[key]
        out[key] = value
        # metadata 以 template（zh）為準；en 自己有寫也接受（例如 description）。
        tmeta = template.get(key, (None, None, None))[1]
        use = tmeta if lang != TEMPLATE and tmeta is not None else meta
        if use is not None:
            out["@" + key] = use
    return json.dumps(out, ensure_ascii=False, indent=2) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="合併 lib/l10n/parts/*.arb")
    ap.add_argument("--check", action="store_true", help="只比對，不寫檔")
    ap.add_argument("--parts-dir", default=PARTS_DIR, help=argparse.SUPPRESS)
    ap.add_argument("--out-dir", default=L10N_DIR, help=argparse.SUPPRESS)
    args = ap.parse_args(argv)

    merged, errors = collect(args.parts_dir)
    if errors:
        for e in errors:
            print("ERROR " + e, file=sys.stderr)
        print(f"merge_l10n: {len(errors)} 個錯誤，未寫檔", file=sys.stderr)
        return 1

    stale = []
    for lang in LANGS:
        text = render(lang, merged[lang], merged[TEMPLATE])
        path = os.path.join(args.out_dir, f"app_{lang}.arb")
        try:
            with open(path, encoding="utf-8") as f:
                current = f.read()
        except OSError:
            current = None
        if current == text:
            continue
        if args.check:
            stale.append(_rel(path))
        else:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            print(f"wrote {_rel(path)} ({len(merged[lang])} keys)")
    if stale:
        for p in stale:
            print(f"STALE {p}：與 parts 合併結果不同，請執行 py -3 -X utf8 tools/merge_l10n.py", file=sys.stderr)
        return 1
    if args.check:
        print(f"merge_l10n --check OK ({len(merged[TEMPLATE])} keys)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
