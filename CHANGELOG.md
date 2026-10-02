# Changelog

## [3.1.0](https://github.com/kindorg-hq/ci/compare/v3.0.1...v3.1.0) (2026-10-02)


### Features

* **#19:** the GitOps PR writes the Release on the ArgoCD Application ([#30](https://github.com/kindorg-hq/ci/issues/30)) ([44f737c](https://github.com/kindorg-hq/ci/commit/44f737c18cd1509de6a2682310b4c856b530b5b2))

## [3.0.1](https://github.com/kindorg-hq/ci/compare/v3.0.0...v3.0.1) (2026-10-02)


### Bug Fixes

* **#27:** wait on GitOps checks through the REST API; reuse an open PR ([#28](https://github.com/kindorg-hq/ci/issues/28)) ([cb6ebeb](https://github.com/kindorg-hq/ci/commit/cb6ebeb39f276ca3946b16fc48ddf191217bf371))

## [3.0.0](https://github.com/kindorg-hq/ci/compare/v2.1.0...v3.0.0) (2026-10-02)


### ⚠ BREAKING CHANGES

* **#15:** services move to golden-path.yml@v3 and drop release-please; build-image builds the Dockerfile's test stage, so a failing one fails Build.

### Features

* **#11:** a merge to main ships; delivered PRs say so ([#12](https://github.com/kindorg-hq/ci/issues/12)) ([f941c7f](https://github.com/kindorg-hq/ci/commit/f941c7f19d774091580bde45dfa1df52a36a589c))
* **#15:** golden path v3 — one entry workflow, a merge is a Release ([#22](https://github.com/kindorg-hq/ci/issues/22)) ([4a3e086](https://github.com/kindorg-hq/ci/commit/4a3e086e7cf7c7aefc7572d7cf4afedd0d9c18d1)), closes [#15](https://github.com/kindorg-hq/ci/issues/15)
* **#16:** deliveries never overtake each other ([#23](https://github.com/kindorg-hq/ci/issues/23)) ([07a2843](https://github.com/kindorg-hq/ci/commit/07a28432596e12d257f2758d059935cddd108e78))
* **#17:** a recorded Release shows on its PRs and the production deployment ([#24](https://github.com/kindorg-hq/ci/issues/24)) ([b91c1aa](https://github.com/kindorg-hq/ci/commit/b91c1aa355cb4b9bca5a6820011da5b5a88d91ad))


### Bug Fixes

* **#14:** release this repo only after a green self-test; freeze v2 ([#20](https://github.com/kindorg-hq/ci/issues/20)) ([d07909b](https://github.com/kindorg-hq/ci/commit/d07909b001ebcb0595e3b4cedf93916921e3d4c9))
* **#18:** v3 workflows default to v3 actions; drop the v2 checks alias ([#26](https://github.com/kindorg-hq/ci/issues/26)) ([aa88b21](https://github.com/kindorg-hq/ci/commit/aa88b21c22999f2fa162527c7f1e462b170e4792))

## [2.1.0](https://github.com/kindorg-hq/ci/compare/v2.0.0...v2.1.0) (2026-10-02)


### Features

* **#5:** name jobs by stage, trace PRs to work items, agent conventions ([#7](https://github.com/kindorg-hq/ci/issues/7)) ([6744ba6](https://github.com/kindorg-hq/ci/commit/6744ba6f38b4ee62b625c371b47e562167392f3c))

## [2.0.0](https://github.com/kindorg-hq/ci/compare/v1.1.0...v2.0.0) (2026-10-02)


### ⚠ BREAKING CHANGES

* build the artifact once on merge; releases promote it ([#4](https://github.com/kindorg-hq/ci/issues/4))

### Features

* build the artifact once on merge; releases promote it ([#4](https://github.com/kindorg-hq/ci/issues/4)) ([a363d7b](https://github.com/kindorg-hq/ci/commit/a363d7b895324f825b0435c1da1f7ad33af5b6ab))

## [1.1.0](https://github.com/kindorg-hq/ci/compare/v1.0.0...v1.1.0) (2026-10-02)


### Features

* pinned runner labels, egress audit, tools from pinned containers ([#1](https://github.com/kindorg-hq/ci/issues/1)) ([f54fb44](https://github.com/kindorg-hq/ci/commit/f54fb44dc9b431610715016a6c581b44ec85b5dd))


### Bug Fixes

* release tags as vX.Y.Z, without the component prefix ([#3](https://github.com/kindorg-hq/ci/issues/3)) ([28d7b5a](https://github.com/kindorg-hq/ci/commit/28d7b5a8a0632608a286e6fb0daab91e3dd60314))
