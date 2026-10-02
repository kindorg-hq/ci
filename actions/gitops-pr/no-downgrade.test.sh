#!/usr/bin/env bash
# Cases for no-downgrade.sh against fixtures/gitops (hello records 1.4.0,
# fresh records nothing). Runs in self-test and locally:
#   actions/gitops-pr/no-downgrade.test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
guard="$here/no-downgrade.sh"
hello="$root/fixtures/gitops/manifests/hello/base"
fresh="$root/fixtures/gitops/manifests/fresh/base"
failed=0

expect() { # expect pass|fail <dir> <version> <why>
  local want=$1 dir=$2 version=$3 why=$4 got out
  if out=$("$guard" "$dir" "$version" 2>&1); then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then
    echo "ok   $want  $version over $(basename "$(dirname "$dir")"): $why"
  else
    echo "FAIL want $want, got $got: $version over $(basename "$(dirname "$dir")"): $why"
    echo "$out" | sed 's/^/     /'
    failed=1
  fi
}

expect fail "$hello" 1.3.9         "lower patch overtakes nothing"
expect fail "$hello" 1.3.10        "numeric, not lexical: 1.3.10 < 1.4.0"
expect fail "$hello" 0.9.0         "lower major"
expect fail "$hello" v1.3.0        "leading v is stripped, still lower"
expect fail "$hello" 1.4.0-rc.1    "a pre-release ranks below its release"
expect pass "$hello" 1.4.0         "equal: re-delivery"
expect pass "$hello" v1.4.0        "equal with a leading v"
expect pass "$hello" 1.4.0+build.7 "build metadata does not count"
expect pass "$hello" 1.4.1         "higher patch"
expect pass "$hello" 1.10.0        "numeric, not lexical: 1.10.0 > 1.4.0"
expect pass "$hello" 2.0.0         "higher major"
expect pass "$fresh" 0.1.0         "no version recorded: first delivery"
expect fail "$hello" latest        "not SemVer"

# the refusal names both versions
out=$("$guard" "$hello" 1.3.9 2>&1 || true)
if [[ $out == *1.3.9* && $out == *1.4.0* ]]; then
  echo "ok   refusal names both versions: $out"
else
  echo "FAIL refusal does not name both versions: $out"; failed=1
fi

exit $failed
