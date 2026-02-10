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
  cat > "$THEME_TMP" <<'EOF'
<!-- STYLE_INJECT_START -->
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root {
    color-scheme: light dark;
    --bg: #0b0c10;
    --panel: rgba(255,255,255,0.06);
    --text: rgba(255,255,255,0.92);
    --muted: rgba(255,255,255,0.68);
    --link: #7dd3fc;
    --border: rgba(255,255,255,0.12);
    --codebg: rgba(255,255,255,0.08);
    --shadow: 0 10px 30px rgba(0,0,0,0.35);
    --radius: 16px;
    --maxw: 880px;
  }

  @media (prefers-color-scheme: light) {
    :root {
      --bg: #f6f7fb;
      --panel: rgba(0,0,0,0.04);
      --text: rgba(0,0,0,0.86);
      --muted: rgba(0,0,0,0.62);
      --link: #0369a1;
      --border: rgba(0,0,0,0.10);
      --codebg: rgba(0,0,0,0.06);
      --shadow: 0 10px 30px rgba(0,0,0,0.10);
    }
  }

  html, body { height: 100%; }
  body {
    margin: 0;
    background: radial-gradient(1200px 700px at 20% -10%, rgba(125,211,252,0.18), transparent 60%),
                radial-gradient(900px 600px at 90% 10%, rgba(167,139,250,0.16), transparent 55%),
                var(--bg);
    color: var(--text);
    font: 16px/1.7 system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji";
    -webkit-font-smoothing: antialiased;
    text-rendering: optimizeLegibility;
  }

  .__wrap {
    max-width: var(--maxw);
    margin: 0 auto;
    padding: 36px 18px 64px;
  }

  .__card {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    box-shadow: var(--shadow);
    padding: 26px 22px;
    backdrop-filter: blur(8px);
  }

  h1, h2, h3, h4 {
    line-height: 1.2;
    letter-spacing: -0.015em;
    margin: 1.2em 0 0.4em;
  }
  h1 { font-size: 2.0rem; margin-top: 0; }
  h2 { font-size: 1.45rem; }
  h3 { font-size: 1.15rem; }

  p { margin: 0.75em 0; }
  small, .muted { color: var(--muted); }

  a {
    color: var(--link);
    text-underline-offset: 3px;
    text-decoration-thickness: 1px;
  }
  a:hover { text-decoration-thickness: 2px; }

  hr {
    border: none;
    border-top: 1px solid var(--border);
    margin: 22px 0;
  }

  ul, ol { padding-left: 1.25em; }
  li { margin: 0.35em 0; }

  blockquote {
    margin: 16px 0;
    padding: 12px 14px;
    border-left: 4px solid rgba(125,211,252,0.45);
    background: rgba(125,211,252,0.08);
    border-radius: 12px;
  }

  img, video {
    max-width: 100%;
    height: auto;
    border-radius: 14px;
    border: 1px solid var(--border);
  }

  table {
    width: 100%;
    border-collapse: collapse;
    border: 1px solid var(--border);
    border-radius: 14px;
    overflow: hidden;
    display: block;
  }
  th, td {
    padding: 10px 12px;
    border-bottom: 1px solid var(--border);
    vertical-align: top;
  }
  th { text-align: left; background: rgba(127,127,127,0.10); }

  code, pre {
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
    font-size: 0.95em;
  }
  code {
    padding: 0.15em 0.35em;
    border-radius: 8px;
    background: var(--codebg);
    border: 1px solid var(--border);
  }
  pre {
    padding: 14px 16px;
    border-radius: 14px;
    background: var(--codebg);
    border: 1px solid var(--border);
    overflow: auto;
  }
  pre code { border: none; background: transparent; padding: 0; }

  .__card > :first-child { margin-top: 0; }

  @media print {
    body { background: white; color: black; }
    .__card { box-shadow: none; background: white; }
    a { color: black; }
  }
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
