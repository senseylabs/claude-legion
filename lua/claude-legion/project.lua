local utils = require("claude-legion.utils")
local run = utils.run

local M = {}

--- djb2 hash truncated to 8 hex chars
local function hash(str)
  local h = 5381
  for i = 1, #str do
    h = ((h * 33) + str:byte(i)) % 0xFFFFFFFF
  end
  return string.format("%08x", h)
end

function M.get_project_root()
  local ok, project_nvim = pcall(require, "project_nvim.project")
  if ok then
    local root = project_nvim.get_project_root()
    if root then
      return root
    end
  end
  return vim.fn.getcwd()
end

function M.get_project_identity(path)
  path = path or M.get_project_root()

  -- Detect bare repo worktree setup via git
  local esc_path = vim.fn.shellescape(path)
  local ok_bare, bare_output = run("git -C " .. esc_path .. " rev-parse --is-bare-repository 2>/dev/null")
  local ok_common, common_dir = run("git -C " .. esc_path .. " rev-parse --git-common-dir 2>/dev/null")
  local ok_toplevel, toplevel = run("git -C " .. esc_path .. " rev-parse --show-toplevel 2>/dev/null")

  -- For bare repos with worktrees: common_dir is the bare repo, toplevel is the worktree
  -- For linked worktrees of non-bare repos: also show repo/worktree format
  if ok_common and ok_toplevel then
    local repo = vim.fn.fnamemodify(common_dir, ":t")
    local wt = vim.fn.fnamemodify(toplevel, ":t")

    -- Show repo/worktree format for bare repos or when common_dir differs from toplevel/.git
    local is_bare = ok_bare and vim.trim(bare_output) == "true"
    local common_outside_toplevel = not common_dir:find(toplevel .. "/", 1, true) and common_dir ~= toplevel
    if is_bare or common_outside_toplevel then
      return {
        repo = repo,
        worktree = wt,
        display = repo .. "/" .. wt,
      }
    end
  end

  -- Non-bare repo: just use directory name
  local name = vim.fn.fnamemodify(path, ":t")
  return {
    repo = name,
    worktree = nil,
    display = name,
  }
end

function M.get_session_name(path)
  path = path or M.get_project_root()
  local config = require("claude-legion.config")
  return config.options.tmux.session_prefix .. hash(path)
end

function M.list_all_sessions()
  local tmux = require("claude-legion.tmux")
  local sessions = tmux.list_sessions()
  local results = {}
  for _, session_name in ipairs(sessions) do
    local project_root = tmux.get_session_option(session_name, "@claude_project_root")
    local display_name = nil
    if project_root then
      local identity = M.get_project_identity(project_root)
      display_name = identity.display
    end
    table.insert(results, {
      session_name = session_name,
      project_root = project_root,
      display_name = display_name or session_name,
    })
  end
  return results
end

return M
