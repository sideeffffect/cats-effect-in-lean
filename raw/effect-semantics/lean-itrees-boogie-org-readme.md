# boogie-org/lean-itrees: Interaction Trees in Lean 4 (README)

> Source: https://github.com/boogie-org/lean-itrees
> Collected: 2026-11-10
> Published: Unknown

# Interaction Trees in Lean 4

[Interaction trees](https://dl.acm.org/doi/pdf/10.1145/3371119) allow expressing potentially
non-terminating and effectful programs.
The core data structure is the following [coinductive](https://github.com/alexkeizer/QpfTypes) type:
```lean
coinductive ITree (E : Type -> Type) (R : Type) : Type
| ret : R         -> ITree E R
| tau : ITree E R -> ITree E R
| vis : {A : Type} -> E A -> (A -> ITree E R) -> ITree E R
```

`ITree E` forms a monad additionally equipped with `iter`. We can thus use `do`-notation:
```lean
def main : ITree (Mem & AssumeAssert) Nat := do
  let x <- Mem.read "x"
  assume (x < 10)
  return x
```

## ITree Specifications
In order to be able to express constructs such as `assume _;` in intermediate verification languages
such as Boogie 2, [Dijkstra monads for ITrees](https://dl.acm.org/doi/pdf/10.1145/3434307)
can be used.

## Next Up
- Not universe-polymorphic, which prevents us from implementing `interp`.
- A lot of coinductive theorems are missing.
- We assume that `Quotient`ing ITrees along Eutt is possible, see `QITree.lean`.