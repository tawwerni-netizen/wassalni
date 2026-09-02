# Wassalni — Architecture

Plan date: 2026-09-02. Decisions here are binding until amended in this file.

---

## 1. Backend decision

### Recommendation: **Supabase (managed Postgres) + Firebase Cloud Messaging for push**

One database. No microservices. No self-hosting.

| Need | Supabase component |
|---|---|
| Authentication | Supabase Auth (Google Sign-In + email/password) |
| Database | Postgres 15 |
| Image storage | Supabase Storage (S3-compatible, RLS-aware) |
| Realtime updates | Supabase Realtime (`postgres_changes`, RLS-filtered) |
| Messaging | `messages` table + Realtime subscription |
| Search | Postgres `tsvector` + `pg_trgm`, Arabic-normalised |
| Security rules | Row Level Security policies + `SECURITY DEFINER` RPCs |
| Admin operations | `profiles.role` + admin-only RLS policies + audit triggers |
| Scheduled jobs | `pg_cron` |
| Server logic | Postgres functions first; Edge Functions only where HTTP egress is needed (FCM send, share-card render) |
| Push notifications | FCM (free, standalone — no other Firebase service required) |
| Analytics | Firebase Analytics (free, unlimited events) |

### Why this and not Firebase

Firebase is the reflexive Android answer and it loses on the two hardest
requirements in this product.

**1. Search and matching are multi-predicate queries with fuzzy text.**
The matching engine needs, in one query: opposite report type, same community,
status in a set, date within a window, category equal *or* in the same group,
and trigram similarity on a normalised Arabic description. Firestore cannot
express this. You would fan out multiple queries, over-fetch, filter on the
client, and still need Algolia or Typesense for text (~$50/mo minimum, plus a
sync pipeline). In Postgres it is one indexed query costing effectively zero.

**2. Privacy needs row *and* column guarantees that can be tested.**
"Verification answers must never be visible to the claimant" is a hard
requirement. RLS lets us prove it: the policy is declarative, lives next to the
data, applies to every client including a hand-rolled HTTP request, and can be
asserted in pgTAP tests that run in CI. Firestore rules can achieve the same via
document separation, but the rules language cannot join, so multi-party checks
("is this user a participant in the conversation that owns this message?")
require denormalising participant lists into every document and keeping them
consistent — a correctness liability in exactly the area we cannot afford one.

Secondary reasons: transactional guarantees and partial unique indexes solve the
claim race conditions cleanly (§7); audit logging is a trigger, not a service;
`pg_cron` replaces a scheduler.

**Accepted costs of this choice**

- The Kotlin client (`supabase-kt`) is community-maintained, not first-party.
  Mitigation: pin exact versions; keep all data access behind our repository
  interfaces so the SDK is swappable for plain Retrofit against PostgREST.
- No built-in push. Mitigation: FCM directly; roughly one Edge Function.
- Free-tier projects pause after 7 days idle. Mitigation: `pg_cron` heartbeat
  during development; move to Pro before public launch.
- Nearest region to Egypt is `eu-central-1` (Frankfurt), ~60–90 ms RTT. Fine for
  this workload. **Use `eu-central-1`.**

### Cost

| Phase | Monthly |
|---|---|
| Development (Supabase Free + FCM + Firebase Analytics) | **$0** |
| Pilot launch, 1 community, up to 5k users (Supabase Pro) | **$25** |
| Images: max 3 per report, client-compressed to 300 KB WebP, ~4.5 GB at 5k reports | within Pro's 100 GB |
| Egress at 5k MAU browsing compressed thumbnails | within Pro's 250 GB |

Firebase equivalent: roughly $0–10 on Blaze **plus ~$50+ for a search service**.
The search line is what decides it.

---

## 2. Android stack

- Kotlin, JDK 17, minSdk 24, targetSdk 35
- Jetpack Compose + Material 3
- MVVM, Coroutines, `StateFlow`, Repository pattern
- Hilt for DI
- Navigation Compose with type-safe routes (`kotlinx.serialization`)
- Room as offline cache + draft storage (the repository is the single source of truth)
- Coil 3 for images; client-side downscale + WebP compression before upload
- `supabase-kt` (auth, postgrest, storage, realtime), versions pinned
- Firebase: `firebase-messaging` and `firebase-analytics` only
- Testing: JUnit + Turbine + MockK (unit), Compose UI tests + Robolectric,
  pgTAP for RLS, and a Maestro smoke flow for the golden path

### Localisation

**Arabic-first.** `values/` holds Arabic (Egyptian register), `values-en/` holds
English. RTL is the default layout direction and every screen is verified under
LTR too. Dates use Gregorian numerals (Egyptian convention), relative where
possible ("امبارح", "من ٣ أيام").

### Module layout

Deliberately light. Over-modularising an MVP costs build-config time and buys
nothing until there are parallel teams.

```
:app                 // navigation host, DI wiring, feature packages
   feature/auth  feature/onboarding  feature/report  feature/feed
   feature/match feature/claim       feature/chat    feature/moderation
:core:model          // pure Kotlin domain types, no Android deps
:core:data           // repositories, Supabase + Room data sources, mappers
:core:designsystem   // theme, tokens, shared composables, RTL helpers
```

Promotion rule: a feature package graduates to its own Gradle module when it
exceeds roughly 2.5k LOC **or** a second team starts touching it. Not before.

### Configuration and secrets

No secrets in client source. `local.properties` (git-ignored) supplies the
Supabase URL and **anon** key at build time via `buildConfigField`. The anon key
is public by design — RLS is the security boundary, not key secrecy. The
**service role key never appears in the app**, only in Edge Function env vars.
`google-services.json` is git-ignored; a `.template` is committed.

---

## 3. Data model

Full DDL: `db/migrations/0001_init.sql`. Shape and rationale below.

```
profiles ──< reports ──< report_images
    │           │
    │           ├──1 report_private_details         (P1 — participants only)
    │           ├──< private_verification_details   (P2 — finder-only)
    │           ├──< match_candidates >── reports   (self-referencing pair)
    │           └──< claims ──< claim_answers
    │                   │
    │                   └──1 conversations ──< messages
    │
    ├──< moderation_reports
    ├──< notifications
    ├──< device_tokens
    └──< rate_limit_events

communities ──< areas ──< reports
categories (server-driven, grouped)
audit_log
```

### Notes on specific tables

**`profiles`** — mirrors `auth.users`. Holds `display_name`, `community_id`,
`role` (`user` / `moderator` / `admin`), `is_suspended`, trust signals.
Deliberately holds **no phone number, no address, no national ID**.

**`communities`** — a self-referencing tree, not a flat list. Kinds:
`country → governorate → city|district → campus|mall|compound|workplace`.
Each row stores `ancestor_ids uuid[]` (self plus all ancestors, GIN-indexed), so
"everything under this node" is one indexed predicate:
`:scope = any(ancestor_ids)`. A trigger maintains the array and refuses cycles;
re-parenting rewrites the subtree, because a stale `ancestor_ids` would make
scope queries silently wrong rather than fail loudly.

Reports attach only to a `is_reportable` node (a venue or a district) — never to
a governorate or the country. `reports.governorate_id` is denormalised on insert
so matching is a single indexed predicate instead of a tree walk per candidate.

**`areas`** — a coarse landmark inside a venue ("مبنى الهندسة", "الدور الأرضي —
البوابة ٣"). A **curated list per community**, not free text: that is what makes
"same area" a meaningful match signal and what stops users typing their home
address.

**`categories`** — a row, not a Kotlin enum, so categories can be added without a
release. Ships with: phone, wallet, keys, bag, documents, electronics, jewelry,
other. Each has a `group_key` so "phone" and "electronics" can score as a partial
category match.

**`reports`** — the public record. **Every column on this table is P0.** RLS is
row-level, not column-level: anyone who can read the row can read every column
on it. So a P1 field must not live here — hence `report_private_details`.
Carries `normalized_text` (generated column, see §5) and a search vector.

**`report_private_details`** — the P1 location hint. Readable by the report
owner and, once a claim is approved, by the counterparty.

**`private_verification_details`** — question plus expected answer, written by
the finder. RLS: readable **only** by the report owner and admins. Never
returned to a claimant by any code path.

**`claims` / `claim_answers`** — the claimant's submitted answers. Readable by
the claimant and the finder only.

**`report_images`** — `is_public` flag. Public images appear in the feed; private
ones only to the owner and, after approval, the matched party.

---

## 4. Privacy model

Four data tiers. Every column in the schema is assigned exactly one.

| Tier | Contents | Visible to |
|---|---|---|
| **P0 Public** | report type, category, coarse area, date (day granularity), primary colour, public description, public images, status, display name | Any authenticated user, nationwide |
| **P1 Participant** | precise location text, additional images, in-app messages | The two parties of an **approved** claim |
| **P2 Private** | verification questions and expected answers, private identifying details, claim answers | The owning user, plus admins (audited) |
| **P3 System** | moderation notes, abuse reports, audit log, rate-limit events | Moderators and admins only |

### Hard rules

1. **Never stored, anywhere:** national ID numbers, passport numbers, bank card
   numbers, IBANs, document serial numbers. Enforced twice — a client-side
   detector that blocks submission, and a server-side `BEFORE INSERT` trigger
   that rejects free text containing 8 or more consecutive digits or a
   recognisable ID pattern. Both surface the same Arabic explanation, not a
   silent failure.
2. **Phone numbers are never a field.** Contact happens in-app only. A phone
   number typed into a description is caught by rule 1's digit detector.
3. **No exact addresses.** Location is a curated `area_id` plus an optional short
   free-text hint that is P1, not P0.
4. **Share cards are P0-only, always.** Rendered server-side from a whitelist of
   fields; there is no code path that can put a name or an image of a document on
   one.
5. **FOUND reports are coached to under-share.** The composer's helper text and a
   pre-submit review screen push identifying detail into P2.
6. **Verification answers are graded by the finder, never auto-revealed.** The
   system may compute a similarity hint *shown only to the finder*; the finder
   makes the decision. Rationale in §6.
7. **Deletion.** A user can delete their account; reports are anonymised
   (`profile_id` set to null, display name becomes "مستخدم محذوف") rather than
   hard-deleted, so a completed return's history stays coherent. P2 rows are hard
   deleted.

---

## 5. Search

Arabic text needs normalisation before it is searchable. Postgres ships no Arabic
dictionary, so we normalise explicitly and use the `simple` configuration plus
trigram similarity.

`wassalni_normalize_ar(text)` (immutable, used in a generated column):

- strip tashkeel/diacritics (U+064B–U+0652) and tatweel (U+0640)
- fold `أ إ آ ٱ` to `ا`, `ة` to `ه`, `ى` to `ي`, `ؤ` to `و`, `ئ` to `ي`
- fold Arabic-Indic digits `٠-٩` to `0-9`
- lowercase, collapse whitespace, strip punctuation

Indexes: GIN on `to_tsvector('simple', normalized_text)` for ranked search, and a
GIN `gin_trgm_ops` index on `normalized_text` for typo and variant tolerance.

The `search_reports(...)` RPC takes a `p_scope_id` — any node in the community
tree — and matches with `scope = any(communities.ancestor_ids)`. Passing the
user's own community gives a local feed; passing a governorate or the country
root widens it. Ranking puts same-community results first, then text rank
(falling back to trigram similarity when the tsquery returns nothing), then
recency. `REMOVED` and hidden reports are always excluded.

`count_reports_in_scope(scope, type)` backs the "وسّع البحث" affordance: when a
local search is empty, the UI says how many reports exist one level out instead
of showing a dead end.

---

## 6. Matching design

**Rule-based, explainable, and never presented as certainty.**

### Candidate generation (cheap SQL, `LIMIT 200`)

Opposite `report_type`, **same `governorate_id`**, status in {OPEN,
POSSIBLE_MATCH}, different reporter, not previously dismissed, and a date
window: the found date falls within `[lost_date − 2 days, lost_date + 14 days]`
— two days of slack for people who misremember when they lost it. Ordered so
same-venue candidates are considered before the rest of the governorate.

**Search is national; automatic matching is not.** Coverage without a
geographic bound would suggest an Aswan wallet for an Alexandria loss, and a
handful of absurd suggestions destroys the credibility of every real one. The
governorate is where the signal is. Cross-governorate matching for high-value
items is in the backlog behind an explicit user action, not automation.

### Scoring (0–100)

| Signal | Points |
|---|---|
| Same category | 30 |
| Same category group (e.g. phone / electronics) | 15 |
| Same area | 25 |
| Same venue, different area | 12 |
| Same district / city | 6 |
| Same governorate | 3 |
| Date within 1 day | 20 |
| Date within 3 days | 15 |
| Date within 7 days | 10 |
| Date within 14 days | 5 |
| Same primary colour | 10 |
| Adjacent colour (curated adjacency table) | 5 |
| Description trigram similarity >= 0.45 | 15 |
| Description trigram similarity >= 0.30 | 8 |
| Brand exact match | 10 |

Capped at 100. **Threshold 45** to create a `match_candidate`. At most 5 shown,
ordered by score.

### Presentation

The score is **never shown**. The UI shows the reasons that fired, as chips:

> **وجدنا بلاغًا قد يكون مرتبطًا بما تبحث عنه.**
> `نفس المنطقة` · `نفس النوع` · `تاريخ قريب`

Copy is always hedged ("قد يكون"), never "matched" and never a percentage. A user
can dismiss a candidate; dismissal is recorded and the pair is never re-suggested.

### Execution

`AFTER INSERT ON reports` calls `generate_match_candidates(report_id)`, bounded
and synchronous (single-digit milliseconds at MVP scale). A nightly `pg_cron` job
re-runs the last 14 days of open reports to catch candidates created by later
reports and by widened date windows.

### Deferred to backlog

Image embeddings and `pgvector` similarity, weights learned from accept/dismiss
signals, cross-community matching for high-value items.

---

## 7. State machines and race conditions

### Report status

```
OPEN ──► POSSIBLE_MATCH ──► CLAIM_IN_PROGRESS ──► MATCHED ──► RETURNED ──► CLOSED
  ▲            │                    │                                        ▲
  └────────────┴────────────────────┘  (candidate dismissed /                │
                                        all claims rejected)                 │
  OPEN ─────────────────────────────────────────────────────────────────────►┘
        (reporter cancels)

  any state ──────────────────────────────────────────────────► REMOVED (admin)
```

Valid transitions live in a `report_status_transitions` table and are enforced by
a `BEFORE UPDATE` trigger. An invalid transition raises; it does not silently
no-op. Every transition writes to `audit_log`.

The transition table alone is not sufficient, because a report owner legitimately
holds `UPDATE` on their own row and could otherwise simply assert a status. Two
states must be **earned**, checked by the same trigger:

- `matched` requires an existing `approved` claim on the report
- `returned` requires that claim to have **both** confirmation timestamps

Claims go further: clients have **no** `UPDATE` privilege on `claims` at all.
An RLS `WITH CHECK` cannot see the old row, so a permissive update policy would
let a claimant set their own claim to `approved` directly through PostgREST.
Every claim state change goes through a `SECURITY DEFINER` RPC —
`submit_claim`, `grade_claim`, `withdraw_claim`, `confirm_return` — each of
which re-checks who is calling.

### Claim status

`PENDING → VERIFYING → APPROVED | REJECTED`, plus `→ WITHDRAWN` (claimant) and
`→ EXPIRED` (pg_cron, after 7 days idle).

### The three race conditions that matter

**1. Two claimants approved on the same report.**
Guarded by a partial unique index:
`CREATE UNIQUE INDEX ... ON claims (report_id) WHERE status = 'approved'`. The
second approval fails at the database, not in application logic. The approve RPC
also takes `SELECT ... FOR UPDATE` on the report row, so the report status change
and the claim approval are one atomic unit.

**2. Both parties confirm the return simultaneously.**
Return confirmation is two nullable timestamps on the claim
(`finder_confirmed_at`, `claimant_confirmed_at`), each set by an idempotent
`UPDATE ... WHERE <column> IS NULL`. An `AFTER UPDATE` trigger flips the report
to `RETURNED` only when both are non-null. Concurrent confirmations converge on
the same final state, and the trigger is guarded so the success event fires once.

**3. A report is matched while a stale client is still editing it.**
Every mutation RPC takes the client's last-seen `updated_at` and rejects on
mismatch (optimistic concurrency), returning the current state so the UI can
reconcile rather than clobber.

---

## 8. Security model

| Control | Implementation |
|---|---|
| Authentication | Supabase Auth; Google Sign-In primary, email + password fallback. **No SMS OTP** — it costs roughly $0.03–0.05 per message in Egypt and is trivially abusable. Phone verification is deferred to a later trust-signal feature. |
| Authorisation | RLS on **every** table. Default deny; policies added explicitly. No table is left with RLS disabled. |
| Ownership checks | `profile_id = auth.uid()` inside policies; never a client-supplied owner id. |
| Participant-only conversations | The policy joins messages to conversations to claims and checks the caller is the finder or the claimant. Enforced in the database, not the client. |
| Private verification data | Separate table; policy grants `SELECT` only to the report owner and admins. No view, RPC, or Realtime channel exposes it to a claimant. |
| Rate limiting | `rate_limit_events` plus a check inside each mutating RPC. Limits: 5 reports/day, 10 claims/day, 3 abuse reports/day, 30 messages/minute. |
| Abuse reporting | `moderation_reports` with reasons: scam, fake, dangerous, inappropriate, privacy. Content auto-hides once 3 distinct users report it. |
| Storage rules | Bucket policies keyed on the owning report; private images require an approved claim. Signed URLs with a short TTL. |
| Secrets | Anon key only in the client (public by design). Service-role key exists only in Edge Function env. No key in git. |
| Audit | `audit_log` trigger on every report and claim status transition and on every admin action, recording actor, before, after, and timestamp. |
| PII minimisation | See §4. The schema has no column for a phone number, address, or government ID — the safest way to not leak a field is to not have it. |
| Transport | HTTPS only, `cleartextTrafficPermitted="false"`. Certificate pinning deferred (documented risk, low value against the actual threat model). |

### Threat model, briefly

The realistic adversary is **not** a network attacker — it is a **social engineer
claiming an item that isn't theirs**, and secondarily a scammer harvesting
contact details. Almost every control above is aimed at those two. That is why
verification is finder-graded, why contact is in-app only, and why FOUND reports
are coached to under-share.

---

## 9. Decisions log

**2026-09-02**

1. **Backend: Supabase + FCM.** Approved. Region `eu-central-1`.
2. **Project path.** Moved to `H:\Claide Apps\wassalni` (ASCII); `git init` done.
   `applicationId = com.wassalni.app`; the app label stays "وصلني".
3. **Scope: all of Egypt, all four community types.** Implemented as a
   hierarchy (`0003_nationwide_scope.sql`), not as the removal of the community
   boundary: national coverage and national search, governorate-bounded
   automatic matching, local-first ranking. Rationale and the accepted liquidity
   risk are in PROJECT.md §2.

**2026-09-03**

4. **Writes move to `SECURITY DEFINER` RPCs; client table access becomes
   read-mostly.** Root cause: an RLS `WITH CHECK` cannot see the old row, so a
   policy can say "you own this row" but never "you may change this column and
   not that one". That gap produced two live holes — a report owner could revert
   their own auto-hide, and anyone could rewrite `governorate_id` to inject into
   another region's match pool. First instalment applied in
   `0005_harden_report_writes.sql` via column privileges plus moderation RPCs;
   the remaining tables follow in M3 before the client data layer exists.
5. **Identifying fields freeze once a report leaves `open`.** Prevents
   bait-and-switch: post something innocuous, collect claims, rewrite it.
   Wording stays editable, because blocking typo fixes just pushes people to
   delete and repost.

**2026-09-03 — found by actually running the migrations against Postgres, not by review**

6. **A column-level `REVOKE SELECT` cannot shrink a table-level `SELECT` the
   role already holds.** `revoke select (profile_id) on reports from
   authenticated;` (0006) did nothing, because every role already held
   table-level SELECT from Supabase's platform default grant, and a
   column-level revoke only cancels a column-level grant — it doesn't touch a
   broader table-level one. The working pattern, already used for `UPDATE` in
   0005: revoke the table-level privilege entirely, then grant back an
   explicit column list (0006, corrected).
7. **RLS policies on OTHER tables that read `reports.profile_id` in a
   subquery need real `SELECT` privilege on it — a table's own bare
   `profile_id = auth.uid()` in its own policy does not.** Postgres treats a
   table's row under its own policy like a trigger's NEW/OLD — free to read.
   A different table's policy reaching into `reports` via
   `exists (select 1 from reports r where ...)` is an ordinary query and is
   fully subject to column grants. Revoking `profile_id` therefore broke
   every cross-table ownership check in the schema (images, P1/P2 details,
   claims, match candidates, conversations, messages) until each was rewritten
   against a `SECURITY DEFINER` helper, `current_owns_report(uuid)` —
   the same pattern `current_is_staff()`/`current_community_id()` already
   established for `profiles` (0011).
8. **`CREATE OR REPLACE FUNCTION` cannot change a return type or an argument
   list — either one produces a second overload, not a replacement.**
   `search_reports` changing `setof reports` to `setof v_reports`, and all
   eight `_v2`-style functions in 0009 adding `p_expected_updated_at`, each
   silently created an ambiguous overload until an explicit `drop function
   if exists <old signature>` preceded the replacement.
9. **`x = ANY((select ...))` is a trap.** The extra parens make Postgres parse
   it as the SQL-standard `ANY (subquery)` form — compare against each row a
   subquery returns — not `ANY (array)`. A subquery returning one row holding
   one `uuid[]` tried to evaluate `uuid = uuid[]` and failed
   (`reports_set_governorate`, 0003/0005). Select the array into a variable
   first; there is no syntax that makes the array form of `ANY` unambiguous
   inline here.
10. **Optimistic concurrency (0009) raises a distinct `STALE_STATE`
    exception on a mismatch rather than returning the current row.**
    ARCHITECTURE originally implied returning current state inline; a raised
    exception aborts the transaction, so doing that would mean every mutating
    RPC's return type becomes a jsonb envelope instead of a scalar. No client
    exists yet to consume that contract (repositories land in M3/M6), so this
    was deliberately scoped down: the client catches `STALE_STATE` and
    refetches. Revisit if a screen ever needs the row back in the same round
    trip.

All of 6–9 were caught by applying every migration to a real (local, vanilla)
Postgres and running the pgTAP suites against it — none were visible from
reading the SQL. See `db/tests/fixtures/000_local_only_bootstrap.sql` (a
from-scratch replica of Supabase's platform-default grants, without which
`revoke ... from authenticated` tests pass trivially because there was nothing
to revoke) and `db/tests/002_rls_behaviour.sql` (role-switched behavioural
tests, as opposed to 001's schema-structure-only assertions).

### Still open

- Which flagship community gets back-filled and seeded before launch. Coverage
  is national from day one, so this no longer blocks M0–M2 — but it does decide
  whether week 1 has a live community, and it blocks the M10 seeding task.
- Who staffs the moderation queue in week 1, and within what SLA. A national
  launch widens the abuse surface, so this now matters more than it did.
