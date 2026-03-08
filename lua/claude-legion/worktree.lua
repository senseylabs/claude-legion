local utils = require("claude-legion.utils")
local run = utils.run

local M = {}

function M.sanitize_branch(name)
  return name:gsub("/", "-"):gsub("[^%w%-%._]", "")
end

function M.get_bare_root()
  local ok, git_common_dir = run("git rev-parse --git-common-dir")
  if not ok then
    return nil
  end
  -- Resolve to absolute path
  if not git_common_dir:match("^/") then
    git_common_dir = vim.fn.fnamemodify(vim.fn.getcwd() .. "/" .. git_common_dir, ":p"):gsub("/$", "")
  end
  -- git-common-dir returns the bare repo root (both from bare root and worktrees)
  return git_common_dir
end

function M.list_worktrees()
  local ok, output = run("git worktree list --porcelain")
  if not ok then
    return {}
  end

  local worktrees = {}
  local current = {}

  for line in (output .. "\n\n"):gmatch("([^\n]*)\n") do
    if line:match("^worktree ") then
      -- Save previous entry before starting new one
      if current.path and not current.bare then
        table.insert(worktrees, current)
      end
      current = { path = line:match("^worktree (.+)") }
    elseif line:match("^HEAD ") then
      current.head = line:match("^HEAD (.+)")
    elseif line:match("^branch ") then
      current.branch = line:match("^branch refs/heads/(.+)")
    elseif line == "bare" then
      current.bare = true
    end
  end
  -- Save last entry
  if current.path and not current.bare then
    table.insert(worktrees, current)
  end

  return worktrees
end

--- Look up the branch name for a worktree by its path.
local function get_branch_for_worktree(path)
  local worktrees = M.list_worktrees()
  for _, wt in ipairs(worktrees) do
    if wt.path == path then
      return wt.branch
    end
  end
  return nil
end

function M.open_window(path, name)
  local ok, win_index = run("tmux display-message -p '#{window_index}'")
  if not ok then
    vim.notify("Failed to get tmux window index", vim.log.levels.ERROR)
    return
  end
  local cmd = string.format(
    "tmux new-window -a -t :%s -n %s -c %s",
    vim.fn.shellescape(win_index),
    vim.fn.shellescape(name),
    vim.fn.shellescape(path)
  )
  local success, _ = run(cmd)
  if not success then
    vim.notify("Failed to create tmux window", vim.log.levels.ERROR)
  end
end

function M.create_worktree(branch, base_branch)
  local bare_root = M.get_bare_root()
  if not bare_root then
    vim.notify("Not in a bare git repository", vim.log.levels.ERROR)
    return
  end

  local dir_name = M.sanitize_branch(branch)
  local path = bare_root .. "/" .. dir_name

  local cmd = string.format(
    "git worktree add %s -b %s %s",
    vim.fn.shellescape(path),
    vim.fn.shellescape(branch),
    vim.fn.shellescape(base_branch)
  )
  local ok, output = run(cmd)
  if not ok then
    vim.notify("Failed to create worktree: " .. output, vim.log.levels.ERROR)
    return
  end

  vim.notify("Created worktree: " .. dir_name, vim.log.levels.INFO)
  M.open_window(path, dir_name)
end

function M.create_prompt()
  vim.ui.input({ prompt = "Branch name: " }, function(branch)
    if not branch or branch == "" then
      return
    end
    -- Get current branch as default base
    local _, current_branch = run("git rev-parse --abbrev-ref HEAD")
    vim.ui.input({ prompt = "Base branch: ", default = current_branch }, function(base)
      if not base or base == "" then
        return
      end
      M.create_worktree(branch, base)
    end)
  end)
end

function M.remove_worktree(path, opts)
  opts = opts or {}
  local dir_name = vim.fn.fnamemodify(path, ":t")
  -- Query the actual branch name from git worktree metadata
  local branch = get_branch_for_worktree(path)

  local function do_remove()
    local ok, output = run("git worktree remove --force " .. vim.fn.shellescape(path))
    if not ok then
      vim.notify("Failed to remove worktree: " .. output, vim.log.levels.ERROR)
      return
    end
    -- Delete the branch if we found one
    if branch then
      run("git branch -D " .. vim.fn.shellescape(branch))
    end
    vim.notify("Removed worktree and branch: " .. dir_name, vim.log.levels.INFO)
    if opts.on_complete then
      opts.on_complete()
    end
  end

  vim.ui.input({ prompt = "Delete worktree '" .. dir_name .. "'? (y/n): " }, function(answer)
    if answer and answer:lower() == "y" then
      do_remove()
    end
  end)
end

function M.select_worktree()
  local worktrees = M.list_worktrees()

  local items = {}
  table.insert(items, { action = "create", label = "+ Create new worktree" })
  for _, wt in ipairs(worktrees) do
    local branch = wt.branch or "detached"
    local dir = vim.fn.fnamemodify(wt.path, ":t")
    table.insert(items, { worktree = wt, label = dir .. " [" .. branch .. "]" })
  end

  vim.ui.select(items, {
    prompt = "Worktrees",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    if choice.action == "create" then
      M.create_prompt()
    else
      -- Show open/delete submenu for selected worktree
      vim.ui.select({ "Open", "Delete" }, { prompt = choice.label }, function(action)
        if action == "Open" then
          local name = vim.fn.fnamemodify(choice.worktree.path, ":t")
          M.open_window(choice.worktree.path, name)
        elseif action == "Delete" then
          M.remove_worktree(choice.worktree.path, {
            on_complete = function()
              vim.schedule(function()
                M.select_worktree()
              end)
            end,
          })
        end
      end)
    end
  end)
end

return M
