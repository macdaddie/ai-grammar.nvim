local adapters = require("foundation-review.adapters")
local ollama = require("foundation-review.ollama")
local prompt = require("foundation-review.prompt")
local quickfix = require("foundation-review.quickfix")
local validator = require("foundation-review.validate")

local M = {}
local active = {}
local sequence = 0

local function notify(message, level)
  vim.notify("Foundation Review: " .. message, level or vim.log.levels.INFO)
end

local function is_current(review)
  return active[review.buffer] == review
end

local function finish(review)
  if not is_current(review) then
    return
  end

  if not vim.api.nvim_buf_is_valid(review.buffer)
    or vim.api.nvim_buf_get_changedtick(review.buffer) ~= review.changedtick
  then
    active[review.buffer] = nil
    notify("buffer changed; discarded stale results", vim.log.levels.WARN)
    return
  end

  active[review.buffer] = nil
  quickfix.publish(review.buffer, review.result, review.config.quickfix)

  if not review.result.complete then
    notify("review incomplete; inspect quickfix context", vim.log.levels.WARN)
  end
end

local function process_next(review)
  if not is_current(review) then
    return
  end

  review.index = review.index + 1
  local chunk = review.chunks[review.index]
  if not chunk then
    finish(review)
    return
  end

  if chunk.unreviewable then
    review.result.complete = false
    review.result.unreviewable_sections[#review.result.unreviewable_sections + 1] = {
      start_byte = chunk.source_start_byte,
      end_byte = chunk.source_end_byte,
    }
    process_next(review)
    return
  end

  local payload = ollama.build_request(
    review.config.ollama.model,
    prompt.build(chunk.review_text, review.config.checks),
    prompt.system
  )
  local send = review.config._transport or ollama.request

  review.process = send(review.config.ollama, payload, function(err, document)
    if not is_current(review) then
      return
    end

    if err then
      review.result.complete = false
      review.result.failed_chunks[#review.result.failed_chunks + 1] = {
        index = review.index,
        reason = err,
      }
      process_next(review)
      return
    end

    local findings, envelope_error = validator.validate_document(document)
    if not findings then
      review.result.complete = false
      review.result.failed_chunks[#review.result.failed_chunks + 1] = {
        index = review.index,
        reason = envelope_error,
      }
      process_next(review)
      return
    end

    local validation = validator.validate_findings(findings, chunk)
    vim.list_extend(review.result.valid_findings, validation.valid)
    vim.list_extend(review.result.rejected_findings, validation.rejected)
    process_next(review)
  end)
end

function M.start(buffer, config)
  local filetype = vim.bo[buffer].filetype
  if not config.filetypes[filetype] or not adapters.supports(filetype) then
    notify("unsupported filetype: " .. filetype, vim.log.levels.ERROR)
    return nil
  end

  M.cancel(buffer, true)

  local text = table.concat(
    vim.api.nvim_buf_get_lines(buffer, 0, -1, true),
    "\n"
  )
  local chunks, err = adapters.prepare(
    filetype,
    text,
    config.review.chunk_size,
    config.review.hard_limit
  )
  if not chunks then
    notify(err, vim.log.levels.ERROR)
    return nil
  end

  sequence = sequence + 1
  local review = {
    id = sequence,
    buffer = buffer,
    changedtick = vim.api.nvim_buf_get_changedtick(buffer),
    config = config,
    chunks = chunks,
    index = 0,
    result = {
      complete = true,
      valid_findings = {},
      rejected_findings = {},
      failed_chunks = {},
      unreviewable_sections = {},
    },
  }
  active[buffer] = review
  process_next(review)
  return review.id
end

function M.cancel(buffer, silent)
  local review = active[buffer]
  if not review then
    return false
  end

  active[buffer] = nil
  if review.process and review.process.kill then
    pcall(review.process.kill, review.process, 15)
  end
  if not silent then
    notify("review cancelled")
  end
  return true
end

return M
