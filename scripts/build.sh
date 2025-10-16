#!/usr/bin/env bash
set -euo pipefail

script_dir=$(dirname -- "$(readlink -f -- "$0")")
out_dir="$script_dir/../build"
vls_src="$script_dir/../src"

mkdir -p "$out_dir"

if ! command -v v >/dev/null 2>&1; then
  printf '%s\n' "error: 'v' compiler not found in PATH" >&2
  exit 1
fi

out_bin="$out_dir/vls"

v -o "$out_bin" "$vls_src"

printf '%s\n' "Built: $out_bin"