# CI/CD principles

Why the golden path is shaped the way it is. These are the owner's principles,
adapted to kindorg-hq: each one, then **Here:** how it is realised in this org,
or that it deliberately is not (yet). Terms (Stage, Artifact, Release,
Releasable change, Delivery, Production, Work item, Fix forward, Break-glass):
[CONTEXT.md](CONTEXT.md). Mechanics: [README.md](README.md).

They are principles, not rules: use them to judge a change to the pipeline or
a proposed shortcut. A shortcut that breaks one needs the human's decision,
raised in the PR.

## Goals

**Fast feedback** first: the right person gets the right information as early
as possible. **Safe change** second: quality is built in, so a change is safe
for users, systems and the people running them.

Here: a PR gets its Checks in minutes; a merge reports on the PR itself, up to
"running" in Production.

## We do trunk-based development

Main is always releasable. No direct commits to main; short-lived branches; a
PR with a passing build is mandatory; no development, release or hotfix
branches.

Here: one Work item per branch, a few days at most; squash-merge with the PR
title as the commit. A merge to main ships, so merge only what may run in
Production. A peer reviewer is not required (one human plus agents); green
Checks are. A hotfix is just the next Release.

## We own our pipelines

The team builds and maintains its own pipeline, steps and gates; a broken
pipeline is priority one; stability before speed; curated tools, no
proliferation; shared components are powerful but cost upkeep.

Here: this repo is the one shared golden path; a service states what it is,
not how it ships. Tools are a short list (buildx, Trivy, gitleaks, git-cliff,
crane), run as digest-pinned containers; actions are pinned by SHA.

## We measure our pipelines

Pipelines produce timing and failure metrics; a run's outcome is binary,
pass or fail, never "warning"; outputs (versions, evidence, changelogs) are
transparent, immutable and published.

Here: binary, yes: a scan finding fails the Stage; widening a threshold is the
human's call. Published outputs: each run's one summary (version, digests,
GitOps PR, or the step that failed), GitHub Release notes, the `released`
label and recorded/running comment on each PR, the `production` deployment. Timing
and failure-rate metrics beyond what GitHub Actions shows: not yet.

## We improve CI/CD incrementally and continually

Baby steps, skeleton first; pipelines are code, improved iteratively; pipeline
changes may need more governance, because they change how risk is mitigated;
ratchet the quality bar up.

Here: versioned majors (v1, v2, v3 frozen; v4 live: a workflow per event,
runs read as Stages). Every PR here runs `self-test.yml`, and a human merges this repo's
release PR, since its version is a promise to every service.

## We fix forward

Optimise for time to recover, not time between failures. Fixing forward
through the normal pipeline is preferred; rolling back is sometimes necessary.
Canaries and feature flags shrink the blast radius.

Here: no rollback in the pipeline; a bad Release is fixed by the next one, a
`fix(#N)` PR. Break-glass is a manual revert in homelab-k8s, the human's call
only, followed by a written note. Canaries and feature flags: not used.

## We structure our pipelines consistently

Five Stages, Build, Accept, Integrate, Rehearse, Deliver, so everyone speaks
one language. One pipeline per change, merge to Production, so what was built
is what is released. Build and Accept run without dependencies, which makes
them the PR build.

Here: Build → Accept → Deliver, in order, each gating the next; Integrate and
Rehearse stay in the model but have no environments here. One workflow per
event: the pull request runs Build and Accept and publishes nothing, a merge
runs all three, re-delivery runs Deliver only. One job per Stage, named by it
(`ci / Build`, `ci / Accept`, `ci / Deliver`), its work as steps, no matrix;
a run shows only the Stages it runs and one summary, so it reads the same on
a phone.

## We deliver small changes

Small changes limit blast radius and make risk comprehensible. Every change
traces to a Work item at commit level.

Here: the PR title `type(#N): summary` names the Work item and becomes the
squash commit; git-cliff turns it into the Release notes, so each line links
its issue. The title check is a required Check.

## We talk about CI/CD as a sequence of risk mitigations

Each gate treats a named risk; by Production the key risks are resolved. Name
the risks of a change and of the process; prefer automated mitigations to
manual approvals. Pipelines leave immutable evidence of what they mitigated.

Here: tests and image scan (broken or vulnerable code), gitleaks (secrets),
dependency review (vulnerable dependencies), re-scan on re-delivery (new CVEs
since that Release's Accept; Ship delivers the digest Accept scanned moments
before, so its Accept scan is the scan of record), no-downgrade guard and per-service concurrency (a run rolling
Production back). The merge is the approval. Evidence: scan results in runs,
Release notes, the PR's recorded/running comment, the `production`
deployment as the source of truth. Attestations and SBOMs: planned, not done.

## We partner early with Security and Risk

Bring security and risk in when designing work and pipelines; guardrails
trigger deeper engagement; acceptance criteria include NFRs.

Here: no separate Security team, so the guardrails are the Checks and least
privilege. Each Work item states what done looks like. Least privilege: two
GitHub Apps (`kindorg-ci` releases and records, `kindorg-argocd` reports
running), minimal workflow permissions, `persist-credentials: false`, no
secrets on Dependabot PRs. One deliberate widening: `kindorg-ci` also has
Workflows: write, because GitHub refuses an App-created tag or Release whose
commits change workflow files without it (this repo's 4.1.0 failed with
"Resource not accessible by integration" until it was granted, 2026-10-03).
The trade-off: whoever holds its key, the org secret `KINDORG_CI_APP_KEY`,
can now change workflows in the repos the App is installed on.
One named exception to "no secrets where a PR's code runs": self-test's
record-dry-run job (`Deliver: a dry-run record in the real homelab-k8s
changes nothing`) gives a same-repo pull request the App key, to mint a
token limited to `contents: read` on homelab-k8s. A fork's PR and
Dependabot's never get it; a same-repo PR is opened only by the one
maintainer (or an agent on their behalf), and that PR's workflow code could
use the key unrestricted. Accepted, because the job is what proves a change
here re-records Production unchanged before it can reach a service; moving
it to push-only would find that out after the merge.

## We automate all the right things

Stability-first automation. An immutable Artifact goes all the way to
Production after its gates. Manual steps show what to automate next. Steps are
orchestrator-agnostic, runnable locally.

Here: build once, promote: the Artifact is built and scanned on merge; a
Release only adds a version tag to the same digest (checked unchanged) and
homelab-k8s pins it by digest. Never rebuild after merge. Release only a
Releasable change on an accepted commit. Steps are containers and scripts with
their own tests (`record.test.sh`, `no-downgrade.test.sh`,
`annotate-app.test.sh`), so they run
outside Actions.
