local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  return
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local terminal = require("claude-legion.terminal")
local worktree = require("claude-legion.worktree")
local ansi = require("claude-legion.ansi")
local split = require("claude-legion.split")
local tmux = require("claude-legion.tmux")

-- Fix #2: select_key is now {id, session_name} to disambiguate across sessions
local function claude_code_picker(opts, select_key)
  opts = opts or {}

  local instances = terminal.list_all()

  local default_selection = nil
  if select_key and #instances > 0 then
    -- Exact match on both id and session_name
    for i, inst in ipairs(instances) do
      if inst.id == select_key.id and inst.session_name == select_key.session_name then
        default_selection = i
        break
      end
    end
    -- Fallback: nearest id in the same session (guard against nil id from failed create)
    if not default_selection and select_key.id then
      for i, inst in ipairs(instances) do
        if inst.session_name == select_key.session_name and inst.id >= select_key.id then
          default_selection = i
          break
        end
      end
    end
    -- Last resort: last entry in that session, or last entry overall
    if not default_selection then
      for i = #instances, 1, -1 do
        if instances[i].session_name == select_key.session_name then
          default_selection = i
          break
        end
      end
      default_selection = default_selection or #instances
    end
  end

  pickers
    .new(opts, {
      initial_mode = "normal",
      prompt_title = "Claude Legion  a:new t:shell x:kill s:pin S:pin-all r:rename J/K:move",
      default_selection_index = default_selection,
      finder = finders.new_table({
        results = instances,
        entry_maker = function(entry)
          local pin = entry.persistent and "📌 " or "   "
          local type_icon = entry.type == "shell" and "🐚 " or "🤖 "
          local display = entry.project_display .. " - " .. entry.name .. "  " .. pin .. type_icon
          return {
            value = entry,
            display = display,
            ordinal = entry.project_display .. " " .. entry.name,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "Terminal Preview",
        define_preview = function(self, entry)
          local bufnr = self.state.bufnr
          if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end
          local ok, err = pcall(function()
            local output = terminal.capture_pane(entry.value.id, entry.value.session_name)
            if not output or output == "" then
              vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "(no output)" })
              return
            end
            local parsed = ansi.parse(output)
            ansi.apply(bufnr, parsed)
          end)
          if not ok then
            pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, { "(preview error: " .. tostring(err) .. ")" })
          end
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            tmux.select_window(selection.value.session_name, selection.value.id)
            split.open(selection.value.session_name)
          end
        end)

        local function make_key(id, sname)
          return { id = id, session_name = sname }
        end

        local function action_new()
          actions.close(prompt_bufnr)
          local project = require("claude-legion.project")
          local cur_session = project.get_session_name(project.get_project_root())
          local new_id = terminal.create(nil, { background = true })
          vim.schedule(function()
            claude_code_picker(opts, new_id and make_key(new_id, cur_session) or nil)
          end)
        end

        local function action_new_shell()
          actions.close(prompt_bufnr)
          local project = require("claude-legion.project")
          local cur_session = project.get_session_name(project.get_project_root())
          local new_id = terminal.create(nil, { background = true, shell = true })
          vim.schedule(function()
            claude_code_picker(opts, new_id and make_key(new_id, cur_session) or nil)
          end)
        end

        local function action_kill()
          local selection = action_state.get_selected_entry()
          if selection then
            local key = make_key(selection.value.id, selection.value.session_name)
            terminal.kill(selection.value.id, selection.value.session_name)
            actions.close(prompt_bufnr)
            vim.schedule(function()
              claude_code_picker(opts, key)
            end)
          end
        end

        local function action_pin()
          local selection = action_state.get_selected_entry()
          if selection then
            terminal.persist(selection.value.id, selection.value.session_name)
            actions.close(prompt_bufnr)
            vim.schedule(function()
              claude_code_picker(opts, make_key(selection.value.id, selection.value.session_name))
            end)
          end
        end

        local function action_rename()
          local selection = action_state.get_selected_entry()
          if selection then
            vim.ui.input({ prompt = "Rename: ", default = selection.value.name }, function(new_name)
              if new_name and new_name ~= "" then
                terminal.rename(selection.value.id, new_name, selection.value.session_name)
              end
              pcall(actions.close, prompt_bufnr)
              vim.schedule(function()
                claude_code_picker(opts, make_key(selection.value.id, selection.value.session_name))
              end)
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
            local sname = selection.value.session_name
            local new_id = selection.value.id - 1
            terminal.move(selection.value.id, new_id, sname)
            actions.close(prompt_bufnr)
            vim.schedule(function()
              claude_code_picker(opts, make_key(new_id, sname))
            end)
          end
        end

        local function action_move_down()
          local selection = action_state.get_selected_entry()
          if selection then
            local sname = selection.value.session_name
            local windows = tmux.list_windows(sname)
            local max_id = 0
            for _, idx in ipairs(windows) do
              if idx > max_id then max_id = idx end
            end
            if selection.value.id < max_id then
              local new_id = selection.value.id + 1
              terminal.move(selection.value.id, new_id, sname)
              actions.close(prompt_bufnr)
              vim.schedule(function()
                claude_code_picker(opts, make_key(new_id, sname))
              end)
            end
          end
        end

        map("i", "<C-a>", action_new)
        map("i", "<C-t>", action_new_shell)
        map("i", "<C-x>", action_kill)
        map("i", "<C-s>", action_pin)
        map("i", "<C-S>", action_pin_all)
        map("i", "<C-r>", action_rename)

        map("n", "a", action_new)
        map("n", "t", action_new_shell)
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
