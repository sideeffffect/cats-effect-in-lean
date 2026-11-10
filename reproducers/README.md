# Reproducers

One Scala program for each bug record: `reproducers/<bug-id>.scala`, run with `scala-cli`.

- Pin Cats Effect `3.7.1` with a `//> using dep` directive.
- Use only the public API.
- The last line of output on v3.7.1 must be `REPRODUCED <bug-id>`.
- Also run it on the latest `series/3.x`. Record both outputs in the bug record (field `output`).
