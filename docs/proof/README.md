# Mumbli usage proof

Cryptographically verifiable, privacy-preserving evidence that Mumbli dictations happened — without publishing transcript text or user identity.

## The chain

A usage receipt on its own only says "some install signed this." The value comes from the chain that connects it to a specific released binary and a specific source commit:

```
GitHub build provenance    dmg_sha256  →  source commit + workflow
release binding            dmg_sha256  →  cdhash  →  app_identity, grant_id
usage receipt              app_identity + grant_id
epoch proof                Merkle root over the receipt set
```

Each link is independently checkable, and each is signed by a different authority: GitHub/Sigstore signs the provenance, the project issuer signs the release binding and the grant, the install signs its own receipts, and the attestor signs the published aggregate.

### Why a separate release binding

The grant is embedded in the app bundle before the build, so it cannot name the bundle's own `cdhash` — embedding the grant changes that hash. The release binding is signed *after* the release instead, measuring the artifact that actually shipped. That breaks the circularity while still ending up with a receipt bound to a specific build.

## What it proves

With [pinned trusted keys](trusted-keys.json), a published `public-proof.json` shows:

- Total signed dictation events in an epoch
- Distinct anonymous installs (epoch-scoped nullifiers)
- A Merkle root committing to the exact receipt set
- An attestor signature over the aggregate statement

With release bindings supplied, verification additionally shows that each receipt came from an install whose running app matched the exact bundle content of a released DMG, and `gh attestation verify` shows that DMG came from a known commit built by GitHub Actions.

## What it does not prove

Read this part. It bounds every claim above.

- **Completeness.** Receipts are voluntary and Mumbli works offline. A client can simply not write one. Over-reporting is detectable; under-reporting is not. The published count is a verifiable *lower bound* held by an honest publisher, not a measured total.
- **That usage came from the official build.** Mumbli is open source. Anyone can build and use it without a grant, producing real usage and no receipts.
- **That the client told the truth about itself.** `app_identity` is self-reported by client code. Binding it to a released artifact raises the cost of faking it and makes casual forgery detectable, but a determined party controlling their own machine can extract the embedded grant and lie.
- **Transcript content, audio quality, or that a human was speaking.**
- **Dictations from before proof signing was enabled.**

This is cooperative evidence with a verifiable chain — appropriate for "is this open-source function genuinely used," not for adversarial accounting.

## Enable in Mumbli

1. Open **Settings → Usage Proof**
2. Turn on **Sign dictation usage receipts**
3. Dictate normally — the app auto-enrolls from the embedded `project-grant.json` on first signed receipt

Receipts append to:

```
~/Library/Application Support/Mumbli/proof/receipts.jsonl
```

Credentials are epoch-scoped (UTC `YYYY-MM`). When the month rolls over, the app re-enrolls automatically on the next dictation; the grant itself stays valid across epochs.

### Dev fallback (legacy manual credential)

For local builds without a valid embedded grant:

```bash
./scripts/proof/enroll-install.sh
```

## Verify (anyone)

Requires the `pou` CLI from the [proof-of-use](https://github.com/proof-of-use/proof-of-use) repo.

The `docs/proof/<epoch>/…` paths below are created by the first epoch publish (`scripts/proof/publish-proof.sh`); until an epoch has been published, no such directory exists in the repo.

### 1. The published epoch proof

```bash
pou verify-public docs/proof/<epoch>/public-proof.json \
  --trusted-keys docs/proof/trusted-keys.json
```

### 2. The full audit pack, bound to released artifacts

```bash
pou verify-audit \
  docs/proof/<epoch>/public-proof.json \
  docs/proof/<epoch>/audit-pack.json \
  --trusted-keys docs/proof/trusted-keys.json \
  --release-binding docs/proof/releases/v0.6.0/release-binding.json \
  --grant-policy optimistic
```

Pass `--release-binding` once per release. With bindings present, the verifier requires every grant-backed receipt to carry the `app_identity` of the artifact actually shipped for its grant — a receipt claiming a different binary is rejected.

Add `--verify-provenance` to have the verifier run `gh attestation verify` itself rather than just printing the command.

### 3. The released DMG against its build provenance

```bash
gh attestation verify Mumbli-0.6.0.dmg --repo fireharp/mumbli
```

Each release ships two byte-identical DMGs — the versioned `Mumbli-0.6.0.dmg` and a stable-named `Mumbli.dmg` — and both are attestation subjects, so either name verifies. `checksums.txt` on the release lists both digests.

### 4. Cross-check the binding by hand

The binding claims a cdhash for the app inside a DMG with a given SHA-256. Both are re-derivable:

```bash
shasum -a 256 Mumbli-0.6.0.dmg          # must equal artifacts.dmg_sha256
hdiutil attach -nobrowse -readonly Mumbli-0.6.0.dmg
codesign -dv /Volumes/Mumbli/Mumbli.app  # CDHash must equal app.cdhash
hdiutil detach /Volumes/Mumbli
```

## Maintainer flow

```bash
# 1. Before building a release: embed a fresh grant (no cdhash — deliberately)
POU_REPO=$HOME/Prog/Stuff/proof-of-use ./scripts/proof/embed-grant.sh 0.6.0

# 2. Merge the release PR. CI signs, notarizes, attests, and uploads the DMG.

# 3. After the release exists: measure the shipped artifact and sign the binding
./scripts/proof/issue-release-binding.sh v0.6.0

# 4. At the end of an epoch: aggregate, verify, publish
./scripts/proof/publish-proof.sh

# 5. Anchor the epoch proof to a GitHub Release, then attest its digest
./scripts/proof/anchor-proof.sh
gh workflow run attest-proof.yml -f epoch=$(date -u +%Y-%m)
```

### One-time step when switching to Developer ID signing

Until a Developer ID certificate is configured, CI signs ad-hoc: the app has a valid signature and a cdhash, but no team identifier. The grant and allowlist therefore carry `team_id: "PLACEHOLDER"`, which the client treats as "skip the team check."

Once CI signs with a real Developer ID, that check must become real. Reissue both with the actual team ID:

```bash
TEAM_ID=XXXXXXXXXX POU_REPO=$HOME/Prog/Stuff/proof-of-use ./scripts/proof/embed-grant.sh 0.6.0
```

and set the same value in `ProofOfUseLocal/allowlist/mumbli.json`. Receipts from earlier ad-hoc builds were signed with an empty team ID, so they belong to a different `app_identity` — expected, and handled naturally because bindings are per release.

Release signing and the required GitHub secrets are documented in [Release Signing & Provenance](../for-developers/release-signing.mdx).

## Trust model

| Role | Responsibility | Key location |
|------|----------------|--------------|
| Issuer | Signs project grants and release bindings | Maintainer-local, offline, never in CI |
| Attestor | Signs the published aggregate statement | Maintainer-local, offline |
| Install | Signs usage events | Per-device, macOS Keychain, never leaves the device |
| Build platform | Signs build provenance | GitHub Actions + Sigstore |
| Grant registry | Tracks pending / verified / revoked grants | ProofOfUseLocal |

Private keys stay offline; only public keys are pinned in this repo. Revocation is a verify-time policy decision, not cryptography — an Ed25519 signature cannot be un-signed, so a revoked grant is rejected by verifiers consulting the registry rather than disabled on the client.

## Removing the module

Delete `MumbliApp/ProofOfUse/` and remove references from `AppDelegate.swift`, `SettingsView.swift`, and `MenuBarController.swift`.
