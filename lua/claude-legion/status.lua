local tmux = require("claude-legion.tmux")

local M = {}

--- Patterns that indicate Claude Code is waiting for user input.
--- Each entry is a plain-text substring matched against the last N lines of pane content.
--- When the pane_title shows busy (spinner) but any of these match, status becomes "input".
local INPUT_PATTERNS = {
  "Esc to cancel",                      -- permission/tool approval prompts
  "Type here to tell Claude what to change", -- plan acceptance prompts
}

--- Check if pane content contains any input-required pattern.
--- Returns true if user input is needed.
function M.content_needs_input(content)
  if not content then return false end
  for _, pattern in ipairs(INPUT_PATTERNS) do
    if content:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

--- Parse a pane_title string into a status.
--- Claude Code sets pane_title via OSC escape sequences:
---   "\xe2\x9c\xb3 Claude Code" (U+2733, eight spoked asterisk) = idle
---   "\xe2\xa0\x90 Claude Code" / "\xe2\xa0\x82 Claude Code" (braille spinner) = busy
--- Returns "idle", "busy", or nil (title not recognized as Claude Code).
function M.parse_pane_title_status(title)
  if not title or title == "" then return nil end
  -- Claude Code idle: title starts with ✳ (U+2733)
  if title:find("^\xe2\x9c\xb3") then return "idle" end
  -- Claude Code busy: title contains "Claude Code" but doesn't start with ✳
  -- (braille spinner characters like ⠐ ⠂ precede "Claude Code")
  if title:find("Claude Code") then return "busy" end
  -- Not a Claude Code title (shell or other process)
  return nil
end

--- Detect shell instance status via content matching.
function M.get_shell_status(id, sname)
  local output = tmux.capture_pane_tail(sname, id, 3)
  if not output then return "idle" end
  local clean = output:gsub("\27%[[%d;]*[A-Za-z]", "")
  local last_line = ""
  for line in clean:gmatch("[^\n]+") do
    local stripped = line:gsub("%s", "")
    if stripped ~= "" then last_line = line end
  end
  if last_line:match("[%$%%#>]%s*$") then return "idle" end
  return "busy"
end

--- Resolve status for a window given its pane data.
--- Always tries pane_title first (works for any Claude Code process regardless of @claude_type).
--- Falls back to content matching only when pane_title is unrecognized (actual shell processes).
--- Optional `tail` parameter accepts pre-fetched capture-pane content (for batched calls).
function M.resolve_status(win, pane, sname, tail)
  if pane.dead then return "dead" end
  local st = M.parse_pane_title_status(pane.pane_title)
  if st == "busy" then
    local content = tail or tmux.capture_pane_tail(sname, win.id, 5)
    if M.content_needs_input(content) then
      return "input"
    end
    return "busy"
  end
  if st then return st end
  -- pane_title not recognized — use content matching for shell instances
  return M.get_shell_status(win.id, sname)
end

--- Detect instance status using pane_title (primary) with content fallback.
--- Returns "idle", "busy", "input", or "dead".
function M.get_status(id, sname)
  local statuses = tmux.get_pane_statuses(sname)
  local pane = statuses[id]
  if not pane then return "idle" end
  return M.resolve_status({ id = id }, pane, sname)
end

--- Build a flat instance list from session entries, with batched status detection.
--- Takes entries: { {session_name=string, windows={...}, display_name=string}, ... }
--- Returns flat list of instance records with status resolved.
function M.build_instance_list(entries)
  local results = {}
  for _, entry in ipairs(entries) do
    local sname = entry.session_name
    local windows = entry.windows
    local display = entry.display_name
    local statuses = tmux.get_pane_statuses(sname)

    -- Batch-capture tails for busy panes to detect input prompts (avoids N subprocesses)
    local busy_ids = {}
    for _, win in ipairs(windows) do
      local pane = statuses[win.id] or {}
      if not pane.dead and M.parse_pane_title_status(pane.pane_title) == "busy" then
        table.insert(busy_ids, win.id)
      end
    end
    local tails = tmux.capture_pane_tails_batch(sname, busy_ids, 5)

    for _, win in ipairs(windows) do
      local pane = statuses[win.id] or {}
      table.insert(results, {
        id = win.id,
        name = win.name or "claude",
        status = M.resolve_status(win, pane, sname, tails[win.id]),
        persistent = win.persistent,
        type = win.type or "claude",
        session_name = sname,
        project_display = display,
      })
    end
  end
  return results
end

return M
