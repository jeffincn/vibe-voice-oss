#!/usr/bin/env python3
"""Extract CamelCase / snake_case symbols from this repo into the user lexicon."""
from __future__ import annotations
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = Path.home() / "Library/Application Support/VibeVoiceOSS/Lexicon/project.tsv"
SKIP_DIRS = {".build", "node_modules", "dist", "Vendor", "Pods", ".git", "DerivedData"}
EXTS = {".swift", ".ts", ".tsx", ".js", ".py", ".go", ".rs", ".md"}
PATTERN = re.compile(
    r"\b([A-Z][A-Za-z0-9]{3,}|[a-z]+(?:_[a-z0-9]+){1,}|[a-z]+[A-Z][A-Za-z0-9]+)\b"
)
BANNED = {
    "func", "class", "struct", "enum", "return", "import", "public", "private",
    "static", "override", "guard", "throw", "async", "await", "true", "false",
    "null", "undefined", "const", "let", "var",
}


def compact(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def main() -> None:
    mapping: dict[str, str] = {}
    for path in ROOT.rglob("*"):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if not path.is_file() or path.suffix.lower() not in EXTS:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for match in PATTERN.finditer(text):
            symbol = match.group(1)
            if symbol.lower() in BANNED:
                continue
            code = compact(symbol)
            if len(code) >= 4:
                mapping[code] = symbol
        stem = path.stem
        code = compact(stem)
        if len(code) >= 4:
            mapping[code] = stem

    try:
        branches = subprocess.check_output(
            ["git", "branch", "--format=%(refname:short)"],
            cwd=ROOT,
            text=True,
        ).splitlines()
        for branch in branches:
            leaf = branch.split("/")[-1]
            code = compact(leaf)
            if len(code) >= 4:
                mapping[code] = leaf
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    OUT.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# code\tdisplay\tkind  (auto-generated project vocabulary)"]
    for code, display in sorted(mapping.items()):
        lines.append(f"{code}\t{display}\tproject")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"imported {len(mapping)} → {OUT}")


if __name__ == "__main__":
    main()
