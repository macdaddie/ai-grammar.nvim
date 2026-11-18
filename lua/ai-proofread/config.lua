-- AI Proofread: Configuration
-- Default settings and user configuration validation

local M = {}

---Default configuration
M.default_config = {
  language = "en-GB",
  backend = "ollama",

  ollama = {
    url = "http://127.0.0.1:11434",
    model = "gemma4:12b-it-qat",
    temperature = 0,
    timeout_ms = 120000,
    preload = false,
  },

  fm = {
    command = "fm",
    model = "system",
    timeout_ms = 30000,
  },

  filetypes = {
    asciidoc = true,
    markdown = true,
    text = true,
  },

  checks = {
    spelling = true,
    grammar = true,
    punctuation = true,
  },

  review = {
    chunk_size = 2500,
    hard_limit = 12000,
    max_concurrent = 1,
  },

  quickfix = {
    auto_open = true,
  },

  keymaps = {
    review = "<leader>ar",
    review_selection = "<leader>ar",
    apply = "<leader>aa",
    apply_all = "<leader>aA",
    ignore = "<leader>ai",
  },
}

local supported_checks = {
  spelling = true,
  grammar = true,
  punctuation = true,
}

---Validate configuration
--
-- @param config table: User-provided configuration
-- @return table: Validated configuration
-- @return string|nil: Error message if invalid
function M.validate(config)
  if type(config) ~= "table" then
    return nil, "configuration must be a table"
  end

  if config.backend
    and config.backend ~= "ollama"
    and config.backend ~= "fm"
  then
    return nil, "backend must be 'ollama' or 'fm'"
  end

  if config.ollama then
    if config.ollama.url and not config.ollama.url:match("^https?://") then
      return nil, "ollama.url must be a valid HTTP/HTTPS URL"
    end

    if config.ollama.timeout_ms and config.ollama.timeout_ms < 1000 then
      return nil, "ollama.timeout_ms must be at least 1000ms"
    end

    if config.ollama.preload ~= nil
      and type(config.ollama.preload) ~= "boolean"
    then
      return nil, "ollama.preload must be a boolean"
    end

    if config.ollama.keep_alive ~= nil
      and type(config.ollama.keep_alive) ~= "string"
      and type(config.ollama.keep_alive) ~= "number"
    then
      return nil, "ollama.keep_alive must be a string or number"
    end
  end

  if config.filetypes then
    for ft, enabled in pairs(config.filetypes) do
      if type(enabled) ~= "boolean" then
        return nil, string.format("filetypes.%s must be a boolean", ft)
      end
    end
  end

  if config.fm then
    if config.fm.command
      and (type(config.fm.command) ~= "string"
        or config.fm.command == "")
    then
      return nil, "fm.command must be a non-empty string"
    end
    if config.fm.timeout_ms and config.fm.timeout_ms < 1000 then
      return nil, "fm.timeout_ms must be at least 1000ms"
    end
  end

  if config.checks then
    for check, enabled in pairs(config.checks) do
      if not supported_checks[check] then
        return nil, string.format("unsupported check: %s", check)
      end
      if type(enabled) ~= "boolean" then
        return nil, string.format("checks.%s must be a boolean", check)
      end
    end
  end

  if config.review then
    local chunk_size = config.review.chunk_size
      or M.default_config.review.chunk_size
    local hard_limit = config.review.hard_limit
      or M.default_config.review.hard_limit
    if chunk_size < 1 then
      return nil, "review.chunk_size must be positive"
    end
    if hard_limit < chunk_size then
      return nil, "review.hard_limit must not be smaller than chunk_size"
    end
  end

  return config, nil
end

---Merge with defaults
--
-- @param user_config table: User-provided configuration
-- @return table: Merged configuration
function M.merge(user_config)
  return vim.tbl_deep_extend(
    "force",
    vim.deepcopy(M.default_config),
    user_config or {}
  )
end

return M
