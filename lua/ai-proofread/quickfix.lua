-- Quickfix presentation for validated findings.
-- Per ADR-035 the list is append-only: rebuilding it from the controller
-- accumulator would restore entries removed by apply or ignore.
-- See docs/arch/arch_design.adoc, Quickfix Integration.

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
      ai_proofread_id = finding.application_id,
    },
  }
end

local function sort_items(items)
  table.sort(items, function(left, right)
    return left.lnum < right.lnum
      or (left.lnum == right.lnum and left.col < right.col)
  end)
end

-- Progress lives in context so the list title can remain fixed.
local function context_for(review)
  local result = review.result
  return {
    -- False until finish(), and false afterwards for partial reviews.
    complete = review.finished and result.complete,
    rejected = #result.rejected_findings,
    failed_chunks = #result.failed_chunks,
    unreviewable_sections = #(result.unreviewable_sections or {}),
    chunks_done = review.index,
    chunks_total = #review.chunks,
    review_id = review.id,
  }
end

local function current_id()
  local list = vim.fn.getqflist({ id = 0, title = 1 })
  if list.title ~= "AI Proofread" then
    return nil
  end
  return list.id
end

local function create(review)
  vim.fn.setqflist({}, "r", {
    title = "AI Proofread",
    items = {},
    context = context_for(review),
  })
  review.quickfix_id = vim.fn.getqflist({ id = 0 }).id
  review.quickfix_opened = false
end

-- Refresh context without reconstructing entries. `idx = 0` requests every
-- item; `idx = 1` filters the result to the current entry and truncates the
-- list on the following write.
local function rewrite(review, id)
  local list = vim.fn.getqflist({ id = id, items = 1, idx = 0 })
  vim.fn.setqflist({}, "r", {
    id = id,
    title = "AI Proofread",
    items = list.items,
    idx = list.idx,
    context = context_for(review),
  })
  return #list.items
end

-- Append one validated batch. The window opens once, on the first published
-- finding, and the source window is restored immediately afterwards.
function M.append(review, findings)
  local id = review.quickfix_id
  if not id or current_id() ~= id then
    create(review)
    id = review.quickfix_id
  end

  local items = {}
  for _, finding in ipairs(findings) do
    items[#items + 1] = entry(review.buffer, finding)
  end
  sort_items(items)

  if #items > 0 then
    vim.fn.setqflist({}, "a", { id = id, items = items })
  end

  local count = rewrite(review, id)
  local config = review.config.quickfix
  if config.auto_open and not review.quickfix_opened and count > 0 then
    local window = vim.api.nvim_get_current_win()
    vim.cmd(id .. "copen")
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_set_current_win(window)
    end
    review.quickfix_opened = true
  end
end

function M.finish(review)
  local id = review.quickfix_id
  if not id or current_id() ~= id then
    create(review)
    id = review.quickfix_id
  end
  rewrite(review, id)
end

-- Extmarks are authoritative after a plugin-originated edit. Preserve the
-- existing context while swapping in the refreshed coordinates.
function M.refresh_positions(id, positions)
  if not id or current_id() ~= id then
    return
  end

  local list = vim.fn.getqflist({ id = id, items = 1, idx = 0 })
  for _, item in ipairs(list.items) do
    local user_data = item.user_data
    local key = type(user_data) == "table"
        and user_data.ai_proofread_id
      or nil
    local position = key and positions[key] or nil
    if position then
      item.lnum = position.lnum
      item.col = position.col
      item.end_lnum = position.end_lnum
      item.end_col = position.end_col
    end
  end

  vim.fn.setqflist({}, "r", {
    id = id,
    title = "AI Proofread",
    items = list.items,
    idx = list.idx,
    context = list.context,
  })
end

-- Used by cancel and stale detection; unrelated quickfix lists are untouched.
function M.clear(id)
  local list = vim.fn.getqflist({ id = id or 0, title = 1 })
  if list.title ~= "AI Proofread" then
    return
  end
  vim.fn.setqflist({}, "r", {
    id = list.id,
    title = "AI Proofread",
    items = {},
    context = { complete = false },
  })
end

return M
