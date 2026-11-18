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
    vim.notify(
      "AI Proofread: " .. config.backend .. " backend is available",
      vim.log.levels.INFO
    )
    return true
  end

  vim.notify("AI Proofread: " .. message, vim.log.levels.ERROR)
  return false, message
end

return M
