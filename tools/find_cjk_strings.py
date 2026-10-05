"""列出 Dart 原始碼中含中日韓文字（CJK）的字串字面量（註解不算）。

用途：i18n 抽字串時找殘留（見 docs/i18n.md）。無第三方依賴。

    py -3 -X utf8 tools/find_cjk_strings.py                 # 掃 lib/，每檔一行計數
    py -3 -X utf8 tools/find_cjk_strings.py -v lib/core     # 列出每一處（檔:行: 內容）
    py -3 -X utf8 tools/find_cjk_strings.py --allow-file tools/cjk_allow.txt

刻意保留中文（上傳後台、匯出報告）的字面量：在字面量開頭那一行加註解
`// i18n-keep-zh`，或在一段程式前後加 `// i18n-keep-zh-begin`／
`// i18n-keep-zh-end`，就不計入。
--allow-file：每行一個「路徑」或「路徑:行號」（相對 APP_v2 根，/ 分隔），
符合者不計。有殘留時 exit 1，否則 exit 0。
"""

from __future__ import annotations

import argparse
import os
import re
import sys

CJK = re.compile(r"[　-〿㐀-䶿一-鿿＀-￯]")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def string_literals(src: str):
    """逐一產生 (行號, 字面量內容)；略過 // 與 /* */ 註解。

    只做粗略詞法分析：足以處理一般 Dart 原始碼（含 ${...} 內的巢狀字串）。
    """
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            line += src.count("\n", i, j)
            i = j
        elif c in "'\"":
            raw = i > 0 and src[i - 1] in "rR" and (i < 2 or not (src[i - 2].isalnum() or src[i - 2] == "_"))
            start_line = line
            j, text = _scan_string(src, i, raw)
            line += src.count("\n", i, j)
            yield start_line, text
            i = j
        else:
            i += 1


def _scan_string(src: str, i: int, raw: bool):
    """從引號位置 i 掃到字串結尾，回傳 (結尾後位置, 原始內容)。"""
    n = len(src)
    q = src[i]
    triple = src.startswith(q * 3, i)
    delim = q * 3 if triple else q
    j = i + len(delim)
    begin = j
    while j < n:
        if not raw and src[j] == "\\":
            j += 2
            continue
        if not raw and src.startswith("${", j):
            depth, j = 1, j + 2
            while j < n and depth:
                ch = src[j]
                if ch in "'\"":
                    j, _ = _scan_string(src, j, False)
                    continue
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                j += 1
            continue
        if src.startswith(delim, j):
            return j + len(delim), src[begin:j]
        if not triple and src[j] == "\n":
            return j, src[begin:j]
        j += 1
    return n, src[begin:]


def kept_lines(src: str) -> set[int]:
    """標了 i18n-keep-zh（單行）或在 -begin／-end 區段內的行號。"""
    kept, inside = set(), False
    for no, text in enumerate(src.splitlines(), 1):
        if "i18n-keep-zh-begin" in text:
            inside = True
        if inside or "i18n-keep-zh" in text:
            kept.add(no)
        if "i18n-keep-zh-end" in text:
            inside = False
    return kept


def load_allow(path: str | None):
    files, lines = set(), set()
    if not path:
        return files, lines
    with open(path, encoding="utf-8") as f:
        for raw in f:
            entry = raw.split("#", 1)[0].strip().replace("\\", "/")
            if not entry:
                continue
            m = re.match(r"^(.*):(\d+)$", entry)
            if m:
                lines.add((m.group(1), int(m.group(2))))
            else:
                files.add(entry)
    return files, lines


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("paths", nargs="*", default=["lib"])
    ap.add_argument("-v", "--verbose", action="store_true", help="列出每一處")
    ap.add_argument("--allow-file", help="允許清單（路徑或 路徑:行號）")
    args = ap.parse_args(argv)
    allow_files, allow_lines = load_allow(args.allow_file)

    targets = []
    for p in args.paths:
        p = os.path.join(ROOT, p) if not os.path.isabs(p) else p
        if os.path.isfile(p):
            targets.append(p)
            continue
        for d, _, names in os.walk(p):
            targets += [os.path.join(d, x) for x in names if x.endswith(".dart")]

    total = 0
    for path in sorted(targets):
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        # 產生檔（gen-l10n 輸出）本來就是翻譯內容，略過。
        if rel.startswith("lib/l10n/app_localizations") or rel in allow_files:
            continue
        with open(path, encoding="utf-8") as f:
            src = f.read()
        keep = kept_lines(src)
        hits = [
            (ln, s)
            for ln, s in string_literals(src)
            if CJK.search(s) and (rel, ln) not in allow_lines and ln not in keep
        ]
        if not hits:
            continue
        total += len(hits)
        if args.verbose:
            for ln, s in hits:
                print(f"{rel}:{ln}: {s[:80]}")
        else:
            print(f"{len(hits):5d} {rel}")
    print(f"total {total}", file=sys.stderr)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
