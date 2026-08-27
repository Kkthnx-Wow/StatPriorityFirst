# StatPriorityFirst - one-click weekly reminder + import
# ----
# 1) Paste tools/browser_scrape.js on wowhead.com (Console) -> downloads spf-wowhead-export.json
#    (script fetches stat-priority + overview + bis-gear + enchants-gems/consumables pages)
# 2) Re-run this script to import + print OK/FAIL counts
# 3) /reload in-game, then /spf status

$ErrorActionPreference = "Stop"
$ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AddonRoot = Split-Path -Parent $ToolsDir
$ExportCandidates = @(
	(Join-Path $env:USERPROFILE "Downloads\spf-wowhead-export.json"),
	(Join-Path $ToolsDir "spf-wowhead-export.json")
)

Write-Host ""
Write-Host "=== StatPriorityFirst weekly update ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Step 1 - Browser scrape (if you have not already):"
Write-Host "  1. Open https://www.wowhead.com in Chrome/Edge"
Write-Host "  2. DevTools -> Console -> paste tools\browser_scrape.js"
Write-Host "  3. Wait for spf-wowhead-export.json download (~4-7 min; priority + overview + bis-gear + consumables)"
Write-Host ""

$export = $null
foreach ($path in $ExportCandidates) {
	if (Test-Path $path) {
		$export = $path
		break
	}
}

if (-not $export) {
	Write-Host "FAIL  No export found." -ForegroundColor Red
	Write-Host "  Looked for:"
	foreach ($path in $ExportCandidates) {
		Write-Host "    $path"
	}
	Write-Host ""
	Write-Host "Run the browser scrape first, then re-run this script." -ForegroundColor Yellow
	exit 1
}

$age = (Get-Date) - (Get-Item $export).LastWriteTime
Write-Host "Found export: $export" -ForegroundColor Green
Write-Host ("  Age: {0:N1} hours" -f $age.TotalHours)
Write-Host ""
Write-Host "Step 2 - Importing..." -ForegroundColor Cyan

Push-Location $ToolsDir
try {
	$out = & python import_browser_export.py $export 2>&1
	$out | ForEach-Object { Write-Host $_ }

	$ok = ([regex]::Matches(($out | Out-String), "(?m)^OK\s+")).Count
	$fail = ([regex]::Matches(($out | Out-String), "(?m)^FAIL\s+")).Count
	$wrote = ($out | Out-String) -match "Wrote Data/Priorities"
	$gearHits = ([regex]::Matches(($out | Out-String), "gearCards=[1-9]")).Count

	Write-Host ""
	if ($wrote -and $fail -eq 0) {
		Write-Host "OK  Import complete - $ok specs OK, $fail FAIL." -ForegroundColor Green
	} elseif ($wrote) {
		Write-Host "WARN  Import wrote Priorities.lua - $ok OK, $fail FAIL." -ForegroundColor Yellow
	} else {
		Write-Host "FAIL  Import did not write Priorities.lua." -ForegroundColor Red
		exit 1
	}

	$priorities = Join-Path $AddonRoot "Data\Priorities.lua"
	if (Test-Path $priorities) {
		$text = Get-Content $priorities -Raw
		if ($text -match 'scrapedAt\s*=\s*"([^"]+)"') {
			Write-Host "  scrapedAt: $($Matches[1])"
		}
		if ($text -match 'specCount\s*=\s*(\d+)') {
			Write-Host "  specCount: $($Matches[1])"
		}
		if ($text -match 'missingDR\s*=\s*(\d+)') {
			Write-Host "  missingDR: $($Matches[1])"
		}
		if ($text -match 'missingGear\s*=\s*(\d+)') {
			Write-Host "  missingGear: $($Matches[1])"
			if ([int]$Matches[1] -gt 0) {
				Write-Host "  (Re-run browser_scrape.js so export includes gearHtml, or use fetch_gear_batch.py.)" -ForegroundColor Yellow
			}
		}
		Write-Host "  Gear rows with data in import log: $gearHits"
	}

	Write-Host ""
	Write-Host "Step 3 - In-game: /reload then /spf status" -ForegroundColor Cyan
	exit 0
} finally {
	Pop-Location
}
