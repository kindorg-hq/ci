# kindorg-hq/ci

How a service of kindorg-hq gets from a pull request to the home cluster.
Cluster terms (Platform, Application) are defined in homelab-k8s/CONTEXT.md.

## Language

**Checks**:
What every pull request of a service must pass besides its own tests: a Conventional-Commit title, no secrets in the change, no vulnerable dependency added, the image builds and scans clean.
_Avoid_: CI (too broad — the service's own tests are CI too), gates

**Release**:
A version of a service, created by merging the release PR that release-please keeps open: a tag vX.Y.Z, a GitHub Release, a CHANGELOG entry. Only releases reach the cluster.
_Avoid_: deploy (that is Delivery), build

**Delivery**:
Getting a Release into the cluster: images built from the release tag and pushed, scanned, then recorded in homelab-k8s by a pull request — pinned by digest, labelled with the version. ArgoCD rolls out what lands on main.
_Avoid_: deploy job, push to prod

**Fix forward**:
The only way back from a bad Release is the next Release. There is no rollback in the pipeline.
_Avoid_: rollback, revert

**Break-glass**:
The documented exception to Fix forward: a manual revert in homelab-k8s when production is down and a fix cannot ship in time. Always followed by a written note of what went around the process and why.
_Avoid_: hotfix (that is just a Release)

**Golden path**:
The shared part of the pipeline this repo provides — Checks, Release, Delivery. A service keeps its own tests outside it (the escape hatch).
_Avoid_: template, standard pipeline
