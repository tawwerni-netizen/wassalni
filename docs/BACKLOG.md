# Wassalni — Backlog

Everything deliberately deferred. Nothing here enters a milestone without an
explicit decision recorded in `ARCHITECTURE.md`.

## Deferred, likely valuable

| Item | Why deferred | Revisit when |
|---|---|---|
| Image-similarity matching (`pgvector` + a small embedding model) | Adds cost and a model-serving dependency; rule-based matching is unproven at scale first | Report→Match rate plateaus below target with the rule engine tuned |
| Learned matching weights from accept/dismiss signals | Needs volume; a handful of dismissals would overfit | ~2,000 candidate decisions collected |
| Phone verification as a **trust signal** (never as an auth factor) | Egyptian SMS is ~$0.03–0.05/message and abusable | Scam reports exceed the guardrail threshold |
| Institution/B2B partner console (university, mall) | Not MVP; the `communities` entity is already generic enough to support it | A pilot institution asks to own their community |
| Cross-governorate matching for high-value items, behind an explicit user action | Automatic cross-governorate suggestions are almost pure noise and would burn the credibility of real ones. A deliberate "ابحث في كل مصر" on a specific report is different — it is the user accepting the noise | A user asks for it, or travel-related losses show up in support |
| Web app / public search page beyond share cards | Android-first is the correct constraint for Egypt | Post-MVP |
| iOS | Explicitly out of scope | Post-MVP |
| Certificate pinning | Low value against this threat model (the adversary is a social engineer, not a network attacker); adds a rotation failure mode | If a real MITM risk surfaces |
| Reward/finder-thanks mechanic | Introduces money and therefore fraud | Never, without a fraud plan |

## Rejected for MVP (from the original brief)

Advanced computer vision · AI certainty scores presented as fact · payments ·
paid recovery guarantees · live location tracking · public exact addresses ·
phone-number directory · complex maps · video calling · social network features ·
public comments · nationwide institutional management · complex gamification.

## Open questions

- **Which flagship venue gets seeded before launch?** Coverage is national, so
  this no longer blocks M0–M2, but it decides whether week 1 has a live
  community. See `docs/SEEDING.md`.
- Do we back-fill that venue's existing Facebook lost-and-found posts before
  launch? Strongly recommended — an empty feed kills week 1, and a nationally
  empty feed is a larger empty surface than a single-campus one. Requires
  permission from the group admins and the original posters.
- **Moderator staffing.** Who reviews the abuse queue and the venue-request
  queue in week 1, and within what SLA? A national launch widens both surfaces,
  and an unmoderated venue-request queue fills the community tree with
  duplicates that split liquidity.
