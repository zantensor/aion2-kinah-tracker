# Aion 2 gold price tracker — handoff

## Goal
Track the daily gold (基纳/kinah) price for **永恒之塔2, 天族(台服) / 梅斯蘭泰達 天8** from dd373.com.
Source page: `https://www.dd373.com/s-r0f5te-4t9v2k-v0s03h-0-0-0-pccpee-0-0-0-0-0-1-0-3-1.html`

Value isn't today's price — dd373 already shows that. It's the **history and trend**, which dd373 never gives you.

## Current state
`index.html` — single file, no build step, no dependencies.

- Manual daily price entry (date + ¥ price); re-saving a date overwrites it
- SVG line chart, date-scaled x-axis, 7D / 30D / ALL range toggle
- Stats: average, low, high, entry count
- History table with % change vs previous entry, per-row delete
- CSV export; editable server name + unit label; delete-all
- Fonts via Google Fonts CDN (Bricolage Grotesque / IBM Plex Sans / IBM Plex Mono)

**Deployed** (2026-07-21): public repo `zantensor/aion2-kinah-tracker`, live at
`https://zantensor.github.io/aion2-kinah-tracker/`.

**Shared history architecture** (important — keep all paths if editing):
- `data.json` in the repo is the shared source of truth on GitHub Pages. Everyone fetches it on load (cache-busted).
- Visitors get a read-only view (`body.ro` hides all editing UI).
- Admin mode: the owner pastes a fine-grained GitHub token (Contents read/write on this repo only) via the "Admin" button. Token lives in that browser's `localStorage` (`aion2-gh-token`). Saving an entry then commits `data.json` through the GitHub contents API — Pages republishes in ~1 min.
- Claude artifact mode (`window.storage` present) still works as before: private per-user storage, always editable, no GitHub sync.
- `localStorage` (`aion2-gold-log`) is kept as an offline/fallback cache on static hosts.

Data shape: `{ unit: string, server: string, entries: [{ date: "YYYY-MM-DD", price: number }] }`

## Design tokens (keep consistent)
```
--sky #E4E8F6   --mist #FAFBFF   --edge #C9D0E8
--ink #161A38   --ink-soft #5B628C
--aether #3D5BD9 (accent/chart)  --amber #B4761A
--rose #B03A57 (price up)        --jade #22755F (price down)
```
Price up = rose (bad for a buyer), down = jade. Mono + tabular-nums for all numeric display.

## Scraper (added 2026-07-21)
**The "JS-rendered listings" blocker was wrong** — listings ARE server-rendered; the earlier
test simply didn't decompress the forced-gzip response. A plain GET with a browser UA +
`Accept-Encoding` handling returns all 20 first-page listings. No headless browser needed.

`scraper.ps1` (pure PowerShell 5.1, no deps, ASCII-only source — Chinese regex chars built
from char codes) runs via Windows Task Scheduler task **"Aion2 Kinah Price Scraper"** every
6 h (00/06/12/18) on the user's PC (home IP; datacenter IPs get blocked):

1. GET the best-ratio-sorted listing page (`...-1-0-5-1.html`)
2. Split HTML on `goods-list-item` — this excludes promoted-mall rows and platform buyback
   (the tier-mixing trap below) by construction
3. Metric: **median ratio of top-10 regular listings**, stored as ¥ per 100万金 (`100/ratio`)
4. Sanity: ≥5 listings parsed, ratio within 30–250万/元, reject >25% off trailing-7 average
5. Upsert today's entry in `data.json` via GitHub contents API (PAT in local `.env`,
   gitignored); repeat runs same day overwrite. Extra `ratio` field kept per entry.
6. Logs to `scraper.log` (gitignored); failures write `FAIL` lines and touch nothing.

Original blockers, for the record: CORS blocks browser-side fetch (hence PC-side scraper);
robots.txt whitelists only domestic crawlers — 4 requests/day from a residential IP is
indistinguishable from a person checking the page, but keep the cadence gentle.

## Data reliability warning — read this before writing any scraper
Doubao (ByteDance AI, whose crawler dd373 permits) was asked the same question and produced confident output that was **internally contradictory and arithmetically wrong**:

- Claimed "no 天8 kinah listings exist" in one answer, "121 listings" in the next
- Stated 1元 ≈ 67.34万基纳, then "2001元 buys 1347万基纳" — that's 0.67万/元, off by 100×
- Quoted a "1元 = 15.5万基纳" listing, almost certainly a misparse

**Ground truth from search snippets (2026-07-21):** real 天8 kinah listings at ￥18.77 → 1元=71.9233万基纳, and ￥16.10 → 1元=71.4286万基纳. So roughly **71–72万 per yuan** on small auction lots — versus Doubao's claimed 85–100万. A 30–40% gap.

Root cause: the page mixes 极速收货 (platform buyback), bulk retail lots, and small auction lots side by side, at very different ratios. Any scraper **must pin down which tier it's reading** or it will produce numbers that look plausible and are useless.

## Next steps
1. Deploy `index.html` to GitHub Pages (public repo, Settings → Pages → deploy from `main`, root).
2. Log manually for ~1 week to build a baseline.
3. *Only then* consider a GitHub Actions cron scraper committing `data.json` for the page to read.

Caveats for step 3: Actions runs on datacenter IPs that get blocked far more aggressively than a home connection — expect it to work briefly then silently return nothing. The week of manual data from step 2 is what lets you detect that failure. Build in a sanity check that rejects any scraped value more than ~25% off the trailing 7-day average rather than writing it blindly.

## Open decisions
- Which price tier to actually track (buyback vs bulk retail vs small lot) — currently undecided, user logs whatever number matters to them
- Unit label defaults to `100万金`; dd373 quotes per 万 or per 100万 depending on listing. Must be set consistently or the history is meaningless.
