# Bug records

One YAML file for each defect: `bugs/<id>.yaml`.
A `refuted` registry entry names its file in the field `bug`. The registry audit (`lake exe audit`) fails if the file does not exist.

Rules: `AGENTS.md`, section "Bug records and triage". Never open bugs outside this repository.

## Fields

| Field | Content |
|---|---|
| `id` | Same as the file name. |
| `title` | One line. |
| `priority` | Honest priority. Do not inflate it. |
| `kind` | For example `safety`, `liveness`, `law`, `doc-mismatch`. |
| `area` | `kernel`, `core`, `std`, `laws` or `runtime`. |
| `files` | Scala files, as `<path>:<line>` at v3.7.1. |
| `functions` | Public API functions that reach the defect. |
| `summary` | What goes wrong. |
| `likelihood` | How often real programs can hit it. |
| `maybe_intended` | Why the behavior can be deliberate, or `no`. |
| `reproducer` | Path in `reproducers/`. |
| `output` | Output on `v3.7.1` and on the latest `series/3.x`. |
| `expected` | The output that the promise requires. |
| `promised_by` | Law, Scaladoc or doc sentence, with a citation. |
| `cause` | Root cause in the source. |
| `possible_fix` | A fix that we propose. Do not apply it to the model. |
| `duplicates` | Existing issues, and the search queries that you used. |
| `lean` | `property` (prop name) and `theorem` (`*_refuted` name). |

## Ids

- Format: `CE-NNNN`, four digits, starting at `CE-0001`. Give the next free number. Never reuse a number.
- The id is the file name (`bugs/CE-0001.yaml`) and the reproducer directory (`reproducers/CE-0001/Repro.scala`).
- An id is for one defect in Cats Effect, also when the defect is already known upstream. The upstream issue goes into `duplicates`.
- `CE-0001` to `CE-0003` are the Phase 5 calibration bugs (upstream #4687, #4627, #4571).

## Extra fields

- `status`: `draft` until the Lean refutation exists and a reviewer accepted the record.
- `output` also has a `series/3.7.x` key (fixes land there first).
- `lean.theorem: open` means that the refutation is not done yet.
