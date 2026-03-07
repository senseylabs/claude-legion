local config = require("claude-legion.config")

local M = {}

local state = {
  instances = {},
  counter = 0,
  current_id = nil,
}

local function get_win_config()
  local opts = config.options.window
  local width = math.floor(vim.o.columns * opts.width)
  local height = math.floor(vim.o.lines * opts.height)

  local row, col
  if opts.position == "top" then
    row = 0
    col = math.floor((vim.o.columns - width) / 2)
  elseif opts.position == "bottom" then
    row = vim.o.lines - height
    col = math.floor((vim.o.columns - width) / 2)
  else -- center
    row = math.floor((vim.o.lines - height) / 2)
    col = math.floor((vim.o.columns - width) / 2)
  end

  return {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = opts.border,
  }
end

local function open_float(buf)
  local win_config = get_win_config()
  local win = vim.api.nvim_open_win(buf, true, win_config)
  vim.api.nvim_set_option_value("winhl", "Normal:Normal,FloatBorder:FloatBorder", { win = win })
  return win
end

local function open_split(buf)
  local opts = config.options.window
  if opts.type == "vsplit" then
    vim.cmd("vsplit")
  else
    vim.cmd("split")
  end
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  return win
end

local function open_window(buf)
  local opts = config.options.window
  if opts.type == "float" then
    return open_float(buf)
  else
    return open_split(buf)
  end
end

function M.create(name)
  state.counter = state.counter + 1
  local id = state.counter
  name = name or ("claude-" .. id)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", "claude-legion", { buf = buf })

  local win = open_window(buf)

  vim.fn.termopen(config.options.cmd, {
    on_exit = function()
      if state.instances[id] then
        state.instances[id].exited = true
      end
    end,
  })

  vim.cmd("startinsert")

  state.instances[id] = {
    id = id,
    buf = buf,
    win = win,
    name = name,
    exited = false,
  }
  state.current_id = id

  return id
end

function M.toggle(id)
  id = id or state.current_id

  if not id or not state.instances[id] then
    return M.create()
  end

  local instance = state.instances[id]

  if instance.exited then
    M.kill(id)
    return M.create()
  end

  if instance.win and vim.api.nvim_win_is_valid(instance.win) then
    M.hide(id)
  else
    M.show(id)
  end
end

function M.show(id)
  id = id or state.current_id
  if not id or not state.instances[id] then
    return
  end

  local instance = state.instances[id]

  -- Hide any currently visible instance first (for float mode)
  if config.options.window.type == "float" and state.current_id and state.current_id ~= id then
    local current = state.instances[state.current_id]
    if current and current.win and vim.api.nvim_win_is_valid(current.win) then
      M.hide(state.current_id)
    end
  end

  if instance.win and vim.api.nvim_win_is_valid(instance.win) then
    vim.api.nvim_set_current_win(instance.win)
  else
    instance.win = open_window(instance.buf)
  end

  state.current_id = id
  vim.cmd("startinsert")
end

function M.hide(id)
  id = id or state.current_id
  if not id or not state.instances[id] then
    return
  end

  local instance = state.instances[id]
  if instance.win and vim.api.nvim_win_is_valid(instance.win) then
    vim.api.nvim_win_close(instance.win, true)
    instance.win = nil
  end
end

function M.kill(id)
  id = id or state.current_id
  if not id or not state.instances[id] then
    return
  end

  local instance = state.instances[id]

  M.hide(id)

  if vim.api.nvim_buf_is_valid(instance.buf) then
    vim.api.nvim_buf_delete(instance.buf, { force = true })
  end

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
  if instance.exited then
    vim.notify("Claude Code instance has exited", vim.log.levels.WARN)
    return
  end

  local chan = vim.b[instance.buf] and vim.b[instance.buf].terminal_job_id
  if not chan then
    vim.notify("No terminal channel found", vim.log.levels.ERROR)
    return
  end

  vim.api.nvim_chan_send(chan, text .. "\n")
  M.show(id)
end

function M.rename(id, new_name)
  if not id or not state.instances[id] then
    return
  end
  state.instances[id].name = new_name
end

function M.list()
  local result = {}
  for _, instance in pairs(state.instances) do
    local visible = instance.win and vim.api.nvim_win_is_valid(instance.win)
    local status
    if instance.exited then
      status = "exited"
    elseif visible then
      status = "visible"
    else
      status = "hidden"
    end
    table.insert(result, {
      id = instance.id,
      name = instance.name,
      status = status,
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

return M
