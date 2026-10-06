#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=8.13
installation="$root/.tools/gradle-$version"

if [[ ! -x "$installation/bin/gradle" ]]; then
    download_dir=$(mktemp -d)
    trap 'rm -rf "$download_dir"' EXIT
    base="https://services.gradle.org/distributions/gradle-$version-bin.zip"
    checksum=$(curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$base.sha256")
    [[ "$checksum" =~ ^[a-f0-9]{64}$ ]] || { printf 'Invalid official Gradle checksum\n' >&2; exit 1; }
    curl --fail --show-error --location --proto '=https' --tlsv1.2 "$base" --output "$download_dir/gradle.zip"
    printf '%s  %s\n' "$checksum" "$download_dir/gradle.zip" | sha256sum --check --status
    mkdir -p "$root/.tools"
    unzip -q "$download_dir/gradle.zip" -d "$root/.tools"
fi

exec "$installation/bin/gradle" --no-daemon -p "$root/mobile/android" "$@"