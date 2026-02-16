#!/usr/bin/env bash
set -euo pipefail

LIST_FILE=".github/readme-image-mirror-list.txt"

if [[ ! -f "$LIST_FILE" ]]; then
  echo "Mirror list file not found: $LIST_FILE" >&2
  exit 1
fi

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

create_placeholder_svg() {
  local target="$1"
  local label="$2"

  mkdir -p "$(dirname "$target")"
  cat > "$target" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="340" viewBox="0 0 1200 340" role="img" aria-labelledby="title desc">
  <title id="title">${label}</title>
  <desc id="desc">Generated fallback image when external source is unavailable.</desc>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0f172a"/>
      <stop offset="100%" stop-color="#1e293b"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="340" rx="14" fill="url(#bg)"/>
  <text x="50%" y="45%" dominant-baseline="middle" text-anchor="middle" fill="#e2e8f0" font-family="Arial, sans-serif" font-size="34">${label}</text>
  <text x="50%" y="60%" dominant-baseline="middle" text-anchor="middle" fill="#94a3b8" font-family="Arial, sans-serif" font-size="22">External source temporarily unavailable, auto-retry on next CI run</text>
</svg>
EOF
}

updated=0
unchanged=0
failed=0

while IFS='|' read -r raw_target raw_url || [[ -n "${raw_target:-}${raw_url:-}" ]]; do
  target="$(trim "${raw_target:-}")"
  url="$(trim "${raw_url:-}")"
  placeholder_label="$(basename "$target")"

  if [[ -z "$target" || -z "$url" || "$target" == \#* ]]; then
    continue
  fi

  tmp_file="$(mktemp)"
  echo "Mirroring $target"

  if ! curl -A "README-Mirror-Bot/1.0" \
    -H "Accept: image/*,*/*;q=0.8" \
    -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 120 \
    "$url" -o "$tmp_file"; then
    echo "::warning::Failed to download $url"
    rm -f "$tmp_file"
    failed=$((failed + 1))
    if [[ ! -f "$target" && "$target" == *.svg ]]; then
      create_placeholder_svg "$target" "$placeholder_label"
      echo "Generated placeholder: $target"
      updated=$((updated + 1))
    fi
    continue
  fi

  if [[ ! -s "$tmp_file" ]]; then
    echo "::warning::Downloaded file is empty for $url"
    rm -f "$tmp_file"
    failed=$((failed + 1))
    if [[ ! -f "$target" && "$target" == *.svg ]]; then
      create_placeholder_svg "$target" "$placeholder_label"
      echo "Generated placeholder: $target"
      updated=$((updated + 1))
    fi
    continue
  fi

  if [[ "$target" == *.svg ]] && ! grep -qi "<svg" "$tmp_file"; then
    echo "::warning::Downloaded content does not look like SVG for $url"
    rm -f "$tmp_file"
    failed=$((failed + 1))
    if [[ ! -f "$target" && "$target" == *.svg ]]; then
      create_placeholder_svg "$target" "$placeholder_label"
      echo "Generated placeholder: $target"
      updated=$((updated + 1))
    fi
    continue
  fi

  mkdir -p "$(dirname "$target")"

  if [[ -f "$target" ]] && cmp -s "$tmp_file" "$target"; then
    echo "No change: $target"
    rm -f "$tmp_file"
    unchanged=$((unchanged + 1))
    continue
  fi

  mv "$tmp_file" "$target"
  echo "Updated: $target"
  updated=$((updated + 1))
done < "$LIST_FILE"

echo "Mirror summary -> updated: $updated, unchanged: $unchanged, failed: $failed"
exit 0
