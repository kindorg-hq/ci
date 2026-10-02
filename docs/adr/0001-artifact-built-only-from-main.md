# The Artifact is built only from the default branch; PR builds are never promoted

A pull request builds and tests the same image its merge will build, and on an unchanged main the trees are identical, so reusing the PR's image (keyed by tree hash) would save the second build (~80 s for pepic). We decided against it: a PR is an untrusted context — its caller workflow comes from the PR itself, so it could push one image for the tests and another under its own tree's tag, and the merge would promote the substitute to Production. Closing that needs build-provenance attestations verified against `kindorg-hq/ci@v4`, which the free plan offers only for public repos. So the merge builds the Artifact again from protected code, and the second build is made cheap with caches instead — under the same rule: a cache the default branch reads is written only by default-branch runs; PRs may read it, never write it.

## Consequences

- The definition of Artifact in CONTEXT.md (built once, on merge, tagged with its commit SHA) stands.
- Release evidence (Build + Accept) belongs to the commit on main, not to a PR run.
- Revisit if every service repo can verify attestations (paid plan, or all repos public).
