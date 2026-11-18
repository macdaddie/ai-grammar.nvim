local M = {}

function M.check(config)
  local provider = config.backend == "fm"
      and require("ai-proofread.fm")
    or require("ai-proofread.ollama")
  local provider_config = config.backend == "fm"
      and config.fm
    or config.ollama
  local ok, message = provider.check(provider_config)
  if ok then
    local suffix = ""
    if config.backend == "ollama" then
      local loaded = provider.loaded_models(provider_config)
      if loaded and #loaded > 0 then
        suffix = " (loaded: " .. table.concat(loaded, ", ") .. ")"
      end
    end
    vim.notify(
      "AI Proofread: " .. config.backend .. " backend is available" .. suffix,
      vim.log.levels.INFO
    )
    return true
  end

  vim.notify("AI Proofread: " .. message, vim.log.levels.ERROR)
  return false, message
end

return M
