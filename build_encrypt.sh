#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

cd "$SCRIPT_DIR"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

: "${SINGLEFILE_CMD:=npx}"
: "${SINGLEFILE_PKG:=single-file-cli}"
: "${STATICRYPT_CMD:=npx}"
: "${STATICRYPT_PKG:=staticrypt}"

: "${STATICRYPT_PASSWORD:=}"
: "${STATICRYPT_ARGS:=--short}"
: "${SINGLEFILE_ARGS:=}"

INDEX="index.html"
SINGLE="index.single.html"
THEME_TMP=".theme_block.tmp.html"

# Normalize password (fix CRLF + trim)
STATICRYPT_PASSWORD="$(printf '%s' "${STATICRYPT_PASSWORD:-}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [ ! -f "$INDEX" ]; then
  echo "ERROR: '$INDEX' not found in $SCRIPT_DIR"
  exit 1
fi

if [ -z "$STATICRYPT_PASSWORD" ]; then
  echo "ERROR: STATICRYPT_PASSWORD is empty. Set it in .env"
  exit 1
fi

write_theme_block() {
  local css_file="${SCRIPT_DIR}/theme/styles.css"

  if [ ! -f "$css_file" ]; then
    echo "ERROR: Theme file not found: $css_file"
    exit 1
  fi

  cat > "$THEME_TMP" <<EOF
<!-- STYLE_INJECT_START -->
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
$(cat "$css_file")
</style>
<!-- STYLE_INJECT_END -->
EOF
}

inject_theme() {
  file="$1"
  tmp_out=".index.with_theme.tmp.html"
  write_theme_block

  # If markers exist: replace block between markers.
  # Else: insert before </head>.
  if grep -q "<!-- STYLE_INJECT_START -->" "$file"; then
    awk -v theme_file="$THEME_TMP" '
      BEGIN {
        while ((getline line < theme_file) > 0) theme = theme line "\n";
        close(theme_file);
        inblock=0;
      }
      /<!-- STYLE_INJECT_START -->/ { inblock=1; printf "%s", theme; next }
      /<!-- STYLE_INJECT_END -->/   { inblock=0; next }
      inblock==0 { print }
    ' "$file" > "$tmp_out"
  else
    awk -v theme_file="$THEME_TMP" '
      BEGIN {
        while ((getline line < theme_file) > 0) theme = theme line "\n";
        close(theme_file);
      }
      /<\/head>/ && !done { printf "%s", theme; done=1 }
      { print }
    ' "$file" > "$tmp_out"
  fi

  mv -f "$tmp_out" "$file"

  # Wrap body content once (idempotent)
  if ! grep -q 'class="__wrap"' "$file"; then
    awk '
      BEGIN { inserted=0 }
      /<body[^>]*>/ && inserted==0 {
        print;
        print "<div class=\"__wrap\"><div class=\"__card\">";
        inserted=1;
        next
      }
      /<\/body>/ && inserted==1 {
        print "</div></div>";
        print;
        next
      }
      { print }
    ' "$file" > "$tmp_out"
    mv -f "$tmp_out" "$file"
  fi

  rm -f "$THEME_TMP" 2>/dev/null || true
}

sanitize_html() {
  file="$1"

  # Remove <base ...>
  perl -0777 -i -pe 's/<base\b[^>]*>\s*//ig' "$file"

  # Convert file URLs in href/src to basename (covers " and ')
  perl -0777 -i -pe 's/\b(href|src)=(["'"'"'])file:\/\/\/[^"'"'"']*\/([^\/"'"'"']+)\2/$1=$2$3$2/g' "$file"
  perl -0777 -i -pe 's/\b(href|src)=(["'"'"'])file:(?:\/\/localhost)?\/[^"'"'"']*\/([^\/"'"'"']+)\2/$1=$2$3$2/g' "$file"

  # GH Pages project pages fix: href="/NAME.html" -> href="NAME.html"
  perl -0777 -i -pe 's/\bhref=(["'"'"'])\/([^"'"'"']+\.html)\1/href=$1$2$1/g' "$file"
}

echo "0) Injecting theme into $INDEX"
inject_theme "$INDEX"

echo "1) SingleFile: embedding assets into $SINGLE"
"$SINGLEFILE_CMD" "$SINGLEFILE_PKG" $SINGLEFILE_ARGS "$INDEX" "$SINGLE"
sanitize_html "$SINGLE"

echo "2) Replace $INDEX with embedded version"
rm -f "$INDEX"
mv -f "$SINGLE" "$INDEX"

echo "3) Staticrypt: encrypting $INDEX"
rm -rf encrypted
mkdir -p encrypted

"$STATICRYPT_CMD" "$STATICRYPT_PKG" $STATICRYPT_ARGS -p "$STATICRYPT_PASSWORD" "$INDEX"

# Staticrypt output can be either:
# - encrypted/index.html
# - index_encrypted.html (in cwd)
OUT_A="encrypted/$INDEX"
OUT_B="index_encrypted.html"

echo "4) Copy encrypted output back to $INDEX"
if [ -f "$OUT_A" ]; then
  cp -f "$OUT_A" "./$INDEX"
elif [ -f "$OUT_B" ]; then
  mv -f "$OUT_B" "./$INDEX"
else
  echo "ERROR: Could not find staticrypt output. Expected '$OUT_A' or '$OUT_B'"
  echo "Directory listing:"
  ls -la
  [ -d encrypted ] && { echo "encrypted/ listing:"; ls -la encrypted; } || true
  exit 1
fi

# Final sanitize pass (Staticrypt generates new HTML)
sanitize_html "$INDEX"

# Sanity check
if grep -n "file:///" "$INDEX" >/dev/null 2>&1; then
  echo "WARNING: file:/// links still found in $INDEX"
  grep -n "file:///" "$INDEX" || true
  exit 2
fi

echo "Done. '$INDEX' is now themed + single-file + encrypted and ready for GitHub Pages."
