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
  local width
  local height
  local title
  local subtitle
  local base_name

  base_name="$(basename "$target")"
  width="1200"
  height="340"
  title="$label"
  subtitle="Auto-refresh by CI when upstream service recovers"

  case "$base_name" in
    pin-*)
      width="495"
      height="195"
      title="Project card unavailable"
      subtitle="$base_name (retrying in next CI run)"
      ;;
    stats-*)
      width="495"
      height="195"
      title="Statistics unavailable"
      subtitle="$base_name (retrying in next CI run)"
      ;;
    activity-graph.svg)
      width="1200"
      height="340"
      title="Activity graph unavailable"
      subtitle="Retrying in next CI run"
      ;;
    wakatime-*)
      width="960"
      height="320"
      title="WakaTime chart unavailable"
      subtitle="Retrying in next CI run"
      ;;
    sponsors-circle.svg)
      width="640"
      height="640"
      title="Sponsors chart unavailable"
      subtitle="Retrying in next CI run"
      ;;
    header-typing.svg)
      width="900"
      height="80"
      title="Profile header unavailable"
      subtitle="Retrying in next CI run"
      ;;
    visitor-count.svg)
      width="260"
      height="28"
      title="Visitor counter unavailable"
      subtitle=""
      ;;
  esac

  mkdir -p "$(dirname "$target")"
  if [[ "$base_name" == "visitor-count.svg" ]]; then
    cat > "$target" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="260" height="28" viewBox="0 0 260 28" role="img" aria-label="visitor counter unavailable">
  <!-- mirrored-placeholder -->
  <linearGradient id="g" x2="0" y2="100%">
    <stop offset="0" stop-color="#2f334d"/>
    <stop offset="1" stop-color="#1a1b27"/>
  </linearGradient>
  <rect rx="4" width="260" height="28" fill="url(#g)"/>
  <text x="130" y="19" fill="#c0caf5" font-family="Arial, sans-serif" font-size="12" text-anchor="middle">visitor counter unavailable</text>
</svg>
EOF
    return
  fi

  cat > "$target" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title desc">
  <!-- mirrored-placeholder -->
  <title id="title">${title}</title>
  <desc id="desc">Tokyonight-style fallback image generated when upstream image source is unavailable.</desc>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#1a1b27"/>
      <stop offset="100%" stop-color="#16161e"/>
    </linearGradient>
    <linearGradient id="line" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="#7aa2f7"/>
      <stop offset="100%" stop-color="#bb9af7"/>
    </linearGradient>
  </defs>
  <rect width="${width}" height="${height}" rx="14" fill="url(#bg)" />
  <rect x="0" y="0" width="${width}" height="4" fill="url(#line)" />
  <rect x="12" y="12" width="$((${width} - 24))" height="$((${height} - 24))" rx="10" fill="none" stroke="#2f334d" stroke-width="1" />
  <text x="50%" y="44%" dominant-baseline="middle" text-anchor="middle" fill="#c0caf5" font-family="Arial, sans-serif" font-size="28">${title}</text>
  <text x="50%" y="60%" dominant-baseline="middle" text-anchor="middle" fill="#7aa2f7" font-family="Arial, sans-serif" font-size="16">${subtitle}</text>
</svg>
EOF
}

should_refresh_placeholder() {
  local target="$1"
  if [[ ! -f "$target" ]]; then
    return 0
  fi
  if grep -q "mirrored-placeholder" "$target" 2>/dev/null; then
    return 0
  fi
  if grep -q "Generated fallback image when external source is unavailable." "$target" 2>/dev/null; then
    return 0
  fi
  return 1
}

ensure_placeholder_if_needed() {
  local target="$1"
  local placeholder_label="$2"
  if [[ "$target" == *.svg ]] && should_refresh_placeholder "$target"; then
    create_placeholder_svg "$target" "$placeholder_label"
    echo "Generated placeholder: $target"
    updated=$((updated + 1))
  fi
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
    ensure_placeholder_if_needed "$target" "$placeholder_label"
    continue
  fi

  if [[ ! -s "$tmp_file" ]]; then
    echo "::warning::Downloaded file is empty for $url"
    rm -f "$tmp_file"
    failed=$((failed + 1))
    ensure_placeholder_if_needed "$target" "$placeholder_label"
    continue
  fi

  if [[ "$target" == *.svg ]] && ! grep -qi "<svg" "$tmp_file"; then
    echo "::warning::Downloaded content does not look like SVG for $url"
    rm -f "$tmp_file"
    failed=$((failed + 1))
    ensure_placeholder_if_needed "$target" "$placeholder_label"
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
