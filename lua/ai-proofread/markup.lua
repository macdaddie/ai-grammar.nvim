local M = {}

local function add(spans, start_byte, end_byte, kind)
  if start_byte and end_byte and start_byte <= end_byte then
    spans[#spans + 1] = {
      start_byte = start_byte,
      end_byte = end_byte,
      kind = kind,
    }
  end
end

local function lines(text)
  local result = {}
  local start_byte = 1

  while start_byte <= #text do
    local newline = text:find("\n", start_byte, true)
    local end_byte = newline and newline - 1 or #text
    result[#result + 1] = {
      text = text:sub(start_byte, end_byte),
      start_byte = start_byte,
      end_byte = end_byte,
    }
    if not newline then
      break
    end
    start_byte = newline + 1
  end

  return result
end

local function inline_code(spans, text)
  local from = 1
  while from <= #text do
    local opening = text:find("`", from, true)
    if not opening then
      break
    end
    local closing = text:find("`", opening + 1, true)
    if not closing then
      break
    end
    add(spans, opening, closing, "inline_code")
    from = closing + 1
  end
end

local function urls(spans, text)
  local from = 1
  while from <= #text do
    local start_byte, end_byte = text:find("https?://[^%s%]>%)%]]+", from)
    if not start_byte then
      break
    end
    add(spans, start_byte, end_byte, "url")
    from = end_byte + 1
  end
end

local function merge(spans)
  table.sort(spans, function(left, right)
    return left.start_byte < right.start_byte
  end)

  local merged = {}
  for _, span in ipairs(spans) do
    local previous = merged[#merged]
    if previous and span.start_byte <= previous.end_byte + 1 then
      previous.end_byte = math.max(previous.end_byte, span.end_byte)
    else
      merged[#merged + 1] = vim.deepcopy(span)
    end
  end
  return merged
end

function M.protected_regions_asciidoc(text)
  local spans = {}
  local block
  local pending_attribute
  local delimiters = {
    ["----"] = true,
    ["...."] = true,
    ["++++"] = true,
    ["////"] = true,
    ["===="] = true,
  }

  for _, line in ipairs(lines(text)) do
    local trimmed = line.text:match("^%s*(.-)%s*$")

    if block then
      if trimmed == block.delimiter then
        add(spans, block.start_byte, line.end_byte, "block")
        block = nil
      end
    elseif delimiters[trimmed] then
      block = {
        delimiter = trimmed,
        start_byte = pending_attribute or line.start_byte,
      }
      pending_attribute = nil
    elseif trimmed:match("^%[.*%]$")
      and (trimmed:find("source", 1, true)
        or trimmed:find("listing", 1, true)
        or trimmed:find("literal", 1, true)
        or trimmed:find("pass", 1, true)
        or trimmed:find("example", 1, true))
    then
      pending_attribute = line.start_byte
    else
      pending_attribute = nil
      if line.text:match("^:%S+:%s*") then
        add(spans, line.start_byte, line.end_byte, "attribute")
      end
    end
  end

  if block then
    add(spans, block.start_byte, #text, "block")
  end

  inline_code(spans, text)
  urls(spans, text)
  return merge(spans)
end

function M.protected_regions_markdown(text)
  local spans = {}
  local block
  local document_lines = lines(text)

  for index, line in ipairs(document_lines) do
    local marker = line.text:match("^%s*(```+)")
      or line.text:match("^%s*(~~~+)")

    if block then
      if block.marker == "-" and line.text == "---" then
        add(spans, block.start_byte, line.end_byte, "frontmatter")
        block = nil
      elseif marker and marker:sub(1, 1) == block.marker then
        add(spans, block.start_byte, line.end_byte, "code_block")
        block = nil
      end
    elseif marker then
      block = {
        marker = marker:sub(1, 1),
        start_byte = line.start_byte,
      }
    elseif index == 1 and line.text == "---" then
      block = { marker = "-", start_byte = line.start_byte }
    elseif line.text:match("^    %S") then
      add(spans, line.start_byte, line.end_byte, "indented_code")
    end
  end

  if block then
    add(spans, block.start_byte, #text, "code_block")
  end

  inline_code(spans, text)
  urls(spans, text)
  return merge(spans)
end

return M
