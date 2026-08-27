"""
Fetch Wowhead overview pages (Strengths/Weaknesses) and merge into Priorities.lua.

Uses the existing browser export for stat priorities, then curls overview URLs
(or reads overviewHtml from a newer export / local HTML files).

CloudFront often 403s CLI fetches — prefer re-running browser_scrape.js (it
pulls overview pages too), or pass --overview-html for offline files.

Usage:
  python fetch_overviews.py
  python fetch_overviews.py --export ~/Downloads/spf-wowhead-export.json
  python fetch_overviews.py --overview-html DEMONHUNTER-577:~/Downloads/spf-havoc-overview.html
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from scrape_stats import (
    build_catalog,
    fetch_html,
    merge_overview_into_entry,
    parse_spec,
    write_priorities_lua,
)


def parse_overview_html_args(raw: list[str]) -> dict[str, Path]:
    """KEY:path pairs → {specKey: Path}."""
    out: dict[str, Path] = {}
    for item in raw:
        if ":" not in item:
            raise SystemExit(f"--overview-html expects KEY:path, got {item!r}")
        key, path = item.split(":", 1)
        out[key.strip()] = Path(path.strip()).expanduser()
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Merge overview Strengths/Weaknesses into Priorities.lua")
    ap.add_argument(
        "--export",
        type=Path,
        default=Path.home() / "Downloads" / "spf-wowhead-export.json",
        help="Browser export with stat-priority pages (and optional overviewHtml)",
    )
    ap.add_argument("--delay", type=float, default=1.2)
    ap.add_argument("--patch", default="12.0.7")
    ap.add_argument(
        "--spec",
        help="Only fetch/merge overview for matching slug/name (still rewrites all export specs)",
    )
    ap.add_argument(
        "--overview-html",
        action="append",
        default=[],
        metavar="KEY:PATH",
        help="Offline overview HTML, e.g. DEMONHUNTER-577:~/Downloads/spf-havoc-overview.html (repeatable)",
    )
    ap.add_argument(
        "--no-fetch",
        action="store_true",
        help="Never curl Wowhead — only use export overviewHtml / --overview-html files",
    )
    args = ap.parse_args()

    if not args.export.exists():
        print(f"Export not found: {args.export}", file=sys.stderr)
        print("Run browser_scrape.js first, or pass --export", file=sys.stderr)
        return 1

    local_overviews = parse_overview_html_args(args.overview_html)
    for key, path in local_overviews.items():
        if not path.exists():
            print(f"Overview HTML missing for {key}: {path}", file=sys.stderr)
            return 1

    data = json.loads(args.export.read_text(encoding="utf-8"))
    pages = {p["key"]: p for p in (data.get("pages") or []) if p.get("key")}
    catalog = build_catalog()
    overview_filter = None
    if args.spec:
        needle = args.spec.lower()
        overview_filter = {
            s.key
            for s in catalog
            if needle in s.spec_slug or needle in s.spec_name.lower() or needle in s.key.lower()
        }

    parsed = {}
    sw_ok = 0
    for i, spec in enumerate(catalog):
        page = pages.get(spec.key)
        if not page or not (page.get("html") or page.get("markup")):
            print(f"SKIP {spec.key}: not in export")
            continue
        html = page.get("html")
        if not html and page.get("markup"):
            html = f'WH.markup.printHtml({json.dumps(page["markup"])});'
        result = parse_spec(spec, html)
        if not result.ok or not result.entry:
            print(f"FAIL {spec.key}: {result.error}")
            continue
        entry = result.entry
        if page.get("url"):
            entry["sourceURL"] = page["url"]

        want_overview = overview_filter is None or spec.key in overview_filter
        overview_html = None
        if want_overview:
            if spec.key in local_overviews:
                overview_html = local_overviews[spec.key].read_text(encoding="utf-8", errors="replace")
            elif page.get("overviewHtml"):
                overview_html = page["overviewHtml"]
            elif not args.no_fetch:
                try:
                    print(f"[{i + 1}/{len(catalog)}] overview {spec.key}")
                    overview_html = fetch_html(spec.overview_url)
                    time.sleep(args.delay)
                except Exception as e:  # noqa: BLE001
                    print(f"  WARN overview fetch failed: {e}")

        if overview_html:
            merge_overview_into_entry(entry, overview_html)

        sn = len(entry.get("strengths") or [])
        wn = len(entry.get("weaknesses") or [])
        if sn or wn:
            sw_ok += 1
        print(f"OK  {spec.key}  S/W={sn}/{wn}")
        parsed[spec.key] = entry

    if not parsed:
        print("Nothing to write", file=sys.stderr)
        return 1

    write_priorities_lua(parsed, patch=args.patch)
    print(f"Wrote Priorities.lua — {len(parsed)} specs, {sw_ok} with Strengths/Weaknesses")
    if sw_ok < len(parsed):
        print(
            "Tip: CloudFront blocks CLI. Re-paste browser_scrape.js on wowhead.com "
            "(now fetches overview pages too), then import_browser_export.py."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
