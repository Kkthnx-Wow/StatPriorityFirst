"""
Parse Wowhead bis-gear + enchants-gems guides into compact BiS cards.

Wowhead's pretty 2x2 pin cards are client-rendered. Durable sources:
  - Overall BiS slot table (weapons / tier split by source)
  - Raid & M+ highlight tables (icon-badge + tooltip → weapon alts)
  - Trinket tier-list (S = BiS, A = Alternatives)
  - Enchants-gems page headings for flask / potion / food / rune only

Item refs keep Wowhead bonus IDs (e.g. bonus=12806:13335) so in-game
tooltips show Myth-track ilvl, not the naked base item (ilvl 44 junk).
"""

from __future__ import annotations

import re
from typing import Any

from scrape_stats import extract_markup

MAX_PER_SIDE = 6

CARD_LABELS = {
    "weapons": "Weapons",
    "trinkets": "Trinkets",
    "consumables": "Consumables",
    "tier": "Tier Set",
}

WEAPON_SLOTS = {
    "weapon",
    "weapons",
    "main hand",
    "main-hand",
    "mainhand",
    "off-hand",
    "off hand",
    "offhand",
    "one-hand",
    "two-hand",
    "2h weapon",
    "1h weapon",
}

TRINKET_SLOTS = {"trinket", "trinkets", "alt trinket", "alternative trinket"}

TIER_SLOTS = {
    "head",
    "helm",
    "shoulder",
    "shoulders",
    "chest",
    "hands",
    "gloves",
    "legs",
}

# [item=250032 bonus=12806:13335] or [item=250032]
ITEM_TAG_RE = re.compile(r"\[item[=:](\d+)([^\]]*)\]", re.I)
BONUS_ATTR_RE = re.compile(r"bonus=([\d:]+)", re.I)
ICON_BADGE_RE = re.compile(r"\[icon-badge=(\d+)", re.I)
TOOLTIP_RE = re.compile(
    r"\[tooltip name=([^\]]+)](.*?)\[/tooltip]",
    re.I | re.S,
)
BADGE_WITH_TIP_RE = re.compile(
    r"\[icon-badge=(\d+)[^\]]*tooltip=\"([^\"]+)\"",
    re.I,
)
# Raid / M+ / Voidcore / Bonus-roll highlight tip ids — not named trinket blurbs.
HIGHLIGHT_TIP_RE = re.compile(
    r"^(raid_|dung_|voidcore_|bonus_|earlycraft)",
    re.I,
)
# Spec abilities that contain the word "weapon" (Blood DK's Dancing Rune Weapon…).
ABILITY_WEAPON_RE = re.compile(
    r"dancing\s+rune\s+weapon|rune\s+weapon",
    re.I,
)

ItemRef = dict[str, Any]  # { "id": int, "bonuses": list[int] }


def _ref(item_id: int, bonuses: list[int] | None = None) -> ItemRef:
    return {"id": int(item_id), "bonuses": list(bonuses or [])}


def _ref_id(ref: ItemRef | int) -> int:
    if isinstance(ref, int):
        return ref
    return int(ref["id"])


def _build_bonus_map(body: str) -> dict[int, list[int]]:
    """itemID → best bonus list seen on the page (prefer longer / more specific)."""
    out: dict[int, list[int]] = {}
    for iid_s, attrs in ITEM_TAG_RE.findall(body or ""):
        iid = int(iid_s)
        bonuses: list[int] = []
        m = BONUS_ATTR_RE.search(attrs or "")
        if m:
            bonuses = [int(x) for x in m.group(1).split(":") if x.isdigit()]
        prev = out.get(iid)
        if prev is None or len(bonuses) >= len(prev):
            out[iid] = bonuses
    return out


def _refs_from_text(text: str, bonus_map: dict[int, list[int]]) -> list[ItemRef]:
    refs: list[ItemRef] = []
    for iid_s, attrs in ITEM_TAG_RE.findall(text or ""):
        iid = int(iid_s)
        bonuses: list[int] = []
        m = BONUS_ATTR_RE.search(attrs or "")
        if m:
            bonuses = [int(x) for x in m.group(1).split(":") if x.isdigit()]
        elif iid in bonus_map:
            bonuses = list(bonus_map[iid])
        refs.append(_ref(iid, bonuses))
    return refs


def _ref_from_id(item_id: int, bonus_map: dict[int, list[int]]) -> ItemRef:
    return _ref(item_id, bonus_map.get(item_id))


def _dedupe_cap(refs: list[ItemRef], cap: int = MAX_PER_SIDE) -> list[ItemRef]:
    out: list[ItemRef] = []
    seen: set[int] = set()
    for ref in refs:
        iid = _ref_id(ref)
        if iid in seen:
            continue
        seen.add(iid)
        out.append(ref)
        if len(out) >= cap:
            break
    return out


def _norm_slot(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip().lower())


def _is_tier_source(source: str) -> bool:
    s = (source or "").lower()
    return "tier" in s or "catalyst" in s


def _is_alt_source(source: str) -> bool:
    # A slot row Wowhead flags as a secondary pick rather than the BiS.
    return bool(re.search(r"\balt(ernative)?\b|\boptional\b|\bbackup\b", source or "", re.I))


def _overall_bis_chunk(body: str) -> str:
    m = re.search(
        r'\[tab[^\]]*name="Overall BiS"[^\]]*](.*?)\[/tab]',
        body,
        re.I | re.S,
    )
    if m:
        return m.group(1)
    m = re.search(
        r"Best in Slot Gear.*?(?=\[tab name=|\[h2|\Z)",
        body,
        re.I | re.S,
    )
    return m.group(0) if m else body


def _parse_slot_table(chunk: str, bonus_map: dict[int, list[int]]) -> list[tuple[str, list[ItemRef], str]]:
    rows: list[tuple[str, list[ItemRef], str]] = []
    for m in re.finditer(r"\[tr](.*?)\[/tr]", chunk, re.I | re.S):
        tds = re.findall(r"\[td[^\]]*](.*?)\[/td]", m.group(1), re.I | re.S)
        if len(tds) < 2:
            continue
        slot = _norm_slot(re.sub(r"\[/?[^\]]+]", "", tds[0]))
        slot = re.sub(r"<[^>]+>", "", slot)
        if slot in {"slot", "item", "source", "item slot", "name"}:
            continue
        refs = _refs_from_text(tds[1], bonus_map)
        source = ""
        if len(tds) >= 3:
            source = re.sub(r"\[/?[^\]]+]", " ", tds[2])
            source = re.sub(r"\s+", " ", source).strip().lower()
        if not refs:
            continue
        rows.append((slot, refs, source))
    return rows


def _weapon_highlight_refs(body: str, bonus_map: dict[int, list[int]]) -> list[ItemRef]:
    """Raid/M+ icon-badges whose highlight tip is about weapons as a gear slot.

    Incident (BiS, Jul 2026): matching any tip containing "weapon" pulled Blood
    DK trinkets into Weapons Alternatives — their blurbs say "Dancing Rune
    Weapon". Only trust Raid_/Dung_/Voidcore_/Bonus_ tip ids, and scrub ability
    names before the keyword check.
    """
    weapon_tips: set[str] = set()
    for name, text in TOOLTIP_RE.findall(body):
        tip_id = name.strip().lower()
        if not HIGHLIGHT_TIP_RE.match(tip_id):
            continue
        t = re.sub(r"\s+", " ", text).strip().lower()
        t = ABILITY_WEAPON_RE.sub(" ", t)
        if "weapon" in t and "trinket" not in t and "ring" not in t:
            weapon_tips.add(tip_id)
    if not weapon_tips:
        return []
    refs: list[ItemRef] = []
    for iid_s, tip in BADGE_WITH_TIP_RE.findall(body):
        if tip.strip().lower() in weapon_tips:
            refs.append(_ref_from_id(int(iid_s), bonus_map))
    return refs


def _trinket_tier_lists(body: str, bonus_map: dict[int, list[int]]) -> tuple[list[ItemRef], list[ItemRef]]:
    m = re.search(
        r"Best .+? Trinkets.*?</?h2>|\[h2[^\]]*Trinkets[^\]]*](.*?)(?=\[h2|\Z)",
        body,
        re.I | re.S,
    )
    chunk = m.group(0) if m else body
    tl = re.search(r"\[tier-list[^\]]*](.*?)\[/tier-list]", chunk, re.I | re.S)
    if not tl:
        return [], []
    block = tl.group(1)
    tiers = re.findall(r"\[tier](.*?)\[/tier]", block, re.I | re.S)
    bis: list[ItemRef] = []
    alts: list[ItemRef] = []
    for i, tier in enumerate(tiers):
        ids = [int(x) for x in ICON_BADGE_RE.findall(tier)]
        label_m = re.search(r"\[tier-label[^\]]*](.*?)\[/tier-label]", tier, re.I | re.S)
        label = (label_m.group(1) if label_m else "").strip().upper()
        refs = [_ref_from_id(iid, bonus_map) for iid in ids]
        if label == "S" or (i == 0 and not label):
            bis.extend(refs)
        elif label == "A" or i == 1:
            alts.extend(refs)
    return bis, alts


# Combat consumables only — skip enchant/gem matrices on enchants-gems pages.
_CONS_KEEP = re.compile(r"flask|phial|potion|food|feast|rune|consumable", re.I)
_CONS_SKIP = re.compile(
    r"enchant|gem|socket|embellish|craft|weapon|trinket|tier|"
    r"cloak|boot|bracer|wrist|ring|neck|chest|leg|shoulder|belt|glove",
    re.I,
)
_CONS_ALT = re.compile(r"alternative|optional|budget|cheap|filler", re.I)


def _heading_sections(body: str) -> list[tuple[str, str]]:
    """(normalized title, section body) for h2/h3 blocks."""
    out: list[tuple[str, str]] = []
    for m in re.finditer(
        r"\[h([23])[^\]]*](.*?)\[/h\1](.*?)(?=\[h[23]|\Z)",
        body,
        re.I | re.S,
    ):
        title = re.sub(r"\[/?[^\]]+]", " ", m.group(2))
        title = re.sub(r"\s+", " ", title).strip().lower()
        out.append((title, m.group(3)))
    return out


def parse_consumables_lists(html: str) -> tuple[list[ItemRef], list[ItemRef]]:
    """Flask / potion / food / rune picks from an enchants-gems (Consumables) guide."""
    body = extract_markup(html)
    if not body:
        return [], []
    bonus_map = _build_bonus_map(body)
    bis: list[ItemRef] = []
    alts: list[ItemRef] = []
    for title, section in _heading_sections(body):
        if _CONS_SKIP.search(title) and not _CONS_KEEP.search(title):
            continue
        if not _CONS_KEEP.search(title):
            continue
        refs = _refs_from_text(section, bonus_map)
        for iid in ICON_BADGE_RE.findall(section):
            refs.append(_ref_from_id(int(iid), bonus_map))
        if not refs:
            continue
        if _CONS_ALT.search(title):
            alts.extend(refs)
        else:
            bis.extend(refs)
    return bis, alts


def _ids_set(refs: list[ItemRef]) -> set[int]:
    return {_ref_id(r) for r in refs}


def _make_card(cid: str, bis: list[ItemRef], alts: list[ItemRef]) -> dict[str, Any] | None:
    bis_c = _dedupe_cap(bis)
    bis_ids = _ids_set(bis_c)
    alt_c = _dedupe_cap([r for r in alts if _ref_id(r) not in bis_ids])
    if not bis_c and not alt_c:
        return None
    return {
        "id": cid,
        "label": CARD_LABELS[cid],
        "bis": bis_c,
        "alternatives": alt_c,
    }


def parse_gear_cards(html: str, source_url: str | None = None) -> dict[str, Any] | None:
    body = extract_markup(html)
    if not body:
        return None

    bonus_map = _build_bonus_map(body)

    weapons_bis: list[ItemRef] = []
    weapons_alt: list[ItemRef] = []
    trinkets_bis: list[ItemRef] = []
    trinkets_alt: list[ItemRef] = []
    tier_bis: list[ItemRef] = []
    tier_alt: list[ItemRef] = []

    chunk = _overall_bis_chunk(body)
    for slot, refs, source in _parse_slot_table(chunk, bonus_map):
        if slot in WEAPON_SLOTS or "weapon" in slot:
            weapons_bis.extend(refs)
        elif "alt" in slot and "trinket" in slot:
            trinkets_alt.extend(refs)
        elif slot in TRINKET_SLOTS or slot == "trinket":
            trinkets_bis.extend(refs)
        elif slot in TIER_SLOTS:
            # The Overall BiS pick for a tier slot IS that slot's BiS. Wowhead's
            # source column names the drop (a boss, BoE, craft), not always the
            # word "tier"/"catalyst", so we can't gate BiS on that text or most
            # specs end up with an empty Tier card. A row that is explicitly a
            # non-tier alternative for the slot goes to Alternatives instead.
            if source and _is_alt_source(source):
                tier_alt.extend(refs)
            else:
                tier_bis.extend(refs)

    s_bis, a_alts = _trinket_tier_lists(body, bonus_map)
    seen_tb = _ids_set(trinkets_bis)
    for ref in s_bis:
        if _ref_id(ref) not in seen_tb:
            trinkets_bis.append(ref)
            seen_tb.add(_ref_id(ref))
    seen_ta = _ids_set(trinkets_alt)
    for ref in a_alts:
        iid = _ref_id(ref)
        if iid not in seen_tb and iid not in seen_ta:
            trinkets_alt.append(ref)
            seen_ta.add(iid)

    # Weapon highlight alts after trinkets so we can refuse trinket IDs.
    trinket_ids = seen_tb | seen_ta
    seen_w = _ids_set(weapons_bis)
    for ref in _weapon_highlight_refs(body, bonus_map):
        iid = _ref_id(ref)
        if iid in trinket_ids:
            continue
        if iid not in seen_w and iid not in _ids_set(weapons_alt):
            weapons_alt.append(ref)

    # Consumables come from enchants-gems pages via merge_gear_into_entry — not bis-gear.
    cards: list[dict[str, Any]] = []
    for cid, bis, alts in (
        ("weapons", weapons_bis, weapons_alt),
        ("trinkets", trinkets_bis, trinkets_alt),
        ("tier", tier_bis, tier_alt),
    ):
        card = _make_card(cid, bis, alts)
        if card:
            cards.append(card)

    if not cards:
        return None

    # Keep a consumables slot so the UI 2x2 never depends on OrderedCards alone.
    cards.insert(
        min(2, len(cards)),
        {
            "id": "consumables",
            "label": CARD_LABELS["consumables"],
            "bis": [],
            "alternatives": [],
        },
    )

    out: dict[str, Any] = {"cards": cards}
    if source_url:
        out["sourceURL"] = source_url
    return out


def merge_gear_into_entry(
    entry: dict[str, Any],
    gear_html: str,
    gear_url: str | None = None,
    consumables_html: str | None = None,
    consumables_url: str | None = None,
) -> None:
    gear = parse_gear_cards(gear_html, source_url=gear_url)
    if not gear:
        return

    cons_bis, cons_alt = ([], [])
    if consumables_html:
        cons_bis, cons_alt = parse_consumables_lists(consumables_html)
    cons_card = _make_card("consumables", cons_bis, cons_alt) or {
        "id": "consumables",
        "label": CARD_LABELS["consumables"],
        "bis": [],
        "alternatives": [],
    }

    cards = [c for c in gear["cards"] if c.get("id") != "consumables"]
    insert_at = 0
    for i, c in enumerate(cards):
        if c.get("id") == "trinkets":
            insert_at = i + 1
            break
        if c.get("id") == "weapons":
            insert_at = i + 1
    cards.insert(insert_at, cons_card)
    gear["cards"] = cards

    if consumables_url:
        gear["consumablesURL"] = consumables_url

    entry["gear"] = gear