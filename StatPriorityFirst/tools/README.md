# Weekly Wowhead scrape - StatPriorityFirst

Regenerates `Data/Priorities.lua` from Wowhead **stat-priority**, **overview**
(optional S/W), **bis-gear**, and **enchants-gems** (Consumables) pages.

## One-click reminder + import

```powershell
cd "Interface/AddOns/StatPriorityFirst/tools"
powershell -File update.ps1
```

`update.ps1` reminds you to run the browser scrape, then imports
`%USERPROFILE%\Downloads\spf-wowhead-export.json` and prints OK/FAIL counts.
In-game: `/reload` then `/spf status` (reports missing DR and missing BiS gear).

## Recommended: browser console (bypasses CloudFront)

1. Open [wowhead.com](https://www.wowhead.com) in Chrome/Edge.
2. Open DevTools → **Console**.
3. Paste the contents of [`browser_scrape.js`](browser_scrape.js) and Enter.
4. Wait (~4–7 min). It fetches **stat-priority + overview + bis-gear + consumables**
   per spec and downloads **`spf-wowhead-export.json`**.
5. Import via `update.ps1` (above) or:

```bash
cd "Interface/AddOns/StatPriorityFirst/tools"
python import_browser_export.py %USERPROFILE%\Downloads\spf-wowhead-export.json
```

6. `/reload` in-game · `/spf status` for QA (`missingGear` should trend toward 0).

Optional before paste:

```js
window.SPF_DELAY_MS = 1500;  // slower = safer
window.SPF_ONLY = "havoc";   // one spec only (priority + overview + gear)
```

If the file download is blocked, copy from `window.SPF_LAST_EXPORT` instead:

```js
copy(JSON.stringify(window.SPF_LAST_EXPORT))
```

Paste into `tools/spf-wowhead-export.json`, then run `import_browser_export.py` on that file.

## Gear / BiS parse notes

Wowhead’s pretty 2×2 pin cards are client-rendered. Durable markup is the
**Overall BiS** slot table + raid/M+ highlight badges + **trinket tier-list**.
[`parse_gear.py`](parse_gear.py) reshapes that into four cards with **item IDs only**
(names/icons resolve in-game). Cap is 6 IDs per BiS/Alternatives side.

- **Weapons:** Overall BiS weapon slots = BiS, extra raid/M+ highlight weapons = Alternatives.
- **Tier:** `tier`/`catalyst` source = BiS, other BiS armor in those slots = Alternatives.
- **Consumables:** Scraped from `enchants-gems-pve-{dps|healer|tank}` (Wowhead’s Consumables
  nav). Flask / phial / potion / food / feast / augment rune headings only, never gem or
  enchant matrices. Card ↗ copies that page URL (`gear.consumablesURL`).

If a page has no parseable items, `gear` stays empty, never invent IDs.
`/spf status` reports `missingGear`.

Offline merge when CloudFront 403s CLI fetches:

```bash
python fetch_gear_batch.py --html-dir fixtures
# or merge one fixture into priorities_cache.json then rewrite Lua
```

## Overview-only merge (existing export)

If your export already has priorities but no `overviewHtml` (older scrape),
re-run `browser_scrape.js`, **or** merge offline HTML:

```bash
python fetch_overviews.py --no-fetch --overview-html DEMONHUNTER-577:%USERPROFILE%\Downloads\spf-havoc-overview.html
```

CLI curl of Wowhead URLs usually hits CloudFront 403, so prefer the browser path.

## CLI alternatives

```bash
python scrape_stats.py --delay 3
```

If CloudFront 403s:

```powershell
powershell -File download_guides.ps1
python import_cache.py
```

## Partial / debug

```bash
python scrape_stats.py --spec havoc
python scrape_stats.py --from-html havoc.html --class-file DEMONHUNTER --spec-id 577
python scrape_stats.py --html-map DEMONHUNTER:577:cache/DEMONHUNTER-577.html
```

## Outputs

| File | Purpose |
|------|---------|
| `../Data/Priorities.lua` | Addon data (generated) |
| `priorities_cache.json` | Merge cache |
| `last_scrape_report.json` | Per-spec OK/FAIL |
| `cache/*.html` | Optional offline HTML |

Keep `browser_scrape.js` / `scrape_stats.py` catalogs in sync with `Data/Catalog.lua` when Blizzard adds a spec.
