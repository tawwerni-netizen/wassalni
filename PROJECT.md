# وصلني — Wassalni

> ضاع منك شيء؟ يمكن حد لاقيه ومستنيك.

Android app that reconnects people with lost belongings by turning scattered
lost/found chatter (Facebook groups, WhatsApp, security desks, notice boards)
into one structured, local, privacy-safe reporting system.

**Status:** Planning (pre-M0). No code written yet — by design.
**Owner:** universebrands.org@gmail.com
**Plan date:** 2026-09-02

---

## 1. Core loop

```
REPORT LOST  ─┐
              ├─→ SEARCH / FILTER ─→ POSSIBLE MATCH ─→ SAFE CONTACT
REPORT FOUND ─┘                                             │
                                                            ▼
   SHARE CASE ←─ CONFIRM SUCCESS ←─ RETURN ←─ OWNERSHIP VERIFICATION
```

Every arrow in that loop has an analytics event and a state transition. If a
step has no event, it is not shipped.

---

## 2. Market strategy

**Market: all of Egypt, all four community types** — campuses, malls,
compounds, and workplaces. Decided 2026-09-02.

### The constraint this has to survive

The binding constraint is not user count — it is **local liquidity**. A lost
wallet is only findable by someone who was physically in the same place. 500
users in one university are worth more than 50,000 spread thinly nationwide,
and a feed of national noise is worse than an empty local one.

Nationwide coverage does **not** have to mean nationwide matching. We get both
by making scope a **hierarchy** rather than a boundary:

```
مصر (country)
 └─ المحافظة (governorate, 27)
     └─ مدينة / حي (city / district)
         └─ جامعة | مول | كمبوند | مقر عمل   ← reports attach here
             └─ منطقة (curated landmarks)
```

- **Coverage is national.** Anyone anywhere in Egypt can sign up, create a
  community for their campus or compound, and post.
- **Search is national.** The feed defaults to your own community and you can
  widen one level at a time up to the whole country. When a scope is empty, the
  UI says how many reports sit one level out and offers to widen — never a dead
  end.
- **Automatic matching is bounded to the governorate.** A wallet lost in Aswan
  has nothing to do with one found in Alexandria; suggesting it would burn the
  credibility of every real suggestion. Proximity is *scored*, not merely
  required: same area > same venue > same district > same governorate.

This keeps "نفس المنطقة" a meaningful reason chip, which is the thing that makes
match suggestions believable.

### Where effort goes, even though coverage is national

Coverage is cheap; liquidity is not. Marketing and seeding still concentrate on
dense communities one at a time, in this order:

| Rank | Target type | Why | Seeding lever |
|---|---|---|---|
| 1 | Large university campus | Highest density and loss rate (phones, wallets, IDs, keys), Android-first users, existing "lost & found" Facebook groups to migrate | Student unions, faculty groups, campus security |
| 2 | Large mall | High foot traffic, existing lost-and-found desk to partner with | Mall admin desk, food court flyers |
| 3 | Residential compound | Repeat neighbours, high trust, keys and kids' items | Compound WhatsApp admins |
| 4 | Large workplace / industrial campus | Closed population, single HR channel | HR / facilities |

**Health rule:** a community is *live* once it exceeds 20 reports/week. Track
live communities as a first-class metric — national registration numbers are
vanity if no single community is live.

**Risk to watch (accepted, not resolved):** national launch spreads the same
effort across more surface, so the first live community arrives later than it
would with a single-campus launch. The mitigation is the seeding order above
plus back-filling one flagship campus before launch (§7). If no community is
live 6 weeks after launch, concentrate all effort on one and stop the rest.

---

## 3. Users

**Lost Reporter** — 18+. Lost something valuable or important. Anxious, in a
hurry, will abandon a form longer than ~60 seconds. Motivated to give *lots* of
detail.

**Found Reporter** — 18+. Found something and wants to return it. Altruistic
but low-patience: zero personal upside, so friction kills them. Must be
protected from scam claimants and from being asked to reveal identifying detail.

**Institution Partner (future, NOT MVP)** — university, mall, company. Keep the
`community` entity generic enough that an institution can later own one.

---

## 4. The asymmetry that drives the whole design

LOST and FOUND reports are **not mirror images**. This is the single most
important product insight in Wassalni and it shapes the schema, the UI copy,
and the verification flow.

| | LOST report | FOUND report |
|---|---|---|
| More public detail is… | **Good** — helps a finder recognise the item | **Dangerous** — lets an impostor describe an item they never saw |
| Public description should be | Rich and specific | Deliberately generic ("محفظة جلد بني") |
| Identifying details | Public where safe (never IDs/card/serial numbers) | **Private** — they become the verification questions |
| Who verifies whom | The finder verifies the claimant | — |

The report composer therefore has **two different coaching modes**. A FOUND
composer actively warns the user: "لا تكتب التفاصيل المميزة هنا — احتفظ بها
للتأكد من صاحبها."

---

## 5. MVP scope

### In

- Email/Google auth, minimum data collected
- Onboarding: pick community → 🔴 فقدت شيئًا / 🟢 وجدت شيئًا
- Create report (type, category, images, colour, brand, area, date, approximate
  time, description, private identifying details)
- Configurable categories (server-driven list, not a client enum)
- Feed + search + filters (type, category, area, date, colour)
- Rule-based, **explainable** possible-match suggestions
- Claim flow with finder-graded ownership verification
- In-app messaging, opened only after a claim is approved
- Two-sided return confirmation → RETURNED + success moment
- Abuse reporting + admin moderation
- Privacy-safe share cards

### Out (explicitly not built)

Computer-vision matching · AI certainty scores presented as fact · payments ·
paid recovery guarantees · live location tracking · public exact addresses ·
phone-number directory · complex maps · video calls · social feed · public
comments · nationwide institution management · iOS · gamification.

Anything here that a stakeholder asks for goes to `docs/BACKLOG.md`, not into a
milestone.

---

## 6. Metrics

**North star:** *Items returned per active community per week.*

| Metric | Definition | MVP target |
|---|---|---|
| Report→Match rate | reports with ≥1 candidate above threshold / reports | ≥ 35% |
| Match→Return rate | reports reaching RETURNED / reports reaching MATCHED | ≥ 25% |
| Median time to resolution | report_created → RETURNED | ≤ 72h |
| D7 retention | users active on day 7 | ≥ 15% |
| Reports per active area | reports / community / week | ≥ 20 |
| **Live communities** | communities above 20 reports/week | ≥ 1 at week 6, ≥ 3 at week 12 |
| Search success rate | searches followed by a report_viewed within 60s | ≥ 40% |
| Scope-widen rate | searches that widen scope because the local one was empty | watch — a high value means liquidity is thin |

**Guardrail metrics** (a launch is a failure if these move the wrong way):
false-claim rate, abuse reports per 100 reports, median finder time-to-first-response.

### Tracked events

`onboarding_completed` · `report_started` · `report_created` ·
`search_performed` · `search_scope_widened` · `report_viewed` ·
`possible_match_detected` ·
`claim_started` · `claim_submitted` · `claim_verified` ·
`conversation_started` · `return_marked` · `receipt_confirmed` ·
`report_resolved` · `share_clicked`

No event may carry PII, free-text descriptions, image URLs, or precise
location. Allowed params: ids (opaque), category, report type, community id,
counts, durations, enum reasons.

---

## 7. Growth

**Primary loop — the share card.** Every LOST report generates a privacy-safe
image + deep link:

```
🔴 فقدت مفاتيح في [المنطقة]
ساعدني أرجعها.
```

Contains only: type, category, coarse area, date, app branding. Never a name,
phone, image of documents, or exact place. The link opens a public read-only
report page with two CTAs: "أنا لقيتها" and "حمّل التطبيق".

**Secondary loop — the success card.**

```
❤️ الحاجة رجعت لصاحبها.
```

Generated after RETURNED, opt-in, no identities, no item photo unless both
parties opt in.

**Seeding, not virality, wins week 1.** Before launch, back-fill the pilot
community with real historical lost/found posts (with permission) from its
existing Facebook group so the first user sees a populated feed, not a void.

---

## 8. Definition of MVP done

A real user can, on a real device, against production infrastructure:

1. Install the app
2. Create an account
3. Select a local community
4. Report something LOST or FOUND
5. Search relevant reports
6. Receive possible-match suggestions with visible reasons
7. Start a safe claim flow
8. Verify ownership without exposing unnecessary private information
9. Communicate safely in-app
10. Confirm a successful return (two-sided)
11. Report abuse

…and a security review confirms that no unauthenticated or non-participant
actor can read private verification details, messages, or contact information.

---

## 9. Documents

- `ARCHITECTURE.md` — backend choice, data model, privacy/security model, matching design, state machines
- `TASKS.md` — milestones M0–M10 with acceptance criteria, tests, security checks, cost impact
- `db/migrations/` — the schema, as executable SQL
- `docs/BACKLOG.md` — everything deliberately deferred
