#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/export-public-key.sh PRIMARY_FINGERPRINT [name]

PRIMARY_FINGERPRINT  Full fingerprint of an EXISTING GPG primary key (40 hex digits).
name                 Output basename without extension (default: archive-keyring).

Examples:
  gpg --list-keys --keyid-format LONG --with-fingerprint --with-subkey-fingerprint
  ./scripts/export-public-key.sh 0123456789ABCDEF0123456789ABCDEF01234567
  ./scripts/export-public-key.sh 0123456789ABCDEF0123456789ABCDEF01234567 nginx-archive-keyring

Exports ONLY public material; it NEVER runs --export-secret-keys.
USAGE
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
fingerprint=${1// /}
name=${2:-archive-keyring}

if [[ ! "$fingerprint" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "Error: use the full 40-character PRIMARY key fingerprint." >&2
  exit 2
fi
if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ || "$name" == *..* ]]; then
  echo "Error: invalid output name: $name" >&2
  exit 2
fi

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
keys_dir="$root/keys"
mkdir -p "$keys_dir"
tmpdir=$(mktemp -d)
trap 'rm -rf -- "$tmpdir"' EXIT

# Minimal OpenPGP export is compatible with APT's Signed-By keyring format.
gpg --batch --export-options export-minimal --export "$fingerprint" > "$tmpdir/$name.gpg"
gpg --batch --armor --export-options export-minimal --export "$fingerprint" > "$tmpdir/$name.asc"

if [[ ! -s "$tmpdir/$name.gpg" || ! -s "$tmpdir/$name.asc" ]]; then
  echo "Error: no matching public key found in the active GPG keyring." >&2
  exit 1
fi
actual_fpr=$(gpg --batch --show-keys --with-colons --with-fingerprint "$tmpdir/$name.gpg" | awk -F: '$1 == "fpr" { print $10; exit }')
if [[ "${actual_fpr^^}" != "${fingerprint^^}" ]]; then
  echo "Error: the supplied fingerprint is not the primary key fingerprint ($actual_fpr)." >&2
  exit 1
fi

# An armor/dearmor round trip should produce identical public key packets.
if ! gpg --batch --dearmor < "$tmpdir/$name.asc" | cmp -s - "$tmpdir/$name.gpg"; then
  echo "Error: ASCII and binary exports differ." >&2
  exit 1
fi

printf '%s\n' "${actual_fpr^^}" > "$tmpdir/$name.fingerprint"
install -m 0644 "$tmpdir/$name.gpg" "$keys_dir/$name.gpg"
install -m 0644 "$tmpdir/$name.asc" "$keys_dir/$name.asc"
install -m 0644 "$tmpdir/$name.fingerprint" "$keys_dir/$name.fingerprint"

printf 'Exported PUBLIC key to:\n  keys/%s.gpg\n  keys/%s.asc\n  keys/%s.fingerprint\n' "$name" "$name" "$name"
printf 'Primary fingerprint: %s\n' "${actual_fpr^^}"
gpg --batch --show-keys --with-fingerprint "$keys_dir/$name.gpg"
