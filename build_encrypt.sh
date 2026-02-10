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

# Normalize password (fix CRLF + trim)
STATICRYPT_PASSWORD="$(printf '%s' "${STATICRYPT_PASSWORD:-}" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

sanitize_html() {
  file="$1"

  # Remove <base ...>
  perl -0777 -i -pe 's/<base\b[^>]*>\s*//ig' "$file"

  # Convert href/src file URLs to just the filename (covers " and ')
  perl -0777 -i -pe 's/\b(href|src)=(["'"'"'])file:\/\/\/[^"'"'"']*\/([^\/"'"'"']+)\2/$1=$2$3$2/g' "$file"
  perl -0777 -i -pe 's/\b(href|src)=(["'"'"'])file:(?:\/\/localhost)?\/[^"'"'"']*\/([^\/"'"'"']+)\2/$1=$2$3$2/g' "$file"

  # GitHub Pages Project Pages fix: href="/NAME.html" -> href="NAME.html"
  perl -0777 -i -pe 's/\bhref=(["'"'"'])\/([^"'"'"']+\.html)\1/href=$1$2$1/g' "$file"
}

if [ ! -f "$INDEX" ]; then
  echo "ERROR: '$INDEX' not found in $SCRIPT_DIR"
  exit 1
fi

echo "1) SingleFile: embedding assets into $SINGLE"
"$SINGLEFILE_CMD" "$SINGLEFILE_PKG" $SINGLEFILE_ARGS "$INDEX" "$SINGLE"
sanitize_html "$SINGLE"

echo "2) Replace $INDEX with embedded version"
rm -f "$INDEX"
mv -f "$SINGLE" "$INDEX"

echo "3) Staticrypt: encrypting $INDEX -> ./encrypted/"
rm -rf encrypted
mkdir -p encrypted

if [ -z "$STATICRYPT_PASSWORD" ]; then
  echo "ERROR: STATICRYPT_PASSWORD is empty. Set it in .env"
  exit 1
fi

"$STATICRYPT_CMD" "$STATICRYPT_PKG" $STATICRYPT_ARGS -p "$STATICRYPT_PASSWORD" "$INDEX"

# staticrypt with a single file sometimes outputs <name>_encrypted.html in cwd,
# and sometimes uses ./encrypted/. We support both.
OUT_A="encrypted/$INDEX"
OUT_B="index_encrypted.html"

echo "4) Copy encrypted output back to $INDEX"
if [ -f "$OUT_A" ]; then
  cp -f "$OUT_A" "./$INDEX"
elif [ -f "$OUT_B" ]; then
  mv -f "$OUT_B" "./$INDEX"
else
  echo "ERROR: Could not find staticrypt output. Expected '$OUT_A' or '$OUT_B'"
  ls -la
  [ -d encrypted ] && ls -la encrypted || true
  exit 1
fi

# Final sanitize pass (just in case)
sanitize_html "$INDEX"

# Sanity check
if grep -n "file:///" "$INDEX" >/dev/null 2>&1; then
  echo "WARNING: file:/// links still found in $INDEX"
  grep -n "file:///" "$INDEX" || true
  exit 2
fi

echo "Done. '$INDEX' is now single-file + encrypted and ready for GitHub Pages."
