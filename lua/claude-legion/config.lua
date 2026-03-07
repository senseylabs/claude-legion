local M = {}

M.defaults = {
  window = {
    type = "float",
    width = 0.9,
    height = 0.9,
    border = "rounded",
    position = "center",
  },
  cmd = "claude",
  keys = {
    toggle = "<leader>ac",
    new = "<leader>an",
    select = "<leader>at",
    send = "<leader>as",
    kill = "<leader>ak",
  },
  set_keymaps = true,
  telescope = {
    enabled = true,
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
