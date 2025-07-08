# Default target - run checks and tests
all: typecheck test

# Run all test files
test: deps/mini.nvim deps/plenary.nvim
	@echo "Running tests..."
	@nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" -c "qa!" 2>&1 | cat

# Run test from file at `$FILE` environment variable
test_file: deps/mini.nvim
	@echo "Running test file: $(FILE)"
	@nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')" -c "qa!" 2>&1 | cat

# Format Lua code with stylua
format:
	stylua lua scripts tests

# Run static analysis (primary type checking tool)
typecheck:
	@echo "Running static analysis with luacheck..."
	@luacheck lua scripts tests

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.nvim $@

deps/plenary.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim $@
