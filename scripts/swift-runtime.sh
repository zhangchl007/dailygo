#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$root/.tools/apt/lists/partial" "$root/.tools/apt/archives/partial" "$root/.tools/runtime"
options=(
    -o "Dir::Etc::sourcelist=$root/scripts/ubuntu-noble.sources"
    -o Dir::Etc::sourceparts=-
    -o "Dir::State::lists=$root/.tools/apt/lists"
    -o "Dir::Cache::archives=$root/.tools/apt/archives"
    -o "Dir::Cache::pkgcache=$root/.tools/apt/pkgcache.bin"
    -o "Dir::Cache::srcpkgcache=$root/.tools/apt/srcpkgcache.bin"
    -o Debug::NoLocking=1
)
apt-get "${options[@]}" update

for package in libncurses6 libxml2 libicu74; do
    metadata=$(apt-cache "${options[@]}" show "$package")
    version=$(printf '%s\n' "$metadata" | sed -n 's/^Version: //p' | head -n 1)
    metadata=$(apt-cache "${options[@]}" show "$package=$version")
    filename=$(printf '%s\n' "$metadata" | sed -n 's/^Filename: //p' | head -n 1)
    checksum=$(printf '%s\n' "$metadata" | sed -n 's/^SHA256: //p' | head -n 1)
    [[ "$checksum" =~ ^[a-f0-9]{64}$ ]] || { printf 'Missing verified package hash\n' >&2; exit 1; }
    archive="$root/.tools/apt/archives/$package.deb"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "https://archive.ubuntu.com/ubuntu/$filename" --output "$archive"
    printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
    dpkg-deb --extract "$archive" "$root/.tools/runtime"
    printf 'Verified runtime %s=%s\n' "$package" "$version"
done