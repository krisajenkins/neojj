#!/bin/bash
# Generates fixture files from a demo JJ repository
# These fixtures are used for testing NeoJJ without relying on random change IDs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$SCRIPT_DIR/demo-repo"
OUTPUT_DIR="$PROJECT_ROOT/tests/fixtures/jj-outputs"

# Set deterministic environment
export JJ_USER="Test User"
export JJ_EMAIL="test@example.com"
export JJ_TIMESTAMP="2024-01-01T12:00:00Z"

# Ensure demo repo exists
if [ ! -d "$REPO_DIR/.jj" ]; then
    echo "Demo repository not found. Creating it first..."
    "$SCRIPT_DIR/create-demo-repo.sh"
fi

# Ensure output directory exists (don't delete - it may contain other fixtures)
mkdir -p "$OUTPUT_DIR"

cd "$REPO_DIR"

echo "Generating fixture files..."

# =============================================================================
# Helper function to capture command output
# =============================================================================
capture() {
    local bookmark="$1"
    local cmd_name="$2"
    shift 2
    local output_file="$OUTPUT_DIR/${bookmark}-${cmd_name}.txt"

    echo "  Capturing: $bookmark / $cmd_name"

    # Switch to bookmark state
    jj edit "$bookmark" 2>/dev/null || true

    # Run command and capture output
    "$@" > "$output_file" 2>&1 || true
}

capture_json() {
    local bookmark="$1"
    local cmd_name="$2"
    shift 2
    local output_file="$OUTPUT_DIR/${bookmark}-${cmd_name}.json"

    echo "  Capturing: $bookmark / $cmd_name (JSON)"

    # Switch to bookmark state
    jj edit "$bookmark" 2>/dev/null || true

    # Run command and capture output
    "$@" > "$output_file" 2>&1 || true
}

# =============================================================================
# Bookmark: initial (empty repo with just .gitignore)
# =============================================================================
echo ""
echo "=== State: initial ==="

capture "initial" "status" \
    jj --color never status

capture "initial" "log" \
    jj --color never log --limit 10

capture_json "initial" "log-json" \
    jj --color never log -r @ --template "json(self)" --no-graph

capture "initial" "show-at" \
    jj --color never show @

# =============================================================================
# Bookmark: feature-start (basic project structure)
# =============================================================================
echo ""
echo "=== State: feature-start ==="

capture "feature-start" "status" \
    jj --color never status

capture "feature-start" "log" \
    jj --color never log --limit 10

capture_json "feature-start" "log-json" \
    jj --color never log -r @ --template "json(self)" --no-graph

capture "feature-start" "show-at" \
    jj --color never show @

capture "feature-start" "diff-main-lua" \
    jj --color never diff --git src/main.lua

# =============================================================================
# Bookmark: multiple-changes (modified, deleted, added files)
# =============================================================================
echo ""
echo "=== State: multiple-changes ==="

capture "multiple-changes" "status" \
    jj --color never status

capture "multiple-changes" "log" \
    jj --color never log --limit 10

capture_json "multiple-changes" "log-json" \
    jj --color never log -r @ --template "json(self)" --no-graph

capture "multiple-changes" "show-at" \
    jj --color never show @

capture "multiple-changes" "diff-main-lua" \
    jj --color never diff --git src/main.lua

# =============================================================================
# Bookmark: conflict-state (merge with conflicts)
# =============================================================================
echo ""
echo "=== State: conflict-state ==="

capture "conflict-state" "status" \
    jj --color never status

capture "conflict-state" "log" \
    jj --color never log --limit 10

capture_json "conflict-state" "log-json" \
    jj --color never log -r @ --template "json(self)" --no-graph

capture "conflict-state" "show-at" \
    jj --color never show @

# =============================================================================
# Bookmark: merge-state (merge with resolved and unresolved conflicts)
# =============================================================================
echo ""
echo "=== State: merge-state ==="

capture "merge-state" "status" \
    jj --color never status

capture "merge-state" "log" \
    jj --color never log --limit 10

capture_json "merge-state" "log-json" \
    jj --color never log -r @ --template "json(self)" --no-graph

capture "merge-state" "show-at" \
    jj --color never show @

# =============================================================================
# Additional useful outputs
# =============================================================================
echo ""
echo "=== Additional outputs ==="

# Bookmark list (useful for validation)
jj --color never bookmark list > "$OUTPUT_DIR/bookmark-list.txt"
echo "  Captured: bookmark-list"

# Log with graph showing all bookmarks
jj edit initial 2>/dev/null || true
jj --color never log -r "all()" --limit 20 > "$OUTPUT_DIR/log-all.txt"
echo "  Captured: log-all"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Generated fixtures ==="
ls -la "$OUTPUT_DIR"

echo ""
echo "Done! Fixtures saved to: $OUTPUT_DIR"
