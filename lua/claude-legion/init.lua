local M = {}

function M.setup(opts)
  local config = require("claude-legion.config")
  config.setup(opts)

  local terminal = require("claude-legion.terminal")
  local picker = require("claude-legion.picker")

  -- Commands
  vim.api.nvim_create_user_command("ClaudeCode", function()
    terminal.toggle()
  end, { desc = "Toggle Claude Code instance" })

  vim.api.nvim_create_user_command("ClaudeCodeNew", function(cmd_opts)
    local name = cmd_opts.args ~= "" and cmd_opts.args or nil
    terminal.create(name)
  end, { nargs = "?", desc = "Create new Claude Code instance" })

  vim.api.nvim_create_user_command("ClaudeCodeSelect", function()
    local has_telescope, _ = pcall(require, "telescope")
    if has_telescope and config.options.telescope.enabled then
      require("telescope").extensions.claude_code.select()
    else
      picker.select()
    end
  end, { desc = "Select Claude Code instance" })

  vim.api.nvim_create_user_command("ClaudeCodeSend", function(cmd_opts)
    local lines
    if cmd_opts.range > 0 then
      lines = vim.api.nvim_buf_get_lines(0, cmd_opts.line1 - 1, cmd_opts.line2, false)
    else
      vim.notify("Select text first (visual mode)", vim.log.levels.WARN)
      return
    end
    local text = table.concat(lines, "\n")
    terminal.send(nil, text)
  end, { range = true, desc = "Send selection to Claude Code" })

  vim.api.nvim_create_user_command("ClaudeCodeKill", function()
    terminal.kill()
  end, { desc = "Kill current Claude Code instance" })

  -- Keymaps
  if config.options.set_keymaps then
    local keys = config.options.keys
    vim.keymap.set("n", keys.toggle, "<cmd>ClaudeCode<cr>", { desc = "Toggle Claude Code" })
    vim.keymap.set("n", keys.new, "<cmd>ClaudeCodeNew<cr>", { desc = "New Claude Code instance" })
    vim.keymap.set("n", keys.select, "<cmd>ClaudeCodeSelect<cr>", { desc = "Select Claude Code instance" })
    vim.keymap.set("v", keys.send, ":'<,'>ClaudeCodeSend<cr>", { desc = "Send to Claude Code" })
    vim.keymap.set("n", keys.kill, "<cmd>ClaudeCodeKill<cr>", { desc = "Kill Claude Code instance" })
  end

  -- Auto-reload files modified by Claude
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("ClaudeLegionReload", { clear = true }),
    callback = function()
      local buf_ft = vim.bo.filetype
      if buf_ft ~= "claude-legion" then
        vim.cmd("silent! checktime")
      end
    end,
  })

  -- Register telescope extension if available
  vim.schedule(function()
    local has_telescope, telescope = pcall(require, "telescope")
    if has_telescope and config.options.telescope.enabled then
      telescope.load_extension("claude_code")
    end
  end)
end

return M
