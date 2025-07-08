local api = vim.api

api.nvim_create_user_command("NeoJj", function(o)
  local neojj = require("neojj")
  neojj.open(require("neojj.lib.util").parse_command_args(o.fargs))
end, {
  nargs = "*",
  desc = "Open NeoJj",
  complete = function(arglead)
    local neojj = require("neojj")
    return neojj.complete(arglead)
  end,
})
