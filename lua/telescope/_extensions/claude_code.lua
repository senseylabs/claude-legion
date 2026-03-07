local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  return
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local terminal = require("claude-legion.terminal")

local function claude_code_picker(opts)
  opts = opts or {}

  local instances = terminal.list()

  if #instances == 0 then
    terminal.create()
    return
  end

  pickers
    .new(opts, {
      prompt_title = "Claude Legion Instances",
      finder = finders.new_table({
        results = instances,
        entry_maker = function(entry)
          local display = string.format("[%s] %s (#%d)", entry.status, entry.name, entry.id)
          return {
            value = entry,
            display = display,
            ordinal = entry.name .. " " .. entry.status,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            terminal.show(selection.value.id)
          end
        end)

        map("i", "<C-n>", function()
          actions.close(prompt_bufnr)
          terminal.create()
        end)

        map("i", "<C-d>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            terminal.kill(selection.value.id)
            actions.close(prompt_bufnr)
            vim.schedule(function()
              claude_code_picker(opts)
            end)
          end
        end)

        map("i", "<C-r>", function()
          local selection = action_state.get_selected_entry()
          if selection then
            vim.ui.input({ prompt = "Rename: ", default = selection.value.name }, function(new_name)
              if new_name and new_name ~= "" then
                terminal.rename(selection.value.id, new_name)
                actions.close(prompt_bufnr)
                vim.schedule(function()
                  claude_code_picker(opts)
                end)
              end
            end)
          end
        end)

        return true
      end,
    })
    :find()
end

return telescope.register_extension({
  exports = {
    select = claude_code_picker,
  },
})
