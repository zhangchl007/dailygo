#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if command -v swift >/dev/null 2>&1; then
    exec swift "$@"
fi

version=6.0.3
name="swift-$version-RELEASE-ubuntu24.04"
installation="$root/.tools/$name"
if [[ ! -x "$installation/usr/bin/swift" ]]; then
    download_dir=$(mktemp -d)
    trap 'rm -rf "$download_dir"' EXIT
    mkdir -p "$download_dir/keyring"
    chmod 700 "$download_dir/keyring"
    base="https://download.swift.org/swift-$version-release/ubuntu2404/swift-$version-RELEASE/$name.tar.gz"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/swiftlang/swift-org-website/main/keys/all-keys.asc --output "$download_dir/keys.asc"
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$base.sig" --output "$download_dir/swift.sig"
    curl --fail --show-error --location --proto '=https' --tlsv1.2 "$base" --output "$download_dir/swift.tar.gz"
    gpg --batch --homedir "$download_dir/keyring" --import "$download_dir/keys.asc"
    gpg --batch --homedir "$download_dir/keyring" --verify "$download_dir/swift.sig" "$download_dir/swift.tar.gz"
    mkdir -p "$root/.tools"
    tar -xzf "$download_dir/swift.tar.gz" -C "$root/.tools"
fi

export LD_LIBRARY_PATH="$root/.tools/runtime/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$installation/usr/bin/swift" "$@"