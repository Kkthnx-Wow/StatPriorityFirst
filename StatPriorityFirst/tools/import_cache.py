"""Import tools/cache/*.html into Data/Priorities.lua via scrape_stats parsers."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

CACHE = Path(__file__).resolve().parent / "cache"
SCRAPE = Path(__file__).resolve().parent / "scrape_stats.py"


def main() -> int:
    files = sorted(CACHE.glob("*.html"))
    if not files:
        print(f"No HTML in {CACHE}. Run download_guides.ps1 first.", file=sys.stderr)
        return 1

    args = [sys.executable, str(SCRAPE)]
    for path in files:
        # CLASSFILE-SPECID.html
        stem = path.stem
        if "-" not in stem:
            continue
        class_file, spec_id = stem.rsplit("-", 1)
        if not spec_id.isdigit():
            continue
        args.append("--html-map")
        args.append(f"{class_file}:{spec_id}:{path}")

    print("Running:", " ".join(args[:4]), f"... ({len(files)} files)")
    return subprocess.call(args)


if __name__ == "__main__":
    raise SystemExit(main())
