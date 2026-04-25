#!/bin/sh
# Version bump script — single source of truth for all version references.
#
# Usage:
#   ./scripts/version-bump.sh 0.9.5         # bump VERSION + regen
#   ./scripts/version-bump.sh "$(cat VERSION)"  # regen-without-bump
#
# Mirrors the cyrius pattern (see cyrius/scripts/version-bump.sh):
# `VERSION` is the source of truth; `src/version_str.cyr` is
# AUTO-GENERATED from VERSION and committed. No source file embeds
# the version literal anywhere else — every module that needs the
# version reads `SANDHI_VERSION` (defined in the generated file).
#
# CI verifies drift by re-running this script with the current
# VERSION and checking `git diff` is clean.

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Current: $(cat VERSION)"
    exit 1
fi

NEW="$1"
OLD=$(cat VERSION | tr -d '[:space:]')

# 1. Always regenerate src/version_str.cyr — same-version invocations
#    are the documented "regenerate without bumping" path.
cat > src/version_str.cyr <<EOF
# src/version_str.cyr — AUTO-GENERATED from \`VERSION\` by
# \`scripts/version-bump.sh\`. Do NOT edit by hand; the next bump
# will overwrite. To regenerate without bumping, run:
#
#   sh scripts/version-bump.sh "\$(cat VERSION)"
#
# This file is the single source of truth for \`SANDHI_VERSION\`
# at runtime. Every module that needs the version reads this var
# (e.g. the User-Agent builder in \`src/http/client.cyr\`). Bump
# the literal here ONLY by running version-bump.sh; CI's drift
# check fails if VERSION and this file disagree.

var SANDHI_VERSION = "$NEW";
EOF

if [ "$NEW" = "$OLD" ]; then
    echo "Already at $OLD (regenerated src/version_str.cyr)"
    exit 0
fi

# 2. VERSION file (source of truth)
echo "$NEW" > VERSION

# 3. CHANGELOG.md — add new section after [Unreleased] if missing
if ! grep -q "^## \[$NEW\]" CHANGELOG.md 2>/dev/null; then
    sed -i "/^## \[Unreleased\]/a\\
\\
## [$NEW] — $(date +%Y-%m-%d)" CHANGELOG.md 2>/dev/null || true
fi

echo "$OLD -> $NEW"
echo ""
echo "Updated:"
echo "  VERSION"
echo "  src/version_str.cyr (regenerated)"
echo "  CHANGELOG.md (added section header — fill in entries manually)"
echo ""
echo "Next: regenerate dist/sandhi.cyr ('cyrius distlib') and commit"
echo "      everything together — CI's dist-drift + version-sync"
echo "      checks both gate the PR."
