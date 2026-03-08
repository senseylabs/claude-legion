local config = require("claude-legion.config")
local tmux = require("claude-legion.tmux")

local M = {}

local state = {
  instances = {},
  counter = 0,
  current_id = nil,
}

local function session_name()
  return config.options.tmux.session_name
end

local function rebuild_state()
  local sname = session_name()
  if not tmux.session_exists(sname) then
    state.instances = {}
    state.counter = 0
    state.current_id = nil
    return
  end
  local old_current = state.current_id
  local new_instances = {}
  local max_id = 0
  -- Single tmux call to fetch all window data
  local windows = tmux.list_windows_full(sname)
  for _, win in ipairs(windows) do
    new_instances[win.id] = {
      id = win.id,
      session = sname,
      name = win.name or "claude",
      persistent = win.persistent,
    }
    if win.id > max_id then
      max_id = win.id
    end
  end
  state.instances = new_instances
  -- Never decrease counter to avoid name collisions
  if max_id > state.counter then
    state.counter = max_id
  end
  -- Preserve current_id if it still exists, otherwise pick highest
  if old_current and new_instances[old_current] then
    state.current_id = old_current
  else
    state.current_id = max_id > 0 and max_id or nil
  end
end

function M.create(name, opts)
  opts = opts or {}
  if not tmux.is_tmux() then
    vim.notify("Claude Legion requires tmux", vim.log.levels.ERROR)
    return nil
  end

  if vim.fn.executable(config.options.cmd) == 0 then
    vim.notify("'" .. config.options.cmd .. "' not found in PATH", vim.log.levels.ERROR)
    return nil
  end

  state.counter = state.counter + 1
  name = name or "claude"

  local sname = session_name()
  local window_id = tmux.create_window(sname, config.options.cmd, config.options.tmux.popup_dismiss_key)
  if not window_id then
    vim.notify("Failed to create tmux window", vim.log.levels.ERROR)
    return nil
  end

  state.instances[window_id] = {
    id = window_id,
    session = sname,
    name = name,
    persistent = false,
  }
  tmux.set_name(sname, window_id, name)
  state.current_id = window_id

  if not opts.background then
    M.show(window_id)
  end
  return window_id
end

function M.toggle(id)
  id = id or state.current_id

  if not id or not state.instances[id] then
    return M.create()
  end

  if not tmux.window_exists(session_name(), id) then
    M.kill(id)
    return M.create()
  end

  M.show(id)
end

function M.show(id)
  M.reconnect()
  id = id or state.current_id
  if not id or not state.instances[id] then
    return
  end

  local opts = config.options.tmux
  tmux.display_popup(session_name(), id, opts.popup_width, opts.popup_height)
  state.current_id = id
end

function M.hide()
  tmux.close_popup()
  vim.cmd("silent! checktime")
end

function M.kill(id)
  id = id or state.current_id
  if not id or not state.instances[id] then
    return
  end

  if tmux.window_exists(session_name(), id) then
    tmux.kill_window(session_name(), id)
  end
  tmux.clear_popup_window()

  -- Renumber remaining windows sequentially and rebuild state
  tmux.renumber_windows(session_name())
  rebuild_state()
end

function M.move(from_id, to_id)
  if not from_id or not state.instances[from_id] then
    return
  end
  if not to_id or to_id < 1 then
    return
  end
  local sname = session_name()
  if not tmux.window_exists(sname, from_id) then
    return
  end
  tmux.swap_windows(sname, from_id, to_id)
  rebuild_state()
end

function M.send(id, text)
  id = id or state.current_id
  if not id or not state.instances[id] then
    vim.notify("No Claude Code instance to send to", vim.log.levels.WARN)
    return
  end

  if not tmux.window_exists(session_name(), id) then
    vim.notify("Claude Code instance has exited", vim.log.levels.WARN)
    return
  end

  local sname = session_name()
  if text:find("\n") then
    tmux.send_text(sname, id, text)
  else
    tmux.send_keys(sname, id, text)
  end
  M.show(id)
end

function M.rename(id, new_name)
  if not id or not state.instances[id] then
    return
  end
  state.instances[id].name = new_name
  tmux.set_name(session_name(), id, new_name)
end

function M.persist(id)
  id = id or state.current_id
  if not id or not state.instances[id] then
    return
  end
  local instance = state.instances[id]
  instance.persistent = not instance.persistent
  tmux.set_persistent(session_name(), id, instance.persistent)
  local label = instance.persistent and "persistent" or "ephemeral"
  vim.notify(instance.name .. " is now " .. label, vim.log.levels.INFO)
end

function M.persist_all()
  local any_unpinned = false
  for _, instance in pairs(state.instances) do
    if not instance.persistent then
      any_unpinned = true
      break
    end
  end
  -- If any unpinned, pin all. If all pinned, unpin all.
  local new_state = any_unpinned
  local sname = session_name()
  for _, instance in pairs(state.instances) do
    instance.persistent = new_state
    tmux.set_persistent(sname, instance.id, new_state)
  end
  vim.notify(new_state and "All sessions pinned" or "All sessions unpinned", vim.log.levels.INFO)
end

function M.list()
  M.reconnect()
  local result = {}
  local sname = session_name()
  for _, instance in pairs(state.instances) do
    local alive = tmux.window_exists(sname, instance.id)
    table.insert(result, {
      id = instance.id,
      name = instance.name,
      status = alive and "alive" or "dead",
      persistent = instance.persistent,
    })
  end
  table.sort(result, function(a, b)
    return a.id < b.id
  end)
  return result
end

function M.get_current_id()
  return state.current_id
end

function M.reconnect()
  local sname = session_name()
  if not tmux.session_exists(sname) then
    return
  end
  -- Single tmux call to fetch all window data
  local windows = tmux.list_windows_full(sname)
  for _, win in ipairs(windows) do
    if not state.instances[win.id] then
      state.instances[win.id] = {
        id = win.id,
        session = sname,
        name = win.name or "claude",
        persistent = win.persistent,
      }
      if win.id > state.counter then
        state.counter = win.id
      end
      if not state.current_id then
        state.current_id = win.id
      end
    end
  end
end

function M.kill_all()
  -- Collect IDs to kill first to avoid mutating state.instances while iterating
  local to_kill = {}
  local has_persistent = false
  for id, instance in pairs(state.instances) do
    if instance.persistent then
      has_persistent = true
    else
      table.insert(to_kill, id)
    end
  end
  for _, id in ipairs(to_kill) do
    M.kill(id)
  end
  if not has_persistent then
    tmux.kill_session(session_name())
  end
end

return M
