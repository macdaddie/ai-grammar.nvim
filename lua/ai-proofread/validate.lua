local locator = require("ai-proofread.locator")

local M = {}

M.RejectionReason = {
  SCHEMA_INVALID = "schema_invalid",
  NOT_EXACT = "not_exact",
  NOT_UNIQUE = "not_unique",
  PROTECTED = "protected",
  UNSUPPORTED_CATEGORY = "unsupported_category",
  TYPE_MISMATCH = "type_mismatch",
  NO_CHANGE = "no_change",
  STALE = "stale",
}

local categories = {
  spelling = "correction",
  grammar = "correction",
  punctuation = "correction",
}

local required_fields = {
  type = true,
  category = true,
  original = true,
  suggestion = true,
  message = true,
}

local function line_and_column(text, absolute_byte)
  local line = 1
  local line_start = 1

  for byte = 1, absolute_byte - 1 do
    if text:sub(byte, byte) == "\n" then
      line = line + 1
      line_start = byte + 1
    end
  end

  return line, absolute_byte - line_start + 1
end

local function overlaps(span_start, span_end, protected)
  return span_start <= protected.end_byte
    and span_end >= protected.start_byte
end

function M.validate_schema(finding)
  if type(finding) ~= "table" then
    return false
  end

  for field in pairs(required_fields) do
    if type(finding[field]) ~= "string" or finding[field] == "" then
      return false
    end
  end

  for field in pairs(finding) do
    if not required_fields[field] then
      return false
    end
  end

  if finding.type ~= "correction" then
    return false
  end

  return true
end

function M.validate_finding(finding, chunk)
  if not M.validate_schema(finding) then
    return nil, M.RejectionReason.SCHEMA_INVALID
  end

  local expected_type = categories[finding.category]
  if not expected_type then
    return nil, M.RejectionReason.UNSUPPORTED_CATEGORY
  end
  if finding.type ~= expected_type then
    return nil, M.RejectionReason.TYPE_MISMATCH
  end

  local match = locator.find(chunk.review_text, finding.original)
  if match.status ~= "exact" then
    return nil, match.status
  end

  if chunk.target_start_byte
    and (match.start_byte < chunk.target_start_byte
      or match.end_byte > chunk.target_end_byte)
  then
    return nil, M.RejectionReason.NOT_EXACT
  end

  local source_start = chunk.offset_map[match.start_byte]
  local source_end = chunk.offset_map[match.end_byte]
  if not source_start or not source_end then
    return nil, M.RejectionReason.NOT_EXACT
  end

  for _, protected in ipairs(chunk.protected_spans or {}) do
    if overlaps(source_start, source_end, protected) then
      return nil, M.RejectionReason.PROTECTED
    end
  end

  local line, column = line_and_column(
    chunk.document_text,
    source_start
  )
  local end_line, end_column = line_and_column(
    chunk.document_text,
    source_end
  )
  local source_text = chunk.document_text:sub(source_start, source_end)
  if finding.suggestion == finding.original
    or finding.suggestion == source_text
  then
    return nil, M.RejectionReason.NO_CHANGE
  end

  return {
    line = line,
    column = column,
    end_line = end_line,
    end_column = end_column,
    source_start_byte = source_start,
    source_end_byte = source_end,
    source_text = source_text,
    severity = "warning",
    type = finding.type,
    category = finding.category,
    original = finding.original,
    suggestion = finding.suggestion,
    message = finding.message,
  }
end

function M.validate_findings(findings, chunk)
  local result = { valid = {}, rejected = {} }
  for _, finding in ipairs(findings) do
    local valid, reason = M.validate_finding(finding, chunk)
    if valid then
      result.valid[#result.valid + 1] = valid
    else
      result.rejected[#result.rejected + 1] = {
        finding = finding,
        reason = reason,
      }
    end
  end
  return result
end

function M.validate_document(document)
  if type(document) ~= "table"
    or type(document.findings) ~= "table"
    or not vim.islist(document.findings)
  then
    return nil, M.RejectionReason.SCHEMA_INVALID
  end

  for field in pairs(document) do
    if field ~= "findings" then
      return nil, M.RejectionReason.SCHEMA_INVALID
    end
  end

  return document.findings
end

return M
