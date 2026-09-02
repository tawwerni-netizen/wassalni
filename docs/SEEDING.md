# Seeding the community tree

Coverage is national from day one; liquidity is not. This file is the operational
counterpart to PROJECT.md §2.

## Tree shape

```
مصر                      kind=country      is_reportable=false
 └─ المحافظة (27)         kind=governorate  is_reportable=false
     └─ مدينة / حي         kind=city|district is_reportable=true
         └─ الجامعة / المول / الكمبوند / مقر العمل
                          kind=campus|mall|compound|workplace  is_reportable=true
             └─ منطقة      (areas table, curated)
```

Egypt and the 27 governorates ship in `db/migrations/0003_nationwide_scope.sql`.
Everything below that is operational data, seeded per launch — not a migration.

## Rules

1. **Never make a governorate or the country reportable.** A report attached to
   "القاهرة" is unmatchable and pollutes every feed under it. The
   `reports_set_governorate` trigger rejects it.
2. **Areas are curated, never free text.** 6–20 per venue. Use names people
   actually say out loud ("بوابة ٣", "كافيتيريا الهندسة", "الدور الأرضي")
   — not official names nobody uses.
3. **A venue with no areas is not ready to launch.** "نفس المنطقة" is the
   strongest match signal; without areas the venue scores at most 12 on
   proximity and suggestions get noticeably worse.
4. **Duplicate venues are the main failure mode of an open tree.** Two entries
   for the same campus split its liquidity in half. The venue-request queue
   (M9) exists for exactly this; deduplicate before approving.

## Launch order

Coverage is national, but seeding effort is sequential. One flagship venue at a
time, in the order in PROJECT.md §2 (campus → mall → compound → workplace).

For the flagship, before launch:

- [ ] Curated area list agreed with someone who actually works there
- [ ] Back-fill of real historical lost/found posts from the venue's existing
      Facebook group — **with permission from the group admins and the original
      posters**, and with all identifying detail stripped to P0
- [ ] At least 20 seeded reports, mixed LOST and FOUND, spread across areas and
      the last 14 days, so matching has something to work with on day one
- [ ] A named moderator for that venue

## Health check

A community is **live** at ≥20 reports/week. Track live communities, not
registrations — national sign-up numbers are vanity if no single community is
live. If nothing is live at week 6, stop broad marketing and put all effort into
one venue.
