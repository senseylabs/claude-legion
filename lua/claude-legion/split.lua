local config = require("claude-legion.config")
local utils = require("claude-legion.utils")
local run = utils.run

local M = {}

local state = {
  pane_id = nil,
  current_session = nil,
}

-- Fix #13: suppress stderr on dead pane probe
local function pane_exists()
  if not state.pane_id then
    return false
  end
  local ok, _ = run("tmux display-message -t " .. vim.fn.shellescape(state.pane_id) .. " -p '#{pane_id}' 2>/dev/null")
  return ok
end

function M.open(session_name)
  session_name = session_name or state.current_session
  if not session_name then
    return
  end

  local tmux = require("claude-legion.tmux")
  if not tmux.is_tmux() then
    vim.notify("Claude Legion: not running inside tmux", vim.log.levels.ERROR)
    return
  end

  -- If pane already showing this session, just focus it
  if pane_exists() and state.current_session == session_name then
    run("tmux select-pane -t " .. vim.fn.shellescape(state.pane_id))
    return
  end

  -- If pane exists showing different session, kill it first
  if pane_exists() then
    run("tmux kill-pane -t " .. vim.fn.shellescape(state.pane_id))
    state.pane_id = nil
  end

  -- Ensure the claude-legion session exists before trying to attach
  if not tmux.session_exists(session_name) then
    vim.notify("Claude Legion: session " .. session_name .. " not found", vim.log.levels.WARN)
    return
  end

  -- Fix #8: use env -u TMUX instead of fragile TMUX='' shell escaping
  local width = math.floor(config.options.tmux.split_width * 100 + 0.5)
  local attach_cmd = "env -u TMUX tmux -L claude-legion attach-session -t " .. vim.fn.shellescape(session_name)

  -- Split and focus the new pane automatically
  local ok, output = run(
    "tmux split-window -h -l " .. width .. "% -P -F '#{pane_id}' " .. vim.fn.shellescape(attach_cmd)
  )
  if ok and output ~= "" then
    state.pane_id = vim.trim(output)
    state.current_session = session_name
  else
    vim.notify("Claude Legion: failed to open split pane" .. (output and (": " .. output) or ""), vim.log.levels.ERROR)
  end
end

-- Fix #5: close() clears current_session to prevent stale state
function M.close()
  if pane_exists() then
    run("tmux kill-pane -t " .. vim.fn.shellescape(state.pane_id))
  end
  state.pane_id = nil
  state.current_session = nil
  vim.cmd("silent! checktime")
end

function M.toggle(session_name)
  session_name = session_name or state.current_session
  if pane_exists() and state.current_session == session_name then
    M.close()
  else
    M.open(session_name)
  end
end

function M.is_open()
  return pane_exists()
end

function M.switch_session(session_name)
  if not pane_exists() then
    return
  end
  run("tmux kill-pane -t " .. vim.fn.shellescape(state.pane_id))
  state.pane_id = nil
  state.current_session = nil
  M.open(session_name)
end

function M.get_current_session()
  return state.current_session
end

function M.cleanup()
  if pane_exists() then
    run("tmux kill-pane -t " .. vim.fn.shellescape(state.pane_id))
  end
  state.pane_id = nil
  state.current_session = nil
end

return M
