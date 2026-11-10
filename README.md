# Claude Code in Datadog LLM Observability

Every Claude Code session on my Mac sends its OpenTelemetry traces, metrics and logs to Datadog (us5) through a
native OpenTelemetry Collector run by launchd. Each turn, model call and tool call (with its command and duration)
shows up in LLM Observability (the "Agent Observability" pages in the app), with token counts and an estimated cost.

## Files

| File | What |
|---|---|
| `otel.yaml` | Collector config: OTLP in on `127.0.0.1:4318`, DogStatsD on `8125`, Datadog exporter out |
| `run-collector.sh` | Reads the API key from the macOS keychain (`datadog-api-key`) and starts `otelcol-contrib` |
| `datadog.otelcol.plist` | launchd job template that keeps the collector running |
| `claude-settings.json` | The `env` block to merge into `~/.claude/settings.json` |

## Setup (macOS)

1. Download the `otelcol-contrib` darwin tarball for your Mac (built with v0.165) from
   https://github.com/open-telemetry/opentelemetry-collector-releases/releases, extract it, put the binary at
   `~/.local/opt/otelcol/otelcol-contrib`, `chmod +x` it, and clear the download flag with
   `xattr -d com.apple.quarantine ~/.local/opt/otelcol/otelcol-contrib`.
2. Store the API key: `security add-generic-password -s datadog-api-key -a "$USER" -w` (it prompts for the key,
   which keeps it out of the shell history).
3. In `otel.yaml`, set `hostname` and `site` to yours.
4. From this repo's folder (the job points at it, so keep the clone there): `mkdir -p ~/.local/state`, then
   `sed "s#__REPO__#$PWD#; s#__HOME__#$HOME#" datadog.otelcol.plist > ~/Library/LaunchAgents/datadog.otelcol.plist`
   and `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/datadog.otelcol.plist`.
5. Merge the `env` block of `claude-settings.json` into `~/.claude/settings.json` and start a new Claude Code session.

Privacy: `claude-settings.json` sends content, not only numbers. `OTEL_LOG_USER_PROMPTS`,
`OTEL_LOG_ASSISTANT_RESPONSES`, `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT` and `OTEL_LOG_RAW_API_BODIES`
(full API request and response bodies) put prompts, answers, commands and their output in Datadog. Dropping
those lines removes most of that content (not tested line by line). Every span also carries the Claude account's
email and ids (`user.email`, `user.account_id`, `user.account_uuid`, `organization.id`) in the test run (content flags on).

## What the collector fixes

- Claude Code's `claude_code.llm_request` spans carry no `gen_ai.operation.name` and their own token attribute
  names, so LLM Observability filed them as workflow steps without tokens. The collector names them `chat`
  calls and copies the token counts (input = fresh + cache read + cache write).
- Tool spans get their command as `gen_ai.tool.call.arguments` and, when present, their output as
  `gen_ai.tool.call.result`.

## Gaps left

- A failed command is marked on the child `claude_code.tool.execution` span (`error.type: tool_error`), which
  LLM Observability files as a workflow. The `claude_code.tool` span its Tools table reads carries no failure
  flag, so every tool shows a 0% error rate; a span-level collector rule cannot see the child.
- Traces show "No content": the prompt rides on the `claude_code.interaction` span as `user_prompt`, an attribute
  LLM Observability does not read as the trace's input, and model spans carry no message content.
- In the Traces list, many model and tool calls show up as traces of their own next to the turn that holds them.

## One week of numbers (Nov 3 to 10, 2026)

| | |
|---|---|
| Model calls | 34k, over 548 sessions (local transcripts) |
| Input tokens | 4.12B by the local transcripts, 3.25B by the `claude_code.token.usage` metric (gap not reconciled yet) |
| Read from prompt cache | 97.4% of input tokens (both sources) |
| Context per model call | median 109k tokens, p90 208k, max 320k (local transcripts) |
| Share of input tokens from calls above 100k context | 74% |
| Estimated cost (Datadog) | $1.51k; Datadog estimates caching saved a further $6.31k |
| Bash calls | 24.0k, p95 24.2 s |
| Edit / Read / Write calls | 1.91k / 1.68k / 726 |

Each model call resends the whole conversation, so nearly every input token is a reread served from the prompt
cache, and the input tokens of a session are its number of calls times its average context.
