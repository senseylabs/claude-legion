local terminal = require("claude-legion.terminal")
local split = require("claude-legion.split")
local tmux = require("claude-legion.tmux")

local M = {}

function M.select()
  local instances = terminal.list_all()

  local items = {}
  for _, inst in ipairs(instances) do
    local type_icon = inst.type == "shell" and "🐚 " or "🤖 "
    table.insert(items, {
      label = (inst.persistent and "📌 " or "   ") .. type_icon .. inst.project_display .. " - " .. inst.name,
      id = inst.id,
      session_name = inst.session_name,
    })
  end

  vim.ui.select(items, {
    prompt = "Claude Legion Instances",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      tmux.select_window(choice.session_name, choice.id)
      split.open(choice.session_name)
    end
  end)
end

return M
