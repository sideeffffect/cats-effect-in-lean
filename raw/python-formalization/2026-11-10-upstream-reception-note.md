# python-formalization: upstream reception of filed bugs (research note)

> Source: https://github.com/python/cpython/issues/161688 (and 161689-161693, 158748, 158786); https://discuss.python.org/t/formalizing-cpython-in-lean-findings-from-a-machine-checked-model-and-how-youd-like-them/109978
> Collected: 2026-11-10
> Published: 2026-11-09

Own note from `gh issue view` / `gh pr list` and the Discourse JSON API on 2026-11-10.

## Filed issues (all opened 2026-11-09, all OPEN on 2026-11-10)

| Issue | Labels | Status |
|---|---|---|
| gh-161688 bytearray.strip() UAF via `__release_buffer__` | interpreter-core, type-crash | fix PR gh-161701 open (by a third party) |
| gh-161689 ElementTree backward slice assignment dup/loss of child | type-bug, interpreter-core, topic-XML | no PR yet |
| gh-161690 dict.fromkeys() GC-tracks non-GC object (3.15 regression) | type-bug, interpreter-core, 3.15, 3.16 | sergey-miryanov offered a PR; author asked him to go ahead and offered to test |
| gh-161691 memoryview released mid `==`/setitem still used | interpreter-core, type-crash | no PR yet |
| gh-161692 functools.partial keyword merge stack buffer overflow (new in 3.15) | extension-modules, type-crash, 3.15, 3.16 | fix PR gh-161698 open |
| gh-161693 dict.setdefault segfault, split-table dict, str-subclass key | interpreter-core, type-crash | fix PR gh-161704 open |

All six were triaged with labels within a day, and three have fix PRs within a day. No issue was closed as invalid or spam.

## Discourse thread

Posted 2026-11-09 in Core Development. On 2026-11-10 it had only the original post (no replies). It asks maintainers how they want the remaining ~400 reports (few at a time, grouped by module, or left in the repo).

## Context: the October 2026 bulk-filing incident ("bugforge")

- gh-158748 (closed): one of ~90 automated reports filed on 4 Oct 2026 by an automated property-testing tool (bugforge). Maintainer ZeroIntensity: "This is not allowed. Please stop flooding our issue tracker and instead compile a gist with your findings, and then track them with a single issue."
- gh-158786 (closed): the tracking issue that replaced them. Reporter admitted the reports were not reviewed by a human. picnixz: "You are meant to. Maintainers do not have the time..." hugovk linked https://devguide.python.org/getting-started/ai-tools/. terryjreedy called the design "buggy or even a bit fraudulent" because it read one-sentence doc statements literally (AGENTS.md cites this as python/cpython#158786: "maintainers have rejected literal one-sentence readings").
- python-formalization reacted by: (1) using bugforge-results as a duplicate source, (2) a human-read, Codex-checked prelaunch review, (3) filing only 6 crash bugs at launch and asking on Discourse about the rest, (4) grouping related findings per module.
