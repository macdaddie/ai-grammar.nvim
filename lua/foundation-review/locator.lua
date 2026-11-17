local M = {}

local function occurrences(text, quotation)
  local matches = {}
  local from = 1

  while from <= #text do
    local start_byte, end_byte = text:find(quotation, from, true)
    if not start_byte then
      break
    end

    matches[#matches + 1] = {
      start_byte = start_byte,
      end_byte = end_byte,
    }
    from = start_byte + 1
  end

  return matches
end

local function collapse_whitespace(text)
  local output = {}
  local start_map = {}
  local end_map = {}
  local source_byte = 1

  while source_byte <= #text do
    local byte = text:sub(source_byte, source_byte)
    if byte:match("%s") then
      local run_start = source_byte
      while source_byte <= #text
        and text:sub(source_byte, source_byte):match("%s")
      do
        source_byte = source_byte + 1
      end

      output[#output + 1] = " "
      start_map[#output] = run_start
      end_map[#output] = source_byte - 1
    else
      output[#output + 1] = byte
      start_map[#output] = source_byte
      end_map[#output] = source_byte
      source_byte = source_byte + 1
    end
  end

  return table.concat(output), start_map, end_map
end

local function result_for(matches, start_map, end_map)
  if #matches == 0 then
    return { status = "not_exact" }
  end
  if #matches > 1 then
    return { status = "not_unique" }
  end

  local match = matches[1]
  return {
    status = "exact",
    start_byte = start_map and start_map[match.start_byte]
      or match.start_byte,
    end_byte = end_map and end_map[match.end_byte]
      or match.end_byte,
  }
end

function M.find(text, quotation)
  if type(text) ~= "string" or type(quotation) ~= "string"
    or quotation == ""
  then
    return { status = "not_exact" }
  end

  local exact = occurrences(text, quotation)
  if #exact > 0 then
    return result_for(exact)
  end

  local collapsed_text, start_map, end_map = collapse_whitespace(text)
  local collapsed_quotation = collapse_whitespace(quotation)
  local fallback = occurrences(collapsed_text, collapsed_quotation)
  return result_for(fallback, start_map, end_map)
end

return M
