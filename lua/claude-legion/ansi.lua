--- ANSI escape sequence parser for Neovim buffer highlighting.
local M = {}

local hl_cache = {}
local ns = vim.api.nvim_create_namespace("claude_legion_ansi")

local base_colors = {
  [0] = "#000000",
  [1] = "#800000",
  [2] = "#008000",
  [3] = "#808000",
  [4] = "#000080",
  [5] = "#800080",
  [6] = "#008080",
  [7] = "#c0c0c0",
}

local bright_colors = {
  [0] = "#808080",
  [1] = "#ff0000",
  [2] = "#00ff00",
  [3] = "#ffff00",
  [4] = "#0000ff",
  [5] = "#ff00ff",
  [6] = "#00ffff",
  [7] = "#ffffff",
}

--- Convert a 256-color index to a hex string.
local function color256_to_hex(n)
  if n < 8 then
    return base_colors[n]
  elseif n < 16 then
    return bright_colors[n - 8]
  elseif n < 232 then
    n = n - 16
    local r = math.floor(n / 36)
    local g = math.floor((n % 36) / 6)
    local b = n % 6
    r = r > 0 and (r * 40 + 55) or 0
    g = g > 0 and (g * 40 + 55) or 0
    b = b > 0 and (b * 40 + 55) or 0
    return string.format("#%02x%02x%02x", r, g, b)
  else
    local v = (n - 232) * 10 + 8
    return string.format("#%02x%02x%02x", v, v, v)
  end
end

--- Build or retrieve a highlight group for the given attributes.
local function get_hl_group(attrs)
  local parts = {}
  if attrs.fg then table.insert(parts, "f" .. attrs.fg:gsub("#", "")) end
  if attrs.bg then table.insert(parts, "b" .. attrs.bg:gsub("#", "")) end
  if attrs.bold then table.insert(parts, "bo") end
  if attrs.italic then table.insert(parts, "it") end
  if attrs.underline then table.insert(parts, "ul") end
  if attrs.reverse then table.insert(parts, "rv") end
  if attrs.dim then table.insert(parts, "dm") end
  if attrs.strikethrough then table.insert(parts, "st") end

  if #parts == 0 then return nil end

  local key = table.concat(parts, "_")
  if hl_cache[key] then return hl_cache[key] end

  local name = "ClaudeLegionAnsi_" .. key
  local hl = {}

  if attrs.fg then hl.fg = attrs.fg end
  if attrs.bg then hl.bg = attrs.bg end
  if attrs.bold then hl.bold = true end
  if attrs.italic then hl.italic = true end
  if attrs.underline then hl.underline = true end
  if attrs.reverse then hl.reverse = true end
  if attrs.strikethrough then hl.strikethrough = true end

  vim.api.nvim_set_hl(0, name, hl)
  hl_cache[key] = name
  return name
end

--- Resolve a color from SGR parameters.
--- Returns the new index position and a color string (hex).
local function parse_color(codes, i)
  local mode = codes[i]
  if mode == 5 and codes[i + 1] then
    return i + 2, color256_to_hex(codes[i + 1])
  elseif mode == 2 and codes[i + 1] and codes[i + 2] and codes[i + 3] then
    return i + 4, string.format("#%02x%02x%02x", codes[i + 1], codes[i + 2], codes[i + 3])
  end
  return i + 1, nil
end

--- Parse SGR codes and update attrs table.
local function apply_sgr(codes_str, attrs)
  if codes_str == "" then
    for k in pairs(attrs) do attrs[k] = nil end
    return
  end

  local codes = {}
  for num in codes_str:gmatch("([^;]+)") do
    table.insert(codes, tonumber(num) or 0)
  end

  local i = 1
  while i <= #codes do
    local c = codes[i]
    if c == 0 then
      for k in pairs(attrs) do attrs[k] = nil end
    elseif c == 1 then attrs.bold = true
    elseif c == 2 then attrs.dim = true
    elseif c == 3 then attrs.italic = true
    elseif c == 4 then attrs.underline = true
    elseif c == 7 then attrs.reverse = true
    elseif c == 9 then attrs.strikethrough = true
    elseif c == 21 then attrs.bold = nil
    elseif c == 22 then attrs.bold = nil; attrs.dim = nil
    elseif c == 23 then attrs.italic = nil
    elseif c == 24 then attrs.underline = nil
    elseif c == 27 then attrs.reverse = nil
    elseif c == 29 then attrs.strikethrough = nil
    elseif c >= 30 and c <= 37 then
      attrs.fg = base_colors[c - 30]
    elseif c == 38 then
      i = i + 1
      local ni, color = parse_color(codes, i)
      if color then attrs.fg = color end
      i = ni
      goto continue
    elseif c == 39 then attrs.fg = nil
    elseif c >= 40 and c <= 47 then
      attrs.bg = base_colors[c - 40]
    elseif c == 48 then
      i = i + 1
      local ni, color = parse_color(codes, i)
      if color then attrs.bg = color end
      i = ni
      goto continue
    elseif c == 49 then attrs.bg = nil
    elseif c >= 90 and c <= 97 then
      attrs.fg = bright_colors[c - 90]
    elseif c >= 100 and c <= 107 then
      attrs.bg = bright_colors[c - 100]
    end
    i = i + 1
    ::continue::
  end
end

--- Strip any escape sequence starting at pos. Returns end position or nil.
local function skip_escape(raw, pos)
  -- CSI sequences: ESC [ ... <final byte>
  local _, csi_end = raw:find("^\027%[[\032-\063]*[\064-\126]", pos)
  if csi_end then return csi_end end
  -- Two-byte sequences: ESC <char> (e.g. ESC(B)
  local _, twobyte_end = raw:find("^\027[%(%)%*%+%-%.%/][^\027]?", pos)
  if twobyte_end then return twobyte_end end
  -- Single ESC followed by a letter
  local _, esc_end = raw:find("^\027%a", pos)
  if esc_end then return esc_end end
  return nil
end

--- Parse an ANSI-escaped string into plain lines and highlight regions.
function M.parse(text)
  local lines = {}
  local highlights = {}
  local attrs = {}

  local raw_lines = vim.split(text, "\n")

  for lnum, raw in ipairs(raw_lines) do
    local clean = {}
    local col = 0
    local pos = 1
    local len = #raw

    while pos <= len do
      -- Match SGR sequence: ESC[ ... m
      local esc_start, esc_end, sgr = raw:find("\027%[([%d;]*)m", pos)
      if esc_start == pos then
        apply_sgr(sgr, attrs)
        pos = esc_end + 1
      elseif esc_start then
        -- Text (and possibly non-SGR escapes) between pos and the next SGR
        local scan = pos
        while scan < esc_start do
          local skip_end = skip_escape(raw, scan)
          if skip_end then
            scan = skip_end + 1
          else
            -- Find next escape or the SGR start
            local next_esc = raw:find("\027", scan)
            local text_end = (next_esc and next_esc < esc_start) and (next_esc - 1) or (esc_start - 1)
            local chunk = raw:sub(scan, text_end)
            if #chunk > 0 then
              local hl_group = get_hl_group(attrs)
              if hl_group then
                table.insert(highlights, { lnum - 1, col, col + #chunk, hl_group })
              end
              table.insert(clean, chunk)
              col = col + #chunk
            end
            scan = text_end + 1
          end
        end
        apply_sgr(sgr, attrs)
        pos = esc_end + 1
      else
        -- No more SGR sequences; consume remaining text, skipping non-SGR escapes
        local scan = pos
        while scan <= len do
          local skip_end = skip_escape(raw, scan)
          if skip_end then
            scan = skip_end + 1
          else
            local next_esc = raw:find("\027", scan)
            local text_end = next_esc and (next_esc - 1) or len
            local chunk = raw:sub(scan, text_end)
            if #chunk > 0 then
              local hl_group = get_hl_group(attrs)
              if hl_group then
                table.insert(highlights, { lnum - 1, col, col + #chunk, hl_group })
              end
              table.insert(clean, chunk)
              col = col + #chunk
            end
            scan = text_end + 1
          end
        end
        break
      end
    end

    table.insert(lines, table.concat(clean))
  end

  return { lines = lines, highlights = highlights, namespace = ns }
end

--- Apply parsed result to a buffer.
function M.apply(bufnr, parsed)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, parsed.lines)
  for _, hl in ipairs(parsed.highlights) do
    pcall(vim.api.nvim_buf_add_highlight, bufnr, parsed.namespace, hl[4], hl[1], hl[2], hl[3])
  end
end

return M
