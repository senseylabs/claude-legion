local config = require("claude-legion.config")
local tmux = require("claude-legion.tmux")
local project = require("claude-legion.project")
local split = require("claude-legion.split")

local M = {}

local state = { current_id = nil }

local function session_name()
  return project.get_session_name(project.get_project_root())
end

function M.create(name, opts)
  opts = opts or {}
  local is_shell = opts.shell or false

  if not is_shell and vim.fn.executable(config.options.cmd) == 0 then
    vim.notify("'" .. config.options.cmd .. "' not found in PATH", vim.log.levels.ERROR)
    return nil
  end

  name = name or (is_shell and "shell" or "claude")

  local sname = session_name()
  local cmd = not is_shell and config.options.cmd or nil
  local window_id = tmux.create_window(sname, cmd)
  if not window_id then
    vim.notify("Failed to create tmux window", vim.log.levels.ERROR)
    return nil
  end

  -- Store project root as session option for cross-project discovery (sync to avoid race)
  tmux.set_session_option_sync(sname, "@claude_project_root", project.get_project_root())

  -- Fix #6: use synchronous writes so metadata is committed before split.open()
  tmux.set_name_sync(sname, window_id, name)
  tmux.set_type_sync(sname, window_id, is_shell and "shell" or "claude")
  tmux.set_persistent_sync(sname, window_id, true)
  state.current_id = window_id

  if not opts.background then
    tmux.select_window(sname, window_id)
    split.open(sname)
  end
  return window_id
end

-- Fix #3: toggle() resets stale current_id before deciding what to do
function M.toggle(id)
  id = id or state.current_id
  local sname = session_name()

  if not id or not tmux.window_exists(sname, id) then
    -- current_id was stale or nil — try to find an existing window
    state.current_id = nil
    local windows = tmux.list_windows_full(sname)
    if #windows > 0 then
      -- Session has windows — show the last one (always open, never close)
      id = windows[#windows].id
      state.current_id = id
      tmux.select_window(sname, id)
      split.open(sname)
    else
      -- No windows at all — create a new instance
      if split.is_open() then
        split.close()
      end
      M.create()
    end
    return
  end

  -- Window exists — toggle the split
  tmux.select_window(sname, id)
  split.toggle(sname)
end

function M.show(id, target_session)
  local sname = target_session or session_name()
  id = id or state.current_id

  if not id or not tmux.window_exists(sname, id) then
    local windows = tmux.list_windows_full(sname)
    if #windows == 0 then
      return
    end
    id = windows[#windows].id
  end

  tmux.select_window(sname, id)
  split.open(sname)
  state.current_id = id
end

function M.hide()
  split.close()
end

function M.kill(id, target_session)
  local sname = target_session or session_name()
  id = id or state.current_id
  if not id or not tmux.window_exists(sname, id) then
    return
  end

  tmux.kill_window(sname, id)
  tmux.renumber_windows(sname)

  local windows = tmux.list_windows_full(sname)
  if #windows > 0 then
    state.current_id = windows[#windows].id
  else
    state.current_id = nil
  end
end

function M.move(from_id, to_id, target_session)
  if not from_id or not to_id or to_id < 1 then
    return
  end
  local sname = target_session or session_name()
  if not tmux.window_exists(sname, from_id) then
    return
  end
  tmux.swap_windows(sname, from_id, to_id)
end

function M.send(id, text)
  id = id or state.current_id
  local sname = session_name()
  if not id or not tmux.window_exists(sname, id) then
    vim.notify("No Claude Code instance to send to", vim.log.levels.WARN)
    return
  end

  if text:find("\n") then
    tmux.send_text(sname, id, text)
  else
    tmux.send_keys(sname, id, text)
  end
  tmux.select_window(sname, id)
  split.open(sname)
end

function M.rename(id, new_name, target_session)
  local sname = target_session or session_name()
  if not id or not tmux.window_exists(sname, id) then
    return
  end
  tmux.set_name(sname, id, new_name)
end

function M.persist(id, target_session)
  local sname = target_session or session_name()
  id = id or state.current_id
  if not id or not tmux.window_exists(sname, id) then
    return
  end
  local current = tmux.is_persistent(sname, id)
  local new_val = not current
  tmux.set_persistent(sname, id, new_val)
  local name = tmux.get_name(sname, id) or "claude"
  local label = new_val and "persistent" or "ephemeral"
  vim.notify(name .. " is now " .. label, vim.log.levels.INFO)
end

function M.persist_all()
  local sname = session_name()
  local windows = tmux.list_windows_full(sname)
  local any_unpinned = false
  for _, win in ipairs(windows) do
    if not win.persistent then
      any_unpinned = true
      break
    end
  end
  local new_val = any_unpinned
  for _, win in ipairs(windows) do
    tmux.set_persistent(sname, win.id, new_val)
  end
  vim.notify(new_val and "All sessions pinned" or "All sessions unpinned", vim.log.levels.INFO)
end

function M.list()
  local sname = session_name()
  local windows = tmux.list_windows_full(sname)
  local identity = project.get_project_identity()
  local result = {}
  for _, win in ipairs(windows) do
    table.insert(result, {
      id = win.id,
      name = win.name or "claude",
      status = "alive",
      persistent = win.persistent,
      type = win.type or "claude",
      session_name = sname,
      project_display = identity.display,
    })
  end
  return result
end

function M.list_all()
  local sessions = project.list_all_sessions()
  local results = {}
  for _, sess in ipairs(sessions) do
    local windows = tmux.list_windows_full(sess.session_name)
    for _, win in ipairs(windows) do
      table.insert(results, {
        id = win.id,
        name = win.name or "claude",
        persistent = win.persistent,
        type = win.type or "claude",
        session_name = sess.session_name,
        project_display = sess.display_name,
      })
    end
  end
  return results
end

function M.capture_pane(id, target_session)
  local sname = target_session or session_name()
  return tmux.capture_pane(sname, id)
end

function M.get_current_id()
  return state.current_id
end

--- Re-adopt orphaned sessions. Returns true if windows were found.
function M.reconnect()
  local sname = session_name()
  if not tmux.session_exists(sname) then
    state.current_id = nil
    return false
  end
  local windows = tmux.list_windows_full(sname)
  if #windows > 0 then
    state.current_id = windows[1].id
    return true
  else
    state.current_id = nil
    return false
  end
end

-- Fix #7: kill session directly instead of per-window loop (avoids renumber race)
function M.kill_all()
  local sname = session_name()
  if tmux.session_exists(sname) then
    tmux.kill_session(sname)
  end
  split.cleanup()
  state.current_id = nil
end

return M
