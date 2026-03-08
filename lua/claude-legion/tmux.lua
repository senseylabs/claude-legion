local utils = require("claude-legion.utils")
local run = utils.run
local run_async = utils.run_async

local M = {}

local SERVER = "claude-legion"
-- Use a high numeric index to avoid colliding with user hooks (tmux arrays are numeric)
local HOOK_INDEX = 99

local function srv(tmux_args)
  return "tmux -L " .. SERVER .. " " .. tmux_args
end

local function srv_async(tmux_args)
  run_async(srv(tmux_args))
end

local function build_key_bindings(detach_key)
  local parts = { "bind-key -n " .. detach_key .. " detach-client" }
  for i = 1, 9 do
    table.insert(parts, "bind-key -n M-" .. i .. " select-window -t :" .. i)
  end
  return table.concat(parts, " \\; ")
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
  local window_id
  if not M.session_exists(session_name) then
    -- Batch: new-session + set-option + bind-keys + move-window in one call
    local esc_name = vim.fn.shellescape(session_name)
    local chain = "new-session -d -s " .. esc_name
      .. " \\; set-option -t " .. esc_name .. " status off"
      .. " \\; set-option -t " .. esc_name .. " base-index 1"
      .. " \\; " .. build_key_bindings(detach_key or "C-]")
      .. " \\; move-window -s " .. esc_name .. ":0 -t " .. esc_name .. ":1"
    local ok, _ = run(srv(chain))
    if not ok then
      return nil
    end
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
    vim.fn.shellescape("TMUX='' " .. attach_cmd .. " || true")
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

--- Fetch window index, persistent flag, and name in a single tmux call.
--- Returns a list of { id = number, persistent = bool, name = string|nil }.
function M.list_windows_full(session_name)
  local sep = "|||"
  local fmt = "#{window_index}" .. sep .. "#{@claude_persistent}" .. sep .. "#{@claude_name}"
  local ok, output = run(srv("list-windows -t " .. vim.fn.shellescape(session_name) .. " -F " .. vim.fn.shellescape(fmt)))
  if not ok then
    return {}
  end
  local results = {}
  for line in output:gmatch("[^\n]+") do
    local idx_str, persist_str, name_str = line:match("^(.-)|||(.-)|||(.*)$")
    local idx = tonumber(vim.trim(idx_str or ""))
    if idx then
      local name = (name_str and vim.trim(name_str) ~= "") and vim.trim(name_str) or nil
      table.insert(results, {
        id = idx,
        persistent = vim.trim(persist_str or "") == "1",
        name = name,
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

function M.is_persistent(session_name, window_id)
  local target = session_name .. ":" .. window_id
  local ok, output = run(srv("show-options -wv -t " .. vim.fn.shellescape(target) .. " @claude_persistent"))
  return ok and vim.trim(output) == "1"
end

function M.set_name(session_name, window_id, name)
  local target = session_name .. ":" .. window_id
  srv_async("set-option -w -t " .. vim.fn.shellescape(target) .. " @claude_name " .. vim.fn.shellescape(name))
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
  run_async("tmux set-option -w @claude_popup " .. vim.fn.shellescape(session_name))
end

function M.clear_popup_window()
  run_async("tmux set-option -wu @claude_popup")
end

function M.setup_popup_auto_close(width, height)
  -- Write a hook script that reopens the popup if the target window had one open
  local script_path = vim.fn.stdpath("data") .. "/claude-legion-hook.sh"
  local script = string.format([[#!/bin/sh
sess=$(tmux display-message -p '#{@claude_popup}')
if [ -n "$sess" ]; then
  tmux display-popup -w %d%% -h %d%% -E "TMUX='' tmux -L claude-legion attach-session -t \"$sess\" || true"
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
  -- Use a hook array entry to avoid clobbering user hooks
  -- Quote the hook name to prevent shell glob expansion of [N]
  local hook_name = vim.fn.shellescape("after-select-window[" .. HOOK_INDEX .. "]")
  run("tmux set-hook -g " .. hook_name .. " " .. vim.fn.shellescape("run-shell " .. script_path))
end

function M.cleanup_popup_auto_close()
  local hook_name = vim.fn.shellescape("after-select-window[" .. HOOK_INDEX .. "]")
  run_async("tmux set-hook -gu " .. hook_name)
end

function M.setup_toggle_key(key, width, height)
  -- Bind key in outer tmux to reopen popup when it's closed.
  -- When popup is open, the inner tmux catches the key and detaches (closing popup).
  -- When popup is closed, the outer tmux catches the key and reopens it.
  local script_path = vim.fn.stdpath("data") .. "/claude-legion-toggle.sh"
  local script = string.format([[#!/bin/sh
sess=$(tmux display-message -p '#{@claude_popup}')
if [ -n "$sess" ]; then
  tmux display-popup -w %d%% -h %d%% -E "TMUX='' tmux -L claude-legion attach-session -t \"$sess\" || true"
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
  run_async("tmux unbind-key -n " .. key)
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
