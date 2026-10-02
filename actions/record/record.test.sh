#!/usr/bin/env bash
# Cases for record.sh against a git copy of fixtures/gitops (hello records
# 1.4.0, fresh nothing yet, with two images). Runs in self-test and locally
# (needs docker):
#   actions/record/record.test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
record="$here/record.sh"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo="$work/homelab-k8s"
failed=0

cp -R "$root/fixtures/gitops" "$repo"
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm fixture
commit() { git -C "$repo" -c user.name=t -c user.email=t@t commit -qam "$1"; }
reset() { git -C "$repo" reset -q --hard; }

yq() { docker run --rm -i -u "$(id -u):$(id -g)" -v "$repo:/work" -w /work \
  mikefarah/yq:4.54.1@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e "$@"; }
build() { docker run --rm -u "$(id -u):$(id -g)" -v "$repo:/work" -w "/work/manifests/$1/base" \
  registry.k8s.io/kustomize/kustomize:v5.8.1@sha256:899fcd3bc898160e62bcaf82932b0cb29ba38d16272353db2e7acbba82129429 build .; }
check() { # check <why> <want> <got>
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; failed=1; fi
}
has() { # has <why> <needle> <haystack>
  if [[ $3 == *"$2"* ]]; then echo "ok   $1"; else echo "FAIL $1: no '$2' in:"; echo "$3" | sed 's/^/     /'; failed=1; fi
}
# run pass|fail <why> <app> [VAR=value ...] — record.sh's stdout in $out, stderr in $err
run() {
  local want=$1 why=$2 app=$3 got; shift 3
  if out=$(env "${release[@]}" "$@" "$record" "$repo" "$app" 2>"$work/err"); then got=pass; else got=fail; fi
  err=$(cat "$work/err")
  check "$want: $why" "$want" "$got"
  [ "$got" = "$want" ] || echo "$err" | sed 's/^/     /'
}
list() { # list name=digest ... → an Artifact list
  local sep= e; printf '['
  for e in "$@"; do printf '%s{"name":"%s","image":"ghcr.io/kindorg-hq/%s","digest":"%s"}' "$sep" "${e%%=*}" "${e%%=*}" "${e#*=}"; sep=,; done
  printf ']'
}
ann() { yq ".metadata.annotations[\"kindorg.dev/$2\"] // \"\"" "apps/$1.yaml"; }
recorded() { sed -nE 's/^[[:space:]]*app\.kubernetes\.io\/version:[[:space:]]*([^[:space:]]+).*/\1/p' "$repo/manifests/$1/base/kustomization.yaml"; }

d1="sha256:$(printf '1%.0s' {1..64})"; d2="sha256:$(printf '2%.0s' {1..64})"; d3="sha256:$(printf '3%.0s' {1..64})"
sha="$(printf 'a%.0s' {1..40})"
release=(SOURCE_REPO=https://github.com/kindorg-hq/fresh SOURCE_SHA="$sha" ENVIRONMENT_URL=https://fresh.example)

# first delivery: no version recorded yet, two images
run pass "first delivery" fresh VERSION=0.1.0 IMAGES="$(list fresh="$d1" fresh-worker="$d2")"
rendered=$(build fresh)
has "the image is pinned by digest" "image: ghcr.io/kindorg-hq/fresh@$d1" "$rendered"
has "so is the second one (its tag dropped)" "image: ghcr.io/kindorg-hq/fresh-worker@$d2" "$rendered"
check "the version is recorded" 0.1.0 "$(recorded fresh)"
has "the version labels the pod template" "app.kubernetes.io/version: 0.1.0" "$rendered"
has "the diff is printed" "+    app.kubernetes.io/version: 0.1.0" "$out"
has "verified, said on stderr" "verified: manifests/fresh/base renders ghcr.io/kindorg-hq/fresh@$d1" "$err"
# annotations written
check "annotation source-sha" "$sha" "$(ann fresh source-sha)"
check "annotation version" 0.1.0 "$(ann fresh version)"
check "annotation images, as kustomize pins them" "ghcr.io/kindorg-hq/fresh@$d1 ghcr.io/kindorg-hq/fresh-worker@$d2" "$(ann fresh images)"
check "annotation environment-url" https://fresh.example "$(ann fresh environment-url)"
check "only that app's files change" "apps/fresh.yaml manifests/fresh/base/kustomization.yaml" "$(git -C "$repo" diff --name-only | sort | paste -sd ' ' -)"
commit "deploy(fresh): 0.1.0"

# re-delivery: the same Release again changes nothing
run pass "re-delivery" fresh VERSION=0.1.0 IMAGES="$(list fresh="$d1" fresh-worker="$d2")"
check "re-delivery prints no diff" "" "$out"
check "re-delivery leaves the checkout clean" "" "$(git -C "$repo" status --porcelain)"
has "re-delivery says so" "already records fresh 0.1.0: no diff" "$err"

# upgrade: hello 1.4.0 → 1.5.0
run pass "upgrade" hello VERSION=1.5.0 IMAGES="$(list hello="$d3")" SOURCE_REPO=https://github.com/kindorg-hq/hello
check "the new version is recorded" 1.5.0 "$(recorded hello)"
rendered=$(build hello)
has "the new digest renders" "image: ghcr.io/kindorg-hq/hello@$d3" "$rendered"
check "the old digest is gone" 0 "$(grep -c "sha256:0000" <<< "$rendered")"
has "the diff shows the move" "-    app.kubernetes.io/version: 1.4.0" "$out"
check "annotation version moves" 1.5.0 "$(ann hello version)"
reset

# downgrade refused, nothing changed
run fail "downgrade" hello VERSION=1.3.0 IMAGES="$(list hello="$d3")"
has "the refusal names the recorded version" "1.4.0" "$err"
has "and the refused one" "refusing to record 1.3.0" "$err"
check "a refusal changes nothing" "" "$(git -C "$repo" status --porcelain)"
reset

# an image name the manifests do not use: the pin would be a no-op
run fail "image name not in the manifests" hello VERSION=1.5.0 IMAGES="$(list hello="$d3" hallo="$d1")"
has "the failure names the image" "hallo: manifests/hello/base does not render ghcr.io/kindorg-hq/hallo@$d1" "$err"
has "and what the manifests do render" "render: ghcr.io/kindorg-hq/hello@$d3" "$err"
reset

# no release commit: the Application is left as it is
run pass "no release commit" hello VERSION=1.5.0 IMAGES="$(list hello="$d3")" SOURCE_SHA=
check "no annotations without a release commit" "manifests/hello/base/kustomization.yaml" "$(git -C "$repo" diff --name-only)"
reset

run fail "an app without manifests" pepic VERSION=1.0.0 IMAGES="$(list pepic="$d1")"
has "names the missing directory" "no manifests/pepic/base" "$err"
run fail "an image without digest" hello VERSION=1.5.0 IMAGES="$(list hello=)"
has "names the entry" "no digest" "$err"
echo "# a stray edit" >> "$repo/apps/hello.yaml"
run fail "a checkout with changes of its own" hello VERSION=1.5.0 IMAGES="$(list hello="$d3")"
reset

[ $failed -eq 0 ] && echo "all cases pass" || { echo "some cases failed"; exit 1; }
