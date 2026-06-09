#!/usr/bin/env bash
# Stoa server installer — bootstrap the hub on a fresh machine.
#
#   curl -fsSL https://raw.githubusercontent.com/a-athaullah/stoa/master/install.sh | bash
#   # or, from a clone:
#   ./install.sh
#
# Auto-detects the OS (Linux / macOS / Windows-via-WSL or Git Bash), checks
# prerequisites, fetches the code, installs deps, then runs `node cli.js install`
# which links the `stoa` command and enables the background gateway service.
#
# Native Windows (PowerShell, no bash): use install.ps1 instead:
#   irm https://raw.githubusercontent.com/a-athaullah/stoa/master/install.ps1 | iex

set -e

# Repo to clone (only used when not already inside a checkout). Auto-detects from
# this script's git origin so it follows whatever fork you cloned; falls back to
# upstream. Override with STOA_REPO_URL.
detect_repo() {
  if [ -n "${STOA_REPO_URL:-}" ]; then echo "$STOA_REPO_URL"; return; fi
  local dir o
  dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  o="$(git -C "${dir:-.}" remote get-url origin 2>/dev/null || git remote get-url origin 2>/dev/null || true)"
  if [ -n "$o" ]; then echo "$o"; else echo "https://github.com/asharijuang/stoa"; fi
}
REPO_URL="$(detect_repo)"
# Managed app location (Hermes-style): code lives in ~/.stoa/app, data in ~/.stoa/server.
INSTALL_DIR="${STOA_DIR:-$HOME/.stoa/app}"
REPO_SLUG="$(echo "$REPO_URL" | sed -E 's#.*github\.com[:/]+##; s#\.git$##')"

# ── Detect OS ──────────────────────────────────────────────────────────────────
case "$(uname -s)" in
  Linux*)               OS=linux ;;
  Darwin*)              OS=mac ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *)                    OS=unknown ;;
esac
echo "=== Stoa installer ==="
echo "OS detected: ${OS}"

if [ "$OS" = "windows" ]; then
  echo "  (running under a bash shell on Windows — WSL works fully; native Git Bash"
  echo "   can't manage a background service. For native Windows use install.ps1.)"
elif [ "$OS" = "unknown" ]; then
  echo "  Unsupported OS. Proceeding anyway, but the gateway service may not install."
fi

# ── Check prerequisites ──────────────────────────────────────────────────────────
for cmd in git node npm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' not found. Install it first:"
    echo "  - Node.js 20+ (includes npm): https://nodejs.org/"
    echo "  - git: https://git-scm.com/"
    exit 1
  fi
done

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$NODE_MAJOR" -lt 20 ]; then
  echo "ERROR: Node 20+ required (found $(node -v)). Upgrade Node and re-run."
  exit 1
fi
echo "ok: node $(node -v), npm $(npm -v), git present"

# ── Get the code ────────────────────────────────────────────────────────────────
# Priority: current checkout (dev) → prebuilt GitHub release tarball (no build!) → git clone.
if [ -f "./cli.js" ] && [ -f "./server.js" ]; then
  INSTALL_DIR="$(pwd)"
  echo "[1/3] Using current checkout: ${INSTALL_DIR}"
elif [ -d "${INSTALL_DIR}/.git" ]; then
  echo "[1/3] Updating existing clone: ${INSTALL_DIR}"
  git -C "${INSTALL_DIR}" pull --ff-only || echo "  (pull skipped — local changes)"
else
  ASSET_URL="$(curl -fsSL "https://api.github.com/repos/${REPO_SLUG}/releases/latest" 2>/dev/null | grep -oE 'https://[^"]+\.tar\.gz' | head -1)"
  mkdir -p "${INSTALL_DIR}"
  if [ -n "${ASSET_URL}" ]; then
    echo "[1/3] Installing from latest release — prebuilt, no build: ${ASSET_URL##*/}"
    curl -fsSL "${ASSET_URL}" | tar xz -C "${INSTALL_DIR}" --strip-components=1
  else
    echo "[1/3] No release found for ${REPO_SLUG} — cloning source from ${REPO_URL}"
    rmdir "${INSTALL_DIR}" 2>/dev/null || true
    git clone "${REPO_URL}" "${INSTALL_DIR}"
  fi
  [ -n "${REPO_SLUG}" ] && echo "${REPO_SLUG}" > "${INSTALL_DIR}/.stoa-source" 2>/dev/null || true
fi
cd "${INSTALL_DIR}"

# ── Install dependencies (runtime only — no esbuild, no compile spike) ───────────
echo "[2/3] Installing dependencies…"
npm install --omit=dev --no-audit --no-fund

# ── Bootstrap: link the `stoa` command + enable the gateway ───────────────────────
echo "[3/3] Bootstrapping (link command + enable gateway)…"
node cli.js install

echo ""
echo "=== Done ==="
echo "Open the dashboard:  stoa dashboard"
echo "Check status:        stoa gateway status"
echo "Stop the server:     stoa gateway stop"
echo ""
echo "If 'stoa' isn't found, restart your shell or run: npm link  (from ${INSTALL_DIR})"
