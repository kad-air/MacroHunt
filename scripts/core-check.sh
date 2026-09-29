#!/usr/bin/env bash
# MacroHunt core check — fails loudly (non-zero exit) when the app's core logic is wrong.
#
#   scripts/core-check.sh              # offline checks + live Anthropic API checks
#   OFFLINE=1 scripts/core-check.sh    # offline checks only
#
# Compiles the app's platform-neutral sources (the Claude client, the photo downsampler,
# credentials/settings, the meal model) into a macOS CLI together with
# scripts/core-check/main.swift, then runs it:
#   offline  photo payloads stay under the API's 5 MB / 1568 px limits and upright;
#            Claude responses decode past a leading thinking block, and truncation,
#            refusals and HTTP errors surface as specific errors; a fresh install's
#            calorie goal is 2000 (it was 0); meal-type defaults.
#   live     needs ANTHROPIC_API_KEY. A text analyze call is checked against USDA values
#            for two large hard-boiled eggs, a photo analyze call must be accepted, and a
#            reflection must come back. This is what proves the model, effort and fallback
#            settings in ClaudeAPI.swift are accepted by the real API. About a cent per run.
#
# No simulator, no signing, nothing written to the keychain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${OUT_DIR:-/tmp/macrohunt-core-check}"
mkdir -p "$OUT_DIR"

SOURCES=(
  "$ROOT/MacroHunt/Models/Meal.swift"
  "$ROOT/MacroHunt/Services/ClaudeAPI.swift"
  "$ROOT/MacroHunt/Utilities/APIError.swift"
  "$ROOT/MacroHunt/Utilities/NetworkConfig.swift"
  "$ROOT/MacroHunt/Utilities/ImageDownsampler.swift"
  "$ROOT/MacroHunt/Utilities/CredentialsManager.swift"
  "$ROOT/MacroHunt/Utilities/KeychainHelper.swift"
  "$ROOT/scripts/core-check/main.swift"
)

echo "core-check: compiling app sources into a macOS CLI…"
xcrun --sdk macosx swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos15.0" \
  -o "$OUT_DIR/core-check" "${SOURCES[@]}"

exec "$OUT_DIR/core-check"
