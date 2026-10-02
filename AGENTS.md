# Changing a kindorg-hq repository

Shared conventions for every repo on the golden path (v3). Terms (Stage,
Artifact, Release, Releasable change, Delivery, Production, Work item, Fix
forward, Break-glass): [CONTEXT.md](CONTEXT.md). How the pipeline works:
[README.md](README.md).

## A change, end to end

1. **Work item.** Find the issue the change belongs to (`gh issue list`), or
   open one (`gh issue create`) with what is wrong and what done looks like.
2. **Branch** off the default branch; one Work item per branch, a few days at
   most.
3. **PR title** becomes the commit after the squash merge, and the Release
   notes are built from it: `type(#N): summary` — `feat` (new behaviour),
   `fix` (repair), `perf`, `chore`, `ci`, `docs`, `refactor`, `test`. Breaking:
   `!` after the scope, `feat(#7)!: …`, with a `BREAKING CHANGE:` line in the
   body.
4. **Green before merge.** Every Build and Accept check of the PR passes,
   the service's tests included (the Dockerfile's `test` stage). Fix the
   cause; widening a threshold or skipping a scan is the human's decision,
   raised in the PR.
5. **Squash-merge** your own PR once it is green.

## A merge to the default branch ships

There is no release PR and no later approval: **merge only what may run in
Production.** What ships:

- A **Releasable change** — `feat`, `fix`, `perf` or breaking — becomes a
  Release on merge and is delivered. Anything else (`chore`, `docs`, `ci`,
  `test`, `refactor`) ships with the next Release.
- Runtime dependency bumps are `fix(deps)`, so they ship; Actions and
  base-image bumps are `chore(deps)`. Dependabot's `commit-message.prefix`
  says which.

## Reading a PR's state

Where a merged PR is, from its page or `gh`:

- no `released` label — merged, not in a Release yet (only a Releasable
  change cuts one; the rest ship with the next);
- `released` label — in a Release; the comment names it:
  - "vX.Y.Z recorded" — in homelab-k8s, not yet running;
  - "running" / "degraded" — ArgoCD's word, on the release commit's PR.
    The pipeline's work ends at recorded; recorded → running is ArgoCD
    Notifications in homelab-k8s (the `kindorg-argocd` App), configured in
    `bootstrap/argocd/notifications.yaml` there, from the `kindorg.dev/*`
    annotations the GitOps PR writes on `apps/<app>.yaml`. A comment stuck at
    recorded is a cluster question: `kubectl -n argocd logs
    deploy/argocd-notifications-controller` (homelab-k8s README,
    Notifications).
- The source of truth is the release commit's `production` deployment:
  `in_progress` = recorded, `success` = running, `failure` = degraded.

  ```sh
  gh api "repos/OWNER/REPO/deployments?environment=production&ref=SHA" --jq '.[0].id'
  gh api "repos/OWNER/REPO/deployments/ID/statuses" --jq '.[0].state'
  ```

## When a delivery goes wrong

- **Re-deliver the latest Release** (a delivery died on the way):
  `gh workflow run pipeline.yml` in the service repo. It promotes the existing
  Artifact again and never rebuilds; it cannot deliver an older version.
- **Fix forward.** A bad Release is fixed by the next one: a `fix(#N)` PR,
  merged when green.
- **Break-glass** (a manual revert in homelab-k8s) is the human's call, never
  an agent's.

## Changing this repo (kindorg-hq/ci)

Services follow the major tag `@v3`, so a change here reaches all of them at
the next release of this repo. Each PR runs `self-test.yml`: the Checks and
`golden-path.yml` against `fixtures/hello` with the PR's own actions, the
artifact path with a dry-run Release and promotion, the report dry run, the
no-downgrade cases, the Application annotation cases, and actionlint. Show
new behaviour there as a dry run when it would otherwise write somewhere. A change to an input or output of a
reusable workflow or action is breaking (`!`).

This repo is the exception to "a merge ships": merging to main only updates
its release PR. **The human merges that PR**; never merge it or move a tag
yourself.
