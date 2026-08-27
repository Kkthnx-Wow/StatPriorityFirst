/**
 * StatPriorityFirst — Wowhead browser scraper
 * ----
 * Paste this into DevTools console on https://www.wowhead.com (any page).
 * It fetches every Midnight stat-priority guide from YOUR browser session
 * (no CloudFront CLI block), then downloads spf-wowhead-export.json.
 *
 * Then:
 *   cd tools
 *   python import_browser_export.py spf-wowhead-export.json
 *
 * Options (set before pasting, or edit below):
 *   window.SPF_DELAY_MS = 1200   // ms between requests
 *   window.SPF_ONLY = "havoc"    // optional slug filter (all four page types)
 */
(async function StatPriorityFirstBrowserScrape() {
  "use strict";

  const DELAY_MS = Number(window.SPF_DELAY_MS) || 1200;
  const ONLY = (window.SPF_ONLY || "").toLowerCase().trim();

  const ROLE_SUFFIX = {
    DAMAGER: "stat-priority-pve-dps",
    HEALER: "stat-priority-pve-healer",
    TANK: "stat-priority-pve-tank",
  };

  const OVERVIEW_SUFFIX = {
    DAMAGER: "overview-pve-dps",
    HEALER: "overview-pve-healer",
    TANK: "overview-pve-tank",
  };

  // Midnight BiS guides share a single bis-gear slug (role pages redirect here).
  const GEAR_SUFFIX = {
    DAMAGER: "bis-gear",
    HEALER: "bis-gear",
    TANK: "bis-gear",
  };

  // Flasks / potions / food live on the Consumables nav page (enchants-gems).
  const CONSUMABLES_SUFFIX = {
    DAMAGER: "enchants-gems-pve-dps",
    HEALER: "enchants-gems-pve-healer",
    TANK: "enchants-gems-pve-tank",
  };

  // Keep in sync with Data/Catalog.lua + scrape_stats.py
  const CATALOG = [
    ["WARRIOR", "warrior", [
      [71, "Arms", "arms", "DAMAGER"],
      [72, "Fury", "fury", "DAMAGER"],
      [73, "Protection", "protection", "TANK"],
    ]],
    ["PALADIN", "paladin", [
      [65, "Holy", "holy", "HEALER"],
      [66, "Protection", "protection", "TANK"],
      [70, "Retribution", "retribution", "DAMAGER"],
    ]],
    ["HUNTER", "hunter", [
      [253, "Beast Mastery", "beast-mastery", "DAMAGER"],
      [254, "Marksmanship", "marksmanship", "DAMAGER"],
      [255, "Survival", "survival", "DAMAGER"],
    ]],
    ["ROGUE", "rogue", [
      [259, "Assassination", "assassination", "DAMAGER"],
      [260, "Outlaw", "outlaw", "DAMAGER"],
      [261, "Subtlety", "subtlety", "DAMAGER"],
    ]],
    ["PRIEST", "priest", [
      [256, "Discipline", "discipline", "HEALER"],
      [257, "Holy", "holy", "HEALER"],
      [258, "Shadow", "shadow", "DAMAGER"],
    ]],
    ["DEATHKNIGHT", "death-knight", [
      [250, "Blood", "blood", "TANK"],
      [251, "Frost", "frost", "DAMAGER"],
      [252, "Unholy", "unholy", "DAMAGER"],
    ]],
    ["SHAMAN", "shaman", [
      [262, "Elemental", "elemental", "DAMAGER"],
      [263, "Enhancement", "enhancement", "DAMAGER"],
      [264, "Restoration", "restoration", "HEALER"],
    ]],
    ["MAGE", "mage", [
      [62, "Arcane", "arcane", "DAMAGER"],
      [63, "Fire", "fire", "DAMAGER"],
      [64, "Frost", "frost", "DAMAGER"],
    ]],
    ["WARLOCK", "warlock", [
      [265, "Affliction", "affliction", "DAMAGER"],
      [266, "Demonology", "demonology", "DAMAGER"],
      [267, "Destruction", "destruction", "DAMAGER"],
    ]],
    ["MONK", "monk", [
      [268, "Brewmaster", "brewmaster", "TANK"],
      [270, "Mistweaver", "mistweaver", "HEALER"],
      [269, "Windwalker", "windwalker", "DAMAGER"],
    ]],
    ["DRUID", "druid", [
      [102, "Balance", "balance", "DAMAGER"],
      [103, "Feral", "feral", "DAMAGER"],
      [104, "Guardian", "guardian", "TANK"],
      [105, "Restoration", "restoration", "HEALER"],
    ]],
    ["DEMONHUNTER", "demon-hunter", [
      [577, "Havoc", "havoc", "DAMAGER"],
      [581, "Vengeance", "vengeance", "TANK"],
      [1480, "Devourer", "devourer", "DAMAGER"],
    ]],
    ["EVOKER", "evoker", [
      [1467, "Devastation", "devastation", "DAMAGER"],
      [1468, "Preservation", "preservation", "HEALER"],
      [1473, "Augmentation", "augmentation", "DAMAGER"],
    ]],
  ];

  function sleep(ms) {
    return new Promise((r) => setTimeout(r, ms));
  }

  function buildSpecs() {
    const out = [];
    for (const [classFile, classSlug, specs] of CATALOG) {
      for (const [specID, name, specSlug, role] of specs) {
        if (ONLY && !specSlug.includes(ONLY) && !name.toLowerCase().includes(ONLY)) {
          continue;
        }
        out.push({
          classFile,
          classSlug,
          specID,
          name,
          specSlug,
          role,
          key: `${classFile}-${specID}`,
          url: `https://www.wowhead.com/guide/classes/${classSlug}/${specSlug}/${ROLE_SUFFIX[role]}`,
          overviewUrl: `https://www.wowhead.com/guide/classes/${classSlug}/${specSlug}/${OVERVIEW_SUFFIX[role]}`,
          gearUrl: `https://www.wowhead.com/guide/classes/${classSlug}/${specSlug}/${GEAR_SUFFIX[role]}`,
          consumablesUrl: `https://www.wowhead.com/guide/classes/${classSlug}/${specSlug}/${CONSUMABLES_SUFFIX[role]}`,
        });
      }
    }
    return out;
  }

  /** Pull the largest WH.markup.printHtml("...") string that looks like guide body. */
  function extractMarkup(html) {
    let best = null;
    const re = /WH\.markup\.printHtml\(/g;
    let m;
    while ((m = re.exec(html))) {
      const after = html.slice(m.index + m[0].length).trimStart();
      if (after.startsWith("WH.getPageData")) continue;
      if (!after.startsWith('"')) continue;
      let i = html.indexOf('"', m.index + m[0].length) + 1;
      let raw = "";
      while (i < html.length) {
        const c = html[i];
        if (c === "\\") {
          raw += html.slice(i, i + 2);
          i += 2;
          continue;
        }
        if (c === '"') break;
        raw += c;
        i++;
      }
      if (raw.includes("[db=live]") || raw.includes("Stat Priority") || raw.length > 2000) {
        if (!best || raw.length > best.length) best = raw;
      }
    }
    if (!best) return null;
    return best
      .replace(/\\\//g, "/")
      .replace(/\\r\\n/g, "\n")
      .replace(/\\n/g, "\n")
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, "\\");
  }

  function downloadJson(obj, filename) {
    const blob = new Blob([JSON.stringify(obj, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }

  if (!location.hostname.includes("wowhead.com")) {
    console.error("[SPF] Open https://www.wowhead.com first, then paste again.");
    return;
  }

  const specs = buildSpecs();
  console.log(`[SPF] Fetching ${specs.length} priority + overview + bis-gear + consumables guides (delay ${DELAY_MS}ms)…`);

  const pages = [];
  let ok = 0;
  let fail = 0;

  async function fetchPage(url) {
    const resp = await fetch(url, { credentials: "include" });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const html = await resp.text();
    if (html.includes("403 ERROR") && /cloudfront/i.test(html)) {
      throw new Error("CloudFront 403");
    }
    return html;
  }

  for (let i = 0; i < specs.length; i++) {
    const spec = specs[i];
    const label = `[${i + 1}/${specs.length}] ${spec.key}`;
    try {
      const html = await fetchPage(spec.url);
      const markup = extractMarkup(html);
      if (!markup) throw new Error("no guide markup found");

      let overviewHtml = null;
      let overviewError = null;
      try {
        await sleep(Math.max(400, DELAY_MS * 0.5));
        overviewHtml = await fetchPage(spec.overviewUrl);
      } catch (ovErr) {
        overviewError = String(ovErr && ovErr.message ? ovErr.message : ovErr);
      }

      let gearHtml = null;
      let gearError = null;
      try {
        await sleep(Math.max(400, DELAY_MS * 0.5));
        gearHtml = await fetchPage(spec.gearUrl);
      } catch (gErr) {
        gearError = String(gErr && gErr.message ? gErr.message : gErr);
      }

      let consumablesHtml = null;
      let consumablesError = null;
      try {
        await sleep(Math.max(400, DELAY_MS * 0.5));
        consumablesHtml = await fetchPage(spec.consumablesUrl);
      } catch (cErr) {
        consumablesError = String(cErr && cErr.message ? cErr.message : cErr);
      }

      pages.push({
        classFile: spec.classFile,
        specID: spec.specID,
        name: spec.name,
        role: spec.role,
        url: spec.url,
        overviewUrl: spec.overviewUrl,
        gearUrl: spec.gearUrl,
        consumablesUrl: spec.consumablesUrl,
        key: spec.key,
        ok: true,
        error: null,
        overviewError,
        gearError,
        consumablesError,
        markup,
        html,
        overviewHtml,
        gearHtml,
        consumablesHtml,
      });
      ok++;
      const swHint = overviewHtml && /Strengths\s+and\s+Weaknesses/i.test(overviewHtml) ? "+SW" : "noSW";
      const gearHint = gearHtml && /\[item=\d+/i.test(gearHtml) ? "+gear" : "noGear";
      const consHint = consumablesHtml && /\[item=\d+/i.test(consumablesHtml) ? "+cons" : "noCons";
      console.log(`${label} OK (${markup.length} chars, ${swHint}, ${gearHint}, ${consHint})`);
    } catch (err) {
      fail++;
      pages.push({
        classFile: spec.classFile,
        specID: spec.specID,
        name: spec.name,
        role: spec.role,
        url: spec.url,
        overviewUrl: spec.overviewUrl,
        gearUrl: spec.gearUrl,
        consumablesUrl: spec.consumablesUrl,
        key: spec.key,
        ok: false,
        error: String(err && err.message ? err.message : err),
        markup: null,
        html: null,
        overviewHtml: null,
        gearHtml: null,
        consumablesHtml: null,
      });
      console.warn(`${label} FAIL`, err);
    }
    if (i + 1 < specs.length) await sleep(DELAY_MS);
  }

  const exportPayload = {
    scrapedAt: new Date().toISOString().slice(0, 10),
    source: "wowhead-browser",
    patch: "12.0.7",
    ok,
    fail,
    pages,
  };

  // Also stash on window for copy/paste if download is blocked
  window.SPF_LAST_EXPORT = exportPayload;
  downloadJson(exportPayload, "spf-wowhead-export.json");

  console.log(
    `[SPF] Done. ok=${ok} fail=${fail}. Downloaded spf-wowhead-export.json\n` +
      `Also available as window.SPF_LAST_EXPORT\n` +
      `Next: python import_browser_export.py spf-wowhead-export.json`
  );
  return exportPayload;
})();
