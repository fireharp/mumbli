# Mumbli usage proof

Cryptographically verifiable, privacy-preserving proof that Mumbli dictations happened — without publishing transcript text or user identity.

## What it proves

With [pinned trusted keys](trusted-keys.json), a published `public-proof.json` shows:

- Total signed dictation events in an epoch
- Distinct anonymous installs (epoch-scoped nullifiers)
- A Merkle root committing to the exact receipt set
- An attestor signature over the aggregate statement

## What it does not prove

- Transcript content or audio quality
- That every dictation was included before publish (honest publisher assumption)
- Sybil resistance beyond issuer enrollment policy
- Dictations before proof signing was enabled

## Enable in Mumbli

1. Open **Settings → Usage Proof**
2. Turn on **Sign dictation usage receipts**
3. Run enrollment once (issues an install credential):

```bash
cd mac-app
./scripts/proof/enroll-install.sh
```

4. Dictate normally — receipts append to:

```
~/Library/Application Support/Mumbli/proof/receipts.jsonl
```

## Publish (maintainer)

```bash
cd mac-app
./scripts/proof/publish-proof.sh
```

This aggregates receipts, verifies locally, and writes epoch artifacts under `docs/proof/`.

## Verify (anyone)

Requires [proof-of-use](https://github.com/proof-of-use/proof-of-use) `pou` CLI:

```bash
git clone https://github.com/fireharp/mumbli.git
cd mumbli/mac-app

# Build pou from proof-of-use repo, or use a release binary
pou verify-public docs/proof/2026-07/public-proof.json \
  --trusted-keys docs/proof/trusted-keys.json
```

Optional full audit (includes individual redacted receipts):

```bash
pou verify-audit \
  docs/proof/2026-07/public-proof.json \
  docs/proof/2026-07/audit-pack.json \
  --trusted-keys docs/proof/trusted-keys.json
```

On success, `pou` prints the public statement (counts + Merkle root).

## Trust model

| Role | Key in trusted-keys.json |
|------|--------------------------|
| Issuer | Signs install credentials (one per device per epoch) |
| Attestor | Signs the published aggregate statement |

Private keys stay offline. Only public keys are pinned in this repo.

## Removing the module

Delete `MumbliApp/ProofOfUse/`, remove the single hook in `AppDelegate.swift`, and drop the two UI insertions in `SettingsView` / `MenuBarController`.
