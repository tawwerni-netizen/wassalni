# Wassalni — Milestones and Tasks

Plan date: 2026-09-02.

**Rules of engagement**

- One milestone at a time. A milestone is not done until *all four* of its
  Acceptance / Tests / Security / Cost sections pass.
- Model split — **Opus**: architecture, backend, privacy/security, data model,
  matching logic, race conditions, hard debugging, code review. **Sonnet**:
  screens, Compose UI, ViewModels, repositories, integration, tests, bug fixes
  on approved tasks.
- Anything not in a milestone goes to `docs/BACKLOG.md`.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done

---

## M0 — Architecture and project setup

Decisions resolved 2026-09-02 (ARCHITECTURE.md §9): Supabase approved, project
moved to `H:\Claide Apps\wassalni`, scope is nationwide-hierarchical.

### Written (not yet compiled — see the toolchain gate below)

- [x] Move to an ASCII path (`H:\Claide Apps\wassalni`); app label stays وصلني
- [x] `git init`
- [x] `.gitignore` (Android + `local.properties` + `google-services.json` + keystores)
- [x] Gradle: version catalog, Kotlin 2.0.21, AGP 8.7.3, JDK 17, minSdk 24,
      targetSdk 35, Compose BOM, Hilt, `supabase-kt` — all pinned
- [x] Modules `:app`, `:core:model`, `:core:data`, `:core:designsystem`
- [x] Design system: colour/type/spacing tokens, light + dark, **RTL by default**,
      Arabic-loosened type ramp, LOST/FOUND as semantic tokens
- [x] String resources: `values/` = Arabic (default), `values-en/` = English
- [x] `buildConfigField` wiring for `SUPABASE_URL` / `SUPABASE_ANON_KEY`
- [x] Placeholder home screen with the two primary actions, previewed in
      RTL/LTR × light/dark × 200% font scale
- [x] `ArabicText` client-side normaliser + sensitive-number guard, with 22 unit
      tests asserting parity with the SQL functions
- [x] Seed migration `0004`: 8 categories with `group_key`, 16 colours, colour
      adjacency
- [x] pgTAP suite `db/tests/001_schema_invariants.sql` (25 assertions)
- [x] CI: Gradle build + unit tests, and a Postgres job that applies every
      migration and runs the pgTAP suite

### Blocked on the toolchain

- [ ] **Install JDK 17 + Android SDK** (this machine has JRE 1.8 only, no SDK)
- [ ] First Gradle sync — generates `gradle-wrapper.jar` and `sdk.dir`
- [ ] `./gradlew assembleDebug` and `./gradlew test` actually green
- [ ] Add Cairo or IBM Plex Sans Arabic to `res/font` and point `Type.kt` at it
      (currently `FontFamily.Default`)
- [ ] ktlint/detekt + a lint rule failing the build on hardcoded user-facing strings

### Blocked on a Supabase project

- [ ] Create the project in `eu-central-1`
- [ ] Apply `0001`–`0004` (**no migration has been run against a live Postgres
      yet — expect syntax fixes on the first apply**)
- [ ] Run the pgTAP suite against it
- [ ] Seed the first cities/districts and 5–10 launch venues with real curated
      `areas` (see `docs/SEEDING.md`)

**Acceptance** — a debug APK installs on a device and reaches the placeholder
home screen in Arabic RTL; every migration applies from clean with zero manual
steps; the pgTAP suite passes.

**Tests** — `ArabicTextTest` green (22 tests); `001_schema_invariants.sql` green
(25 assertions), including one that fails if *any* public table is added without
RLS.

**Security** — no key in git; service-role key exists only in the Supabase
dashboard; `.gitignore` verified by attempting to add `local.properties`;
cleartext traffic disabled in every build type; backup and device-transfer
excluded for prefs, databases and files.

**Cost** — $0. Supabase Free.

---

## M1 — Authentication and onboarding

### Database, verified against a real Postgres (11 migrations, 44+7 pgTAP assertions, all green)

- [x] `profiles` row created on first sign-in (`0008`: `AFTER INSERT ON auth.users` trigger)
- [x] `v_my_profile`: self-only view exposing `role`/`is_suspended`, which
      0006's column-narrowing had accidentally hidden from a user reading
      their own row (`0010`)
- [x] `anonymize_my_data()` RPC: reports anonymised, P2 hard-deleted (`0010`).
      **Not done: deleting the `auth.users` row itself** — Supabase's own
      guidance is the Admin API (service role), not raw SQL, and that needs an
      Edge Function this environment cannot deploy. See LIMITATIONS below.
- [x] Storage buckets + `storage.objects` policies mirroring `report_images`;
      explicit Realtime publication allowlist (`0007`)
- [x] Optimistic concurrency (`p_expected_updated_at`) on every mutating RPC (`0009`)
- [x] Found and fixed while implementing (see ARCHITECTURE.md §9, decisions
      6–9): a column-revoke that did nothing because a table-level grant
      already covered it; every cross-table ownership policy broken by that
      same revoke; two `CREATE OR REPLACE` overload collisions; one
      `ANY((select ...))` parsed as the wrong SQL form entirely
### Android — compiles and builds (debug + release/R8), NOT device-tested

- [x] `AuthRepository` / `SupabaseAuthRepository`: email sign-up, email sign-in,
      Google ID-token sign-in, sign-out
- [x] `ProfileRepository` / `SupabaseProfileRepository`: `sessionState` combines
      `auth.sessionStatus` with a manual `refresh()` trigger — needed because a
      plain DB write (e.g. setting a display name) doesn't change the auth
      session, so nothing would otherwise tell the UI the row changed
- [x] `SessionState` (Loading/SignedOut/Suspended/SignedIn) as the single gate
      for the whole app — `WassalniApp.kt` renders `SuspendedScreen` with no
      `NavHost` around it at all, not just "no button leads anywhere"
- [x] Display-name capture screen, shown while the profile still has the
      signup trigger's placeholder name
- [x] Google Sign-In implemented via Credential Manager +
      `auth.signInWith(IDToken)`, gated on `BuildConfig.GOOGLE_WEB_CLIENT_ID` —
      hidden rather than shown broken, since no Google Cloud OAuth client
      exists yet (see LIMITATIONS)
- [x] Language switcher (`AppLocale`, Settings screen) — Arabic default,
      English switch, `WassalniTheme`'s layout direction follows the active
      locale rather than being pinned
- [ ] Session persistence / silent refresh — relies on `autoLoadFromStorage` +
      `alwaysAutoRefresh` from M0's Supabase client config; unverified without
      a live project or a device to kill-and-relaunch against
- [ ] Onboarding value-prop screen — `HomePlaceholderScreen` still stands in;
      real onboarding is M4 scope

**Verified this session:** `assembleDebug`, `assembleRelease` (R8 minification
succeeds with the credential-manager keep rule from M0), and `test` (22/22,
unchanged — `core:model` wasn't touched) all green. **Not verified:** nothing
has run on a device or emulator — none exists in this environment and setting
one up (system image download, AVD creation) was out of scope for this pass.
The sign-in flow, the display-name gate, the suspended gate, and the language
switch are all unexercised at runtime.

**Two real API mistakes caught only by compiling, not by review:**
`SessionStatus` lives at `io.github.jan.supabase.auth.status`, not
`io.github.jan.supabase.auth` — a plausible guess that was simply wrong. And
`Postgrest.update()`'s DSL (`set("col", value)` / `filter { eq(...) }`) was
verified against the real docs before writing it, specifically because a wrong
guess there would have been a silent runtime failure rather than a compile
error.

**Decision recorded:** no SMS OTP. Egyptian SMS costs roughly $0.03–0.05 per
message and is trivially abusable; phone verification moves to the backlog as a
*trust signal*, not an auth factor.

**Acceptance** — a new user completes sign-up to the home screen in under 60
seconds with no keyboard entry beyond a display name (Google path). **Not yet
demonstrated** — needs a device/emulator and a live Supabase project.

**Tests** — ViewModel unit tests for each auth state; Compose test for the
onboarding flow; instrumented test that a killed-and-relaunched app stays
signed in. **None of these exist yet** — this pass produced the implementation,
not its test coverage.

**Security** — tokens in `EncryptedSharedPreferences`; no credential logging
(a lint rule fails the build on `Log.*` containing `token`/`password`); pgTAP:
user A cannot `SELECT` user B's `profiles` row outside their community; a
suspended user's `INSERT` on `reports` is denied.

**Cost** — $0. Auth is free to 50k MAU.

---

## M2 — Community tree, scope, and location

- [ ] Hierarchical community picker: governorate → city/district → venue,
      Arabic-searchable at every level, no precise-location permission
- [ ] "My community not listed" → request a new venue (moderator-approved, so
      the tree does not fill with junk under a national launch)
- [ ] Curated `areas` list per venue, Arabic-searchable
- [ ] **Scope control** on the feed: my venue / my district / my governorate /
      all Egypt, defaulting to my venue and persisted
- [ ] Empty-scope affordance backed by `count_reports_in_scope`: "مفيش بلاغات
      هنا — في ١٢ بلاغ في [المحافظة]. وسّع البحث؟" — never a dead end
- [ ] Change-home-community flow
- [ ] Admin seeding script for a new venue and its areas

**Acceptance** — a user in Assiut sees their own campus by default, can widen to
all of Egypt in two taps, and can never file a report against a governorate or
the country node.

**Tests** — repository tests for each scope level; a test that widening from
venue to governorate is a strict superset; UI test for Arabic search at each
tree level; a cycle-detection test on `communities.parent_id`.

**Security** — pgTAP: `reports_insert` is rejected when `community_id` points at
a non-reportable node; the `reports_area_in_community` trigger rejects an
area/venue mismatch; re-parenting a community rewrites the whole subtree's
`ancestor_ids` (a stale array makes scope queries silently wrong, which is worse
than an error).

**Cost** — $0. `ancestor_ids` is a GIN-indexed array; scope is one predicate.

---

## M3 — Create a lost/found report

- [ ] Composer: type, category, images (max 3), colour, brand, area, date,
      approximate time bucket, description
- [ ] **Type-aware coaching.** LOST: "اكتب كل التفاصيل اللي تساعد اللي لقاها."
      FOUND: "لا تكتب التفاصيل المميزة هنا — احتفظ بها للتأكد من صاحبها."
- [ ] FOUND-only: private verification questions + expected answers step
- [ ] Client-side sensitive-number detector (blocks submit, explains why)
- [ ] Image pipeline: downscale, WebP, ≤300 KB, strip EXIF **including GPS**
- [ ] Draft autosave in Room; resume after a kill
- [ ] Pre-submit review screen showing "ده اللي هيشوفه الناس" vs "ده اللي محدش
      هيشوفه"

**Acceptance** — a report is created end-to-end in under 90 seconds; a FOUND
report's private answers are visible nowhere in the public detail screen.

**Tests** — unit tests for the sensitive-number detector (Arabic-Indic digits,
spaced and dashed forms, false-positive cases like prices and years); EXIF-strip
test asserting no GPS tag survives; draft restore test.

**Security** — pgTAP: an `INSERT` with a card-like number in the description
raises `SENSITIVE_NUMBER_IN_PUBLIC_TEXT`; a user cannot insert a report with
another user's `profile_id`; a claimant role gets **zero rows** from
`private_verification_details` for a report they did not create — this is the
single most important test in the suite.

**Cost** — storage begins. 3 images × 300 KB × expected volume; still $0 on
Free during development.

---

## M4 — Feed, search, filters

- [ ] Paged feed, scope-aware, local-first ranking, LOST/FOUND visually distinct
- [ ] `search_reports(p_scope_id, …)` RPC wired to a debounced search field
- [ ] Filters: type, category, area, date range, colour — plus the scope selector
- [ ] `search_scope_widened` analytics event (a high rate means thin liquidity)
- [ ] Empty states that convert ("مفيش نتائج — اعمل بلاغ وهنبلغك لو حد لقاها")
- [ ] Offline cache (Room) with a stale indicator
- [ ] Report detail screen with a privacy-safe share card + deep link

**Acceptance** — searching "محفظه" finds a report titled "محفظة" (normalisation
works); filters compose correctly; results from the user's own venue rank above
equally-relevant ones from elsewhere in the governorate; the feed renders from
cache when offline.

**Tests** — SQL tests for `wassalni_normalize_ar` across tashkeel, alef
variants, taa marbuta, and Arabic-Indic digits; paging tests; a share-card
snapshot test asserting no name and no image appear on it.

**Security** — pgTAP: `share_card_payload` returns only whitelisted fields, and
returns nothing for a hidden or removed report; search never returns
`is_hidden` or `removed` rows; the deep link's public page requires no auth but
exposes only P0.

**Cost** — egress grows with feed browsing. Thumbnails served at ≤50 KB; the
full image loads only on the detail screen.

---

## M5 — Possible matching

- [ ] Wire `generate_match_candidates` trigger + nightly `pg_cron` sweep
- [ ] "بلاغات ممكن تكون مرتبطة" section on the report detail and home screens
- [ ] Reason chips (`نفس المنطقة`, `نفس النوع`, `تاريخ قريب`, `نفس المحافظة`, …)
      — **score never rendered**
- [ ] Dismiss a suggestion (recorded; the pair is never re-suggested)
- [ ] Push + in-app notification on `possible_match`

**Acceptance** — creating a LOST report that matches an existing FOUND report
produces a suggestion within one second, with at least two visible reasons, and
both owners are notified.

**Tests** — a scoring test table: pairs with expected score bands and expected
reason sets; a test that no suggestion is ever created between two reports by
the same user; a test that a dismissed pair does not reappear after the nightly
sweep; **a test that reports in different governorates never produce a candidate,
however similar they are** — this is the guard on suggestion credibility under a
national launch.

**Security** — pgTAP: a user sees `match_candidates` only for reports they own;
a suggestion never leaks a field the viewer could not already see on the
candidate's public detail screen.

**Copy review (blocking)** — every string in this milestone must be hedged. Any
string implying certainty ("تم العثور على مطابقة") fails review.

**Cost** — matching is a bounded SQL loop. Negligible.

---

## M6 — Claim and ownership verification

- [ ] Claim entry from a FOUND report detail
- [ ] Answer the finder's verification questions (`submit_claim` RPC)
- [ ] Finder's grading screen: sees the claimant's answers, marks each
      correct/incorrect, approves or rejects. A similarity hint may be shown
      **to the finder only**
- [ ] Approve → conversation created, report → `matched`, other claims rejected
- [ ] Claim states surfaced clearly on both sides; withdraw and expiry handled

**Acceptance** — a second claimant cannot be approved on a report that already
has an approved claim; the claimant never sees the expected answers, before or
after grading.

**Tests** — **concurrency test**: two sessions call `grade_claim(approve=true)`
on different claims for the same report simultaneously; exactly one succeeds and
the other fails with a unique-violation, leaving consistent state. Plus a state
machine test asserting every invalid report transition raises.

**Security** — pgTAP, run as the claimant role: `SELECT * FROM
private_verification_details` returns 0 rows; the `submit_claim` RPC does not
return expected answers in any field; a user cannot claim their own report; a
non-participant cannot read `claim_answers`.

**Cost** — negligible.

---

## M7 — Messaging

- [ ] Conversation list + thread, Realtime subscription on `messages`
- [ ] Send/receive, read receipts, optimistic send with retry
- [ ] Conversation opens only for an `approved` claim; locks after `returned`
- [ ] Sensitive-number guard on messages, with an Arabic explanation
- [ ] Report/block from inside a thread
- [ ] FCM: device token registration + an Edge Function that sends on new message

**Acceptance** — two devices exchange messages in under two seconds; a third
user with the conversation id cannot read or post to it.

**Tests** — Realtime reconnect-after-network-loss test; message ordering under
concurrent sends; rate-limit test at 30 messages/minute.

**Security** — pgTAP: a non-participant `SELECT` on `messages` returns 0 rows
even with a known `conversation_id`; a participant cannot post to a conversation
whose claim is not `approved`; Realtime is configured RLS-aware and
`private_verification_details` is excluded from the publication.

**Cost** — Realtime connections count toward the plan's concurrent limit. At
5k MAU this is comfortably inside Pro. Push is free.

---

## M8 — Return confirmation

- [ ] "تم التسليم" (finder) and "تم الاستلام" (claimant) actions
- [ ] `confirm_return` RPC; report → `returned` only when both have confirmed
- [ ] Success moment: "الحمد لله... الحاجة رجعت لصاحبها ❤️"
- [ ] Optional success share card (opt-in, no identities)
- [ ] P2 data deleted on return

**Acceptance** — one-sided confirmation leaves the report in `matched` with a
clear "في انتظار تأكيد الطرف التاني" state; two-sided flips it to `returned`
exactly once.

**Tests** — **concurrency test**: both parties call `confirm_return`
simultaneously; the report ends `returned`, `returns_count` increments exactly
once per user, and the success notification is emitted once. Idempotency test:
calling `confirm_return` three times changes nothing after the first.

**Security** — pgTAP: only the two participants can call `confirm_return`;
after return, `private_verification_details` and `claim_answers` for that claim
are gone; the conversation is locked.

**Cost** — $0.

---

## M9 — Safety, moderation, admin

- [ ] Report abuse from a report, a message, or a profile (5 reasons)
- [ ] Auto-hide at 3 distinct reports (already in schema) + user-facing state
- [ ] Rate limits wired into every mutating RPC
- [ ] Moderator console (web, Supabase-hosted or a minimal Next.js page using
      the service role): review queue, hide/unhide, suspend, audit trail
- [ ] Safety guidance screen: meet in a public place, never send money, never
      share ID photos — shown before the first conversation
- [ ] In-app "Blocked users" list
- [ ] Venue-request review queue (a national launch means anyone can propose a
      new community; unmoderated, the tree fills with junk and duplicates)
- [ ] Moderation queue filterable by governorate, so review can be delegated

**Acceptance** — a moderator can hide a report and suspend an account in under
30 seconds; a suspended user can sign in but cannot create, claim, or message.

**Tests** — auto-hide threshold test; rate-limit tests for each action; a test
that every admin action writes an `audit_log` row.

**Security** — pgTAP: a non-staff user cannot update `moderation_reports`,
cannot read `audit_log`, and cannot perform a `staff_only` report transition.
**Full manual security review of the privacy model happens here**, against the
checklist in ARCHITECTURE.md §4 and §8.

**Cost** — the moderator console is static/serverless. $0–5.

---

## M10 — Analytics and release readiness

- [ ] Firebase Analytics with the 14 events from PROJECT.md §6
- [ ] Event-schema test: every event asserted to carry no PII, no free text, no
      image URL, no precise location
- [ ] Crashlytics or Sentry
- [ ] R8/ProGuard rules, app size budget, baseline profile
- [ ] Play Store listing (Arabic-first), Data Safety form, privacy policy,
      account-deletion URL (Play requires it)
- [ ] Internal testing track → closed beta with ~30 users from the flagship venue
- [ ] **Seed one flagship community** with real historical lost/found posts (with
      permission) so its first users see a populated feed. National coverage does
      not remove this need — it makes it sharper, because a nationally-empty feed
      is a much larger empty surface
- [ ] Dashboard for the metrics in PROJECT.md §6, including **live communities**
      and scope-widen rate

**Acceptance** — the full golden path runs on a release build against
production; the Data Safety form matches what the app actually collects, field
for field.

**Tests** — Maestro end-to-end smoke: sign up → pick community → report LOST →
search → see a match → claim → verify → chat → confirm return. Runs on CI
nightly against a staging project.

**Security** — an independent pass over the pgTAP suite; a manual attempt to
read another user's private details using a raw HTTP client and a stolen anon
key (this must fail — the anon key is public, RLS is the boundary); dependency
vulnerability scan.

**Cost** — move to Supabase Pro ($25/mo) before public launch: no idle pausing,
daily backups, log retention. Total run rate at launch: **$25/mo**.

---

## Cross-cutting, every milestone

- [ ] Every user-facing string in `strings.xml`, Arabic default, reviewed for
      Egyptian register
- [ ] Every screen checked in RTL **and** LTR, light and dark, and at 200% font
      scale
- [ ] TalkBack labels on every interactive element
- [ ] No new table without RLS and a pgTAP test in the same PR
- [ ] No new user-facing string implying match certainty
