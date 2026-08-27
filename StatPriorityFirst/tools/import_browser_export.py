"""
Import spf-wowhead-export.json from tools/browser_scrape.js → Data/Priorities.lua

Usage:
  python import_browser_export.py spf-wowhead-export.json
  python import_browser_export.py ~/Downloads/spf-wowhead-export.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from scrape_stats import (
    REPORT_PATH,
    SpecDef,
    merge_overview_into_entry,
    parse_spec,
    write_priorities_lua,
)
from parse_gear import merge_gear_into_entry


def main() -> int:
    ap = argparse.ArgumentParser(description="Import browser Wowhead export into Priorities.lua")
    ap.add_argument("export", type=Path, help="Path to spf-wowhead-export.json")
    ap.add_argument("--patch", default="12.1.0")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not args.export.exists():
        print(f"File not found: {args.export}", file=sys.stderr)
        return 1

    data = json.loads(args.export.read_text(encoding="utf-8"))
    pages = data.get("pages") or []
    if not pages:
        print("Export has no pages[]", file=sys.stderr)
        return 1

    parsed = {}
    report = {
        "scrapedAt": data.get("scrapedAt"),
        "source": data.get("source", "wowhead-browser"),
        "results": [],
    }

    for page in pages:
        class_file = page.get("classFile")
        spec_id = page.get("specID")
        if not class_file or spec_id is None:
            continue
        spec = SpecDef(
            class_file=class_file,
            class_name=class_file,
            class_slug="",
            spec_id=int(spec_id),
            spec_name=page.get("name") or str(spec_id),
            spec_slug="",
            role=page.get("role") or "DAMAGER",
        )
        html = page.get("html")
        if not html and page.get("markup"):
            html = f'WH.markup.printHtml({json.dumps(page["markup"])});'
        if not html:
            report["results"].append(
                {"key": spec.key, "url": page.get("url"), "ok": False, "error": page.get("error") or "no html"}
            )
            print(f"FAIL {spec.key}: {page.get('error') or 'no html'}")
            continue

        result = parse_spec(spec, html)
        if result.ok and result.entry:
            if page.get("url"):
                result.entry["sourceURL"] = page["url"]
            # Overview page (Strengths/Weaknesses + real >>/> chain) when present
            overview_html = page.get("overviewHtml") or page.get("overview_html")
            if overview_html:
                merge_overview_into_entry(result.entry, overview_html)
            gear_html = page.get("gearHtml") or page.get("gear_html")
            if gear_html:
                merge_gear_into_entry(
                    result.entry,
                    gear_html,
                    gear_url=page.get("gearUrl") or page.get("gear_url"),
                    consumables_html=page.get("consumablesHtml") or page.get("consumables_html"),
                    consumables_url=page.get("consumablesUrl") or page.get("consumables_url"),
                )
            sw_n = len(result.entry.get("strengths") or [])
            wk_n = len(result.entry.get("weaknesses") or [])
            gear_n = len((result.entry.get("gear") or {}).get("cards") or [])
            parsed[spec.key] = result.entry
            report["results"].append({"key": spec.key, "url": page.get("url"), "ok": True, "error": None})
            print(f"OK  {spec.key}  variants={len(result.entry['variants'])}  S/W={sw_n}/{wk_n}  gearCards={gear_n}")
        else:
            report["results"].append(
                {"key": spec.key, "url": page.get("url"), "ok": False, "error": result.error}
            )
            print(f"FAIL {spec.key}: {result.error}")

    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    sidecar = Path(__file__).resolve().parent / "priorities_cache.json"
    sidecar.write_text(json.dumps(parsed, indent=2), encoding="utf-8")

    if args.dry_run:
        print(f"Dry run — {len(parsed)} specs would be written")
        return 0 if parsed else 1

    if not parsed:
        print("Nothing parsed — Priorities.lua unchanged", file=sys.stderr)
        return 1

    write_priorities_lua(parsed, patch=args.patch or data.get("patch") or "12.1.0")
    print(f"Wrote Data/Priorities.lua ({len(parsed)} specs). /reload in-game.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
