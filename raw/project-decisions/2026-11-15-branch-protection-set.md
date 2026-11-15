# Branch protection on main set (2026-11-15)

Decision 57, step 4. Done after CI run on 51e483a was green (all jobs, 26 min).

`gh api -X PUT repos/sideeffffect/cats-effect-in-lean/branches/main/protection`:
- required status checks (strict: false): "Lean build and proof checks", "Difftest runner (Scala)", "Forbidden proof escapes", "Inventory check", "Wiki lint", "heavy-proofs", "twin-checks";
- enforce_admins: false (admins can still push directly; a red check shows on the commit);
- no required pull-request reviews; force pushes and branch deletion are not allowed.

`twin-checks` replaces the old job "Fixed-twin checks (heavy, sequential)" (track P, twin matrix). If a required job is renamed, update the protection in the same change.
