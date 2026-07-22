# Changelog — 卡拉米俱樂部 kinah tracker

> Session log for picking up where we left off. Architecture/how-it-works lives in
> `CONTEXT.md` — read that first; this file is the "what happened, when" record.

## 2026-07-21 — v1.0: from local HTML to fully automated guild tracker (one session)

### Infrastructure
- Installed GitHub CLI, authenticated as **zantensor** (device flow)
- Created public repo **zantensor/aion2-kinah-tracker**; GitHub Pages from `main` root
  - Live: https://zantensor.github.io/aion2-kinah-tracker/
  - Decision: public repo + free Pages (private repo would need Pro or Cloudflare Pages)
- Fine-grained PAT (Contents RW, this repo only) stored in local `.env` (gitignored) and in
  owner's browser localStorage for admin mode
- Git identity uses noreply email; commits co-authored by Claude

### Scraper (the big discovery)
- **dd373 listings are NOT JS-rendered** — old blocker was a gzip-decompression mistake.
  Plain HTTP GET works. No headless browser.
- `scraper.ps1`: PowerShell 5.1, zero deps, ASCII-only source (PS 5.1 + BOM-less UTF-8 issue;
  Chinese regex built from `[char]` codes)
- Metric: median 万基納/元 ratio of top-10 regular listings (best-ratio sort page), excludes
  premium-mall & buyback tiers by splitting on `goods-list-item`
- Sanity: ≥5 listings, ratio 30–250, reject >25% off trailing-7 avg; failures log-only
- Scheduled task **"Aion2 Kinah Price Scraper"**: every 6 h (00/06/12/18 GMT+8), catch-up on
  wake; verified firing autonomously (18:00 run landed while we worked)
- Same-day runs **average** into one daily price (`samples` array); `low`/`high` = widest
  daily listing range → chart band
- Writes `data.json` via GitHub contents API; stamps `updated` with +08:00 offset

### Page evolution (index.html, single file)
- Read-only for guildmates; admin via hidden `…/#admin` (token prompt; `#admin` again = logout)
- Full UI in 繁體中文; currency 基納 (was 金)
- Unit: **¥ per 1億基納** (was per 100萬金 — small numbers confused vs lot totals)
- Masthead **卡拉米俱樂部** (gradient ink→aether) + bigger subtitle line
- Hero: gradient price + glow, count-up animation, unit chip (right of price, enlarged),
  掛單區間 spread line, 最後更新 timestamp with pulsing green dot (amber + 更新暫停中 if >8 h stale)
- Chart: shaded low–high band around median line
- **商人比價** panel: Taobao vendors vs DD373 baseline, manual admin add/edit/delete with
  auto date+time stamps — seeded: 森林游戲業務 ¥125, 小二哥網游 ¥120 (both 21/07 18:50)
- **人民幣/台幣 toggle**: live FX (open.er-api.com + jsDelivr fallback, 12 h cache),
  per-visitor persistence, TWD rounds to whole dollars
- Whole numbers drop decimals (¥105 not ¥105.00); decimals kept when meaningful (¥101.99)
- Dates: **DD/MM/YY** table, **DD/MM** chart & vendor chips (user preference, saved to memory)
- Fonts: tried native stack (JhengHei), LXGW WenKai → settled on **Noto Sans TC** webfont;
  PingFang for Apple devices as fallback-first isn't used since Noto loads everywhere
- Removed: Export CSV, visible Admin button (moved to #admin)

### Data
- 20/07/26: ¥109 (user-provided seed, zero-width band)
- 21/07/26: ¥105 avg (samples 105, 105; ratio ~95.24; spread 101.99–107) — first scraped day
- Market note: regular listings ~92–96万/元 today; Taobao vendors +14–19% premium

### Known state / gotchas for next session
- Local repo can lag origin (scraper commits via API) → `git pull --rebase` first
- Scraper log: `scraper.log` in project folder; task check:
  `Get-ScheduledTaskInfo -TaskName 'Aion2 Kinah Price Scraper'`
- PC must be on for scrapes; gaps in chart are just missed days
- User preferences in Claude memory: GMT+8 timezone, DD/MM/YY dates

### Ideas floated but not built
- Self-hosted 粉圓體 (jf open-huninn) font if Noto ever disappoints
- Vendor price history (currently latest-only per vendor)
