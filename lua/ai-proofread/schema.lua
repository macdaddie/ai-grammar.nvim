local finding = {
  type = "object",
  properties = {
    type = {
      type = "string",
      enum = { "correction" },
    },
    category = {
      type = "string",
      enum = {
        "spelling",
        "grammar",
        "punctuation",
      },
    },
    original = { type = "string", minLength = 1 },
    suggestion = { type = "string", minLength = 1 },
    message = { type = "string", minLength = 1 },
  },
  required = {
    "type",
    "category",
    "original",
    "suggestion",
    "message",
  },
  additionalProperties = false,
}

return {
  type = "object",
  properties = {
    findings = {
      type = "array",
      items = finding,
      minItems = 0,
    },
  },
  required = { "findings" },
  additionalProperties = false,
}
