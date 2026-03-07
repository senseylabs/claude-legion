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

local function claude_code_picker(opts)
  opts = opts or {}

  local instances = terminal.list()

  pickers
    .new(opts, {
      initial_mode = "normal",
      prompt_title = "Claude Legion  a:new x:kill s:pin S:pin-all r:rename",
      finder = finders.new_table({
        results = instances,
        entry_maker = function(entry)
          local pin = entry.persistent and "📌 " or "   "
          local display = pin .. entry.name
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
          terminal.create(nil, { background = true })
          vim.schedule(function()
            claude_code_picker(opts)
          end)
        end

        local function action_kill()
          local selection = action_state.get_selected_entry()
          if selection then
            terminal.kill(selection.value.id)
            actions.close(prompt_bufnr)
            vim.schedule(function()
              claude_code_picker(opts)
            end)
          end
        end

        local function action_pin()
          local selection = action_state.get_selected_entry()
          if selection then
            terminal.persist(selection.value.id)
            actions.close(prompt_bufnr)
            vim.schedule(function()
              claude_code_picker(opts)
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
                  claude_code_picker(opts)
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
