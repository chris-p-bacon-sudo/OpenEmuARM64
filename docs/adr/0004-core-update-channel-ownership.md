# ADR-0004: Own the core auto-update channel

## Status

Accepted

## Context

Every emulator core plugin OpenEmu-Silicon ships embeds a `SUFeedURL` in its `Info.plist`. Sparkle reads that URL from the **installed** plugin bundle, not from `oecores.xml`, so it determines where updates come from for users who already have the core — regardless of where they originally installed it from.

Until this ADR, 24 of the 27 shipped cores still pointed at `https://raw.github.com/OpenEmu/OpenEmu-Update/master/<core>_appcast.xml`. That repo is upstream-owned, has been dormant for years, and could be archived or deleted at any time. Three cores (Dolphin, 4DO, Flycast) had previously been migrated ad-hoc to nickybmon-hosted appcasts.

The practical consequence: when a `cores-vX.Y.Z` release is published, existing installs of those 24 cores never see the update. Their Sparkle client polls a URL that returns the same stale appcast it has for years. Only brand-new installs (which fetch the bootstrap list from `oecores.xml`, already nickybmon-owned) receive the new build. The update channel was effectively write-only for 24 of 27 cores.

This blocked the next coordinated host+cores release: there was no point cutting `cores-vX.Y.Z` if 24 cores' installed bundles couldn't see it.

## Decision

1. Migrate every shipped core's `SUFeedURL` to:

   ```
   https://raw.githubusercontent.com/OpenEmu-Silicon/OpenEmu-Silicon/main/Appcasts/<core>.xml
   ```

   `<core>` is the lowercased core name. The matching file already exists under `Appcasts/` in this repo. nickybmon is the sole source of truth for core updates going forward.

2. Sign new core appcast entries with the host app's existing Sparkle EdDSA keypair (already used for the host appcast and stored in keychain). `Scripts/update_core_appcast.py` was extended with a `--sign-zip` flag that invokes Sparkle's `sign_update`, parses the resulting `sparkle:edSignature` and `length`, and embeds them on the new `<enclosure>`. The keypair lookup mirrors `Scripts/release.sh` — DerivedData first, repo SPM cache as fallback. No new keypair is generated.

3. Add `Scripts/check-core-feed-urls.sh` as a CI guardrail that fails if any tracked `Info.plist` references the upstream host, or if a core's `SUFeedURL` points at an `Appcasts/<core>.xml` that doesn't exist in the working tree. Wire it into `Scripts/verify.sh --core` as a precondition.

4. Existing entries in each `Appcasts/<core>.xml` are left unsigned. They point at already-shipped binaries; retroactive signing is not useful and not in scope. New entries published from the next cores release onward will carry signatures.

## Alternatives considered

- **Custom domain / CDN for appcast hosting.** Rejected for now. nickybmon chose to stay on `raw.githubusercontent.com` for operational simplicity; revisit if GitHub raw rate-limits or availability becomes an issue. Tracked as out-of-band follow-up.
- **Generate a new EdDSA keypair specifically for cores.** Rejected. The host app and cores already share trust (cores are signed plugins loaded by the host); using a single keypair keeps the surface area small and removes a "which key was used" footgun at signature-verification time.
- **Retroactively sign existing appcast entries.** Rejected as out of scope. Those entries describe binaries that were already published unsigned; signing the appcast entry without re-signing the binary doesn't add real protection, and re-signing every shipped core is real release work that belongs in the next coordinated cores release.

## Consequences

**Easier:**

- A `cores-vX.Y.Z` release actually reaches existing users. The update channel is now read/write end-to-end.
- The shipped product no longer has a structural dependency on upstream `OpenEmu/OpenEmu-Update`.
- Future core updates are cryptographically signed; a compromised CDN cannot push a malicious payload to existing installs.
- A regression that re-introduces an upstream URL fails `verify.sh --core` and any CI that runs `check-core-feed-urls.sh`.

**Harder:**

- nickybmon is the sole source of truth for core updates. There is no upstream fallback — though the upstream channel was already non-functional, so this is formalising reality rather than removing a real escape hatch.
- Every new core must add its `Appcasts/<name>.xml` and set `SUFeedURL` correctly in the same commit; the guardrail enforces this but it is one more step.

**Risks accepted:**

- `raw.githubusercontent.com` is GitHub's discretion, not a contractual SLA. If GitHub ever rate-limits or removes raw hosting, every installed core stops seeing updates until the URL pattern changes — and changing the URL requires shipping a core update over the channel that just broke. Mitigation deferred (custom domain follow-up).
- The plist edits are inert until each core is rebuilt with them. Until the next cores release, behaviour for existing users is unchanged.
