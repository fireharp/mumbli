# Mumbli usage proof

Cryptographically verifiable, privacy-preserving proof that Mumbli dictations happened — without publishing transcript text or user identity.

## What it proves

With [pinned trusted keys](trusted-keys.json), a published `public-proof.json` shows:

- Total signed dictation events in an epoch
- Distinct anonymous installs (epoch-scoped nullifiers)
- A Merkle root committing to the exact receipt set
- An attestor signature over the aggregate statement
- (When using grant-backed credentials) receipts bound to an embedded project grant and app identity

## What it does not prove

- Transcript content or audio quality
- That every dictation was included before publish (honest publisher assumption)
- Sybil resistance beyond issuer grant policy
- Dictations before proof signing was enabled

## Enable in Mumbli

1. Open **Settings → Usage Proof**
2. Turn on **Sign dictation usage receipts**
3. Dictate normally — the app auto-enrolls from the embedded `project-grant.json` on first signed receipt

Receipts append to:

```
~/Library/Application Support/Mumbli/proof/receipts.jsonl
```

### Dev fallback (legacy manual credential)

For unsigned local builds without a valid embedded grant:

```bash
cd mac-app
./scripts/proof/enroll-install.sh
```

## Build release grant (maintainer)

Embed a fresh grant before archiving:

```bash
cd mac-app
POU_REPO=$HOME/Prog/Stuff/proof-of-use ./scripts/proof/embed-grant.sh 0.5.0 /path/to/Mumbli.app
```

Async package review (placeholder):

```bash
$POU_REPO/ProofOfUseLocal/scripts/verify-build.sh /path/to/Mumbli.app grant-id grant-file.json
```

## Publish (maintainer)

```bash
cd mac-app
./scripts/proof/publish-proof.sh
```

This verifies receipts against the grant registry, aggregates, verifies locally, and writes epoch artifacts under `docs/proof/`.

## Verify (anyone)

Requires [proof-of-use](https://github.com/proof-of-use/proof-of-use) `pou` CLI:

```bash
POU_REPO=$HOME/Prog/Stuff/proof-of-use
$POU_REPO/ProofOfUseLocal/scripts/verify-local.sh
```

Or manually:

```bash
pou verify-public docs/proof/2026-07/public-proof.json \
  --trusted-keys docs/proof/trusted-keys.json
```

Optional full audit with grant registry:

```bash
pou verify-audit \
  docs/proof/2026-07/public-proof.json \
  docs/proof/2026-07/audit-pack.json \
  --trusted-keys docs/proof/trusted-keys.json \
  --grant-registry $POU_REPO/ProofOfUseLocal/registry/grant-registry.json \
  --grant-policy optimistic
```

## Trust model

| Role | Responsibility |
|------|----------------|
| Issuer | Signs project grants at build; optional per-install credentials (dev) |
| Grant registry | Tracks pending / verified / revoked grants (ProofOfUseLocal) |
| Install | Signs usage events locally from Keychain identity |
| Attestor | Signs published aggregate statement |

Private keys stay offline. Only public keys are pinned in this repo.

## Removing the module

Delete `MumbliApp/ProofOfUse/` and remove references from `AppDelegate.swift`, `SettingsView.swift`, and `MenuBarController.swift`.
