local config = require("claude-legion.config")
local tmux = require("claude-legion.tmux")

local M = {}

local state = {
  instances = {},
  counter = 0,
  current_id = nil,
}

local function session_name(id)
  return config.options.tmux.session_prefix .. id
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
  local id = state.counter
  name = name or ("claude-" .. id)

  local sname = session_name(id)
  if not tmux.create_session(sname, config.options.cmd, config.options.tmux.popup_dismiss_key) then
    vim.notify("Failed to create tmux session", vim.log.levels.ERROR)
    return nil
  end

  state.instances[id] = {
    id = id,
    session = sname,
    name = name,
    persistent = false,
  }
  tmux.set_name(sname, name)
  state.current_id = id

  if not opts.background then
    M.show(id)
  end
  return id
end

function M.toggle(id)
  M.reconnect()
  id = id or state.current_id

  if not id or not state.instances[id] then
    return M.create()
  end

  local instance = state.instances[id]
  if not tmux.session_exists(instance.session) then
    M.kill(id)
    return M.create()
  end

  M.show(id)
end

function M.show(id)
  id = id or state.current_id
  if not id or not state.instances[id] then
    return
  end

  local instance = state.instances[id]
  local opts = config.options.tmux

  tmux.display_popup(instance.session, opts.popup_width, opts.popup_height)
  state.current_id = id
end

function M.hide(id)
  tmux.close_popup()
  vim.cmd("silent! checktime")
end

function M.kill(id)
  id = id or state.current_id
  if not id or not state.instances[id] then
    return
  end

  local instance = state.instances[id]

  if tmux.session_exists(instance.session) then
    tmux.kill_session(instance.session)
  end
  tmux.clear_popup_window()

  state.instances[id] = nil

  if state.current_id == id then
    state.current_id = nil
    local max_id = nil
    for iid, _ in pairs(state.instances) do
      if not max_id or iid > max_id then
        max_id = iid
      end
    end
    state.current_id = max_id
  end
end

function M.send(id, text)
  id = id or state.current_id
  if not id or not state.instances[id] then
    vim.notify("No Claude Code instance to send to", vim.log.levels.WARN)
    return
  end

  local instance = state.instances[id]
  if not tmux.session_exists(instance.session) then
    vim.notify("Claude Code instance has exited", vim.log.levels.WARN)
    return
  end

  if text:find("\n") then
    tmux.send_text(instance.session, text)
  else
    tmux.send_keys(instance.session, text)
  end
  M.show(id)
end

function M.rename(id, new_name)
  if not id or not state.instances[id] then
    return
  end
  state.instances[id].name = new_name
  tmux.set_name(state.instances[id].session, new_name)
end

function M.persist(id)
  id = id or state.current_id
  if not id or not state.instances[id] then
    return
  end
  local instance = state.instances[id]
  instance.persistent = not instance.persistent
  tmux.set_persistent(instance.session, instance.persistent)
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
  for _, instance in pairs(state.instances) do
    instance.persistent = new_state
    tmux.set_persistent(instance.session, new_state)
  end
  vim.notify(new_state and "All sessions pinned" or "All sessions unpinned", vim.log.levels.INFO)
end

function M.list()
  M.reconnect()
  local result = {}
  for _, instance in pairs(state.instances) do
    local alive = tmux.session_exists(instance.session)
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
  local prefix = config.options.tmux.session_prefix
  local sessions = tmux.list_sessions(prefix)
  for _, sname in ipairs(sessions) do
    local id_str = sname:sub(#prefix + 1)
    local id = tonumber(id_str)
    if id and not state.instances[id] then
      local persistent = tmux.is_persistent(sname)
      local name = tmux.get_name(sname) or ("claude-" .. id)
      state.instances[id] = {
        id = id,
        session = sname,
        name = name,
        persistent = persistent,
      }
      if id > state.counter then
        state.counter = id
      end
      if not state.current_id then
        state.current_id = id
      end
    end
  end
end

function M.kill_all()
  local has_persistent = false
  for id, instance in pairs(state.instances) do
    if instance.persistent then
      has_persistent = true
    else
      M.kill(id)
    end
  end
  if not has_persistent then
    tmux.kill_server()
  end
end

return M
