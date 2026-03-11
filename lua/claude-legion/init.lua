local M = {}

function M.setup(opts)
  local config = require("claude-legion.config")
  config.setup(opts)

  local terminal = require("claude-legion.terminal")
  local picker = require("claude-legion.picker")
  local project = require("claude-legion.project")
  local split = require("claude-legion.split")
  local tmux = require("claude-legion.tmux")

  -- Commands
  vim.api.nvim_create_user_command("ClaudeCode", function()
    terminal.toggle()
  end, { desc = "Toggle Claude Code instance" })

  vim.api.nvim_create_user_command("ClaudeCodeNew", function(cmd_opts)
    local name = cmd_opts.args ~= "" and cmd_opts.args or nil
    terminal.create(name)
  end, { nargs = "?", desc = "Create new Claude Code instance" })

  vim.api.nvim_create_user_command("ClaudeTerminal", function(cmd_opts)
    local name = cmd_opts.args ~= "" and cmd_opts.args or nil
    terminal.create(name, { shell = true })
  end, { nargs = "?", desc = "Create new plain terminal" })

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

  vim.api.nvim_create_user_command("ClaudeCodePersist", function()
    terminal.persist()
  end, { desc = "Toggle persistence on current Claude Code instance" })

  local worktree = require("claude-legion.worktree")

  vim.api.nvim_create_user_command("ClaudeWorktreeCreate", function()
    worktree.create_prompt()
  end, { desc = "Create new git worktree" })

  vim.api.nvim_create_user_command("ClaudeWorktreeList", function()
    local has_telescope, _ = pcall(require, "telescope")
    if has_telescope and config.options.telescope.enabled then
      require("telescope").extensions.claude_code.worktrees()
    else
      worktree.select_worktree()
    end
  end, { desc = "List git worktrees" })

  -- Keymaps
  if config.options.set_keymaps then
    local keys = config.options.keys
    vim.keymap.set("n", keys.toggle, "<cmd>ClaudeCode<cr>", { desc = "Toggle Claude Code" })
    vim.keymap.set("n", keys.new, "<cmd>ClaudeCodeNew<cr>", { desc = "New Claude Code instance" })
    vim.keymap.set("n", keys.select, "<cmd>ClaudeCodeSelect<cr>", { desc = "List all terminals" })
    vim.keymap.set("n", keys.terminal, "<cmd>ClaudeTerminal<cr>", { desc = "New plain terminal" })
    vim.keymap.set("v", keys.send, ":'<,'>ClaudeCodeSend<cr>", { desc = "Send to Claude Code" })
    vim.keymap.set("n", keys.kill, "<cmd>ClaudeCodeKill<cr>", { desc = "Kill Claude Code instance" })
    local wt_keys = config.options.worktree.keys
    vim.keymap.set("n", wt_keys.create, "<cmd>ClaudeWorktreeCreate<cr>", { desc = "Create git worktree" })
    vim.keymap.set("n", wt_keys.list, "<cmd>ClaudeWorktreeList<cr>", { desc = "List git worktrees" })

    -- Fix #10: guard quick-switch with session_exists check
    if keys.quick_switch then
      for i = 1, 9 do
        vim.keymap.set("n", "<M-" .. i .. ">", function()
          local sname = project.get_session_name(project.get_project_root())
          if not tmux.session_exists(sname) then
            return
          end
          tmux.select_window(sname, i)
          split.open(sname)
        end, { desc = "Switch to Claude Code instance " .. i })
      end
    end
  end

  -- Fix #4: DirChanged closes stale split when new project has no session
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("ClaudeLegionDirChanged", { clear = true }),
    callback = function()
      terminal.reconnect()
      if split.is_open() then
        local root = project.get_project_root()
        local sname = project.get_session_name(root)
        if tmux.session_exists(sname) then
          split.switch_session(sname)
        else
          split.close()
        end
      end
    end,
  })

  -- Re-adopt orphaned sessions and auto-open split if found
  local found = terminal.reconnect()
  if found and tmux.is_tmux() then
    vim.schedule(function()
      local sname = project.get_session_name(project.get_project_root())
      split.open(sname)
    end)
  end

  -- Close the split pane on exit (sessions persist in tmux)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("ClaudeLegionCleanup", { clear = true }),
    callback = function()
      split.cleanup()
    end,
  })

  -- Auto-reload files modified by Claude when switching back
  local augroup = vim.api.nvim_create_augroup("ClaudeLegionReload", { clear = true })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = augroup,
    callback = function()
      vim.cmd("silent! checktime")
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      vim.cmd("silent! checktime")
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
