local M = {}

local function entry(buffer, finding)
  return {
    bufnr = buffer,
    lnum = finding.line,
    col = finding.column,
    end_lnum = finding.end_line,
    end_col = finding.end_column,
    type = "W",
    text = string.format(
      "[%s] %s Suggestion: %s",
      finding.category,
      finding.message,
      finding.suggestion
    ),
    user_data = {
      foundation_review_id = finding.application_id,
    },
  }
end

function M.publish(buffer, result, config)
  local items = {}
  for _, finding in ipairs(result.valid_findings) do
    items[#items + 1] = entry(buffer, finding)
  end
  table.sort(items, function(left, right)
    return left.lnum < right.lnum
      or (left.lnum == right.lnum and left.col < right.col)
  end)

  vim.fn.setqflist({}, "r", {
    title = "Foundation Review",
    items = items,
    context = {
      complete = result.complete,
      rejected = #result.rejected_findings,
      failed_chunks = #result.failed_chunks,
      unreviewable_sections = #(result.unreviewable_sections or {}),
    },
  })

  if config.auto_open and #items > 0 then
    vim.cmd.copen()
  end
end

return M
