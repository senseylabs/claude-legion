local M = {}

M.defaults = {
  tmux = {
    split_width = 0.40,
    session_prefix = "cl-",
  },
  cmd = "claude",
  keys = {
    toggle = "<leader>ac",
    new = "<leader>an",
    select = "<leader>aa",
    send = "<leader>as",
    kill = "<leader>ak",
    terminal = "<leader>at",
    quick_switch = true,
  },
  set_keymaps = true,
  telescope = {
    enabled = true,
  },
  worktree = {
    keys = {
      create = "<leader>wc",
      list = "<leader>wl",
    },
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
