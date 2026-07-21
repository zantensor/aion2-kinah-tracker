# 卡拉米俱樂部 — Aion 2 kinah price tracker

## What this is
Automated daily price tracker for kinah (基納) on **永恒之塔2, 天族(台服) / 梅斯蘭泰達 天8**,
scraped from dd373.com every 6 hours, published for the guild (卡拉米俱樂部) on GitHub Pages.
Value isn't today's price — dd373 shows that. It's the **history and trend**, which dd373
never gives you, plus a comparison against Taobao vendors.

- **Live site:** https://zantensor.github.io/aion2-kinah-tracker/
- **Repo (public):** https://github.com/zantensor/aion2-kinah-tracker
- **Source page:** https://www.dd373.com/s-r0f5te-4t9v2k-v0s03h-0-0-0-pccpee-0-0-0-0-0-1-0-3-1.html
- **Timezone:** everything is GMT+8 (Singapore/Taiwan; user + guild + scraper PC all GMT+8)

## Architecture (as of 2026-07-21, all working end-to-end)
```
Windows Task Scheduler ("Aion2 Kinah Price Scraper", every 6 h: 00/06/12/18, catch-up on wake)
  └─ scraper.ps1 (this folder, pure PowerShell 5.1, zero deps)
       ├─ GET dd373 best-ratio page (plain HTTP + gzip decompress — NO headless browser needed)
       ├─ parse regular listings, compute metric + spread, sanity-check
       └─ upsert today's entry in data.json via GitHub contents API (PAT from .env)
            └─ GitHub Pages republishes (~1 min) → index.html fetches data.json on load
```
The user's PC must be on for scrapes; missed runs fire on next boot (StartWhenAvailable).
Days with no runs = gaps in the chart, harmless.

## Files
- `index.html` — the whole site, single file, no build step
- `data.json` — shared source of truth (see Data shape)
- `scraper.ps1` — scraper; ASCII-only source (PS 5.1 misreads BOM-less UTF-8; the Chinese
  regex is built from `[char]` codes)
- `.env` — `GITHUB_PAT=...` fine-grained token, Contents read/write on this repo ONLY.
  **gitignored, never commit.** Same token is pasted into the owner's browser for admin mode.
- `.gitignore` — `.env`, `scraper.log`
- `scraper.log` — one line per run: `OK price=… ratio=… listings=…` or `FAIL reason`

## Scraper details
1. GET the **best-ratio-sorted** listing page (URL suffix `...-1-0-5-1.html`)
2. Split HTML on `goods-list-item` — promoted 热卖商城 rows and 极速收货 buyback live outside
   those blocks, so the tier-mixing trap (see warning below) is excluded by construction
3. **Metric: median ratio (万基納/元) of the top-10 regular listings**, stored as
   ¥ per 1億基納 = `10000/ratio`. Spread: `low`/`high` = best/worst of that same top-10.
4. Sanity: ≥5 listings parsed; ratio within 30–250万/元; reject >25% off trailing-7 average.
   On any failure: log FAIL, write nothing.
5. Same-day runs accumulate: `samples` collects each run's median, `price` = their average,
   `low`/`high` = widest range observed that day, `ratio` derived from averaged price.
   A new day starts a fresh entry.
6. Stamps top-level `updated` (ISO, `+08:00` offset).

Historical note: an earlier assessment claimed listings were JS-rendered and needed a headless
browser — wrong. The test had merely failed to decompress dd373's forced-gzip response.
CORS still blocks browser-side fetching (hence the PC-side scraper), and robots.txt only
whitelists domestic crawlers — 4 requests/day from a residential IP is indistinguishable from
a person checking the page, but keep the cadence gentle.

## Data shape (`data.json`)
```
{
  unit: "1億基納",            // display unit; price = ¥ per this quantity
  server: "梅斯蘭泰達 天8",
  updated: "2026-07-21T18:31:08+08:00",   // last write, shown with live/stale dot
  entries: [ { date, price, ratio, low, high, samples: [..] } ],  // one per day
  vendors: [ { name, price, updated: "YYYY-MM-DD HH:mm" } ]       // Taobao sellers, manual
}
```
Seeded entry: 2026-07-20 @ ¥109 was provided by the user (not scraped); its low/high equal
price, so the chart band is zero-width there.

## Page features (`index.html`)
All UI in **繁體中文** (`lang="zh-Hant"`). Currency of record is CNY.
**Numeric dates are always day-first: DD/MM/YY (table), DD/MM (chart, vendor chips) — user
preference, never MM/DD.** Long Chinese dates (2026年7月21日) stay as-is.

- **Masthead**: 卡拉米俱樂部 in gradient (ink→aether), subtitle 永恆之塔2 · server · 基納價格
- **Hero**: gradient price with glow + count-up animation (rolls 0→price on load, old→new on
  change/currency switch; disabled for prefers-reduced-motion); unit chip 每 1億基納;
  掛單區間 low–high line; 最後更新 timestamp rendered in Asia/Taipei with a pulsing green dot
  that turns amber + 更新暫停中 when data is >8 h old (missed scrape signal)
- **Currency toggle** (hero top-right): 人民幣 / 台幣. TWD is display-only conversion of every
  number (hero, spread, chart labels, stats, tables); rate from open.er-api.com (fallback:
  jsDelivr fawazahmed0 currency-api), cached 12 h in localStorage; per-visitor choice
  remembered (`aion2-cur`). TWD rounds to whole dollars. FX note line shows the live rate.
- **Chart**: SVG line of daily median with shaded low–high band (only drawn when every entry
  in range has low/high), 7天/30天/全部 toggle, y-labels in active currency
- **Stats**: 平均/最低/最高/筆數 across the selected range (across days — intraday spread is
  the band/掛單區間, a deliberate distinction)
- **商人比價**: DD373 (自動, baseline) vs manually-tracked Taobao vendors, sorted cheapest
  first, ±% vs baseline (rose = premium, jade = cheaper), per-vendor updated chip
  (MM/DD HH:mm). Percentages recompute automatically as DD373 moves.
- **歷史紀錄**: per-day table with ±% vs previous day
- **Modes**:
  - Visitor (default): read-only; `body.ro` hides every editing control
  - **Admin**: open `…/#admin`, paste the GitHub PAT once per browser (stored in
    localStorage `aion2-gh-token`; `#admin` again = logout). Unlocks: 登記價格 manual form,
    row deletes, vendor add/edit/delete, unit/server rename, clear-all. Every save commits
    data.json via the contents API and refreshes `updated`.
  - Claude artifact mode (`window.storage` present): private per-user storage, always
    editable, no GitHub sync. Keep all three paths if editing.
- localStorage `aion2-gold-log` doubles as offline/fallback cache on static hosts.

## Fonts & design
- Latin/digits: Bricolage Grotesque (display) / IBM Plex Sans (body) / IBM Plex Mono (all
  numerals, tabular-nums)
- CJK: **Noto Sans TC webfont** (explicit user choice after trying native-stack JhengHei and
  LXGW WenKai) → fallbacks PingFang TC/SC, Hiragino, Source Han Sans, JhengHei
- Numbers display without decimals when whole (¥105), with decimals when not (¥101.99)

Design tokens (keep consistent):
```
--sky #E4E8F6   --mist #FAFBFF   --edge #C9D0E8
--ink #161A38   --ink-soft #5B628C
--aether #3D5BD9 (accent/chart)  --amber #B4761A (stale)
--rose #B03A57 (price up / vendor premium)   --jade #22755F (price down / cheaper)
```
Price up = rose (bad for a buyer), down = jade.

## Data reliability warning (kept for the record)
Doubao (ByteDance AI) produced confidently wrong numbers for this exact question: contradictory
listing counts, arithmetic off by 100×, and a "1元=15.5万" figure that is actually a promoted
premium-mall row — not representative. Root cause: the dd373 page mixes 极速收货 (platform
buyback ~102万/元), premium mall lots (67万 and worse), and regular auction lots (~92–96万/元
as of 2026-07-21) side by side. The scraper reads ONLY regular listings; keep it that way.

## Operational notes
- Scheduled task: `Get-ScheduledTaskInfo -TaskName 'Aion2 Kinah Price Scraper'`
- Manual scrape: `powershell -NoProfile -ExecutionPolicy Bypass -File scraper.ps1`
- If dd373 changes markup or blocks the IP → FAIL lines in scraper.log; page dot goes amber
  after 8 h; manual admin entry is the fallback
- If the PAT expires: make a new fine-grained token (Contents RW, this repo only), update
  `.env` AND re-paste via `#admin`
- Local repo may lag behind origin (scraper commits via API) — `git pull --rebase` before
  local edits
