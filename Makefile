# Run all test files
test: deps/mini.nvim deps/plenary.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run test from file at `$FILE` environment variable
test_file: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

# Format Lua code with stylua
format:
	stylua lua scripts tests

# Run type checking with lua-language-server (filters known Neovim/testing globals)
typecheck:
	@echo "Running type checking..."
	@lua-language-server --check lua 2>&1 | grep -v "Undefined global \`vim\`" | grep -v "Undefined global \`MiniTest\`" || true
	@lua-language-server --check scripts 2>&1 | grep -v "Undefined global \`vim\`" | grep -v "Undefined global \`MiniTest\`" || true  
	@lua-language-server --check tests 2>&1 | grep -v "Undefined global \`vim\`" | grep -v "Undefined global \`MiniTest\`" || true
	@echo "Type checking complete."

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/echasnovski/mini.nvim $@

deps/plenary.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim $@
