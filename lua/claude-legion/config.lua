local M = {}

M.defaults = {
  tmux = {
    popup_width = 90,
    popup_height = 90,
    session_prefix = "claude-legion-",
    popup_dismiss_key = "C-]",
  },
  cmd = "claude",
  keys = {
    toggle = "<leader>ac",
    new = "<leader>an",
    select = "<leader>at",
    send = "<leader>as",
    kill = "<leader>ak",
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

local function project_hash()
  local cwd = vim.fn.getcwd()
  -- Simple djb2 hash truncated to 8 hex chars
  local h = 5381
  for i = 1, #cwd do
    h = ((h * 33) + cwd:byte(i)) % 0xFFFFFFFF
  end
  return string.format("%08x", h)
end

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  -- Scope session prefix to project directory
  M.options.tmux.session_prefix = M.options.tmux.session_prefix .. project_hash() .. "-"
end

return M
