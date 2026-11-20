# AGENTS.md

## Repository state

- Runnable Lua plugin with `lua/`, `plugin/`, `tests/`, Vim
  help and CI.
- Project name is `ai-proofread.nvim`; the checkout directory is `vim_apple_intelligence`. Do not rename paths to match the directory.
- Run the headless suite with
  `nvim --headless -u tests/minimal_init.lua -i NONE -l tests/run.lua`.
- Validate AsciiDoc with
  `asciidoctor -o /dev/null docs/arch/<file>.adoc`.
  `Ignoring <gem> because its extensions are not built` lines
  on stderr are expected.

## Sources of truth

- `docs/arch/adr.adoc` overrides prose in the other two documents. Decision status lives in the register table at the top of that file.
- `docs/arch/concept.adoc` covers scope, UX, and success criteria. `docs/arch/arch_design.adoc` covers components, data contracts, and the `fm` and Ollama inference transports.
- `README.adoc` and `doc/ai-proofread.txt` are user-facing; keep commands, options, backend behaviour and aliases in step with the implementation.

## Document conventions

- AsciiDoc only. Each file starts with a blank line, then `= Title`.
- Hard-wrap prose at roughly 60–63 characters, one sentence per line. Preserve this when editing.
- No Markdown syntax, hard-coded section numbers, or `---` horizontal rules.
- On substantive edits, bump `:revnumber:` minor and set `:revdate:`. Current revisions: concept 0.9, arch_design 0.10, adr 0.8.
- British English (`en-GB`) is both the product default and the documentation convention. Never "correct" `colour`, `behaviour`, or collective agreement such as "The team have".

## Decisions an agent would otherwise reverse

- ADR-028 locks scope to exactly three categories: spelling,
  grammar and punctuation.
  Sentence readability, ambiguity, redundancy, logic,
  terminology consistency and general style are out of scope;
  adding any requires a new accepted ADR.
- ADR-034 permits the native `fm` command as an optional
  lower-quality backend.
  Do not introduce `pcc`, cloud fallback or a custom Swift
  helper.
- Model selection is provisional: `gemma4:12b-it-qat` primary, `qwen3.5:9b-q4_K_M` principal alternative, `qwen3.5:4b-q4_K_M` lightweight comparison. Model IDs are configuration values, never hard-coded dependencies.
- Never delete or rewrite an accepted ADR. Add a new ADR using `Supersedes:: ADR-0NN`, then update the decision register table.

## Implementation constraints already decided

- Source quote validation and markup pre-masking belong in
  code, not prompts (ADR-016, ADR-019, ADR-021).
  Accept only a unique exact match or the bounded
  whitespace-collapsed fallback.
  Reject findings that overlap protected content, have an
  unsupported category or belong to a stale review.
- Neovim quickfix columns are byte-oriented. Compute UTF-8 byte offsets from the buffer; never trust model-supplied coordinates.
- Ollama contract: `POST /api/generate` with `stream: false`, `options.temperature: 0`, and `format` set to a JSON Schema. The findings JSON arrives as a string in the top-level `response` field and must be decoded a second time.
- Native `fm` contract: `fm respond --model system --no-stream --greedy --schema <packaged> --instructions <system>` with the prompt on standard input. The response is direct JSON, not nested in an Ollama-style `response` field.
- Ollama preload and `keep_alive` apply only to the `ollama` backend. The `fm` model is managed by macOS.
- Reject no-op findings whose suggestion equals the model's `original` or the validated source slice.
- Thinking-capable models (`qwen3.5:*`) can return an empty `response` unless `think: false` is set. This is a harness observation, not yet an ADR.
- The plugin must not download models. The health check reports a missing model and fails visibly.

## Commits

- Commit messages are short, lower-case, prefix-free sentences, for example `updated design to go with independant ollama models instead of fm`. No Conventional Commits.
