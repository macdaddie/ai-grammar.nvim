local markup = require("foundation-review.markup")

local M = {}

local scanners = {
  text = function()
    return {}
  end,
  markdown = markup.protected_regions_markdown,
  asciidoc = markup.protected_regions_asciidoc,
}

local function paragraph_spans(text)
  local spans = {}
  local start_byte = 1

  while start_byte <= #text do
    local separator_start, separator_end = text:find(
      "\n%s*\n",
      start_byte
    )
    local end_byte = separator_start and separator_start - 1 or #text

    if end_byte >= start_byte then
      spans[#spans + 1] = {
        start_byte = start_byte,
        end_byte = end_byte,
      }
    end

    if not separator_end then
      break
    end
    start_byte = separator_end + 1
  end

  return spans
end

local function chunk_spans(text, budget, hard_limit)
  if text == "" then
    return {}
  end

  local paragraphs = paragraph_spans(text)
  local units = {}

  for _, paragraph in ipairs(paragraphs) do
    if paragraph.end_byte - paragraph.start_byte + 1 <= budget then
      units[#units + 1] = paragraph
    else
      local start_byte = paragraph.start_byte
      while start_byte <= paragraph.end_byte do
        local budget_end = math.min(
          start_byte + budget - 1,
          paragraph.end_byte
        )
        local sentence_end

        for byte = start_byte, budget_end do
          local character = text:sub(byte, byte)
          local following = text:sub(byte + 1, byte + 1)
          if (character == "." or character == "!" or character == "?")
            and (following == "" or following:match("%s"))
          then
            sentence_end = byte
          end
        end

        if not sentence_end then
          sentence_end = paragraph.end_byte
        end

        units[#units + 1] = {
          start_byte = start_byte,
          end_byte = sentence_end,
          unreviewable = sentence_end - start_byte + 1 > hard_limit,
        }
        start_byte = sentence_end + 1
        while start_byte <= paragraph.end_byte
          and text:sub(start_byte, start_byte):match("%s")
        do
          start_byte = start_byte + 1
        end
      end
    end
  end

  local chunks = {}
  local current

  for _, paragraph in ipairs(units) do
    if not current then
      current = vim.deepcopy(paragraph)
    elseif paragraph.end_byte - current.start_byte + 1 <= budget then
      current.end_byte = paragraph.end_byte
      current.unreviewable = current.unreviewable or paragraph.unreviewable
    else
      chunks[#chunks + 1] = current
      current = vim.deepcopy(paragraph)
    end
  end

  if current then
    chunks[#chunks + 1] = current
  end

  return chunks
end

local function intersects(left, right)
  return left.start_byte <= right.end_byte
    and left.end_byte >= right.start_byte
end

local function build_chunk(text, span, protected_spans)
  local source_text = text:sub(span.start_byte, span.end_byte)
  local bytes = {}
  local offset_map = {}
  local relevant_protected = {}

  for _, protected in ipairs(protected_spans) do
    if intersects(span, protected) then
      relevant_protected[#relevant_protected + 1] = protected
    end
  end

  for relative = 1, #source_text do
    local absolute = span.start_byte + relative - 1
    local protected = false
    for _, protected_span in ipairs(relevant_protected) do
      if absolute >= protected_span.start_byte
        and absolute <= protected_span.end_byte
      then
        protected = true
        break
      end
    end

    local byte = source_text:sub(relative, relative)
    bytes[relative] = protected and byte ~= "\n" and " " or byte
    offset_map[relative] = absolute
  end

  return {
    review_text = table.concat(bytes),
    source_text = source_text,
    document_text = text,
    source_start_byte = span.start_byte,
    source_end_byte = span.end_byte,
    offset_map = offset_map,
    protected_spans = relevant_protected,
    unreviewable = span.unreviewable or false,
  }
end

function M.supports(filetype)
  return scanners[filetype] ~= nil
end

function M.prepare(filetype, text, budget, hard_limit)
  local scanner = scanners[filetype]
  if not scanner then
    return nil, "unsupported_filetype"
  end

  local protected_spans = scanner(text)
  local chunks = {}
  hard_limit = hard_limit or math.max(budget, 12000)
  for _, span in ipairs(chunk_spans(text, budget, hard_limit)) do
    chunks[#chunks + 1] = build_chunk(text, span, protected_spans)
  end
  return chunks
end

return M
