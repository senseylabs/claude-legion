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
local worktree = require("claude-legion.worktree")

local function claude_code_picker(opts, select_id)
  opts = opts or {}

  local instances = terminal.list()

  local default_selection = nil
  if select_id and #instances > 0 then
    for i, inst in ipairs(instances) do
      if inst.id == select_id then
        default_selection = i
        break
      end
    end
    -- If exact match not found (e.g. after delete), pick closest position
    if not default_selection then
      for i, inst in ipairs(instances) do
        if inst.id >= select_id then
          default_selection = i
          break
        end
      end
      -- If all remaining are before the deleted id, pick the last one
      default_selection = default_selection or #instances
    end
  end

  pickers
    .new(opts, {
      initial_mode = "normal",
      prompt_title = "Claude Legion  a:new x:kill s:pin S:pin-all r:rename J/K:move",
      default_selection_index = default_selection,
      finder = finders.new_table({
        results = instances,
        entry_maker = function(entry)
          local pin = entry.persistent and "📌 " or "   "
          local display = entry.id .. ". " .. pin .. entry.name
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

        local function action_new()
          actions.close(prompt_bufnr)
          local new_id = terminal.create(nil, { background = true })
          vim.schedule(function()
            claude_code_picker(opts, new_id)
          end)
        end

        local function action_kill()
          local selection = action_state.get_selected_entry()
          if selection then
            local killed_id = selection.value.id
            terminal.kill(selection.value.id)
            actions.close(prompt_bufnr)
            vim.schedule(function()
              claude_code_picker(opts, killed_id)
            end)
          end
        end

        local function action_pin()
          local selection = action_state.get_selected_entry()
          if selection then
            terminal.persist(selection.value.id)
            actions.close(prompt_bufnr)
            vim.schedule(function()
              claude_code_picker(opts, selection.value.id)
            end)
          end
        end

        local function action_rename()
          local selection = action_state.get_selected_entry()
          if selection then
            vim.ui.input({ prompt = "Rename: ", default = selection.value.name }, function(new_name)
              if new_name and new_name ~= "" then
                terminal.rename(selection.value.id, new_name)
                actions.close(prompt_bufnr)
                vim.schedule(function()
                  claude_code_picker(opts, selection.value.id)
                end)
              end
            end)
          end
        end

        local function action_pin_all()
          terminal.persist_all()
          actions.close(prompt_bufnr)
          vim.schedule(function()
            claude_code_picker(opts)
          end)
        end

        local function action_move_up()
          local selection = action_state.get_selected_entry()
          if selection and selection.value.id > 1 then
            local new_id = selection.value.id - 1
            terminal.move(selection.value.id, new_id)
            actions.close(prompt_bufnr)
            vim.schedule(function()
              claude_code_picker(opts, new_id)
            end)
          end
        end

        local function action_move_down()
          local selection = action_state.get_selected_entry()
          if selection then
            local all = terminal.list()
            if selection.value.id < #all then
              local new_id = selection.value.id + 1
              terminal.move(selection.value.id, new_id)
              actions.close(prompt_bufnr)
              vim.schedule(function()
                claude_code_picker(opts, new_id)
              end)
            end
          end
        end

        map("i", "<C-a>", action_new)
        map("i", "<C-x>", action_kill)
        map("i", "<C-s>", action_pin)
        map("i", "<C-S>", action_pin_all)
        map("i", "<C-r>", action_rename)

        map("n", "a", action_new)
        map("n", "x", action_kill)
        map("n", "s", action_pin)
        map("n", "S", action_pin_all)
        map("n", "r", action_rename)
        map("n", "K", action_move_up)
        map("n", "J", action_move_down)

        return true
      end,
    })
    :find()
end

local function worktree_picker(opts)
  opts = opts or {}

  local worktrees = worktree.list_worktrees()

  pickers
    .new(opts, {
      initial_mode = "normal",
      prompt_title = "Worktrees  a:new x:remove",
      finder = finders.new_table({
        results = worktrees,
        entry_maker = function(entry)
          local branch = entry.branch or "detached"
          local dir = vim.fn.fnamemodify(entry.path, ":t")
          local display = dir .. " [" .. branch .. "]"
          return {
            value = entry,
            display = display,
            ordinal = dir .. " " .. branch,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            local name = vim.fn.fnamemodify(selection.value.path, ":t")
            worktree.open_window(selection.value.path, name)
          end
        end)

        local function action_new()
          actions.close(prompt_bufnr)
          worktree.create_prompt()
        end

        local function action_remove()
          local selection = action_state.get_selected_entry()
          if selection then
            actions.close(prompt_bufnr)
            worktree.remove_worktree(selection.value.path, {
              on_complete = function()
                vim.schedule(function()
                  worktree_picker(opts)
                end)
              end,
            })
          end
        end

        map("i", "<C-a>", action_new)
        map("i", "<C-x>", action_remove)
        map("n", "a", action_new)
        map("n", "x", action_remove)

        return true
      end,
    })
    :find()
end

return telescope.register_extension({
  exports = {
    select = claude_code_picker,
    worktrees = worktree_picker,
  },
})
