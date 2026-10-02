# Changing a kindorg-hq repository

Shared conventions for every repo that uses this golden path. Terms
(Artifact, Release, Delivery, Stage, Work item, Fix forward, Break-glass):
[CONTEXT.md](CONTEXT.md).

## A change, end to end

1. **Work item.** Find the issue the change belongs to (`gh issue list`), or
   open one (`gh issue create`) with what is wrong and what done looks like.
2. **Branch** off the main branch; one Work item per branch, a few days at
   most.
3. **PR title** is the commit message after the squash merge, and
   release-please builds the changelog from it:
   `type(#N): summary` — `feat` (new behaviour), `fix` (repair), `chore`,
   `ci`, `docs`, `refactor`, `test`; add `!` after the scope for a breaking
   change: `feat(#7)!: …`, with a `BREAKING CHANGE:` line in the body.
   `feat` and `fix` make a Release; the rest ride along with the next one.
4. **Green before merge.** Every Build and Accept job of the PR passes. Fix
   the cause; widening a threshold or skipping a scan is a decision for the
   human, raised in the PR.
5. **Squash-merge** your own PR once it is green.

## Releases and the cluster

- A merge to the main branch builds the Artifact; it does not deploy.
- **The human merges release PRs** ("release x.y.z", opened by kindorg-ci).
  That merge is the decision to ship; delivery to the cluster follows from it.
  In this repo it also moves the major tag for every service at once.
- Production problems are fixed forward: a `fix(#N)` PR, then its release.
  Break-glass (a manual revert in homelab-k8s) is the human's call.
- Re-delivering the latest release after a failed delivery:
  `gh workflow run pipeline` in the service repo. It promotes the existing
  Artifact; it never rebuilds.

## Changing this repo (kindorg-hq/ci)

Services follow a major tag (`@v2`, frozen at 2.1.0; v3 is next), so a
change here reaches all of them on the next release. Each PR runs
`self-test.yml`: the PR stages against
`fixtures/hello` using the PR's own actions, the artifact path (build, scan,
promote with an unchanged digest), and actionlint. A change to an input or
output of a reusable workflow is breaking (`!`), and moves services to the
next major. On push to main the release waits for the same self-test to pass
on that commit.
