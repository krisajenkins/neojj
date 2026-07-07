-- Health check for NeoJJ, surfaced via `:checkhealth neojj`.
--
-- Neovim auto-discovers `lua/<plugin>/health.lua` on the runtimepath and calls
-- its exported `check()`, so no manual registration is needed.

local M = {}

-- Minimum supported versions. These mirror the Requirements section of the
-- README/vimdoc. They may tighten as the plugin grows; keep them in sync.
local MIN_NVIM = { 0, 9, 0 }
local MIN_JJ = { 0, 9, 0 }

-- Feature-detect the vim.health API. The `start/ok/warn/error/info` names are
-- Neovim 0.10+; earlier versions (we support >= 0.9.0) used `report_*`.
local health = vim.health
-- The report functions accept an optional advice arg (string|string[]); LLS's
-- bundled stub mistypes several as single-arg, so pin the shim's signature.
---@type table<string, fun(msg: string, advice?: string[])>
local h = {
	start = health.start or health.report_start,
	ok = health.ok or health.report_ok,
	warn = health.warn or health.report_warn,
	error = health.error or health.report_error,
	info = health.info or health.report_info,
}

-- Format a {major, minor, patch} table as "x.y.z".
local function version_string(v)
	return string.format("%d.%d.%d", v[1] or 0, v[2] or 0, v[3] or 0)
end

-- Return true when `parsed` (a vim.version() result) is older than the
-- {major, minor, patch} `minimum`.
local function is_older(parsed, minimum)
	return vim.version.cmp(parsed, minimum) < 0
end

local function check_neovim()
	local v = vim.version()
	local current = string.format("%d.%d.%d", v.major, v.minor, v.patch)
	if is_older({ v.major, v.minor, v.patch }, MIN_NVIM) then
		h.warn(string.format("Neovim %s is older than the minimum supported %s", current, version_string(MIN_NVIM)))
	else
		h.ok("Neovim " .. current)
	end
end

local function check_jj()
	-- vim.fn.exepath takes a single {name} argument; LLS's bundled vim stub
	-- mistypes it as zero-arg, so silence that false positive.
	---@diagnostic disable-next-line: redundant-parameter
	local jj_path = vim.fn.exepath("jj")
	if jj_path == "" then
		h.error("jj executable not found on PATH", {
			"Install Jujutsu: https://github.com/martinvonz/jj#installation",
		})
		return
	end

	-- `jj --version` prints e.g. "jj 0.43.0". Read it without going through
	-- plenary so this check stands on its own.
	local output = vim.fn.systemlist({ jj_path, "--version" })
	local version = nil
	for _, line in ipairs(output or {}) do
		version = line:match("(%d+%.%d+%.%d+)")
		if version then
			break
		end
	end

	if not version then
		h.warn("Found jj at " .. jj_path .. " but could not parse its version")
		return
	end

	local parsed = vim.version.parse(version)
	if parsed and is_older(parsed, MIN_JJ) then
		h.warn(
			string.format(
				"jj %s at %s is older than the minimum supported %s",
				version,
				jj_path,
				version_string(MIN_JJ)
			)
		)
	else
		h.ok(string.format("jj %s (%s)", version, jj_path))
	end
end

local function check_plenary()
	-- plenary.async and plenary.job are both used by the jj CLI integration.
	local missing = {}
	for _, mod in ipairs({ "plenary.async", "plenary.job" }) do
		if not pcall(require, mod) then
			table.insert(missing, mod)
		end
	end

	if #missing == 0 then
		h.ok("plenary.nvim is installed")
	else
		h.error("plenary.nvim is not available (missing: " .. table.concat(missing, ", ") .. ")", {
			"Install nvim-lua/plenary.nvim with your plugin manager",
		})
	end
end

function M.check()
	h.start("neojj")
	check_neovim()
	check_jj()
	check_plenary()
end

return M
