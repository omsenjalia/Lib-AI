# Vendored: fable-mode

This directory vendors the [fable-mode](https://github.com/mrtooher/fable-mode) skill
family and agent definitions into the repository, so they are versioned with the
project instead of living only in a user's `~/.claude` directory.

- **Upstream commit:** `a368f94a36e38c9b42648cc9b4a2a28347d165ea` (2026-09-02)
- **Upstream license:** none published at that commit — vendored as-is, treat as
  third-party code and check licensing before redistributing publicly.

## Layout

Claude Code loads project-scoped skills from `.claude/skills/<name>/SKILL.md` and
agent definitions from `.claude/agents/<name>.md`. Folder names must match the
`name:` field in each frontmatter or the skill will not trigger.

| Path | Source |
| --- | --- |
| `skills/fable-mode/SKILL.md` | upstream `SKILL.md` |
| `skills/fable-fable/SKILL.md` | upstream `fable-fable/SKILL.md` |
| `skills/fable-opus/SKILL.md` | upstream `fable-opus/SKILL.md` |
| `skills/fable-sonnet/SKILL.md` | upstream `fable-sonnet/SKILL.md` |
| `skills/fable-haiku/SKILL.md` | upstream `fable-haiku/SKILL.md` |
| `skills/execution-guardrails/SKILL.md` | upstream `execution-guardrails/SKILL.md` |
| `skills/double-check/SKILL.md` | upstream `double-check/SKILL.md` |
| `agents/fable-orchestrator.md` | upstream `agents/fable-orchestrator.md` |
| `agents/fable-worker-sonnet.md` | upstream `agents/fable-worker-sonnet.md` |
| `agents/fable-worker-haiku.md` | upstream `agents/fable-worker-haiku.md` |
| `agents/fable-verifier.md` | upstream `agents/fable-verifier.md` |

Deliberately not vendored: `bench/` (benchmark harness), `install.sh` (installs to
user scope, not project scope), and `whistlepot-gateway/` (the author's unrelated
personal-agent prompt).

## Updating

```bash
git clone https://github.com/mrtooher/fable-mode.git /tmp/fable-mode
cd /tmp/fable-mode && git checkout a368f94a36e38c9b42648cc9b4a2a28347d165ea
# copy the 11 files above into .claude/, then update the pinned commit above
```

Verify a refresh by diffing the vendored files against the upstream clone before
committing; file contents should be byte-identical.
