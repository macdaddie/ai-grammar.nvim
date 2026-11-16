# AGENTS.md

## Repository state

- Design documentation only. There is no `lua/`, `plugin/`, `tests/`, manifest, or CI. The repository structure shown in `docs/arch/arch_design.adoc` is the intended plugin layout, not the current tree.
- Project name is `foundation-review.nvim`; the checkout directory is `vim_apple_intelligence`. Do not rename paths to match the directory.
- Only verifiable command: `asciidoctor -o /dev/null docs/arch/<file>.adoc`. Exit status 0 is the check; `Ignoring <gem> because its extensions are not built` lines on stderr are expected. There is no test suite, linter, or build step.

## Sources of truth

- `docs/arch/adr.adoc` overrides prose in the other two documents. Decision status lives in the register table at the top of that file.
- `docs/arch/concept.adoc` covers scope, UX, and success criteria. `docs/arch/arch_design.adoc` covers components, data contracts, and the Ollama transport.

## Document conventions

- AsciiDoc only. Each file starts with a blank line, then `= Title`.
- Hard-wrap prose at roughly 60–63 characters, one sentence per line. Preserve this when editing.
- No Markdown syntax, hard-coded section numbers, or `---` horizontal rules.
- On substantive edits, bump `:revnumber:` minor and set `:revdate:`. Current revisions: concept 0.3, arch_design 0.3, adr 0.2.
- British English (`en-GB`) is both the product default and the documentation convention. Never "correct" `colour`, `behaviour`, or collective agreement such as "The team have".

## Decisions an agent would otherwise reverse

- ADR-017 locks scope to exactly four categories: spelling, grammar, punctuation, sentence readability. Ambiguity, redundancy, logic, terminology consistency, and general style are out of scope; adding any requires a new accepted ADR.
- Apple Foundation Models and Swift are rejected (ADR-014, ADR-018). Do not reintroduce `fm`, `pcc`, or a Swift helper as a backend.
- Model selection is provisional: `gemma4:12b-it-qat` primary, `qwen3.5:9b-q4_K_M` principal alternative, `qwen3.5:4b-q4_K_M` lightweight comparison. Model IDs are configuration values, never hard-coded dependencies.
- Never delete or rewrite an accepted ADR. Add a new ADR using `Supersedes:: ADR-0NN`, then update the decision register table.

## Implementation constraints already decided

- Exact-substring quote validation and markup pre-masking belong in code, not prompts (ADR-016, ADR-019). Reject findings whose quote is not a unique exact substring, overlaps protected content, has an unsupported category, or belongs to a stale review.
- Neovim quickfix columns are byte-oriented. Compute UTF-8 byte offsets from the buffer; never trust model-supplied coordinates.
- Ollama contract: `POST /api/generate` with `stream: false`, `options.temperature: 0`, and `format` set to a JSON Schema. The findings JSON arrives as a string in the top-level `response` field and must be decoded a second time.
- Thinking-capable models (`qwen3.5:*`) can return an empty `response` unless `think: false` is set. This is a harness observation, not yet an ADR.
- The plugin must not download models. The health check reports a missing model and fails visibly.

## Commits

- Commit messages are short, lower-case, prefix-free sentences, for example `updated design to go with independant ollama models instead of fm`. No Conventional Commits.
