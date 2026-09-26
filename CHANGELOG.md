# Changelog

## [0.9.0-beta] - 2026-09-26

The first public beta. Everything is new, so here's a tour instead of a diff.

### Vault and the Jealousmeter
- Your wealth is one number: gold on every character and in the warband bank,
  your active auctions, and every item you could sell. Items are valued at their
  market price, or at the vendor price if they can't go to the auction house.
  Soulbound, warbound and equipped gear isn't counted.
- Items that barely sell show up separately as "speculative", so a stack of
  something nobody buys doesn't inflate your wealth. There's a tab that shows
  where each of them sits.
- Gallywix watches your wealth and gets more jealous with every level. Past the
  gold cap he gets fancy frames. The bar shows how much gold the next marks need.
- Gold goals: a wealth target with a forecast, or saving up for a purchase.

### Ledger
- Every change to your gold lands in one category: auction house, vendor,
  repairs, quests, loot, crafting, mail or other. Sending gold to your own alts
  or the warband bank is neutral.
- Rules for mail (boosting payments, for example), trade partners it remembers,
  and a small popup after trades.
- An auction house log with sale rate, average prices and the deposits you lost.
- Single bookings are kept for 90 days, daily totals after that.

### Gatherer
- Farm sessions with a small HUD, gold per hour, auto-pause and a summary at
  the end.
- Alerts for valuable loot, your expected highlights and a watchlist.
- Farm statistics and raid/dungeon lockouts for all characters. Farms and
  watchlists can be shared as strings.

### Workshop
- Each craft remembers which reagents went in and what you paid for them.
  Intermediates you crafted yourself count at their craft cost. Multicraft,
  resourcefulness and concentration are handled.
- Profit per recipe and quality, compared with what actually sold. Crafting
  orders with commission and rewards, salvaging, and what a point of
  concentration is worth to you.

### Dashboard and Insights
- The dashboard covers 1 to 365 days: wealth, net income, where most gold came
  from, the most expensive expense, gold per character, a calendar heatmap,
  records and streaks, plus cards from every module and a comment from Gallywix.
- Insights loads when you open it: history charts, a cash flow diagram, and
  daily and weekly reports.

### Everything else
- Import your TSM Accounting or Journalator history without duplicates, and undo
  it if something looks off (`/gob import`).
- Link several WoW accounts into one wealth figure.
- A setup window on first login (`/gob setup`) for price source and modules.
- Settings with an explanation next to every option. Modules you switch off
  disappear everywhere.
- Prices come from TradeSkillMaster, Auctionator or vendor prices; CraftSim can
  provide craft costs.
- English and German. Other languages are welcome through CurseForge.
