local M = {}

local SERVER = "claude-legion"
local server_initialized = false

local function run(cmd)
  local output = vim.fn.system(cmd)
  return vim.v.shell_error == 0, vim.trim(output)
end

local function srv(tmux_args)
  return "tmux -L " .. SERVER .. " " .. tmux_args
end

local function ensure_server()
  if server_initialized then
    return
  end
  -- The server starts automatically when a session is created.
  -- We set up a no-prefix binding so the user can detach (dismiss popup).
  -- This runs after the first session exists; bind-key is global per server.
  server_initialized = true
end

local function setup_detach_key(key)
  run(srv("bind-key -n " .. key .. " detach-client"))
end

function M.setup_quick_switch_keys()
  for i = 1, 9 do
    run(srv("bind-key -n M-" .. i .. " switch-client -t '#{s/-[0-9]+$/-" .. i .. "/:session_name}'"))
  end
end

function M.is_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

function M.create_session(name, cmd, detach_key)
  ensure_server()
  local ok, _ = run(srv("new-session -d -s " .. vim.fn.shellescape(name)))
  if not ok then
    return false
  end
  -- Hide status bar so popup looks clean
  run(srv("set-option -t " .. vim.fn.shellescape(name) .. " status off"))
  -- Set up detach key (idempotent, global to server)
  setup_detach_key(detach_key or "C-]")
  -- Set up quick-switch keys (idempotent, runs after server exists)
  M.setup_quick_switch_keys()
  -- Start the command
  run(srv("send-keys -t " .. vim.fn.shellescape(name) .. " " .. vim.fn.shellescape(cmd) .. " Enter"))
  return true
end

function M.session_exists(name)
  local ok, _ = run(srv("has-session -t " .. vim.fn.shellescape(name)))
  return ok
end

function M.kill_session(name)
  run(srv("kill-session -t " .. vim.fn.shellescape(name)))
end

function M.display_popup(session_name, width, height)
  M.mark_popup_window(session_name)
  local attach_cmd = "tmux -L " .. SERVER .. " attach-session -t " .. vim.fn.shellescape(session_name)
  local cmd = string.format(
    "tmux display-popup -w %d%% -h %d%% -E %s",
    width,
    height,
    vim.fn.shellescape("TMUX='' " .. attach_cmd)
  )
  vim.fn.jobstart(cmd)
end

function M.close_popup()
  M.clear_popup_window()
  run("tmux display-popup -C")
end

function M.send_keys(session_name, text)
  run(srv("send-keys -t " .. vim.fn.shellescape(session_name) .. " -l " .. vim.fn.shellescape(text)))
  run(srv("send-keys -t " .. vim.fn.shellescape(session_name) .. " Enter"))
end

function M.list_sessions(prefix)
  local ok, output = run(srv("list-sessions -F '#{session_name}'"))
  if not ok then
    return {}
  end
  local sessions = {}
  for line in output:gmatch("[^\n]+") do
    local name = vim.trim(line)
    if not prefix or name:sub(1, #prefix) == prefix then
      table.insert(sessions, name)
    end
  end
  return sessions
end

function M.kill_server()
  run(srv("kill-server"))
end

function M.set_persistent(session_name, persistent)
  if persistent then
    run(srv("set-environment -t " .. vim.fn.shellescape(session_name) .. " CLAUDE_LEGION_PERSISTENT 1"))
  else
    run(srv("set-environment -t " .. vim.fn.shellescape(session_name) .. " -u CLAUDE_LEGION_PERSISTENT"))
  end
end

function M.is_persistent(session_name)
  local ok, output = run(srv("show-environment -t " .. vim.fn.shellescape(session_name) .. " CLAUDE_LEGION_PERSISTENT"))
  return ok and output:match("=1") ~= nil
end

function M.set_name(session_name, name)
  run(srv("set-environment -t " .. vim.fn.shellescape(session_name) .. " CLAUDE_LEGION_NAME " .. vim.fn.shellescape(name)))
end

function M.get_name(session_name)
  local ok, output = run(srv("show-environment -t " .. vim.fn.shellescape(session_name) .. " CLAUDE_LEGION_NAME"))
  if ok then
    local name = output:match("=(.+)")
    if name and name ~= "" then
      return name
    end
  end
  return nil
end

function M.mark_popup_window(session_name)
  run("tmux set-option -w @claude_popup " .. vim.fn.shellescape(session_name))
end

function M.clear_popup_window()
  run("tmux set-option -wu @claude_popup")
end

function M.setup_popup_auto_close(width, height)
  -- Write a hook script that reopens the popup if the target window had one open
  local script_path = vim.fn.stdpath("data") .. "/claude-legion-hook.sh"
  local script = string.format([[#!/bin/sh
sess=$(tmux display-message -p '#{@claude_popup}')
if [ -n "$sess" ]; then
  tmux display-popup -w %d%% -h %d%% -E "TMUX='' tmux -L claude-legion attach-session -t \"$sess\""
else
  tmux display-popup -C 2>/dev/null
fi
]], width, height)
  local f = io.open(script_path, "w")
  if f then
    f:write(script)
    f:close()
    os.execute("chmod +x " .. vim.fn.shellescape(script_path))
  end
  run("tmux set-hook -g after-select-window " .. vim.fn.shellescape("run-shell " .. script_path))
end

function M.cleanup_popup_auto_close()
  run("tmux set-hook -gu after-select-window")
end

function M.send_text(session_name, text)
  local tmpfile = vim.fn.tempname()
  local f = io.open(tmpfile, "w")
  if not f then
    return
  end
  f:write(text)
  f:close()
  run(srv("load-buffer " .. vim.fn.shellescape(tmpfile)))
  run(srv("paste-buffer -t " .. vim.fn.shellescape(session_name)))
  os.remove(tmpfile)
end

return M
