#!/usr/bin/env bash
# Cases for annotate-app.sh against fixtures/gitops/apps/hello.yaml (a copy).
# Runs in self-test and locally (needs docker):
#   actions/record/annotate-app.test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
annotate="$here/annotate-app.sh"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cp "$root/fixtures/gitops/apps/hello.yaml" "$work/hello.yaml"
file="$work/hello.yaml"
failed=0

yq() { docker run --rm -i -u "$(id -u):$(id -g)" -v "$work:/work" -w /work \
  mikefarah/yq:4.54.1@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e "$@"; }
check() { # check <why> <want> <got>
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; failed=1; fi
}
run() { # run pass|fail <why> [VAR=value ...] -- <file> <app>
  local want=$1 why=$2 got out; shift 2
  local -a vars=(); while [ "$1" != -- ]; do vars+=("$1"); shift; done; shift
  if out=$(env "${base[@]}" ${vars[@]+"${vars[@]}"} "$annotate" "$@" 2>&1); then got=pass; else got=fail; fi
  check "$want: $why" "$want" "$got"
  [ "$got" = "$want" ] || echo "$out" | sed 's/^/     /'
}
ann() { yq ".metadata.annotations[\"kindorg.dev/$1\"] // \"\"" hello.yaml; }

sha1=$(printf '1%.0s' {1..40}); sha2=$(printf '2%.0s' {1..40})
img1="ghcr.io/kindorg-hq/hello@sha256:$(printf 'a%.0s' {1..64})"
img2="ghcr.io/kindorg-hq/worker@sha256:$(printf 'b%.0s' {1..64})"
base=(SOURCE_REPO=https://github.com/kindorg-hq/hello SOURCE_SHA="$sha1" VERSION=1.4.0
      IMAGES="$img1 $img2" ENVIRONMENT_URL=https://hello.example)
spec_before=$(yq 'del(.metadata.annotations)' hello.yaml)

run pass "first delivery annotates the Application" -- "$file" hello
check "source-repo" https://github.com/kindorg-hq/hello "$(ann source-repo)"
check "source-sha is the full SHA" "$sha1" "$(ann source-sha)"
check "version" 1.4.0 "$(ann version)"
check "images, space separated, by digest" "$img1 $img2" "$(ann images)"
check "environment-url" https://hello.example "$(ann environment-url)"
check "nothing else changes" "$spec_before" "$(yq 'del(.metadata.annotations)' hello.yaml)"

before=$(cat "$file")
run pass "re-delivery" -- "$file" hello
check "re-delivery leaves the file byte for byte (no diff, no PR)" "$before" "$(cat "$file")"

run pass "next Release, no environment url" SOURCE_SHA="$sha2" VERSION=1.5.0 IMAGES="$img1" ENVIRONMENT_URL= -- "$file" hello
check "source-sha moves" "$sha2" "$(ann source-sha)"
check "version moves" 1.5.0 "$(ann version)"
check "images follow" "$img1" "$(ann images)"
check "an empty environment url removes the annotation" "" "$(ann environment-url)"

run fail "another app's Application" -- "$file" pepic
run fail "no Application file" -- "$work/missing.yaml" hello
run fail "short SHA" SOURCE_SHA=1234567 -- "$file" hello
run fail "image by tag, not digest" IMAGES="ghcr.io/kindorg-hq/hello:1.4.0" -- "$file" hello
run fail "version not X.Y.Z" VERSION=latest -- "$file" hello
run fail "source repo not on GitHub" SOURCE_REPO=https://example.com/x/y -- "$file" hello

[ $failed -eq 0 ] && echo "all cases pass" || { echo "some cases failed"; exit 1; }
