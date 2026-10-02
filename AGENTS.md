# Changing a kindorg-hq repository

Shared conventions for every repo of kindorg-hq that ships through ci (v4). Terms (Stage,
Artifact, Release, Releasable change, Delivery, Production, Work item, Fix
forward, Break-glass): [CONTEXT.md](CONTEXT.md). How the pipeline works:
[README.md](README.md).
Why the pipeline is shaped this way: [PRINCIPLES.md](PRINCIPLES.md) — read it
before changing the pipeline or proposing a shortcut.

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

## Reading a run

A service has three workflows, one per event: `pull-request.yml`,
`ship.yml`, `redeliver.yml`. Their runs read as Stages:

- **Its name** says which event and what: "PR #12: feat(#7): …" (a pull
  request), the merged PR's title under `ship` (a merge), "Re-deliver the
  latest Release".
- **Its graph** is one box per Stage: `ci / Build` → `ci / Accept` (pull
  request), `ci / Build` → `ci / Accept` → `ci / Deliver` (Ship),
  `ci / Deliver` (re-delivery). A failed box's failing step names the check
  or the action.
- **Its summary**, one at the top: Accept's table of checks on a pull
  request; on Ship and re-delivery a heading — "Ship vX.Y.Z", "Ship <sha7>:
  nothing to release", "Re-deliver vX.Y.Z", or "…: failed at <step>" — then
  the Release, commit, digests and GitOps PR, and what each step said,
  collapsed.

```sh
gh run list --workflow ship.yml --limit 5      # name, status, per merge
gh run view RUN_ID                             # Stages and their steps
gh run view RUN_ID --log-failed                # the failing step's log
```

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

- **Re-deliver the latest Release** (a delivery died on the way, the
  summary says "failed at …" after the Release was cut):
  `gh workflow run redeliver.yml` in the service repo. It promotes the
  existing Artifact again and never rebuilds; it cannot deliver an older
  version. A version already recorded changes nothing, and a Release already
  running stays running.
- **Fix forward.** A bad Release is fixed by the next one: a `fix(#N)` PR,
  merged when green.
- **Break-glass** (a manual revert in homelab-k8s) is the human's call, never
  an agent's.

## Changing this repo (kindorg-hq/ci)

Services follow the major tag `@v4`, so a change here reaches all of them at
the next release of this repo. Each PR runs `self-test.yml` with the PR's own
actions on `fixtures/`: `pull-request.yml` (job `ci`), `ship.yml` with a
dry-run Release (job `ship`), `redeliver.yml` as a dry run of this repo's
latest Release (job `redeliver`), the list form of the image actions, the Artifact list,
no-downgrade and Application annotation cases, and actionlint. Show new
behaviour there as a dry run when it would otherwise write somewhere.

- **One job per Stage**, named `Build`, `Accept` or `Deliver`; details are
  its steps, named in words. No matrix, no further nesting: a service's
  check names are `ci / <Stage>`, and its ruleset requires them.
- **Change ship.yml and redeliver.yml together.** Their Deliver jobs are
  kept step for step the same from promote to report (one file each: a
  shared reusable workflow would nest the names a level deeper); self-test
  fails when they drift.
- **Breaking** (`!`): a change to an input of `pull-request.yml`,
  `ship.yml` or `redeliver.yml`, or to a job name (it is a required check
  name). Those three workflows are the public interface; `actions/` are
  internal to them, so changing an action's inputs or outputs is not
  breaking.
- **The images travel as the Artifact list**, `[{"name", "image",
  "digest"}]`, made once by Build (or `find-artifact` on re-delivery) and only
  read afterwards; its shape and the name → address mapping live in
  `actions/artifact/artifact.sh`. Read `image`/`digest` from it, never
  rebuild an address from a name.
- A required check renamed or removed here: switch this repo's ruleset to
  the names the PR's run shows before merging, or the PR cannot merge.

This repo is the exception to "a merge ships": merging to main only updates
its release PR. **The human merges that PR**; never merge it or move a tag
yourself.
