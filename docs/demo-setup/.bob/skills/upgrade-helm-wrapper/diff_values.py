#!/usr/bin/env python3
"""diff_values.py - dry-run schema diff for an upstream subchart bump in a BYOP wrapper chart.

Compares the vendored subchart's values.yaml (OLD) with a freshly pulled one (NEW), then checks
every key the wrapper maps into the subchart namespace against both.

Usage:
    diff_values.py <service-version-dir> <new-upstream-chart-dir> [--subchart NAME]

    e.g. diff_values.py services/redishelm/v2 /tmp/up/redis

Mapped keys are read from the three wrapper files that feed the subchart namespace:
    chart/values.yaml, values-test.yaml, template/values.yaml.tmpl  (Jinja stripped)

Exit status: 0 no mapped key broken, 1 at least one mapped key no longer exists upstream,
2 usage / environment problem. Requires PyYAML (e.g. /tmp/jv/bin/python).
"""

import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("[ERROR] PyYAML missing. Use: /tmp/jv/bin/python (python3 -m venv /tmp/jv && /tmp/jv/bin/pip install pyyaml)")


def flatten(node, prefix=""):
    """Dotted-path -> leaf value. Empty dicts, None, scalars and lists are leaves."""
    if isinstance(node, dict) and node:
        out = {}
        for k, v in node.items():
            out.update(flatten(v, f"{prefix}.{k}" if prefix else str(k)))
        return out
    return {prefix: node}


def load_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text()) or {}


def load_template(path: Path) -> dict:
    """Strip Jinja so the broker template parses as YAML: keep the `if` branch, drop `else`."""
    lines, in_else = [], False
    for line in path.read_text().splitlines():
        s = line.strip()
        if s.startswith("{%"):
            if "else" in s:
                in_else = True
            elif "endif" in s:
                in_else = False
            continue
        if not in_else:
            lines.append(re.sub(r"\{\{.*?\}\}", "x", line))
    return yaml.safe_load("\n".join(lines)) or {}


def known(path: str, flat: dict) -> bool:
    """True if `path` is an upstream key, or lives under an upstream map/None leaf (free-form)."""
    if path in flat:
        return True
    parts = path.split(".")
    return any(".".join(parts[:i]) in flat and not isinstance(flat[".".join(parts[:i])], (str, int, float, bool))
               for i in range(1, len(parts)))


def main() -> int:
    args = sys.argv[1:]
    sub = None
    if "--subchart" in args:
        i = args.index("--subchart")
        sub = args[i + 1]
        del args[i:i + 2]
    if len(args) != 2:
        print(__doc__)
        return 2
    svc, new_dir = Path(args[0]), Path(args[1])

    if sub is None:
        deps = load_yaml(svc / "chart/Chart.yaml").get("dependencies") or []
        if len(deps) != 1:
            print("[ERROR] wrapper has != 1 dependency; pass --subchart NAME", file=sys.stderr)
            return 2
        sub = deps[0]["name"]

    old_file = svc / "chart/charts" / sub / "values.yaml"
    new_file = new_dir / "values.yaml"
    for f in (old_file, new_file):
        if not f.is_file():
            print(f"[ERROR] not found: {f}", file=sys.stderr)
            return 2

    old, new = flatten(load_yaml(old_file)), flatten(load_yaml(new_file))

    print(f"== upstream values diff: {sub} (old: {old_file}  new: {new_file}) ==")
    removed = sorted(k for k in old if not known(k, new))
    added = sorted(k for k in new if not known(k, old))
    changed = sorted(k for k in old if k in new and old[k] != new[k])
    for title, keys in (("REMOVED/RENAMED upstream keys", removed), ("ADDED upstream keys", added)):
        print(f"\n{title}: {len(keys)}")
        for k in keys:
            print(f"  {k}")
    print(f"\nCHANGED upstream defaults: {len(changed)}")
    for k in changed:
        print(f"  {k}: {old[k]!r} -> {new[k]!r}")

    mapped = {}
    for rel, loader in (("chart/values.yaml", load_yaml), ("values-test.yaml", load_yaml),
                        ("template/values.yaml.tmpl", load_template)):
        f = svc / rel
        if f.is_file():
            for k in flatten((loader(f)).get(sub, {})):
                mapped.setdefault(k, set()).add(rel)

    print(f"\n== wrapper-mapped keys under `{sub}:` ({len(mapped)}) ==")
    broken = 0
    for k in sorted(mapped):
        if k == "":
            continue
        where = ", ".join(sorted(mapped[k]))
        if known(k, old) and not known(k, new):
            broken += 1
            print(f"  [BREAKING] {sub}.{k}  (set in {where}) exists in OLD, gone in NEW")
        elif not known(k, new):
            print(f"  [WARN]     {sub}.{k}  (set in {where}) is not an upstream key in OLD or NEW")
        else:
            print(f"  [OK]       {sub}.{k}")
    print(f"\n{broken} breaking mapped key(s)")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
