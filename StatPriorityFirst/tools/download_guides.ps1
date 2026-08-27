# Download all Wowhead stat-priority guides into tools/cache/ (slow + polite).
# Use when CloudFront rate-limits the Python scraper.
#
#   powershell -File download_guides.ps1
#   python scrape_stats.py --html-map ...  (or use import_cache.py)

$ErrorActionPreference = "Stop"
$CacheDir = Join-Path $PSScriptRoot "cache"
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
$DelaySec = 4

# classFile, specId, classSlug, specSlug, roleSuffix
$Specs = @(
  @("WARRIOR",71,"warrior","arms","stat-priority-pve-dps"),
  @("WARRIOR",72,"warrior","fury","stat-priority-pve-dps"),
  @("WARRIOR",73,"warrior","protection","stat-priority-pve-tank"),
  @("PALADIN",65,"paladin","holy","stat-priority-pve-healer"),
  @("PALADIN",66,"paladin","protection","stat-priority-pve-tank"),
  @("PALADIN",70,"paladin","retribution","stat-priority-pve-dps"),
  @("HUNTER",253,"hunter","beast-mastery","stat-priority-pve-dps"),
  @("HUNTER",254,"hunter","marksmanship","stat-priority-pve-dps"),
  @("HUNTER",255,"hunter","survival","stat-priority-pve-dps"),
  @("ROGUE",259,"rogue","assassination","stat-priority-pve-dps"),
  @("ROGUE",260,"rogue","outlaw","stat-priority-pve-dps"),
  @("ROGUE",261,"rogue","subtlety","stat-priority-pve-dps"),
  @("PRIEST",256,"priest","discipline","stat-priority-pve-healer"),
  @("PRIEST",257,"priest","holy","stat-priority-pve-healer"),
  @("PRIEST",258,"priest","shadow","stat-priority-pve-dps"),
  @("DEATHKNIGHT",250,"death-knight","blood","stat-priority-pve-tank"),
  @("DEATHKNIGHT",251,"death-knight","frost","stat-priority-pve-dps"),
  @("DEATHKNIGHT",252,"death-knight","unholy","stat-priority-pve-dps"),
  @("SHAMAN",262,"shaman","elemental","stat-priority-pve-dps"),
  @("SHAMAN",263,"shaman","enhancement","stat-priority-pve-dps"),
  @("SHAMAN",264,"shaman","restoration","stat-priority-pve-healer"),
  @("MAGE",62,"mage","arcane","stat-priority-pve-dps"),
  @("MAGE",63,"mage","fire","stat-priority-pve-dps"),
  @("MAGE",64,"mage","frost","stat-priority-pve-dps"),
  @("WARLOCK",265,"warlock","affliction","stat-priority-pve-dps"),
  @("WARLOCK",266,"warlock","demonology","stat-priority-pve-dps"),
  @("WARLOCK",267,"warlock","destruction","stat-priority-pve-dps"),
  @("MONK",268,"monk","brewmaster","stat-priority-pve-tank"),
  @("MONK",270,"monk","mistweaver","stat-priority-pve-healer"),
  @("MONK",269,"monk","windwalker","stat-priority-pve-dps"),
  @("DRUID",102,"druid","balance","stat-priority-pve-dps"),
  @("DRUID",103,"druid","feral","stat-priority-pve-dps"),
  @("DRUID",104,"druid","guardian","stat-priority-pve-tank"),
  @("DRUID",105,"druid","restoration","stat-priority-pve-healer"),
  @("DEMONHUNTER",577,"demon-hunter","havoc","stat-priority-pve-dps"),
  @("DEMONHUNTER",581,"demon-hunter","vengeance","stat-priority-pve-tank"),
  @("DEMONHUNTER",1480,"demon-hunter","devourer","stat-priority-pve-dps"),
  @("EVOKER",1467,"evoker","devastation","stat-priority-pve-dps"),
  @("EVOKER",1468,"evoker","preservation","stat-priority-pve-healer"),
  @("EVOKER",1473,"evoker","augmentation","stat-priority-pve-dps")
)

$i = 0
foreach ($s in $Specs) {
  $i++
  $classFile, $specId, $classSlug, $specSlug, $suffix = $s
  $out = Join-Path $CacheDir "$classFile-$specId.html"
  $url = "https://www.wowhead.com/guide/classes/$classSlug/$specSlug/$suffix"
  Write-Host "[$i/$($Specs.Count)] $classFile-$specId"
  if ((Test-Path $out) -and (Get-Item $out).Length -gt 5000) {
    Write-Host "  skip (cached)"
    continue
  }
  try {
    # Invoke-WebRequest often survives when curl.exe is CloudFront-blocked.
    $resp = Invoke-WebRequest -Uri $url -UserAgent $UA -UseBasicParsing -TimeoutSec 60
    if ($resp.Content -match "403 ERROR" -and $resp.Content -match "cloudfront") {
      Write-Host "  FAIL CloudFront 403 — wait and retry later"
      Start-Sleep -Seconds 30
      continue
    }
    [IO.File]::WriteAllText($out, $resp.Content)
    Write-Host "  OK $($resp.Content.Length) bytes"
  } catch {
    Write-Host "  FAIL $_"
  }
  Start-Sleep -Seconds $DelaySec
}

Write-Host ""
Write-Host "Next: python import_cache.py"
