if vim.g.loaded_foundation_review then
  return
end
vim.g.loaded_foundation_review = true

vim.api.nvim_create_user_command("FoundationReview", function()
  require("foundation-review").review()
end, {
  desc = "Review the current buffer with Foundation Review",
})

vim.api.nvim_create_user_command("FoundationReviewCancel", function()
  require("foundation-review").cancel()
end, {
  desc = "Cancel the current Foundation Review request",
})

vim.api.nvim_create_user_command("FoundationReviewHealth", function()
  require("foundation-review").health()
end, {
  desc = "Check the Foundation Review configuration",
})
