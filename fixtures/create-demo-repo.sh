#!/bin/bash
# Creates the demo repository with all required states

set -e

REPO_DIR="fixtures/demo-repo"

# Set deterministic environment for reproducible Change IDs
export JJ_USER="Test User"
export JJ_EMAIL="test@example.com"
export JJ_TIMESTAMP="2024-01-01T12:00:00Z"

# Clean up any existing repo
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

# Initialize repository
jj git init

# Create initial state - empty repo
echo "*.swp" > .gitignore
echo "temp/" >> .gitignore
jj describe -m "Initial commit"
jj bookmark create initial

# Create feature-start state - basic project structure
jj new -m "Add project structure"
mkdir -p src tests docs
cat > src/main.lua << 'EOF'
-- Main module
local M = {}

function M.hello()
    return "Hello from NeoJJ test"
end

return M
EOF

cat > src/utils.lua << 'EOF'
-- Utility functions
local U = {}

function U.format(str)
    return string.upper(str)
end

return U
EOF

cat > tests/test_main.lua << 'EOF'
-- Test file
local main = require('src.main')

assert(main.hello() == "Hello from NeoJJ test")
EOF

jj bookmark create feature-start

# Create conflict state
# Branch 1: Add config with one implementation
jj new initial -m "Add config (version 1)"
mkdir -p src
cat > src/config.lua << 'EOF'
-- Configuration v1
return {
    version = "1.0",
    feature_flag = true
}
EOF
jj bookmark create config-v1

# Branch 2: Add config with different implementation
jj new initial -m "Add config (version 2)"
mkdir -p src
cat > src/config.lua << 'EOF'
-- Configuration v2
return {
    version = "2.0",
    feature_flag = false,
    new_option = "added"
}
EOF
jj bookmark create config-v2

# Create merge with conflict
jj new config-v1
jj new config-v1 config-v2 -m "Merge: Add config versions"
jj bookmark create conflict-state

# Create multiple-changes state
jj new feature-start -m "Work in progress: multiple changes"

# Modify existing file
cat >> src/main.lua << 'EOF'

function M.new_feature()
    return "This is new"
end
EOF

# Delete a file
rm src/utils.lua

# Add new file
cat > tests/test_new.lua << 'EOF'
-- New test file
print("New test")
EOF

# Create untracked file
echo "temporary file" > temp.txt

jj bookmark create multiple-changes

# Create merge-state with resolved and unresolved conflicts
jj new feature-start -m "Modify main.lua"
echo "Additional content" >> src/main.lua
jj bookmark create modify-main

jj new feature-start -m "Add components"
echo "Different content" >> src/main.lua
mkdir -p src/components
echo "-- New component" > src/components/ui.lua
jj bookmark create add-components

jj new modify-main add-components -m "Merge: Features in progress"
# This creates a conflict in main.lua but not in ui.lua
jj bookmark create merge-state

echo "Demo repository created successfully!"
echo "Available bookmarks:"
jj bookmark list | cat
