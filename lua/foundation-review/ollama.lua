local schema = require("foundation-review.schema")

local M = {}

local function decode_json(value)
  local ok, decoded = pcall(vim.json.decode, value)
  if not ok then
    return nil, decoded
  end
  return decoded
end

function M.build_request(model, prompt, system)
  return {
    model = model,
    prompt = prompt,
    system = system,
    stream = false,
    think = false,
    options = { temperature = 0 },
    format = schema,
  }
end

function M.decode_response(body)
  local transport, transport_error = decode_json(body)
  if not transport then
    return nil, "invalid_transport_json: " .. tostring(transport_error)
  end
  if type(transport) ~= "table" then
    return nil, "invalid_transport_envelope"
  end
  if type(transport.response) ~= "string"
    or transport.response == ""
  then
    return nil, "empty_response"
  end

  local document, document_error = decode_json(transport.response)
  if document == nil then
    return nil, "invalid_model_json: " .. tostring(document_error)
  end

  if type(document) == "string" then
    document, document_error = decode_json(document)
    if document == nil then
      return nil, "invalid_nested_model_json: "
        .. tostring(document_error)
    end
  end

  if type(document) ~= "table" then
    return nil, "invalid_model_envelope"
  end
  return document
end

function M.request(config, payload, callback)
  local command = {
    "curl",
    "--silent",
    "--show-error",
    "--fail-with-body",
    "--max-time",
    tostring(math.ceil(config.timeout_ms / 1000)),
    "--header",
    "Content-Type: application/json",
    "--data-binary",
    "@-",
    config.url .. "/api/generate",
  }

  return vim.system(command, {
    text = true,
    stdin = vim.json.encode(payload),
    timeout = config.timeout_ms,
  }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback("transport_error", nil, result)
        return
      end

      local document, err = M.decode_response(result.stdout)
      callback(err, document, result)
    end)
  end)
end

function M.check(config)
  local result = vim.system({
    "curl",
    "--silent",
    "--show-error",
    "--fail-with-body",
    config.url .. "/api/tags",
  }, { text = true }):wait()

  if result.code ~= 0 then
    return false, "Ollama is not responding at " .. config.url
  end

  local tags = decode_json(result.stdout)
  if type(tags) ~= "table" or type(tags.models) ~= "table" then
    return false, "Ollama returned an invalid model list"
  end

  for _, model in ipairs(tags.models) do
    if model.name == config.model or model.model == config.model then
      return true
    end
  end
  return false, "Ollama model is not installed: " .. config.model
end

return M
