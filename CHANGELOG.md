# Changelog

## 2.0.0

Midnight Season 2 (patch 12.1.0).

- Interface bumped to **120100** (12.1.0)
- License moved to **All Rights Reserved** — added `LICENSE`, README license section, `## License` in the toc
- Stat priorities and BiS refreshed from Wowhead for Season 2 (`Data/Priorities.lua`)
- Import pipeline (`import_browser_export.py`, `scrape_stats.py`) now stamps patch `12.1.0` by default
- Added a project `.luacheckrc` (WoW globals declared) so the addon lints clean

## 1.2.0

Post-launch polish pass — empty states, BiS tooltips/borders, Compare, DR, Character bar, and build memory.

- Unspecced / follow-you shows pick-a-specialization (never “run the scrape”); Character bar uses short “No Spec”
- `GetPlayerSpecID` treats `0` as no-spec; mid-respec is debounced so talent edits don’t reset build tab / Compare
- Build memory is per class/spec (`lastVariantByKey`)
- BiS quality borders + Myth bonuses (`12806`/`13335`) resolve from the display hyperlink; incomplete tags complete either way
- Compare picks the first pair of differing builds; titles show Raid/M+ tags
- DR meter lays out after next-breakpoint lines; hovers fall back to Midnight defaults; spell tokens render gold
- Item `(true N)` skips equipped gear and tags once per tooltip paint
- Empty states wrap; narrow gear footers use “Alts”; `/spf status` says “updated”
- Panel saves `relativePoint`; minimap drag no longer toggles the panel on release
- Character bar opens the panel when unspecced; prefers open panel / remembered build

## 1.0.0 — first public release

PvE (Raid / Mythic+) stat priorities and BiS from Wowhead, with a friendly panel, Character-frame bar, live DR, and a weekly scrape pipeline.

### Highlights

- Floating `/spf` panel: class/spec browser, build pills, Compare
- Bottom tabs: **Priority** · **How It Works** · **Diminishing Returns**
- Stacked BiS rows (Weapons / Trinkets / Consumables / Tier) with quality borders and Wowhead copy-links
- Live DR: breakpoints, true rating / lost to DR, readable bracket meter
- Optional item-tooltip `(true N)` append (Settings, off by default)
- Compact priority bar above PaperDoll; soft ElvUI / EllesmereUI skins when those suites theme the character sheet
- Minimap button on the map rim (flat chrome; soft suite skins) — no gold tracking border
- Blizzard Settings options (minimap, lock, scale, follow-your-spec, character bar, item true-rating)
- Weekly Wowhead scrape under `tools/` (`browser_scrape.js` + import); `/spf status` reports `missingDR` / `missingGear`
- Never calls protected `LaunchURL` — copy-link popup instead

### Midnight

- Interface **120007**
- Secret-safe live rating paths where Blizzard tags stats
- SimC conversion tables + % brackets for true/lost rating
