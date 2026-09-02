# وصلني — Wassalni

Android app that reconnects people with lost belongings.

> ضاع منك شيء؟ يمكن حد لاقيه ومستنيك.

- **What it is and why** — [PROJECT.md](PROJECT.md)
- **How it is built** — [ARCHITECTURE.md](ARCHITECTURE.md)
- **What is next** — [TASKS.md](TASKS.md)

**Status:** M0 (project setup). The app builds to a placeholder home screen.

---

## Getting set up

### 1. Toolchain

You need **JDK 17** and the **Android SDK**. Installing Android Studio gets both
(it bundles a JetBrains Runtime 17 and the SDK manager):

```bash
winget install --id Google.AndroidStudio -e
```

Open this folder in Android Studio and let it sync — that also generates
`gradle/wrapper/gradle-wrapper.jar` and writes `sdk.dir` into
`local.properties`. Nothing else is needed for a debug build.

If you would rather build from the command line, install a JDK 17 and the
command-line SDK tools, then run `gradle wrapper` once to produce the wrapper
jar.

### 2. Supabase

Create a project in the **`eu-central-1` (Frankfurt)** region — it is the
closest to Egypt, at roughly 60–90 ms.

Apply the migrations in order, from the SQL editor or `psql`:

```bash
for f in db/migrations/*.sql; do psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"; done
```

Then run the schema invariants:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/tests/001_schema_invariants.sql
```

Seed the community tree for your launch venues — see [docs/SEEDING.md](docs/SEEDING.md).
Egypt and the 27 governorates ship in `0003`; districts and venues do not.

### 3. Local config

```bash
cp local.properties.template local.properties
```

Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` from **Project Settings → API**.

The anon key is **public by design** — it identifies the project and authorises
nothing. Row Level Security is the security boundary. The **service_role key
must never go in this file, the app, or git**; it bypasses RLS entirely and
belongs only in Edge Function environment variables.

### 4. Build

```bash
./gradlew assembleDebug
```

---

## Layout

```
app/                    navigation host, DI wiring, feature packages
core/model/             pure Kotlin domain types (no Android dependency)
core/data/              repositories, Supabase + Room data sources
core/designsystem/      theme, tokens, shared composables, RTL helpers
db/migrations/          the schema, as executable SQL
db/tests/               pgTAP invariants, run in CI
docs/                   backlog, seeding playbook
```

## Ground rules

These are not style preferences — each one exists because breaking it caused, or
would cause, a specific failure.

1. **No new table without RLS and a pgTAP test in the same PR.** Default deny;
   one table with RLS off is a full data leak.
2. **P1 and P2 data never becomes a column on a publicly-readable table.** RLS is
   row-level: any column on a readable row is readable.
3. **No user-facing string implies match certainty.** "قد يكون", never "تم
   العثور على مطابقة", and never a percentage.
4. **Every user-facing string lives in `strings.xml`,** Arabic default.
5. **Every screen is checked in RTL and LTR, light and dark, at 200% font scale.**
6. **`ArabicText.normalize` and `wassalni_normalize_ar()` must stay identical.**
   If they drift, the client shows matches the server cannot find.
7. **The schema has no column for a phone number, address, or government ID.**
   The safest way to not leak a field is to not have it.
