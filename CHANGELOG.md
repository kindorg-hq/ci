# Changelog

## [4.2.0](https://github.com/kindorg-hq/ci/compare/v4.1.1...v4.2.0) (2026-10-02)


### Features

* **#66:** Build runs a service's compose tests against the built images ([#67](https://github.com/kindorg-hq/ci/issues/67)) ([1c44e40](https://github.com/kindorg-hq/ci/commit/1c44e4000960a693260bc9d90f25fdaa485da722))

## [4.1.1](https://github.com/kindorg-hq/ci/compare/v4.1.0...v4.1.1) (2026-10-02)


### Bug Fixes

* **#46:** one summary per run, client-id for the App token ([#65](https://github.com/kindorg-hq/ci/issues/65)) ([3969edb](https://github.com/kindorg-hq/ci/commit/3969edbfddda7eb1cb1c47eebfbdafa82536aefe))
* **#62:** grant actions: read to self-test when releasing ([#63](https://github.com/kindorg-hq/ci/issues/63)) ([96e8ce6](https://github.com/kindorg-hq/ci/commit/96e8ce6f6f45a214d1136ae021c122c51b98bc44))

## [4.1.0](https://github.com/kindorg-hq/ci/compare/v4.0.0...v4.1.0) (2026-10-02)


### Features

* **#49:** recording in homelab-k8s is one tested module that verifies its result ([#53](https://github.com/kindorg-hq/ci/issues/53)) ([320c52e](https://github.com/kindorg-hq/ci/commit/320c52e98fde126d45250ac6637ae2f083f85375))
* **#50:** Delivery is one module; ship and re-deliver only choose the Release ([#55](https://github.com/kindorg-hq/ci/issues/55)) ([6c9527a](https://github.com/kindorg-hq/ci/commit/6c9527ab9eb223e955701f0dbc2645d3d254a43d))

## [4.0.0](https://github.com/kindorg-hq/ci/compare/v3.1.0...v4.0.0) (2026-10-02)


### ⚠ BREAKING CHANGES

* **#37:** services move to pull-request.yml, ship.yml and redeliver.yml @v4 (README, Migrating from v3 → v4); v3 entry workflows are removed from main (@v3 keeps them). build-image, scan-image and promote-image drop the single-image inputs (name/context/dockerfile, ref, image), the ref/digest outputs and build-image's `version`.

### Features

* **#33:** build, scan and promote take a list of images ([#40](https://github.com/kindorg-hq/ci/issues/40)) ([f19fab9](https://github.com/kindorg-hq/ci/commit/f19fab9c7a0b0fc2abcb1b133e68ad2a437721b0))
* **#34:** v4 Ship runs Build → Accept → Deliver ([#43](https://github.com/kindorg-hq/ci/issues/43)) ([d202438](https://github.com/kindorg-hq/ci/commit/d202438aee83cbfe565bd4a37c5d7856026eda21))
* **#35:** v4 pull request runs Build → Accept, two checks ([#42](https://github.com/kindorg-hq/ci/issues/42)) ([83de72d](https://github.com/kindorg-hq/ci/commit/83de72d0066db9391ce184146fefb9051f28f3f2))
* **#36:** v4 re-deliver runs one Deliver job ([#44](https://github.com/kindorg-hq/ci/issues/44)) ([f182074](https://github.com/kindorg-hq/ci/commit/f18207424494d3aa5a5d83e8c91707bce7360088))
* **#37:** services enter through pull-request.yml, ship.yml and redeliver.yml ([#45](https://github.com/kindorg-hq/ci/issues/45)) ([af6bad9](https://github.com/kindorg-hq/ci/commit/af6bad9ddb8d58fc78d6ce124d1a7518ae980016))

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
