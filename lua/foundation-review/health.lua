local ollama = require("foundation-review.ollama")

local M = {}

function M.check(config)
  local ok, message = ollama.check(config.ollama)
  if ok then
    vim.notify(
      "Foundation Review: Ollama and model are available",
      vim.log.levels.INFO
    )
    return true
  end

  vim.notify("Foundation Review: " .. message, vim.log.levels.ERROR)
  return false, message
end

return M
