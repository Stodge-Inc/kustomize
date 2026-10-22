#!/usr/bin/env bash
# Builds the Postscript kustomize release artifacts into dist/<version>/.
# Usage: hack/postscript-release.sh <version>   e.g. v5.8.1-ps.1
# Build flags mirror releasing/create-release.sh.

set -euo pipefail

if [[ -z "${1-}" ]]; then
  echo "Usage: $0 <version>   (e.g. v5.8.1-ps.1)" >&2
  exit 1
fi

version=$1
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-ps\.[0-9]+$ ]]; then
  echo "version must look like v5.8.1-ps.1, got: $version" >&2
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "working tree has uncommitted changes; commit them first" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$@"; }
else
  sha256() { shasum -a 256 "$@"; }
fi

git_commit=$(git rev-parse HEAD)
build_date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
release_dir="$repo_root/dist/$version"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

rm -rf "$release_dir"
mkdir -p "$release_dir"

# The root go.work makes ./api the api module, so the patched code is what gets built.
for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64; do
  os=${target%/*}
  arch=${target#*/}
  echo "Building $os/$arch"
  (
    cd "$repo_root/kustomize"
    CGO_ENABLED=0 GOOS=$os GOARCH=$arch go build -trimpath -o "$work_dir/kustomize" -ldflags \
      "-s -w \
      -X sigs.k8s.io/kustomize/api/provenance.version=$version \
      -X sigs.k8s.io/kustomize/api/provenance.gitCommit=$git_commit \
      -X sigs.k8s.io/kustomize/api/provenance.buildDate=$build_date" \
      .
  )
  tar czf "$release_dir/kustomize_${version}_${os}_${arch}.tar.gz" -C "$work_dir" kustomize
  rm "$work_dir/kustomize"
done

(
  cd "$release_dir"
  : > checksums.txt
  for f in kustomize_*.tar.gz; do
    sha256 "$f" >> checksums.txt
  done
  cat checksums.txt
)

echo "Artifacts in $release_dir"
