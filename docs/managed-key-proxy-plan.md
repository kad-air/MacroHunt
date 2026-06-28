# Managed-Key Proxy — Plan & Justification

Status: **proposed / not built.** This documents the intended design for the paid
("we handle the AI") tier so the decision and its constraints are recorded in the repo
before any code is written.

## Why this document exists

MacroHunt's positioning is **local-first, privacy-first, Apple-ecosystem-native**:

- no accounts, no server-side storage of user data;
- the user's food, photos, weight, and notes live **on device + in Apple Health** (and,
  optionally, in the user's own Craft space) — never on our infrastructure;
- two ways to power the AI:
  - **BYOK (free):** the user supplies their own Anthropic key (stored in the Keychain via
    `CredentialsManager`/`KeychainHelper`); the device calls `api.anthropic.com` directly.
    This path is **fully serverless** and already implemented.
  - **Managed (paid):** the user pays through the App Store and we cover the Anthropic API
    cost. This path is **not yet built** and is what this document is about.

The managed tier is the only part of the product that cannot be fully serverless, and it is
easy to get wrong in a way that either (a) leaks a billable secret or (b) breaks the privacy
story. This plan fixes the design so a future implementer doesn't have to re-derive it.

## The core constraint: never ship our Anthropic key in the binary

The naive "managed" implementation embeds our Anthropic key in the app (or fetches it to the
device) and calls Anthropic directly — exactly like the BYOK path but with our key.

**This is a hard no.** An Anthropic key shipped in an iOS binary is extractable in minutes
(strings on the decrypted IPA, a proxy like mitmproxy/Charles on the network, or a jailbroken
device). A leaked key is an **uncapped, unauthenticated billing liability** — anyone who pulls
it can run arbitrary Anthropic traffic on our account until we notice and rotate. No amount of
obfuscation changes the economics; the key reaches the device, so it can be taken from the
device.

Therefore the managed tier requires a **server-side component**: the key must live somewhere
the user's device never sees. That is the entire reason the otherwise-serverless app grows one
small backend.

## Proposed design: a stateless, no-log relay

A thin HTTPS relay that does exactly three things and stores **nothing**:

1. **Authenticate the caller as a paying user** — validate an App Store transaction
   (StoreKit 2 signed `JWSTransaction` / `AppTransaction`, or a server-to-server
   `App Store Server API` lookup) so only entitled installs can spend our budget.
2. **Inject our Anthropic key** and forward the request body to `api.anthropic.com`
   (`/v1/messages`), streaming the response straight back to the device.
3. **Enforce abuse limits** — per-install rate/spend caps so a compromised receipt or a
   runaway client can't drain the account.

What it explicitly does **not** do, to preserve the privacy posture:

- **No persistence of request/response bodies.** Meal photos, descriptions, nutrition
  results, and reflections pass through RAM and are never written to disk or a database. The
  relay is a pass-through, not a store.
- **No user accounts.** Identity is "a valid App Store transaction for this product," not an
  email/password. We never learn who the user is.
- **No analytics on content.** At most, aggregate counters (requests, tokens, errors) keyed
  by an opaque install/transaction id for billing-protection — never food data.

Net effect: the privacy claim shifts from *"no server at all"* to *"no server **stores your
data**; the managed relay forwards your request and forgets it."* That is still a true,
defensible claim, and it should be stated that precisely in the App Store privacy disclosure
and any marketing copy. The BYOK tier remains genuinely serverless and is the stronger
privacy story for users who want it — keep both.

## App Store / IAP constraints (decide before building)

- **Recurring charges must go through StoreKit In-App Purchase.** We cannot take a monthly
  fee out-of-band for in-app functionality. The managed tier's subscription is a StoreKit
  product; the relay trusts StoreKit's signed transaction as the entitlement.
- **BYOK must not look like IAP circumvention.** Present BYOK as an *advanced, optional* path
  and make sure the app does something useful before any key is entered, so review doesn't
  read "core functionality requires an external paid service the user configures" as a broken
  first run or a dodge around IAP. Expect a possible rejection here and budget for a
  clarifying appeal — it's common, not fatal.
- **Receipt validation belongs server-side.** The relay should verify entitlement against the
  App Store Server API (or validate the signed JWS itself), not trust a client-asserted
  "I'm premium" flag.

## Cost model — the number that sets the price floor

The managed tier is only viable if the subscription price clears our **worst-case** Anthropic
cost per retained user. The app's call pattern makes this non-trivial:

- every logged meal triggers **`analyzeMealPhotos`** (Sonnet, image input — image tokens
  dominate), **and**
- the daily reflection **regenerates after every logged meal** (`generateReflection`, Sonnet).

So a heavy user logging 4–6 meals/day incurs `meals × (analyze + reflection)` Sonnet calls
**per day**. Before committing to a price:

1. Measure real token usage for a representative analyze call (with 1–2 photos) and a
   reflection call.
2. Multiply by a heavy-user daily meal count and by 30 for a monthly worst case.
3. Set the subscription price above that, or add mitigations: cache/skip redundant
   reflections (e.g. debounce to at most one regeneration per N minutes), cap photos per
   analyze, or rate-limit at the relay. The reflection-after-every-meal behavior is the
   biggest single cost lever — revisit it for the managed tier specifically.

(See `Services/ClaudeAPI.swift` for the two entry points and `Today`'s `ReflectionViewModel`
for the regeneration trigger.)

## Build order when we do this

1. Decide **managed-vs-BYOK-only.** If the per-meal cost or the ops burden of running a relay
   isn't worth it, ship **BYOK-only** (free, or a one-time unlock) and skip the backend
   entirely. This is a legitimate end state and keeps the app 100% serverless.
2. If building managed: stand up the **stateless relay** (auth → inject key → forward → no
   logs), behind our own infra, with per-install spend caps and alerting on our Anthropic
   spend.
3. Add a **StoreKit subscription product** and entitlement check; gate the managed path on it.
4. Add a client setting to choose **BYOK vs managed**, defaulting to whichever the user has
   set up; `CredentialsManager` already models per-source configuration and is the natural
   home for the flag.
5. Wire `ClaudeAPI` to target either `api.anthropic.com` (BYOK, key from Keychain) or the
   relay base URL (managed, no key on device) based on that flag — the request/response shape
   is otherwise identical.

## One-line summary

BYOK stays serverless and is the privacy flagship; the paid "managed" tier needs **one small
stateless, no-log relay** whose only jobs are validating the App Store purchase and injecting
our Anthropic key server-side — because shipping that key to the device is an unacceptable
billing liability, and a pass-through relay is what lets us offer managed AI without storing a
single byte of the user's food data.
