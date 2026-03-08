local terminal = require("claude-legion.terminal")

local M = {}

function M.select()
  local instances = terminal.list()

  local items = {}
  for _, inst in ipairs(instances) do
    table.insert(items, {
      label = inst.id .. ". " .. (inst.persistent and "📌 " or "   ") .. inst.name,
      id = inst.id,
    })
  end

  vim.ui.select(items, {
    prompt = "Claude Legion Instances",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      terminal.show(choice.id)
    end
  end)
end

return M
