#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
keys_dir="$root/keys"
shopt -s nullglob

# Reject unexpected files in the keys directory (especially mistaken backups).
for file in "$keys_dir"/* "$keys_dir"/.*; do
  [[ -f "$file" ]] || continue
  case "${file##*/}" in
    README.md|.gitkeep) continue ;;
    *.gpg|*.asc|*.fingerprint) ;;
    *) echo "Unexpected file inside keys/: $file" >&2; exit 1 ;;
  esac
done

# Every companion file must have a corresponding binary public keyring.
for file in "$keys_dir"/*.asc "$keys_dir"/*.fingerprint; do
  base=${file%.*}
  [[ -f "$base.gpg" ]] || { echo "Orphan key file: $file" >&2; exit 1; }
done

files=("$keys_dir"/*.gpg)
if (( ${#files[@]} == 0 )); then
  echo "No public keyrings exported yet. Run scripts/export-public-key.sh."
  # A starter repository can be published before the key has been exported.
  exit 0
fi

for binary in "${files[@]}"; do
  base=${binary%.gpg}
  [[ -s "$base.asc" && -s "$base.fingerprint" ]] || { echo "Missing .asc or .fingerprint for $binary" >&2; exit 1; }

  for file in "$binary" "$base.asc"; do
    if gpg --batch --list-packets "$file" 2>/dev/null | grep -Eq '^:(secret key|secret sub key) packet:'; then
      echo "PRIVATE KEY MATERIAL DETECTED: $file" >&2
      exit 1
    fi
    if ! gpg --batch --show-keys --with-colons --with-fingerprint "$file" >/dev/null 2>&1; then
      echo "Invalid OpenPGP public key: $file" >&2
      exit 1
    fi
  done

  if ! gpg --batch --dearmor < "$base.asc" | cmp -s - "$binary"; then
    echo "ASCII/binary key mismatch: $base" >&2
    exit 1
  fi

  fpr=$(gpg --batch --show-keys --with-colons --with-fingerprint "$binary" | awk -F: '$1 == "fpr" { print $10; exit }')
  expected=$(tr -d '[:space:]' < "$base.fingerprint")
  if [[ -z "$fpr" || "${fpr^^}" != "${expected^^}" ]]; then
    echo "Fingerprint mismatch: $base" >&2
    exit 1
  fi
  printf 'OK: %s (%s)\n' "${base##*/}" "${fpr^^}"
done

