"""
Fetch Wowhead bis-gear pages for every catalog spec and merge into Priorities.lua.

Uses tools/priorities_cache.json as the base priority dataset (from the weekly
stat-priority scrape), then attaches gear cards.

Usage:
  python fetch_gear_batch.py
  python fetch_gear_batch.py --spec havoc
  python fetch_gear_batch.py --delay 1.0
  python fetch_gear_batch.py --html-dir fixtures
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from parse_gear import merge_gear_into_entry
from scrape_stats import REPORT_PATH, build_catalog, fetch_html, write_priorities_lua

CACHE = Path(__file__).resolve().parent / "priorities_cache.json"


def resolve_local_html(html_dir: Path, spec) -> Path | None:
    """Match fixtures like demonology_bis.html or WARLOCK-266.html."""
    candidates = [
        html_dir / f"{spec.key}.html",
        html_dir / f"{spec.key}_bis.html",
        html_dir / f"{spec.spec_slug}_bis.html",
        html_dir / f"{spec.spec_slug}.html",
        html_dir / f"{spec.spec_name.lower().replace(' ', '_')}_bis.html",
    ]
    for path in candidates:
        if path.exists():
            return path
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="Fetch bis-gear pages and merge into Priorities.lua")
    ap.add_argument("--spec", help="Filter by slug/name substring")
    ap.add_argument("--delay", type=float, default=1.0)
    ap.add_argument("--patch", default="12.0.7")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument(
        "--html-dir",
        type=Path,
        help="Offline HTML folder (skips network). Names: CLASS-specID.html or {slug}_bis.html",
    )
    args = ap.parse_args()

    if not CACHE.exists():
        print(f"Missing {CACHE.name} — run import_browser_export.py first.", flush=True)
        return 1

    specs = json.loads(CACHE.read_text(encoding="utf-8"))
    catalog = build_catalog()
    if args.spec:
        needle = args.spec.lower()
        catalog = [s for s in catalog if needle in s.spec_slug or needle in s.spec_name.lower()]

    ok = fail = 0
    report = {"source": "bis-gear-batch", "results": []}

    for i, spec in enumerate(catalog):
        entry = specs.get(spec.key)
        if not entry:
            print(f"SKIP {spec.key}: not in priorities_cache.json")
            fail += 1
            continue
        label = f"[{i + 1}/{len(catalog)}] {spec.key}"
        try:
            if args.html_dir:
                local = resolve_local_html(args.html_dir, spec)
                if not local:
                    fail += 1
                    print(f"{label} SKIP  no local HTML in {args.html_dir}")
                    report["results"].append({"key": spec.key, "ok": False, "error": "no local html"})
                    continue
                html = local.read_text(encoding="utf-8", errors="replace")
            else:
                html = fetch_html(spec.gear_url)
            merge_gear_into_entry(entry, html, gear_url=spec.gear_url)
            cards = (entry.get("gear") or {}).get("cards") or []
            if cards:
                ok += 1
                n = sum(len(c.get("bis") or []) + len(c.get("alternatives") or []) for c in cards)
                print(f"{label} OK  cards={len(cards)} items={n}")
                report["results"].append({"key": spec.key, "ok": True, "cards": len(cards)})
            else:
                fail += 1
                print(f"{label} FAIL  no gear cards parsed")
                report["results"].append({"key": spec.key, "ok": False, "error": "no cards"})
        except Exception as e:  # noqa: BLE001 — batch scrape keeps going
            fail += 1
            print(f"{label} FAIL  {e}")
            report["results"].append({"key": spec.key, "ok": False, "error": str(e)})
        if not args.html_dir and i + 1 < len(catalog):
            time.sleep(args.delay)

    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    CACHE.write_text(json.dumps(specs, indent=2), encoding="utf-8")

    if args.dry_run:
        print(f"Dry run — ok={ok} fail={fail}")
        return 0 if ok else 1

    write_priorities_lua(specs, patch=args.patch)
    print(f"Wrote Data/Priorities.lua  ok={ok} fail={fail}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
