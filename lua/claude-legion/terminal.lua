local config = require("claude-legion.config")
local tmux = require("claude-legion.tmux")

local M = {}

local state = { current_id = nil }

local function session_name()
  return config.options.tmux.session_name
end

function M.create(name, opts)
  opts = opts or {}
  local is_shell = opts.shell or false

  if not tmux.is_tmux() then
    vim.notify("Claude Legion requires tmux", vim.log.levels.ERROR)
    return nil
  end

  if not is_shell and vim.fn.executable(config.options.cmd) == 0 then
    vim.notify("'" .. config.options.cmd .. "' not found in PATH", vim.log.levels.ERROR)
    return nil
  end

  name = name or (is_shell and "shell" or "claude")

  local sname = session_name()
  local cmd = not is_shell and config.options.cmd or nil
  local window_id = tmux.create_window(sname, cmd, config.options.tmux.popup_dismiss_key)
  if not window_id then
    vim.notify("Failed to create tmux window", vim.log.levels.ERROR)
    return nil
  end

  tmux.set_name(sname, window_id, name)
  tmux.set_type(sname, window_id, is_shell and "shell" or "claude")
  state.current_id = window_id

  if not opts.background then
    M.show(window_id)
  end
  return window_id
end

function M.toggle(id)
  id = id or state.current_id

  if not id or not tmux.window_exists(session_name(), id) then
    return M.create()
  end

  M.show(id)
end

function M.show(id)
  local sname = session_name()
  id = id or state.current_id

  -- If no current_id or it doesn't exist, discover from tmux
  if not id or not tmux.window_exists(sname, id) then
    local windows = tmux.list_windows_full(sname)
    if #windows == 0 then
      return
    end
    id = windows[#windows].id
  end

  local opts = config.options.tmux
  tmux.display_popup(sname, id, opts.popup_width, opts.popup_height)
  state.current_id = id
end

function M.hide()
  tmux.close_popup()
  vim.cmd("silent! checktime")
end

function M.kill(id)
  id = id or state.current_id
  local sname = session_name()
  if not id or not tmux.window_exists(sname, id) then
    return
  end

  tmux.kill_window(sname, id)
  tmux.clear_popup_window()

  -- Renumber remaining windows sequentially
  tmux.renumber_windows(sname)

  -- Update current_id from remaining windows
  local windows = tmux.list_windows_full(sname)
  if #windows > 0 then
    state.current_id = windows[#windows].id
  else
    state.current_id = nil
  end
end

function M.move(from_id, to_id)
  if not from_id or not to_id or to_id < 1 then
    return
  end
  local sname = session_name()
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
  M.show(id)
end

function M.rename(id, new_name)
  if not id or not tmux.window_exists(session_name(), id) then
    return
  end
  tmux.set_name(session_name(), id, new_name)
end

function M.persist(id)
  id = id or state.current_id
  local sname = session_name()
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
  -- If any unpinned, pin all. If all pinned, unpin all.
  local new_val = any_unpinned
  for _, win in ipairs(windows) do
    tmux.set_persistent(sname, win.id, new_val)
  end
  vim.notify(new_val and "All sessions pinned" or "All sessions unpinned", vim.log.levels.INFO)
end

function M.list()
  local sname = session_name()
  local windows = tmux.list_windows_full(sname)
  local result = {}
  for _, win in ipairs(windows) do
    table.insert(result, {
      id = win.id,
      name = win.name or "claude",
      status = "alive",
      persistent = win.persistent,
      type = win.type or "claude",
    })
  end
  return result
end

function M.capture_pane(id)
  return tmux.capture_pane(session_name(), id)
end

function M.get_current_id()
  return state.current_id
end

function M.reconnect()
  local sname = session_name()
  if not tmux.session_exists(sname) then
    return
  end
  if not state.current_id then
    local windows = tmux.list_windows_full(sname)
    if #windows > 0 then
      state.current_id = windows[1].id
    end
  end
end

function M.kill_all()
  local sname = session_name()
  local windows = tmux.list_windows_full(sname)
  local has_persistent = false
  for _, win in ipairs(windows) do
    if win.persistent then
      has_persistent = true
    else
      tmux.kill_window(sname, win.id)
    end
  end
  if has_persistent then
    tmux.renumber_windows(sname)
  else
    tmux.kill_session(sname)
  end
  tmux.clear_popup_window()
  state.current_id = nil
end

return M
