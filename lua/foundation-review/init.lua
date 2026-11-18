local config_module = require("foundation-review.config")

local M = {}
local current_config = config_module.merge({})

function M.setup(options)
  options = options or {}

  local valid, err = config_module.validate(options)
  if not valid then
    error("foundation-review: " .. err)
  end

  current_config = config_module.merge(options)

  local mappings = {
    review = { callback = M.review, desc = "Review buffer prose" },
    apply = { callback = M.apply, desc = "Apply review correction" },
    apply_all = {
      callback = M.apply_all,
      desc = "Apply all review corrections",
    },
  }
  for name, definition in pairs(mappings) do
    local mapping = current_config.keymaps[name]
    if type(mapping) == "string" and mapping ~= "" then
      vim.keymap.set("n", mapping, definition.callback, {
        desc = definition.desc,
        silent = true,
      })
    end
  end

  return current_config
end

function M.get_config()
  return vim.deepcopy(current_config)
end

function M.review()
  return require("foundation-review.controller").start(
    vim.api.nvim_get_current_buf(),
    current_config
  )
end

function M.cancel()
  return require("foundation-review.controller").cancel(
    vim.api.nvim_get_current_buf()
  )
end

function M.health()
  return require("foundation-review.health").check(current_config)
end

function M.apply()
  return require("foundation-review.apply").current()
end

function M.apply_all()
  return require("foundation-review.apply").all()
end

return M
