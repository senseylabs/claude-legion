local terminal = require("claude-legion.terminal")

local M = {}

function M.select()
  local instances = terminal.list()

  if #instances == 0 then
    terminal.create()
    return
  end

  local items = {}
  for _, inst in ipairs(instances) do
    table.insert(items, {
      label = string.format("[%s] %s (#%d)", inst.status, inst.name, inst.id),
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
