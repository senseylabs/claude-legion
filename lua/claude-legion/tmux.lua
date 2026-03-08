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
  server_initialized = true
end

local function setup_detach_key(key)
  run(srv("bind-key -n " .. key .. " detach-client"))
end

function M.setup_quick_switch_keys()
  for i = 1, 9 do
    run(srv("bind-key -n M-" .. i .. " select-window -t :" .. i))
  end
end

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

function M.create_window(session_name, cmd, detach_key)
  ensure_server()
  local window_id
  if not M.session_exists(session_name) then
    local ok, _ = run(srv("new-session -d -s " .. vim.fn.shellescape(session_name)))
    if not ok then
      return nil
    end
    -- Hide status bar so popup looks clean
    run(srv("set-option -t " .. vim.fn.shellescape(session_name) .. " status off"))
    -- Start window numbering at 1
    run(srv("set-option -t " .. vim.fn.shellescape(session_name) .. " base-index 1"))
    -- Set up server-global keys
    setup_detach_key(detach_key or "C-]")
    M.setup_quick_switch_keys()
    -- The default window is 0; move it to 1 (base-index)
    run(srv("move-window -s " .. vim.fn.shellescape(session_name) .. ":0 -t " .. vim.fn.shellescape(session_name) .. ":1"))
    window_id = 1
  else
    -- Create window at the end (after the highest index)
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
  -- Start the command
  local target = session_name .. ":" .. window_id
  run(srv("send-keys -t " .. vim.fn.shellescape(target) .. " " .. vim.fn.shellescape(cmd) .. " Enter"))
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

function M.display_popup(session_name, window_id, width, height)
  M.mark_popup_window(session_name)
  -- Pre-select the desired window
  run(srv("select-window -t " .. vim.fn.shellescape(session_name .. ":" .. window_id)))
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

function M.kill_server()
  run(srv("kill-server"))
end

function M.set_persistent(session_name, window_id, persistent)
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
  run(srv("set-option -w -t " .. vim.fn.shellescape(target) .. " @claude_name " .. vim.fn.shellescape(name)))
end

function M.get_name(session_name, window_id)
  local target = session_name .. ":" .. window_id
  local ok, output = run(srv("show-options -wv -t " .. vim.fn.shellescape(target) .. " @claude_name"))
  if ok and output ~= "" then
    return vim.trim(output)
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

function M.setup_toggle_key(key, width, height)
  -- Bind key in outer tmux to reopen popup when it's closed.
  -- When popup is open, the inner tmux catches the key and detaches (closing popup).
  -- When popup is closed, the outer tmux catches the key and reopens it.
  local script_path = vim.fn.stdpath("data") .. "/claude-legion-toggle.sh"
  local script = string.format([[#!/bin/sh
sess=$(tmux display-message -p '#{@claude_popup}')
if [ -n "$sess" ]; then
  tmux display-popup -w %d%% -h %d%% -E "TMUX='' tmux -L claude-legion attach-session -t \"$sess\""
fi
]], width, height)
  local f = io.open(script_path, "w")
  if f then
    f:write(script)
    f:close()
    os.execute("chmod +x " .. vim.fn.shellescape(script_path))
  end
  run("tmux bind-key -n " .. key .. " run-shell " .. vim.fn.shellescape(script_path))
end

function M.cleanup_toggle_key(key)
  run("tmux unbind-key -n " .. key)
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
