import KernelEval.Toy
/-!
Counting helpers for the spike report (run with `#eval`, not used in proofs).
`distinctPairs` = number of distinct `(depth, state)` pairs that a memoizing
evaluator (like `decide_cbv`) must visit; `paths` = schedules that plain
kernel reduction of `forallSched` visits.
-/
namespace KernelEval

/-- Number of nodes in the schedule tree of depth `k` (no cut). -/
def paths (b : Nat) : Nat → Nat
  | 0 => 1
  | k + 1 => 1 + b * paths b k

/-- Sum over levels of the number of distinct states at that level. -/
def distinctPairs (code : Code) (bug : Bool) (cs : List Choice) : Nat → List State → Nat
  | 0, ss => ss.length
  | k + 1, ss =>
    ss.length + distinctPairs code bug cs k (dedup (ss.flatMap (fun s => cs.map (step code bug s))) [])

end KernelEval
