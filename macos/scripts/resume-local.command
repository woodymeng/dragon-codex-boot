#!/bin/bash
set -euo pipefail
# Works inside a checkout or alongside the exported Git bundle. No cloud credentials needed.
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'Run this entry on your local Mac. The current host is not macOS.' >&2
    exit 2
fi
if [[ "$(uname -m)" != arm64 ]]; then
    echo 'Use an Apple Silicon Mac and a native terminal (disable Open using Rosetta).' >&2
    exit 2
fi
if ! xcrun --find swift >/dev/null 2>&1 || ! xcrun --show-sdk-path >/dev/null 2>&1; then
    echo 'Install current Xcode Command Line Tools first: xcode-select --install' >&2
    exit 2
fi
script_root="$(cd "$(dirname "$0")" && pwd)"
candidate_root="$(cd "$script_root/../.." && pwd)"
bundle="$script_root/feat-macos-port.bundle"
if [[ -f "$bundle" ]]; then
    [[ -f "$script_root/BUNDLE_SHA256" ]] || { echo 'Missing BUNDLE_SHA256.' >&2; exit 2; }
    (cd "$script_root" && shasum -a 256 -c BUNDLE_SHA256)
    git bundle verify "$bundle" || {
        # Verification outside a Git repository needs an empty temporary repository.
        verify_root="$(mktemp -d "${TMPDIR:-/tmp}/dragon-bundle-check.XXXXXX")"
        git init -q "$verify_root"
        git -C "$verify_root" bundle verify "$bundle"
        # Retain this tiny directory; no broad deletion during recovery.
    }
    bundle_head="$(git bundle list-heads "$bundle" refs/heads/feat/macos-port)"
    expected_commit="${bundle_head%% *}"
    [[ "$expected_commit" =~ ^[a-f0-9]{40}$ ]] || { echo 'Bundle branch missing.' >&2; exit 2; }
    repo_root="${DRAGON_CODEX_LOCAL_ROOT:-$HOME/Developer/dragon-codex-boot-macos-${expected_commit:0:12}}"
    if [[ ! -e "$repo_root" ]]; then
        mkdir -p "$(dirname "$repo_root")"
        git clone --branch feat/macos-port "$bundle" "$repo_root"
        git -C "$repo_root" remote set-url origin https://github.com/woodymeng/dragon-codex-boot.git
    else
        [[ -d "$repo_root/.git" ]] || { echo "Destination exists: $repo_root" >&2; exit 2; }
        [[ "$(git -C "$repo_root" rev-parse HEAD)" == "$expected_commit" ]] || {
            echo 'Existing checkout differs. Set DRAGON_CODEX_LOCAL_ROOT to a new directory.' >&2; exit 2;
        }
    fi
elif [[ -f "$candidate_root/macos/Package.swift" && -d "$candidate_root/.git" ]]; then
    repo_root="$candidate_root"
else
    echo 'Keep this command next to feat-macos-port.bundle, or run it inside the repository.' >&2
    exit 2
fi
[[ "$(git -C "$repo_root" branch --show-current)" == feat/macos-port ]] || {
    echo 'Expected feat/macos-port. Select the intended branch in the local checkout.' >&2; exit 2;
}
log_root="$repo_root/build/local-resume-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$log_root"
exec > >(tee "$log_root/resume.log") 2>&1
trap 'resume_result=$?; echo "Stopped with exit $resume_result. Preserve logs: $log_root"; exit "$resume_result"' ERR
echo "Local repository: $repo_root"
echo "Branch/commit: $(git -C "$repo_root" branch --show-current) $(git -C "$repo_root" rev-parse HEAD)"
echo "Logs: $log_root and $repo_root/build/macos-ci-logs"

# Configure a new profile with the installed app's real identity; preserve any existing profile.
client_app='/Applications/Codex.app'
if [[ ! -f "$client_app/Contents/Info.plist" && -f '/Applications/ChatGPT.app/Contents/Info.plist' ]] \
    && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' '/Applications/ChatGPT.app/Contents/Info.plist')" == com.openai.codex ]]; then
    client_app='/Applications/ChatGPT.app'
fi
user_config="$HOME/Library/Application Support/DragonCodexBoot/launcher.json"
if [[ ! -e "$user_config" && -f "$client_app/Contents/Info.plist" ]]; then
    client_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$client_app/Contents/Info.plist")"
    mkdir -p "$(dirname "$user_config")"
    python3 - "$repo_root/macos/Resources/launcher.example.json" "$client_id" "$client_app" "$user_config" <<'PY'
import json
import sys
from pathlib import Path
config = json.loads(Path(sys.argv[1]).read_text())
config['bundleIdentifier'] = sys.argv[2]
config['applicationPath'] = sys.argv[3]
with open(sys.argv[4], 'x') as output:
    json.dump(config, output, indent=2)
    output.write('\n')
print('Created user configuration with the installed Codex bundle identifier.')
PY
fi
bash "$repo_root/macos/scripts/ci.sh"
app="$repo_root/build/macos-arm64/Dragon Codex Boot.app"
echo 'Actual compilation, core tests, AVFoundation playback, signature and packaging checks passed.'
echo 'Real Codex capture, AX movement, Esc and focus handoff still require desktop acceptance.'
echo "Enable this .app in System Settings > Privacy & Security > Accessibility and Screen Recording: $app"
echo 'Quit and relaunch after granting permissions. Keep this path fixed during acceptance.'
if [[ -z "$(git -C "$repo_root" status --porcelain)" ]] && command -v gh >/dev/null 2>&1 \
    && gh api repos/woodymeng/dragon-codex-boot --jq .permissions.push 2>/dev/null | /usr/bin/grep -qx true; then
    if git -C "$repo_root" -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -u origin feat/macos-port; then
        echo 'Branch pushed to your repository.'
    else
        echo 'Push failed. Local compilation and packages remain available; preserve this log.'
    fi
else
    echo 'Push skipped: local edits, no gh CLI, or no confirmed GitHub write access.'
fi
echo "Open this repository in a LOCAL Codex task: $repo_root"
echo 'Continue the real-window acceptance checklist in LOCAL_HANDOFF.md; diagnose failures from actual logs.'
open "$app"
