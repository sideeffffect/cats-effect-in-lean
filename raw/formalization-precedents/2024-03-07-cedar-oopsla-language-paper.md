# Cedar: A New Language for Expressive, Fast, Safe, and Analyzable Authorization (Extended Version)

> Source: https://arxiv.org/abs/2403.04651 (OOPSLA 2024, Proc. ACM Program. Lang. 8, OOPSLA1)
> Collected: 2026-11-10
> Published: 2024-03-07

[...omitted: everything except abstract and the DRT paragraph of Section 3...]

## Abstract

Cedar is a new authorization policy language designed to be ergonomic, fast, safe, and analyzable. Rather than embed authorization logic in an application's code, developers can write that logic as Cedar policies and delegate access decisions to Cedar's evaluation engine. Cedar's simple and intuitive syntax supports common authorization use-cases with readable policies, naturally leveraging concepts from role-based, attribute-based, and relation-based access control models. Cedar's policy structure enables access requests to be decided quickly. Cedar's policy validator leverages optional typing to help policy writers avoid mistakes, but not get in their way. Cedar's design has been finely balanced to allow for a sound and complete logical encoding, which enables precise policy analysis, e.g., to ensure that when refactoring a set of policies, the authorized permissions do not change. We have modeled Cedar in the Lean programming language, and used Lean's proof assistant to prove important properties of Cedar's design. We have implemented Cedar in Rust, and released it open-source. Comparing Cedar to two open-source languages, OpenFGA and Rego, we find (subjectively) that Cedar has equally or more readable policies, but (objectively) performs far better.

## Section 3 (excerpt on DRT)

The Lean model is executable by compilation to native code, so we use extensive differential random testing to confirm that our Rust code and Lean model agree. We write input generators (for policies, entity stores, and requests) in the style of Pałka et al., and use the cargo fuzz framework to test that equal inputs map to equal outputs. We also use cargo fuzz to test properties directly on the Rust code, e.g., the "round trip" property that a pretty-printed Cedar abstract syntax tree parses back to itself. This testing regime has been fruitful, uncovering nearly two dozen bugs since the project's inception, and forcing us (via CI) to keep the Lean spec and proofs up to date.
