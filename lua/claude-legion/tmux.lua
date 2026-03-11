local utils = require("claude-legion.utils")
local run = utils.run
local run_async = utils.run_async

local M = {}

local SERVER = "claude-legion"

local function srv(tmux_args)
  return "tmux -L " .. SERVER .. " " .. tmux_args
end

local function srv_async(tmux_args)
  run_async(srv(tmux_args))
end

-- Fix #11: removed dead build_key_bindings() — Alt-1..9 handled by Neovim keymaps in init.lua

function M.is_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

function M.session_exists(name)
  local ok, _ = run(srv("has-session -t " .. vim.fn.shellescape(name)))
  return ok
end

function M.window_exists(session_name, window_id)
  local target = session_name .. ":" .. window_id
  local ok, _ = run(srv("display-message -t " .. vim.fn.shellescape(target) .. " -p '#{window_index}'"))
  return ok
end

function M.create_window(session_name, cmd)
  local window_id
  if not M.session_exists(session_name) then
    local esc_name = vim.fn.shellescape(session_name)
    local chain = "new-session -d -s " .. esc_name
      .. " \\; set-option -t " .. esc_name .. " status off"
      .. " \\; set-option -t " .. esc_name .. " base-index 1"
    local ok, _ = run(srv(chain))
    if not ok then
      return nil
    end
    -- Move window 0→1 if needed (no-op if base-index 1 already placed it there)
    run(srv("move-window -s " .. esc_name .. ":0 -t " .. esc_name .. ":1"))
    window_id = 1
  else
    local windows = M.list_windows(session_name)
    local next_id = 1
    for _, idx in ipairs(windows) do
      if idx >= next_id then
        next_id = idx + 1
      end
    end
    local ok, _ = run(srv("new-window -t " .. vim.fn.shellescape(session_name) .. ":" .. next_id))
    if not ok then
      return nil
    end
    window_id = next_id
  end
  if cmd then
    local target = session_name .. ":" .. window_id
    run(srv("send-keys -t " .. vim.fn.shellescape(target) .. " " .. vim.fn.shellescape(cmd) .. " Enter"))
  end
  return window_id
end

function M.kill_window(session_name, window_id)
  local target = session_name .. ":" .. window_id
  run(srv("kill-window -t " .. vim.fn.shellescape(target)))
end

function M.renumber_windows(session_name)
  if not M.session_exists(session_name) then
    return
  end
  run(srv("move-window -r -s " .. vim.fn.shellescape(session_name) .. " -t " .. vim.fn.shellescape(session_name)))
end

function M.swap_windows(session_name, from_id, to_id)
  local src = session_name .. ":" .. from_id
  local dst = session_name .. ":" .. to_id
  run(srv("swap-window -s " .. vim.fn.shellescape(src) .. " -t " .. vim.fn.shellescape(dst)))
end

function M.kill_session(name)
  run(srv("kill-session -t " .. vim.fn.shellescape(name)))
end

function M.select_window(session_name, window_id)
  local target = session_name .. ":" .. window_id
  run(srv("select-window -t " .. vim.fn.shellescape(target)))
end

function M.list_sessions()
  local ok, output = run(srv("list-sessions -F '#{session_name}' 2>/dev/null"))
  if not ok then
    return {}
  end
  local sessions = {}
  for line in output:gmatch("[^\n]+") do
    local name = vim.trim(line)
    if name ~= "" then
      table.insert(sessions, name)
    end
  end
  return sessions
end

function M.set_session_option(session_name, key, value)
  srv_async("set-option -t " .. vim.fn.shellescape(session_name) .. " " .. key .. " " .. vim.fn.shellescape(value))
end

function M.set_session_option_sync(session_name, key, value)
  run(srv("set-option -t " .. vim.fn.shellescape(session_name) .. " " .. key .. " " .. vim.fn.shellescape(value)))
end

function M.get_session_option(session_name, key)
  local ok, output = run(srv("show-options -v -t " .. vim.fn.shellescape(session_name) .. " " .. key .. " 2>/dev/null"))
  if ok and output ~= "" then
    return vim.trim(output)
  end
  return nil
end

function M.get_active_window(session_name)
  local ok, output = run(srv("display-message -t " .. vim.fn.shellescape(session_name) .. " -p '#{window_index}'"))
  if ok then
    return tonumber(vim.trim(output))
  end
  return nil
end

function M.send_keys(session_name, window_id, text)
  local target = session_name .. ":" .. window_id
  run(srv("send-keys -t " .. vim.fn.shellescape(target) .. " -l " .. vim.fn.shellescape(text)))
  run(srv("send-keys -t " .. vim.fn.shellescape(target) .. " Enter"))
end

function M.list_windows(session_name)
  local ok, output = run(srv("list-windows -t " .. vim.fn.shellescape(session_name) .. " -F '#{window_index}'"))
  if not ok then
    return {}
  end
  local windows = {}
  for line in output:gmatch("[^\n]+") do
    local idx = tonumber(vim.trim(line))
    if idx then
      table.insert(windows, idx)
    end
  end
  return windows
end

function M.list_windows_full(session_name)
  local sep = "|||"
  local fmt = "#{window_index}" .. sep .. "#{@claude_persistent}" .. sep .. "#{@claude_name}" .. sep .. "#{@claude_type}"
  local ok, output = run(srv("list-windows -t " .. vim.fn.shellescape(session_name) .. " -F " .. vim.fn.shellescape(fmt)))
  if not ok then
    return {}
  end
  local results = {}
  for line in output:gmatch("[^\n]+") do
    local idx_str, persist_str, name_str, type_str = line:match("^(.-)|||(.-)|||(.-)|||(.*)$")
    local idx = tonumber(vim.trim(idx_str or ""))
    if idx then
      local name = (name_str and vim.trim(name_str) ~= "") and vim.trim(name_str) or nil
      local wtype = (type_str and vim.trim(type_str) ~= "") and vim.trim(type_str) or "claude"
      table.insert(results, {
        id = idx,
        persistent = vim.trim(persist_str or "") == "1",
        name = name,
        type = wtype,
      })
    end
  end
  return results
end

function M.kill_server()
  run(srv("kill-server"))
end

function M.set_persistent(session_name, window_id, persistent)
  local target = session_name .. ":" .. window_id
  if persistent then
    srv_async("set-option -w -t " .. vim.fn.shellescape(target) .. " @claude_persistent 1")
  else
    srv_async("set-option -wu -t " .. vim.fn.shellescape(target) .. " @claude_persistent")
  end
end

-- Synchronous variant for use during create() to avoid race conditions
function M.set_persistent_sync(session_name, window_id, persistent)
  local target = session_name .. ":" .. window_id
  if persistent then
    run(srv("set-option -w -t " .. vim.fn.shellescape(target) .. " @claude_persistent 1"))
  else
    run(srv("set-option -wu -t " .. vim.fn.shellescape(target) .. " @claude_persistent"))
  end
end

function M.is_persistent(session_name, window_id)
  local target = session_name .. ":" .. window_id
  local ok, output = run(srv("show-options -wv -t " .. vim.fn.shellescape(target) .. " @claude_persistent"))
  return ok and vim.trim(output) == "1"
end

function M.set_name(session_name, window_id, name)
  local target = session_name .. ":" .. window_id
  srv_async("set-option -w -t " .. vim.fn.shellescape(target) .. " @claude_name " .. vim.fn.shellescape(name))
end

-- Synchronous variant for use during create()
function M.set_name_sync(session_name, window_id, name)
  local target = session_name .. ":" .. window_id
  run(srv("set-option -w -t " .. vim.fn.shellescape(target) .. " @claude_name " .. vim.fn.shellescape(name)))
end

function M.set_type(session_name, window_id, wtype)
  local target = session_name .. ":" .. window_id
  srv_async("set-option -w -t " .. vim.fn.shellescape(target) .. " @claude_type " .. vim.fn.shellescape(wtype))
end

-- Synchronous variant for use during create()
function M.set_type_sync(session_name, window_id, wtype)
  local target = session_name .. ":" .. window_id
  run(srv("set-option -w -t " .. vim.fn.shellescape(target) .. " @claude_type " .. vim.fn.shellescape(wtype)))
end

function M.get_name(session_name, window_id)
  local target = session_name .. ":" .. window_id
  local ok, output = run(srv("show-options -wv -t " .. vim.fn.shellescape(target) .. " @claude_name"))
  if ok and output ~= "" then
    return vim.trim(output)
  end
  return nil
end

function M.capture_pane(session_name, window_id)
  local target = session_name .. ":" .. window_id
  local cmd = srv("capture-pane -t " .. vim.fn.shellescape(target) .. " -p -e")
  local output = vim.fn.system(cmd)
  if vim.v.shell_error == 0 then
    return output
  end
  return nil
end

function M.send_text(session_name, window_id, text)
  local target = session_name .. ":" .. window_id
  local tmpfile = vim.fn.tempname()
  local f = io.open(tmpfile, "w")
  if not f then
    return
  end
  f:write(text)
  f:close()
  run(srv("load-buffer " .. vim.fn.shellescape(tmpfile)))
  run(srv("paste-buffer -t " .. vim.fn.shellescape(target)))
  os.remove(tmpfile)
end

return M
