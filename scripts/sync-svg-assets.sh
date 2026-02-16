#!/usr/bin/env bash
set -euo pipefail

LIST_FILE=".github/svg-sync-list.txt"

if [[ ! -f "$LIST_FILE" ]]; then
  echo "Missing sync list: $LIST_FILE" >&2
  exit 1
fi

updated=0

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

while IFS='|' read -r raw_target raw_url || [[ -n "${raw_target:-}${raw_url:-}" ]]; do
  line_target="$(trim "${raw_target:-}")"
  line_url="$(trim "${raw_url:-}")"

  if [[ -z "$line_target" || -z "$line_url" || "$line_target" == \#* ]]; then
    continue
  fi

  tmp_file="$(mktemp)"
  echo "Syncing $line_target"
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 120 "$line_url" -o "$tmp_file"

  if ! grep -qi "<svg" "$tmp_file"; then
    echo "Downloaded content is not SVG: $line_url" >&2
    rm -f "$tmp_file"
    exit 1
  fi

  mkdir -p "$(dirname "$line_target")"

  if [[ -f "$line_target" ]] && cmp -s "$tmp_file" "$line_target"; then
    echo "No change: $line_target"
    rm -f "$tmp_file"
    continue
  fi

  mv "$tmp_file" "$line_target"
  updated=$((updated + 1))
  echo "Updated: $line_target"
done < "$LIST_FILE"

echo "Done. Updated SVG files: $updated"
