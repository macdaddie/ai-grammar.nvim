local M = {}

local namespace = vim.api.nvim_create_namespace("foundation-review-apply")
local states = {}

local function notify(message, level)
  vim.notify("Foundation Review: " .. message, level or vim.log.levels.INFO)
end

local function position_less(left_row, left_col, right_row, right_col)
  return left_row < right_row
    or (left_row == right_row and left_col < right_col)
end

local function split_replacement(text)
  return vim.split(text, "\n", { plain = true })
end

local function remove_quickfix_entries(ids)
  local quickfix = vim.fn.getqflist({
    id = 0,
    idx = 0,
    items = 1,
    title = 1,
    context = 1,
  })
  if quickfix.title ~= "Foundation Review" then
    return
  end

  local items = {}
  for _, item in ipairs(quickfix.items) do
    local user_data = item.user_data
    local id = type(user_data) == "table"
        and user_data.foundation_review_id
      or nil
    if not ids[id] then
      items[#items + 1] = item
    end
  end

  vim.fn.setqflist({}, "r", {
    id = quickfix.id,
    title = quickfix.title,
    context = quickfix.context,
    items = items,
  })
  if #items > 0 then
    vim.fn.setqflist({}, "a", {
      id = quickfix.id,
      idx = math.min(quickfix.idx, #items),
    })
  end
end

local function resolve(finding)
  local mark = vim.api.nvim_buf_get_extmark_by_id(
    finding.buffer,
    namespace,
    finding.extmark,
    { details = true }
  )
  if #mark == 0 then
    return nil, "correction range is no longer available"
  end

  local details = mark[3]
  local range = {
    start_row = mark[1],
    start_col = mark[2],
    end_row = details.end_row,
    end_col = details.end_col,
  }
  local current = table.concat(vim.api.nvim_buf_get_text(
    finding.buffer,
    range.start_row,
    range.start_col,
    range.end_row,
    range.end_col,
    {}
  ), "\n")
  if current ~= finding.source_text then
    return nil, "source text changed; correction was not applied"
  end

  return range
end

local function edit(buffer, range, replacement, join)
  vim.api.nvim_buf_call(buffer, function()
    if join then
      vim.cmd("undojoin")
    end
    vim.api.nvim_buf_set_text(
      buffer,
      range.start_row,
      range.start_col,
      range.end_row,
      range.end_col,
      split_replacement(replacement)
    )
  end)
end

local function state_for_quickfix()
  local quickfix = vim.fn.getqflist({ idx = 0, items = 1 })
  local item = quickfix.items[quickfix.idx]
  if not item then
    return nil, nil, "no current Foundation Review finding"
  end

  local user_data = item.user_data
  local id = type(user_data) == "table"
      and user_data.foundation_review_id
    or nil
  local state = states[item.bufnr]
  local finding = state and state.by_id[id] or nil
  if not finding then
    return nil, nil, "current quickfix entry is not an active correction"
  end

  return state, finding
end

local function state_for_all()
  local buffer = vim.api.nvim_get_current_buf()
  if states[buffer] then
    return states[buffer]
  end

  local state = state_for_quickfix()
  return state
end

function M.register(buffer, review_id, findings)
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)

  local state = {
    buffer = buffer,
    review_id = review_id,
    findings = {},
    by_id = {},
  }
  states[buffer] = state

  for index, finding in ipairs(findings) do
    local id = review_id .. ":" .. index
    local tracked = vim.deepcopy(finding)
    tracked.application_id = id
    tracked.buffer = buffer
    tracked.applied = false
    tracked.extmark = vim.api.nvim_buf_set_extmark(
      buffer,
      namespace,
      finding.line - 1,
      finding.column - 1,
      {
        end_row = finding.end_line - 1,
        end_col = finding.end_column,
        right_gravity = false,
        end_right_gravity = true,
      }
    )
    finding.application_id = id
    state.findings[#state.findings + 1] = tracked
    state.by_id[id] = tracked
  end
end

function M.current()
  local _, finding, err = state_for_quickfix()
  if not finding then
    notify(err, vim.log.levels.ERROR)
    return nil, err
  end
  if finding.applied then
    local message = "correction has already been applied"
    notify(message, vim.log.levels.WARN)
    return nil, message
  end

  local range, range_err = resolve(finding)
  if not range then
    notify(range_err, vim.log.levels.WARN)
    return nil, range_err
  end

  edit(finding.buffer, range, finding.suggestion, false)
  finding.applied = true
  pcall(
    vim.api.nvim_buf_del_extmark,
    finding.buffer,
    namespace,
    finding.extmark
  )
  remove_quickfix_entries({ [finding.application_id] = true })
  notify("applied correction")
  return true
end

function M.all()
  local state = state_for_all()
  if not state then
    local message = "no active corrections for this buffer"
    notify(message, vim.log.levels.ERROR)
    return nil, message
  end

  local pending = {}
  for _, finding in ipairs(state.findings) do
    if not finding.applied then
      local range, err = resolve(finding)
      if not range then
        notify(err, vim.log.levels.WARN)
        return nil, err
      end
      pending[#pending + 1] = {
        finding = finding,
        range = range,
      }
    end
  end

  if #pending == 0 then
    local message = "no unapplied corrections"
    notify(message, vim.log.levels.INFO)
    return nil, message
  end

  table.sort(pending, function(left, right)
    return position_less(
      left.range.start_row,
      left.range.start_col,
      right.range.start_row,
      right.range.start_col
    )
  end)
  for index = 2, #pending do
    local previous = pending[index - 1].range
    local current = pending[index].range
    if position_less(
      current.start_row,
      current.start_col,
      previous.end_row,
      previous.end_col
    ) then
      local message = "overlapping corrections were not applied"
      notify(message, vim.log.levels.WARN)
      return nil, message
    end
  end

  local ok, edit_err = pcall(function()
    for index = #pending, 1, -1 do
      local correction = pending[index]
      edit(
        state.buffer,
        correction.range,
        correction.finding.suggestion,
        index < #pending
      )
    end
  end)
  if not ok then
    pcall(vim.api.nvim_buf_call, state.buffer, function()
      vim.cmd("undo")
    end)
    local message = "bulk application failed: " .. tostring(edit_err)
    notify(message, vim.log.levels.ERROR)
    return nil, message
  end

  for _, correction in ipairs(pending) do
    correction.finding.applied = true
    pcall(
      vim.api.nvim_buf_del_extmark,
      state.buffer,
      namespace,
      correction.finding.extmark
    )
  end
  local applied_ids = {}
  for _, correction in ipairs(pending) do
    applied_ids[correction.finding.application_id] = true
  end
  remove_quickfix_entries(applied_ids)
  notify(string.format("applied %d corrections", #pending))
  return true
end

return M
