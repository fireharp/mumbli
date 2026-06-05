---
name: release
description: Guide the Mumbli release workflow — commit with conventional prefixes, create PR, review release-please changelog, merge Release PR, verify DMG on GitHub Release. Use when the user says "release", "ship it", "cut a release", or "/release".
user_invocable: true
---

# Mumbli Release Workflow

You are guiding the user through Mumbli's automated release pipeline. Follow each step in order, checking conditions before proceeding.

## Prerequisites
- `gh` CLI authenticated
- On a feature branch (not `main` directly — main is protected)
- Conventional commit messages (`feat:`, `fix:`, `docs:`, `chore:`, etc.)

## Step 1: Check current state

```bash
git status
git log --oneline -5
gh pr list --repo fireharp/mumbli --state open
```

Report:
- Current branch name
- Whether there are uncommitted changes
- Recent commits and whether they use conventional prefixes
- Any open PRs

## Step 2: Ensure commits use conventional prefixes

Review the commit messages since branching from main:
```bash
git log main..HEAD --oneline
```

If any commit lacks a `feat:`/`fix:`/`docs:`/`chore:`/etc. prefix, warn the user. The PR title (used for squash merge) must have the prefix — that's what release-please reads.

Suggest a PR title based on the commits:
- Multiple features → `feat: <summary of changes>`
- Bug fixes only → `fix: <summary>`
- Mixed → use the most significant type

## Step 3: Create or check PR to main

If no PR exists for the current branch:
```bash
gh pr create --base main --title "<conventional title>" --body "<summary>"
```

If PR already exists, show its status:
```bash
gh pr view --json title,state,mergeable,mergeStateStatus
```

## Step 4: Merge PR to main

Once PR is ready (no conflicts, checks pass):
```bash
gh pr merge <number> --squash
```

The squash merge uses the PR title as the commit message on main — this is what release-please parses.

## Step 5: Wait for release-please

After merge to main, release-please runs and either:
- **Opens a new Release PR** (if none exists)
- **Updates the existing Release PR** (adding new changes to changelog)

Check for it:
```bash
sleep 15
gh pr list --repo fireharp/mumbli --label "autorelease: pending" --state open
```

Then show the changelog:
```bash
gh pr view <release-pr-number> --json body --jq '.body'
```

Present the changelog to the user for review. Ask if they want to:
- **Release now** — merge the Release PR
- **Wait** — accumulate more changes first

## Step 6: Merge Release PR (when user confirms)

```bash
gh pr merge <release-pr-number> --squash
```

This triggers:
1. release-please creates git tag `vX.Y.Z`
2. release-please creates GitHub Release with changelog
3. `build-dmg` job runs on macOS CI → builds archive → creates DMG → uploads to release

## Step 7: Verify release

Wait for CI and check:
```bash
sleep 20
gh release view --repo fireharp/mumbli --json tagName,name,assets --jq '{tag: .tagName, name: .name, assets: [.assets[].name]}'
```

Confirm:
- [ ] Tag exists (e.g., `v0.2.0`)
- [ ] GitHub Release created with changelog
- [ ] `Mumbli-X.Y.Z.dmg` attached as asset

Report the release URL: `https://github.com/fireharp/mumbli/releases/tag/vX.Y.Z`

## Versioning reference

- `feat:` → **minor** bump (0.1.x → 0.2.0)
- `fix:` → **patch** bump (0.1.x → 0.1.y)
- `docs:`, `chore:`, `ci:`, `test:` → no release (hidden in changelog)

## Quick mode

If the user just wants to release what's already on main (Release PR is already open):
- Skip to Step 5, show the changelog, and ask to merge.
