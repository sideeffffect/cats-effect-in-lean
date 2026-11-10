# Independent reviews

Verdicts of independent reviewers. The reviewer is a different agent. It reads the source and the proofs. It does not run anything.
Rubric: `wiki/methodology/agent-workflow.md` (MIRROR, PROPERTY, SETTLED, wrong-function test).

## Format

One Markdown file for each review batch: `review/<date>-<topic>.md`. One section for each inventory row:

```markdown
## <inventory row id>

- entry: <registry entry id>
- mirror: yes | no — <reason>
- property: yes | no — <reason>
- settled: yes | no — <reason>
- wrong-function test: pass | fail — <which broken function>
- verdict: FAITHFUL | HOLLOW
```

For an `excluded` row, write `reason applies: yes | no` and the verdict.
