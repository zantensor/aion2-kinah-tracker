# Aion 2 kinah price scraper - dd373.com -> data.json on GitHub Pages
# Runs every 6 h via Windows Task Scheduler. See CONTEXT.md for architecture.
#
# Metric: median ratio (wan kinah per yuan) of the top-10 regular listings on the
# best-ratio sorted page, stored as yuan per 100 wan kinah (price = 100 / ratio).
# Promoted mall rows and platform buyback are outside goods-list-item blocks, so
# splitting on that class excludes them by construction.
#
# Source is ASCII-only on purpose: PS 5.1 misreads BOM-less UTF-8, so the Chinese
# characters in the regex are built from char codes below.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $root 'scraper.log'
function Log($msg){ ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) | Add-Content -Path $logFile -Encoding UTF8 }

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  # --- config ---
  $url  = 'https://www.dd373.com/s-r0f5te-4t9v2k-v0s03h-0-0-0-pccpee-0-0-0-0-0-1-0-5-1.html' # best-ratio sort
  $repo = 'zantensor/aion2-kinah-tracker'
  $token = ((Get-Content (Join-Path $root '.env')) |
    Where-Object { $_ -match '^GITHUB_PAT=' } | Select-Object -First 1) -replace '^GITHUB_PAT=',''
  if (-not $token) { throw 'GITHUB_PAT not found in .env' }

  # yuan / wan / ji / na characters, kept as char codes so this file stays ASCII
  $yuan = [char]0x5143; $wan = [char]0x4E07; $ji = [char]0x57FA; $na = [char]0x7EB3
  $ratioPattern = "1$yuan=([\d.]+)$wan$ji$na"   # matches: 1<yuan>=NN.NN<wan-kinah>

  # --- fetch listing page (server forces gzip; decompress explicitly) ---
  $req = [System.Net.HttpWebRequest]::Create($url)
  $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36'
  $req.Accept = 'text/html,application/xhtml+xml'
  $req.Headers['Accept-Language'] = 'zh-TW,zh;q=0.9,en;q=0.8'
  $req.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
  $req.Timeout = 30000
  $resp = $req.GetResponse()
  $reader = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
  $html = $reader.ReadToEnd(); $reader.Close(); $resp.Close()

  # --- parse: one ratio per regular listing block ---
  $blocks = $html -split 'goods-list-item'
  $ratios = @()
  for ($i = 1; $i -lt $blocks.Count; $i++) {
    $m = [regex]::Match($blocks[$i], $ratioPattern)
    if ($m.Success) { $ratios += [double]$m.Groups[1].Value }
  }
  if ($ratios.Count -lt 5) { throw "parse failure: only $($ratios.Count) listings found (site changed or blocked?)" }

  $top = @($ratios | Sort-Object -Descending | Select-Object -First 10 | Sort-Object)
  $mid = [int][Math]::Floor($top.Count / 2)
  if ($top.Count % 2 -eq 0) { $median = ($top[$mid - 1] + $top[$mid]) / 2 } else { $median = $top[$mid] }
  $median = [Math]::Round($median, 4)
  if ($median -lt 30 -or $median -gt 250) { throw "ratio $median wan/yuan outside sane bounds (30-250)" }
  $price = [Math]::Round(100 / $median, 4)   # yuan per 100 wan kinah

  # --- load current data.json from GitHub ---
  $headers = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'aion2-kinah-scraper' }
  $get = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/data.json?ref=main" -Headers $headers
  $data = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($get.content)) | ConvertFrom-Json
  $entries = @($data.entries)

  # --- sanity: reject values >25% off the trailing average (CONTEXT.md rule) ---
  if ($entries.Count -ge 3) {
    $recent = @($entries | Sort-Object date | Select-Object -Last 7)
    $avg = ($recent | Measure-Object -Property price -Average).Average
    $dev = [Math]::Abs($price - $avg) / $avg
    if ($dev -gt 0.25) { throw ("price {0} deviates {1:P0} from trailing avg {2:N4} - refusing to write" -f $price, $dev, $avg) }
  }

  # --- upsert today's entry (repeat runs the same day overwrite it) ---
  $today = Get-Date -Format 'yyyy-MM-dd'
  $existing = @($entries | Where-Object { $_.date -eq $today })
  if ($existing.Count) {
    $existing[0].price = $price
    $existing[0] | Add-Member -NotePropertyName ratio -NotePropertyValue $median -Force
  } else {
    $entries += [pscustomobject]@{ date = $today; price = $price; ratio = $median }
  }
  $data.entries = @($entries | Sort-Object date)

  # --- commit back via contents API ---
  $json = $data | ConvertTo-Json -Depth 5
  $body = @{
    message = "Auto price update $today (median $median wan/yuan, n=$($ratios.Count))"
    branch  = 'main'
    sha     = $get.sha
    content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
  } | ConvertTo-Json
  Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/data.json" -Method Put -Headers $headers -Body $body -ContentType 'application/json' | Out-Null

  Log ("OK price={0} ratio={1} listings={2}" -f $price, $median, $ratios.Count)
} catch {
  Log ("FAIL {0}" -f $_.Exception.Message)
  exit 1
}
