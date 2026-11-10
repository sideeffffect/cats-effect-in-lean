import KernelEval.Toy
/-!
Data-representation probes for kernel evaluation. Each `example` below
checks. Failing variants are described in comments with the observed error
(Lean v4.35.0, 2026-11-10).
-/
namespace KernelEval.Repr

/-! ### Well-founded recursion vs structural fuel -/

/-- Same loop as `run`, but terminating by `termination_by` (well-founded). -/
def runWF (code : Code) : List Choice → State → State
  | [], s => s
  | c :: rest, s => runWF code rest (step code false s c)
termination_by cs => cs.length

-- Observed on v4.35.0:
-- * plain `decide` (elaborator reduction) FAILS: well-founded definitions are
--   irreducible; "reduction got stuck at (finRuns (runWF ...)).beq 6".
-- * `decide +kernel` WORKS at 51 and 783 steps (the kernel ignores
--   irreducibility and here can reduce the `Acc.rec` proof), but FAILS at
--   4,815 steps ("failed to reduce ... to `true` or `false`"), while the
--   structural `run` with fuel checks 4,815 steps in 5.7 s.
--   So kernel evaluation of well-founded recursion is fragile. Do not rely on it.
example : finRuns (runWF code (roundRobin 2 51) (init (twoChains 3))) = 6 := by decide +kernel

/-- `decide_cbv` uses the equation lemmas, so well-founded recursion works. -/
example : finRuns (runWF code (roundRobin 2 51) (init (twoChains 3))) = 6 := by decide_cbv

/-! ### `String` and `Array` -/

-- String literals: the kernel has special support for literals, and `decide`
-- on short `String` equality works, but every character becomes a `Char`
-- (a `UInt32` with a validity proof). Prefer `Nat` tags.
example : "finalizer-1" ≠ "finalizer-2" := by decide +kernel

-- `Array` is a structure around `List`; `Array.set!`/`Array.get!` reduce in
-- the kernel through `List` operations. It works, but it is no faster than
-- `List` in the kernel (no O(1) update), and the bounds proofs of `a[i]` add
-- terms. Prefer `List` in model logic.
example : ((List.replicate 200 0).toArray.set! 150 7)[150]! = 7 := by decide +kernel

/-! ### `Fin` vs `Nat` -/

-- `Fin n` values carry a proof `i < n`. `decide` works, but every literal
-- needs the proof term; fiber ids as `Nat` are simpler. Checked:
example : (⟨1, by decide⟩ : Fin 3) ≠ ⟨2, by decide⟩ := by decide +kernel

end KernelEval.Repr
