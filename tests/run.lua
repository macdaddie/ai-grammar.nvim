local failures = 0

local function test(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write("ok - " .. name .. "\n")
    return
  end

  failures = failures + 1
  io.stderr:write("not ok - " .. name .. "\n" .. tostring(err) .. "\n")
end

local function equal(actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(string.format(
      "expected %s, got %s",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

test("public API loads and merges setup options", function()
  local review = require("foundation-review")
  equal(type(review.setup), "function")
  equal(type(review.review), "function")
  equal(type(review.cancel), "function")

  review.setup({
    ollama = { model = "test-model" },
    quickfix = { auto_open = false },
  })

  local config = review.get_config()
  equal(config.ollama.model, "test-model")
  equal(config.ollama.url, "http://127.0.0.1:11434")
  equal(config.quickfix.auto_open, false)
end)

test("plugin registers public commands", function()
  vim.cmd.runtime("plugin/foundation-review.lua")
  equal(vim.fn.exists(":FoundationReview"), 2)
  equal(vim.fn.exists(":FoundationReviewCancel"), 2)
  equal(vim.fn.exists(":FoundationReviewHealth"), 2)
end)

test("validator maps a UTF-8 finding to a line-local byte column", function()
  local validator = require("foundation-review.validate")
  local text = "One café has teh colour."
  local map = {}
  for byte = 1, #text do
    map[byte] = byte
  end

  local finding, reason = validator.validate_finding({
    type = "correction",
    category = "spelling",
    original = "teh",
    suggestion = "the",
    message = "Incorrect spelling.",
  }, {
    review_text = text,
    document_text = text,
    offset_map = map,
    protected_spans = {},
  })

  equal(reason, nil)
  equal(finding.line, 1)
  equal(finding.column, 15)
  equal(finding.source_start_byte, 15)
  equal(finding.source_end_byte, 17)
end)

test("validator rejects an ambiguous exact quotation", function()
  local validator = require("foundation-review.validate")
  local text = "teh first and teh second"
  local map = {}
  for byte = 1, #text do
    map[byte] = byte
  end

  local finding, reason = validator.validate_finding({
    type = "correction",
    category = "spelling",
    original = "teh",
    suggestion = "the",
    message = "Incorrect spelling.",
  }, {
    review_text = text,
    document_text = text,
    offset_map = map,
  })

  equal(finding, nil)
  equal(reason, "not_unique")
end)

test("validator permits one whitespace-collapsed match", function()
  local validator = require("foundation-review.validate")
  local text = "This sentence is hard\nwrapped here."
  local map = {}
  for byte = 1, #text do
    map[byte] = byte
  end

  local finding, reason = validator.validate_finding({
    type = "rewrite",
    category = "structure",
    original = "This sentence is hard wrapped here.",
    suggestion = "This sentence is wrapped here.",
    message = "The sentence structure is difficult to follow.",
  }, {
    review_text = text,
    document_text = text,
    offset_map = map,
  })

  equal(reason, nil)
  equal(finding.source_start_byte, 1)
  equal(finding.source_end_byte, #text)
end)

test("validator rejects a finding that intersects protected content", function()
  local validator = require("foundation-review.validate")
  local text = "Use `teh_code` here."
  local map = {}
  for byte = 1, #text do
    map[byte] = byte
  end

  local finding, reason = validator.validate_finding({
    type = "correction",
    category = "word_choice",
    original = "teh_code",
    suggestion = "the_code",
    message = "Use the intended identifier.",
  }, {
    review_text = text,
    document_text = text,
    offset_map = map,
    protected_spans = {
      { start_byte = 5, end_byte = 14 },
    },
  })

  equal(finding, nil)
  equal(reason, "protected")
end)

test("plain-text chunks preserve exact source bytes", function()
  local adapters = require("foundation-review.adapters")
  local text = "First paragraph.\n\nSecond paragraph."
  local chunks = adapters.prepare("text", text, 20)

  equal(#chunks, 2)
  equal(chunks[1].review_text, "First paragraph.")
  equal(chunks[1].offset_map[1], 1)
  equal(chunks[2].review_text, "Second paragraph.")
  equal(chunks[2].offset_map[1], 19)
  equal(chunks[2].document_text, text)
end)

test("AsciiDoc adapter masks source blocks without moving prose", function()
  local adapters = require("foundation-review.adapters")
  local text = table.concat({
    "Intro teh.",
    "",
    "[source,lua]",
    "----",
    "local teh = 1",
    "----",
    "",
    "Outro teh.",
  }, "\n")

  local chunks = adapters.prepare("asciidoc", text, 1000)
  equal(#chunks, 1)
  equal(chunks[1].review_text:find("local", 1, true), nil)

  local intro = assert(chunks[1].review_text:find("Intro teh.", 1, true))
  local outro = assert(chunks[1].review_text:find("Outro teh.", 1, true))
  equal(chunks[1].offset_map[intro], 1)
  equal(chunks[1].offset_map[outro], text:find("Outro", 1, true))
end)

test("Markdown adapter masks frontmatter and fenced code", function()
  local adapters = require("foundation-review.adapters")
  local text = table.concat({
    "---",
    "title: Teh title",
    "---",
    "",
    "Review teh prose.",
    "",
    "```lua",
    "local teh = true",
    "```",
  }, "\n")

  local chunks = adapters.prepare("markdown", text, 1000)
  equal(#chunks, 1)
  equal(chunks[1].review_text:find("Teh title", 1, true), nil)
  equal(chunks[1].review_text:find("local teh", 1, true), nil)
  assert(chunks[1].review_text:find("Review teh prose.", 1, true))
end)

test("Ollama request enforces deterministic structured output", function()
  local ollama = require("foundation-review.ollama")
  local request = ollama.build_request(
    "test-model",
    "Review this text.",
    "Proofread British English prose."
  )

  equal(request.model, "test-model")
  equal(request.stream, false)
  equal(request.think, false)
  equal(request.options.temperature, 0)
  equal(request.format.type, "object")
  equal(
    request.format.properties.findings.items.properties.category.enum,
    {
      "spelling",
      "grammar",
      "punctuation",
      "sentence_readability",
      "structure",
      "word_choice",
      "consistency",
    }
  )
end)

test("Ollama response decoder returns the findings envelope", function()
  local ollama = require("foundation-review.ollama")
  local model_document = vim.json.encode({
    findings = {
      {
        type = "correction",
        category = "grammar",
        original = "they is",
        suggestion = "they are",
        message = "Use plural agreement.",
      },
    },
  })
  local body = vim.json.encode({ response = model_document })

  local document, err = ollama.decode_response(body)
  equal(err, nil)
  equal(document.findings[1].suggestion, "they are")
end)

test("Ollama response decoder rejects empty and malformed output", function()
  local ollama = require("foundation-review.ollama")

  local document, malformed = ollama.decode_response("not json")
  equal(document, nil)
  assert(malformed:match("^invalid_transport_json"))

  local empty_document, empty = ollama.decode_response(
    vim.json.encode({ response = "" })
  )
  equal(empty_document, nil)
  equal(empty, "empty_response")
end)

test("public review publishes validated findings to quickfix", function()
  local review = require("foundation-review")
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buffer)
  vim.bo[buffer].filetype = "text"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
    "This has teh mistake.",
  })

  local requested
  review.setup({
    keymaps = { review = false },
    quickfix = { auto_open = false },
    _transport = function(_, payload, callback)
      requested = payload
      callback(nil, {
        findings = {
          {
            type = "correction",
            category = "spelling",
            original = "teh",
            suggestion = "the",
            message = "Incorrect spelling.",
          },
        },
      })
      return { kill = function() end }
    end,
  })

  review.review()

  local quickfix = vim.fn.getqflist({ items = 1, title = 1 })
  equal(quickfix.title, "Foundation Review")
  equal(#quickfix.items, 1)
  equal(quickfix.items[1].bufnr, buffer)
  equal(quickfix.items[1].lnum, 1)
  equal(quickfix.items[1].col, 10)
  equal(quickfix.items[1].end_lnum, 1)
  equal(quickfix.items[1].end_col, 12)
  assert(quickfix.items[1].text:find("the", 1, true))
  equal(requested.think, false)
end)

test("review discards findings when the buffer becomes stale", function()
  local review = require("foundation-review")
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buffer)
  vim.bo[buffer].filetype = "text"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "teh text" })
  vim.fn.setqflist({}, "r")

  local complete
  review.setup({
    keymaps = { review = false },
    quickfix = { auto_open = false },
    _transport = function(_, _, callback)
      complete = callback
      return { kill = function() end }
    end,
  })

  review.review()
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "changed text" })
  complete(nil, {
    findings = {
      {
        type = "correction",
        category = "spelling",
        original = "teh",
        suggestion = "the",
        message = "Incorrect spelling.",
      },
    },
  })

  equal(#vim.fn.getqflist(), 0)
end)

test("cancel terminates the active transport and ignores its callback", function()
  local review = require("foundation-review")
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buffer)
  vim.bo[buffer].filetype = "text"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "teh text" })
  vim.fn.setqflist({}, "r")

  local complete
  local killed = false
  review.setup({
    keymaps = { review = false },
    quickfix = { auto_open = false },
    _transport = function(_, _, callback)
      complete = callback
      return {
        kill = function()
          killed = true
        end,
      }
    end,
  })

  review.review()
  equal(review.cancel(), true)
  equal(killed, true)
  complete(nil, { findings = {} })
  equal(#vim.fn.getqflist(), 0)
end)

test("partial failure still publishes findings from successful chunks", function()
  local review = require("foundation-review")
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buffer)
  vim.bo[buffer].filetype = "text"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
    "teh first.",
    "",
    "Second paragraph fails.",
  })

  local call = 0
  review.setup({
    keymaps = { review = false },
    review = { chunk_size = 15 },
    quickfix = { auto_open = false },
    _transport = function(_, _, callback)
      call = call + 1
      if call == 1 then
        callback(nil, {
          findings = {
            {
              type = "correction",
              category = "spelling",
              original = "teh",
              suggestion = "the",
              message = "Incorrect spelling.",
            },
          },
        })
      else
        callback("transport_error")
      end
      return { kill = function() end }
    end,
  })

  review.review()
  local quickfix = vim.fn.getqflist({ items = 1, context = 1 })
  equal(#quickfix.items, 1)
  equal(quickfix.context.complete, false)
  equal(quickfix.context.failed_chunks, 1)
end)

test("long paragraphs split at sentence boundaries", function()
  local adapters = require("foundation-review.adapters")
  local text = "First sentence. Second sentence."
  local chunks = adapters.prepare("text", text, 17)

  equal(#chunks, 2)
  equal(chunks[1].source_text, "First sentence.")
  equal(chunks[2].source_text, "Second sentence.")
  equal(chunks[2].offset_map[1], 17)
end)

test("prompt requires minimal spans for corrections", function()
  local prompt = require("foundation-review.prompt")
  local content = prompt.build("This has teh error.", {
    spelling = true,
  })

  assert(content:find("smallest exact offending substring", 1, true))
  assert(content:find("never quote the complete sentence", 1, true))
  assert(content:find('"teh"', 1, true))
  assert(content:find('"the"', 1, true))
  assert(content:find("local corrections alone resolve", 1, true))
end)

test("sentences beyond the hard limit are reported without inference", function()
  local review = require("foundation-review")
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buffer)
  vim.bo[buffer].filetype = "text"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
    "This single sentence has no early boundary and exceeds the hard limit.",
  })

  local requests = 0
  review.setup({
    keymaps = { review = false },
    review = { chunk_size = 20, hard_limit = 40 },
    quickfix = { auto_open = false },
    _transport = function()
      requests = requests + 1
    end,
  })

  review.review()
  local quickfix = vim.fn.getqflist({ context = 1, title = 1 })
  equal(requests, 0)
  equal(quickfix.title, "Foundation Review")
  equal(quickfix.context.complete, false)
  equal(quickfix.context.unreviewable_sections, 1)
end)

test("validator rejects a non-array findings envelope", function()
  local validator = require("foundation-review.validate")
  local findings, reason = validator.validate_document({
    findings = { unexpected = "object" },
  })
  equal(findings, nil)
  equal(reason, "schema_invalid")
end)

if failures > 0 then
  vim.cmd("cquit " .. failures)
end

vim.cmd("qa!")
