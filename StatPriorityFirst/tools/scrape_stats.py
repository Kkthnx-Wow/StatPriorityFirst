"""
StatPriorityFirst — weekly Wowhead stat-priority scraper.

Pulls each class/spec guide, parses WH.markup BBCode, writes Data/Priorities.lua.

Usage:
  pip install -r requirements.txt
  python scrape_stats.py
  python scrape_stats.py --spec havoc
  python scrape_stats.py --from-html path.html --class-file DEMONHUNTER --spec-id 577
  python scrape_stats.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
OUT_LUA = ROOT / "Data" / "Priorities.lua"
REPORT_PATH = Path(__file__).resolve().parent / "last_scrape_report.json"

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
REQUEST_DELAY = 1.1  # be polite

STAT_NAME_TO_KEY = {
    "strength": "STR",
    "str": "STR",
    "agility": "AGI",
    "agi": "AGI",
    "intellect": "INT",
    "int": "INT",
    "critical strike": "CRIT",
    "crit": "CRIT",
    "haste": "HASTE",
    "mastery": "MASTERY",
    "versatility": "VERS",
    "vers": "VERS",
}

ROLE_SUFFIX = {
    "DAMAGER": "stat-priority-pve-dps",
    "HEALER": "stat-priority-pve-healer",
    "TANK": "stat-priority-pve-tank",
}

OVERVIEW_SUFFIX = {
    "DAMAGER": "overview-pve-dps",
    "HEALER": "overview-pve-healer",
    "TANK": "overview-pve-tank",
}

GEAR_SUFFIX = {
    "DAMAGER": "bis-gear",
    "HEALER": "bis-gear",
    "TANK": "bis-gear",
}


@dataclass
class SpecDef:
    class_file: str
    class_name: str
    class_slug: str
    spec_id: int
    spec_name: str
    spec_slug: str
    role: str

    @property
    def key(self) -> str:
        return f"{self.class_file}-{self.spec_id}"

    @property
    def url(self) -> str:
        suffix = ROLE_SUFFIX[self.role]
        return (
            f"https://www.wowhead.com/guide/classes/"
            f"{self.class_slug}/{self.spec_slug}/{suffix}"
        )

    @property
    def overview_url(self) -> str:
        suffix = OVERVIEW_SUFFIX[self.role]
        return (
            f"https://www.wowhead.com/guide/classes/"
            f"{self.class_slug}/{self.spec_slug}/{suffix}"
        )

    @property
    def gear_url(self) -> str:
        suffix = GEAR_SUFFIX[self.role]
        return (
            f"https://www.wowhead.com/guide/classes/"
            f"{self.class_slug}/{self.spec_slug}/{suffix}"
        )


def build_catalog() -> list[SpecDef]:
    # Mirrors Data/Catalog.lua — keep in sync when Midnight adds specs.
    raw: list[tuple] = [
        ("WARRIOR", "Warrior", "warrior", [
            (71, "Arms", "arms", "DAMAGER"),
            (72, "Fury", "fury", "DAMAGER"),
            (73, "Protection", "protection", "TANK"),
        ]),
        ("PALADIN", "Paladin", "paladin", [
            (65, "Holy", "holy", "HEALER"),
            (66, "Protection", "protection", "TANK"),
            (70, "Retribution", "retribution", "DAMAGER"),
        ]),
        ("HUNTER", "Hunter", "hunter", [
            (253, "Beast Mastery", "beast-mastery", "DAMAGER"),
            (254, "Marksmanship", "marksmanship", "DAMAGER"),
            (255, "Survival", "survival", "DAMAGER"),
        ]),
        ("ROGUE", "Rogue", "rogue", [
            (259, "Assassination", "assassination", "DAMAGER"),
            (260, "Outlaw", "outlaw", "DAMAGER"),
            (261, "Subtlety", "subtlety", "DAMAGER"),
        ]),
        ("PRIEST", "Priest", "priest", [
            (256, "Discipline", "discipline", "HEALER"),
            (257, "Holy", "holy", "HEALER"),
            (258, "Shadow", "shadow", "DAMAGER"),
        ]),
        ("DEATHKNIGHT", "Death Knight", "death-knight", [
            (250, "Blood", "blood", "TANK"),
            (251, "Frost", "frost", "DAMAGER"),
            (252, "Unholy", "unholy", "DAMAGER"),
        ]),
        ("SHAMAN", "Shaman", "shaman", [
            (262, "Elemental", "elemental", "DAMAGER"),
            (263, "Enhancement", "enhancement", "DAMAGER"),
            (264, "Restoration", "restoration", "HEALER"),
        ]),
        ("MAGE", "Mage", "mage", [
            (62, "Arcane", "arcane", "DAMAGER"),
            (63, "Fire", "fire", "DAMAGER"),
            (64, "Frost", "frost", "DAMAGER"),
        ]),
        ("WARLOCK", "Warlock", "warlock", [
            (265, "Affliction", "affliction", "DAMAGER"),
            (266, "Demonology", "demonology", "DAMAGER"),
            (267, "Destruction", "destruction", "DAMAGER"),
        ]),
        ("MONK", "Monk", "monk", [
            (268, "Brewmaster", "brewmaster", "TANK"),
            (270, "Mistweaver", "mistweaver", "HEALER"),
            (269, "Windwalker", "windwalker", "DAMAGER"),
        ]),
        ("DRUID", "Druid", "druid", [
            (102, "Balance", "balance", "DAMAGER"),
            (103, "Feral", "feral", "DAMAGER"),
            (104, "Guardian", "guardian", "TANK"),
            (105, "Restoration", "restoration", "HEALER"),
        ]),
        ("DEMONHUNTER", "Demon Hunter", "demon-hunter", [
            (577, "Havoc", "havoc", "DAMAGER"),
            (581, "Vengeance", "vengeance", "TANK"),
            (1480, "Devourer", "devourer", "DAMAGER"),
        ]),
        ("EVOKER", "Evoker", "evoker", [
            (1467, "Devastation", "devastation", "DAMAGER"),
            (1468, "Preservation", "preservation", "HEALER"),
            (1473, "Augmentation", "augmentation", "DAMAGER"),
        ]),
    ]
    out: list[SpecDef] = []
    for class_file, class_name, class_slug, specs in raw:
        for spec_id, spec_name, spec_slug, role in specs:
            out.append(
                SpecDef(class_file, class_name, class_slug, spec_id, spec_name, spec_slug, role)
            )
    return out


def fetch_html(url: str, timeout: int = 45) -> str:
    """Fetch guide HTML. Prefer curl.exe on Windows — urllib often gets Wowhead 403."""
    import shutil
    import subprocess

    def _validate(body: str) -> str:
        if not body or len(body) < 500:
            raise URLError("empty/short body")
        if "403 ERROR" in body and "cloudfront" in body.lower():
            raise URLError("CloudFront 403 — slow down or use --html-dir / browser cache")
        if "Just a moment" in body and "cf-" in body.lower():
            raise URLError("Cloudflare challenge page")
        return body

    curl = shutil.which("curl") or shutil.which("curl.exe")
    if curl:
        cmd = [
            curl,
            "-sL",
            "-A",
            USER_AGENT,
            "-H",
            "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "-H",
            "Accept-Language: en-US,en;q=0.9",
            "--compressed",
            "--max-time",
            str(timeout),
            url,
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if proc.returncode != 0:
            raise URLError(f"curl failed ({proc.returncode}): {(proc.stderr or '')[:200]}")
        return _validate(proc.stdout)

    req = Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        },
    )
    with urlopen(req, timeout=timeout) as resp:
        return _validate(resp.read().decode("utf-8", errors="replace"))


def extract_markup(html: str) -> str | None:
    """Pull the main guide BBCode body from WH.markup.printHtml(...)."""
    # Prefer the call whose string contains [db=live] (may not be at index 0).
    best: str | None = None
    for m in re.finditer(r"WH\.markup\.printHtml\(", html):
        # Skip getPageData form: printHtml(WH.getPageData(...), ...)
        after = html[m.end() : m.end() + 40].lstrip()
        if after.startswith("WH.getPageData"):
            continue
        if not after.startswith('"'):
            continue
        qstart = m.end() + html[m.end() :].find('"')
        i = qstart + 1
        chars: list[str] = []
        while i < len(html):
            c = html[i]
            if c == "\\":
                chars.append(html[i : i + 2])
                i += 2
                continue
            if c == '"':
                break
            chars.append(c)
            i += 1
        raw = "".join(chars)
        if "[db=live]" in raw or "Stat Priority" in raw or len(raw) > 2000:
            if best is None or len(raw) > len(best):
                best = raw

    if not best:
        return None

    # WH.markup escapes non-ASCII as \uXXXX (e.g. an em dash as —). Lua 5.1
    # has no \u escape, so decode these to real characters before they reach the
    # Lua string writer, or tooltips render the literal "—" text.
    best = re.sub(r"\\u([0-9a-fA-F]{4})", lambda mm: chr(int(mm.group(1), 16)), best)
    return (
        best.replace("\\/", "/")
        .replace("\\r\\n", "\n")
        .replace("\\n", "\n")
        .replace('\\"', '"')
        .replace("\\\\", "\\")
    )


# Midnight secondary DR breakpoints are game-wide (same for every class).
MIDNIGHT_DR_DEFAULTS = {
    "CRIT": [1380, 1840, 2300],
    "HASTE": [1320, 1760, 2200],
    "MASTERY": [1380, 1840, 2300],
    "VERS": [1620, 2160, 2700],
}


def extract_spell_names(html: str) -> dict[str, str]:
    """Wowhead embeds "12345":{"name_enus":"Spell Name" in page data."""
    names: dict[str, str] = {}
    for m in re.finditer(r'"(\d{3,7})"\s*:\s*\{\s*"name_enus"\s*:\s*"((?:\\.|[^"\\])*)"', html):
        raw_name = re.sub(r"\\u([0-9a-fA-F]{4})", lambda mm: chr(int(mm.group(1), 16)), m.group(2))
        names[m.group(1)] = (
            raw_name
            .replace("\\/", "/")
            .replace('\\"', '"')
            .replace("\\\\", "\\")
        )
    return names


def expand_spells(text: str, spell_names: dict[str, str] | None = None) -> str:
    """[spell=12345 …] → real name, or {{spell:12345}} for in-game lookup."""

    def repl(m: re.Match[str]) -> str:
        sid = m.group(1)
        if spell_names and sid in spell_names:
            return spell_names[sid]
        return "{{spell:" + sid + "}}"

    return re.sub(r"\[spell=(\d+)[^\]]*\]", repl, text)


def strip_bbcode(text: str, spell_names: dict[str, str] | None = None) -> str:
    text = expand_spells(text, spell_names)
    text = re.sub(r"\[/?[^\]]+\]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def normalize_stat_name(name: str) -> str | None:
    name = strip_bbcode(name).lower().strip(" :.-")
    # "Critical Strike - Above 1380" → critical strike
    name = re.split(r"\s+-\s+", name, maxsplit=1)[0]
    name = re.sub(r"\s+", " ", name)
    return STAT_NAME_TO_KEY.get(name)


def stat_keys_from_li(text: str) -> list[str]:
    # One list item can group several stats: "Versatility = Critical Strike =
    # Mastery" (tied) or "Agility / Armor / Stamina" (baseline). Split on the
    # separators Wowhead uses and keep every stat that resolves, in order.
    out: list[str] = []
    cleaned = strip_bbcode(text)
    for token in re.split(r"\s*(?:=|/|>|,|\bthen\b|\bor\b)\s*", cleaned, flags=re.I):
        key = normalize_stat_name(token)
        if key and key not in out:
            out.append(key)
    return out


def slugify(label: str) -> str:
    s = strip_bbcode(label).lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or "default"


def parse_priority_lists(body: str, spell_names: dict[str, str] | None = None) -> list[dict[str, Any]]:
    """Find [ol] blocks near 'Stat Priority' labels (hero talent variants)."""
    variants: list[dict[str, Any]] = []

    chunk_re = re.compile(
        r"\[(?:box|div)[^\]]*\](.*?)\[/(?:box|div)\]",
        re.I | re.S,
    )
    for block in chunk_re.finditer(body):
        chunk = block.group(1)
        if not re.search(r"stat\s+priority", chunk, re.I):
            continue
        ol_m = re.search(r"\[ol\](.*?)\[/ol\]", chunk, re.I | re.S)
        if not ol_m:
            continue
        label_m = re.search(
            r"\[b\](.*?(?:Stat Priority).*?)\[/b\]",
            chunk,
            re.I | re.S,
        )
        label = "General"
        if label_m:
            label = strip_bbcode(label_m.group(1), spell_names)
            label = re.sub(r"\s*Stat Priority\s*$", "", label, flags=re.I).strip() or "General"

        priority: list[str] = []
        for li in re.finditer(r"\[li\](.*?)\[/li\]", ol_m.group(1), re.I | re.S):
            for key in stat_keys_from_li(li.group(1)):
                if key not in priority:
                    priority.append(key)
        if priority:
            vid = slugify(label)
            if any(v["id"] == vid and v["priority"] == priority for v in variants):
                continue
            entry = {
                "id": vid,
                "label": label,
                "priority": priority,
            }
            ctx = detect_context(label)
            if ctx:
                entry["context"] = ctx
            variants.append(entry)

    if not variants:
        for ol in re.finditer(r"\[ol\](.*?)\[/ol\]", body, re.I | re.S):
            priority = []
            for li in re.finditer(r"\[li\](.*?)\[/li\]", ol.group(1), re.I | re.S):
                for key in stat_keys_from_li(li.group(1)):
                    if key not in priority:
                        priority.append(key)
            if len(priority) >= 3:
                variants.append({"id": "default", "label": "General", "priority": priority})
                break

    return variants


def parse_stat_blurbs(body: str, spell_names: dict[str, str] | None = None) -> dict[str, dict[str, Any]]:
    """Pull per-stat summaries from 'Stats Explained' style lists."""
    stats: dict[str, dict[str, Any]] = {}

    for m in re.finditer(
        r"\[b\](Strength|Agility|Intellect)\[/b\]\s+(.*?)(?=\n\n|\n\[|\Z)",
        body,
        re.I | re.S,
    ):
        key = normalize_stat_name(m.group(1))
        if not key:
            continue
        summary = strip_bbcode(m.group(2), spell_names)
        summary = re.split(r"\s+For Secondary", summary, maxsplit=1)[0].strip()
        if summary:
            pretty = {"STR": "Strength", "AGI": "Agility", "INT": "Intellect"}.get(key, key)
            if not summary.lower().startswith(pretty.lower()):
                summary = f"{pretty} {summary}"
            stats[key] = {"summary": summary, "notes": []}

    for m in re.finditer(
        r"\[li\]\s*\[b\](Critical Strike|Haste|Mastery|Versatility|Strength|Agility|Intellect)\[/b\]\s*:?\s*(.*?)\[/li\]",
        body,
        re.I | re.S,
    ):
        key = normalize_stat_name(m.group(1))
        if not key:
            continue
        raw = m.group(2)
        if re.search(r"above\s+\d+\s*rating", raw, re.I) and len(strip_bbcode(raw, spell_names)) < 40:
            continue
        notes: list[str] = []
        for div in re.finditer(r"\[div[^\]]*\](.*?)\[/div\]", raw, re.I | re.S):
            note = strip_bbcode(div.group(1), spell_names)
            if note and not re.search(r"above\s+\d+\s*rating", note, re.I):
                notes.append(note)
        summary = strip_bbcode(re.sub(r"\[div[^\]]*\].*?\[/div\]", "", raw, flags=re.I | re.S), spell_names)
        summary = re.sub(r"Advanced Interactions", "", summary, flags=re.I).strip(" :.-")
        if re.search(r"^above\s+\d+\s*rating", summary, re.I):
            continue
        entry = stats.setdefault(key, {"summary": "", "notes": []})
        if summary and not entry["summary"]:
            entry["summary"] = summary
        elif summary and summary not in entry["notes"] and summary != entry["summary"]:
            entry["notes"].append(summary)
        for n in notes:
            if n not in entry["notes"]:
                entry["notes"].append(n)

    return stats


def parse_dr(body: str) -> dict[str, list[int]]:
    """Parse DR breakpoints from the dedicated H2 section (not early guide links)."""
    dr: dict[str, list[int]] = {}

    # Prefer the real heading — early "diminishing returns" links poisoned the old regex.
    heading = re.search(
        r"\[h2[^\]]*\](?:(?!\[/h2\]).)*Diminishing Returns(?:(?!\[/h2\]).)*\[/h2\]",
        body,
        re.I | re.S,
    )
    if heading:
        start = heading.start()
        rest = body[start:]
        nxt = re.search(r"\[h2\b", rest[len(heading.group(0)) :], re.I)
        section = rest[: len(heading.group(0)) + (nxt.start() if nxt else len(rest))]
    else:
        section = body

    for m in re.finditer(
        r"\[b\](Critical Strike|Haste|Mastery|Versatility)\[/b\]\s*[-–—:]?\s*(?:Above\s+)?(\d+)\s*rating",
        section,
        re.I,
    ):
        key = normalize_stat_name(m.group(1))
        if not key:
            continue
        ten = int(m.group(2))
        twenty = int(round(ten * 4 / 3 / 10) * 10)
        thirty = int(round(ten * 5 / 3 / 10) * 10)
        dr[key] = [ten, twenty, thirty]

    # Guides that discuss DR but omit the table still share Midnight's global breakpoints.
    if heading and len(dr) < 4:
        for k, vals in MIDNIGHT_DR_DEFAULTS.items():
            dr.setdefault(k, list(vals))

    return dr


def extract_updated(html: str) -> str | None:
    m = re.search(r'"dateModified"\s*:\s*"(\d{4}-\d{2}-\d{2})', html)
    if m:
        return m.group(1)
    m = re.search(r"Updated:\s*</[^>]+>\s*(\d{4}/\d{2}/\d{2})", html)
    if m:
        return m.group(1).replace("/", "-")
    m = re.search(r'"updated"\s*:\s*"?(\d{10,})"?', html)
    if m:
        try:
            ts = int(m.group(1))
            if ts > 1_000_000_000_000:
                ts //= 1000
            return time.strftime("%Y-%m-%d", time.gmtime(ts))
        except ValueError:
            pass
    return None


def detect_context(label: str) -> str | None:
    """Tag Raid / M+ / AoE style variant labels for UI notes."""
    low = label.lower()
    if "mythic+" in low or re.search(r"\bm\+\b", low) or "dungeon" in low:
        return "mythicplus"
    if "raid" in low:
        return "raid"
    if "aoe" in low or "cleave" in low:
        return "aoe"
    if "single" in low or "st " in low or low.endswith(" st"):
        return "single"
    return None


def intro_notes(body: str, spell_names: dict[str, str] | None = None) -> str:
    text = re.sub(r"\[db=live\]", "", body)
    text = re.sub(r"\[pad\].*", "", text, count=1, flags=re.S)
    prose = strip_bbcode(text.split("[h2")[0], spell_names)
    parts = re.split(r"(?<=[.!?])\s+", prose)
    return " ".join(parts[:2]).strip()


def parse_strengths_weaknesses(
    body: str, spell_names: dict[str, str] | None = None
) -> dict[str, list[str]] | None:
    """Overview guide table: [li icon=plus]/[li icon=minus]."""
    _ = spell_names  # names resolved in-game via {{spell:ID}}
    m = re.search(
        r"Strengths\s+and\s+Weaknesses.*?\[/table\]",
        body,
        re.I | re.S,
    )
    if not m:
        return None
    chunk = m.group(0)
    strengths: list[str] = []
    weaknesses: list[str] = []
    # Keep {{spell:ID}} so the addon can paint gold names + icons in-game.
    for li in re.finditer(r"\[li\s+icon=plus\](.*?)\[/li\]", chunk, re.I | re.S):
        text = strip_bbcode(li.group(1), None)
        if text:
            strengths.append(text)
    for li in re.finditer(r"\[li\s+icon=minus\](.*?)\[/li\]", chunk, re.I | re.S):
        text = strip_bbcode(li.group(1), None)
        if text:
            weaknesses.append(text)
    if not strengths and not weaknesses:
        return None
    return {"strengths": strengths, "weaknesses": weaknesses}


def parse_build_stat_chain(body: str) -> tuple[list[str], list[str]] | None:
    """
    Overview [builds] widget: stats=agi>>crit>mastery>>haste>versatility
    Returns (priority keys, gap glyphs between them) — real Wowhead >> vs >.
    """
    m = re.search(r"stats=([a-z><]+)", body, re.I)
    if not m:
        return None
    raw = m.group(1).lower()
    tokens = re.split(r"(>>|>)", raw)
    tokens = [t for t in tokens if t]
    if len(tokens) < 3:
        return None
    priority: list[str] = []
    gaps: list[str] = []
    expect_stat = True
    for tok in tokens:
        if expect_stat:
            key = STAT_NAME_TO_KEY.get(tok.strip())
            if not key:
                return None
            priority.append(key)
            expect_stat = False
        else:
            if tok not in (">", ">>"):
                return None
            gaps.append(tok)
            expect_stat = True
    if len(gaps) != len(priority) - 1:
        return None
    return priority, gaps


def merge_overview_into_entry(entry: dict[str, Any], overview_html: str) -> None:
    """Attach strengths/weaknesses (+ optional chain gaps) from overview page HTML."""
    body = extract_markup(overview_html)
    if not body:
        return
    spell_names = extract_spell_names(overview_html)
    sw = parse_strengths_weaknesses(body, spell_names)
    if sw:
        entry["strengths"] = sw["strengths"]
        entry["weaknesses"] = sw["weaknesses"]
    chain = parse_build_stat_chain(body)
    if chain:
        priority, gaps = chain
        entry["chainGaps"] = gaps
        # If a variant matches this order, stamp gaps onto it for the UI.
        for v in entry.get("variants") or []:
            if v.get("priority") == priority:
                v["gaps"] = gaps


@dataclass
class ParseResult:
    ok: bool
    entry: dict[str, Any] | None = None
    error: str | None = None


def parse_spec(spec: SpecDef, html: str) -> ParseResult:
    body = extract_markup(html)
    if not body:
        return ParseResult(False, error="no WH.markup.printHtml body")

    spell_names = extract_spell_names(html)
    variants = parse_priority_lists(body, spell_names)
    if not variants:
        return ParseResult(False, error="no stat priority list found")

    stats = parse_stat_blurbs(body, spell_names)
    dr = parse_dr(body)
    updated = extract_updated(html)

    contexts = {v.get("context") for v in variants if v.get("context")}
    context_note = None
    if "raid" in contexts and "mythicplus" in contexts:
        context_note = "This guide splits Raid and Mythic+ priorities — check the tabs."
    elif "mythicplus" in contexts:
        context_note = "Includes a Mythic+ priority tab."
    elif "raid" in contexts:
        context_note = "Includes a Raid priority tab."

    entry = {
        "classFile": spec.class_file,
        "specID": spec.spec_id,
        "name": spec.spec_name,
        "role": spec.role,
        "sourceURL": spec.url,
        "updated": updated or "unknown",
        "variants": variants,
        "stats": stats,
        "dr": dr,
        "notes": intro_notes(body, spell_names),
        "contextNote": context_note,
        "strengths": [],
        "weaknesses": [],
    }
    return ParseResult(True, entry=entry)


# ---
# Lua emitter
# ---

def lua_escape(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "")
    )


def emit_lua_string(s: str, indent: int = 0) -> str:
    pad = "\t" * indent
    if "\n" in s or len(s) > 120:
        # long string
        return f"{pad}[=[{s}]=]"
    return f'{pad}"{lua_escape(s)}"'


def _emit_item_ref(ref: Any) -> str:
    """Plain id, or { id, bonus... } so tooltips can show Myth-track gear."""
    if isinstance(ref, int):
        return str(ref)
    if isinstance(ref, dict):
        item_id = int(ref.get("id") or 0)
        bonuses = ref.get("bonuses") or []
        if not bonuses:
            return str(item_id)
        parts = [str(item_id)] + [str(int(b)) for b in bonuses]
        return "{ " + ", ".join(parts) + " }"
    if isinstance(ref, (list, tuple)) and ref:
        parts = [str(int(x)) for x in ref]
        if len(parts) == 1:
            return parts[0]
        return "{ " + ", ".join(parts) + " }"
    return str(ref)


def emit_spec_lua(key: str, entry: dict[str, Any], indent: int = 2) -> str:
    pad = "\t" * indent
    lines: list[str] = [f'{pad}["{key}"] = {{']
    p = pad + "\t"
    lines.append(f'{p}classFile = "{entry["classFile"]}",')
    lines.append(f'{p}specID = {entry["specID"]},')
    lines.append(f'{p}name = "{lua_escape(entry["name"])}",')
    lines.append(f'{p}role = "{entry["role"]}",')
    lines.append(f'{p}sourceURL = "{lua_escape(entry["sourceURL"])}",')
    lines.append(f'{p}updated = "{lua_escape(entry["updated"])}",')

    lines.append(f"{p}variants = {{")
    for v in entry["variants"]:
        pri = ", ".join(f'"{k}"' for k in v["priority"])
        extras: list[str] = []
        if v.get("context"):
            extras.append(f'context = "{lua_escape(v["context"])}"')
        if v.get("gaps"):
            gaps = ", ".join(f'"{lua_escape(g)}"' for g in v["gaps"])
            extras.append(f"gaps = {{ {gaps} }}")
        extra = (", " + ", ".join(extras)) if extras else ""
        lines.append(
            f'{p}\t{{ id = "{lua_escape(v["id"])}", label = "{lua_escape(v["label"])}", '
            f"priority = {{ {pri} }}{extra} }},"
        )
    lines.append(f"{p}}},")

    lines.append(f"{p}stats = {{")
    for sk, sv in entry["stats"].items():
        notes = ", ".join(f'"{lua_escape(n)}"' for n in sv.get("notes", []) if n)
        lines.append(f"{p}\t{sk} = {{")
        lines.append(f'{p}\t\tsummary = "{lua_escape(sv.get("summary", ""))}",')
        lines.append(f"{p}\t\tnotes = {{ {notes} }},")
        lines.append(f"{p}\t}},")
    lines.append(f"{p}}},")

    lines.append(f"{p}dr = {{")
    for sk, vals in entry["dr"].items():
        joined = ", ".join(str(v) for v in vals)
        lines.append(f"{p}\t{sk} = {{ {joined} }},")
    lines.append(f"{p}}},")

    notes = entry.get("notes") or ""
    lines.append(f'{p}notes = "{lua_escape(notes)}",')
    ctx = entry.get("contextNote")
    if ctx:
        lines.append(f'{p}contextNote = "{lua_escape(ctx)}",')

    strengths = entry.get("strengths") or []
    weaknesses = entry.get("weaknesses") or []
    lines.append(f"{p}strengths = {{")
    for s in strengths:
        lines.append(f'{p}\t"{lua_escape(s)}",')
    lines.append(f"{p}}},")
    lines.append(f"{p}weaknesses = {{")
    for s in weaknesses:
        lines.append(f'{p}\t"{lua_escape(s)}",')
    lines.append(f"{p}}},")

    gear = entry.get("gear")
    if gear and gear.get("cards"):
        lines.append(f"{p}gear = {{")
        if gear.get("sourceURL"):
            lines.append(f'{p}\tsourceURL = "{lua_escape(gear["sourceURL"])}",')
        if gear.get("consumablesURL"):
            lines.append(f'{p}\tconsumablesURL = "{lua_escape(gear["consumablesURL"])}",')
        lines.append(f"{p}\tcards = {{")
        for card in gear["cards"]:
            bis = ", ".join(_emit_item_ref(i) for i in (card.get("bis") or []))
            alts = ", ".join(_emit_item_ref(i) for i in (card.get("alternatives") or []))
            lines.append(
                f'{p}\t\t{{ id = "{lua_escape(card["id"])}", label = "{lua_escape(card.get("label") or card["id"])}", '
                f"bis = {{ {bis} }}, alternatives = {{ {alts} }} }},"
            )
        lines.append(f"{p}\t}},")
        lines.append(f"{p}}},")

    if entry.get("chainGaps"):
        gaps = ", ".join(f'"{lua_escape(g)}"' for g in entry["chainGaps"])
        lines.append(f"{p}chainGaps = {{ {gaps} }},")

    lines.append(f"{pad}}},")
    return "\n".join(lines)


def write_priorities_lua(specs: dict[str, dict[str, Any]], patch: str = "12.1.0") -> None:
    scraped_at = date.today().isoformat()
    missing_dr = sum(1 for e in specs.values() if not e.get("dr"))
    unknown_dates = sum(1 for e in specs.values() if e.get("updated") in (None, "unknown"))
    missing_sw = sum(
        1 for e in specs.values() if not (e.get("strengths") or e.get("weaknesses"))
    )
    missing_gear = sum(
        1 for e in specs.values() if not (e.get("gear") and e["gear"].get("cards"))
    )
    parts = [
        "--[[",
        "\tStatPriorityFirst - Priorities (GENERATED)",
        "\t----",
        "\tDO NOT HAND-EDIT. Regenerated by tools/scrape_stats.py.",
        f"\tScraped: {scraped_at}",
        "--]]",
        "",
        "local _, ns = ...",
        "",
        "ns.Data = {",
        "\tmeta = {",
        f'\t\tscrapedAt = "{scraped_at}",',
        f'\t\tpatch = "{patch}",',
        '\t\tsource = "wowhead",',
        f"\t\tspecCount = {len(specs)},",
        f"\t\tmissingDR = {missing_dr},",
        f"\t\tunknownDates = {unknown_dates},",
        f"\t\tmissingSW = {missing_sw},",
        f"\t\tmissingGear = {missing_gear},",
        "\t},",
        "\tspecs = {",
    ]
    for key in sorted(specs.keys()):
        parts.append(emit_spec_lua(key, specs[key], indent=2))
    parts.append("\t},")
    parts.append("}")
    parts.append("")
    OUT_LUA.write_text("\n".join(parts), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="Scrape Wowhead stat priorities for StatPriorityFirst")
    ap.add_argument("--spec", help="Filter by spec slug substring (e.g. havoc)")
    ap.add_argument("--class-file", help="With --from-html: CLASSFILE")
    ap.add_argument("--spec-id", type=int, help="With --from-html: specID")
    ap.add_argument("--from-html", type=Path, help="Parse a saved HTML file instead of fetching")
    ap.add_argument(
        "--html-map",
        action="append",
        default=[],
        metavar="CLASSFILE:SPECID:PATH",
        help="Parse saved HTML mapped to a spec (repeatable)",
    )
    ap.add_argument("--dry-run", action="store_true", help="Parse but do not write Priorities.lua")
    ap.add_argument("--delay", type=float, default=REQUEST_DELAY)
    ap.add_argument("--patch", default="12.1.0")
    args = ap.parse_args()

    catalog = build_catalog()
    if args.spec:
        needle = args.spec.lower()
        catalog = [s for s in catalog if needle in s.spec_slug or needle in s.spec_name.lower()]
        if not catalog:
            print(f"No specs matched --spec {args.spec!r}", file=sys.stderr)
            return 1

    report: dict[str, Any] = {"scrapedAt": date.today().isoformat(), "results": []}
    parsed: dict[str, dict[str, Any]] = {}

    def ingest(spec: SpecDef, html: str, url_note: str | None = None) -> None:
        result = parse_spec(spec, html)
        report["results"].append(
            {
                "key": spec.key,
                "url": url_note or spec.url,
                "ok": result.ok,
                "error": result.error,
            }
        )
        if result.ok and result.entry:
            parsed[spec.key] = result.entry
            print(f"OK  {spec.key}  variants={len(result.entry['variants'])} stats={list(result.entry['stats'])}")
        else:
            print(f"FAIL {spec.key}: {result.error}")

    if args.html_map:
        by_key = {s.key: s for s in build_catalog()}
        for item in args.html_map:
            parts = item.split(":", 2)
            if len(parts) != 3:
                print(f"Bad --html-map {item!r} (want CLASSFILE:SPECID:PATH)", file=sys.stderr)
                return 1
            class_file, spec_id_s, path_s = parts
            key = f"{class_file}-{spec_id_s}"
            spec = by_key.get(key)
            if not spec:
                print(f"Unknown spec {key}", file=sys.stderr)
                return 1
            path = Path(path_s)
            html = path.read_text(encoding="utf-8", errors="replace")
            ingest(spec, html, url_note=str(path))
    elif args.from_html:
        if not args.class_file or not args.spec_id:
            if len(catalog) == 1:
                spec = catalog[0]
            else:
                print("--from-html requires --class-file and --spec-id (or a single --spec match)", file=sys.stderr)
                return 1
        else:
            spec = next(
                (s for s in build_catalog() if s.class_file == args.class_file and s.spec_id == args.spec_id),
                None,
            )
            if not spec:
                print("Unknown class/spec", file=sys.stderr)
                return 1
        html = args.from_html.read_text(encoding="utf-8", errors="replace")
        ingest(spec, html, url_note=str(args.from_html))
    else:
        for i, spec in enumerate(catalog):
            print(f"[{i + 1}/{len(catalog)}] {spec.key}  {spec.url}")
            try:
                html = fetch_html(spec.url)
                ingest(spec, html)
            except (HTTPError, URLError, TimeoutError, OSError) as e:
                report["results"].append(
                    {"key": spec.key, "url": spec.url, "ok": False, "error": str(e)}
                )
                print(f"  FAIL  {e}")

            if i + 1 < len(catalog):
                time.sleep(args.delay)

    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Report: {REPORT_PATH}")

    if args.dry_run:
        print(f"Dry run — would write {len(parsed)} specs to {OUT_LUA}")
        return 0 if parsed else 1

    if not parsed:
        print("No specs parsed — leaving Priorities.lua unchanged", file=sys.stderr)
        return 1

    # Sidecar JSON lets partial --spec / --from-html / --html-map runs merge into a previous full scrape.
    sidecar = Path(__file__).resolve().parent / "priorities_cache.json"
    if args.spec or args.from_html or args.html_map:
        cache: dict[str, Any] = {}
        if sidecar.exists():
            try:
                cache = json.loads(sidecar.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                cache = {}
        cache.update(parsed)
        parsed = cache
    sidecar.write_text(json.dumps(parsed, indent=2), encoding="utf-8")

    write_priorities_lua(parsed, patch=args.patch)
    ok = sum(1 for r in report["results"] if r["ok"])
    fail = sum(1 for r in report["results"] if not r["ok"])
    print(f"Wrote {OUT_LUA}  ({len(parsed)} specs in file, this run ok={ok} fail={fail})")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
