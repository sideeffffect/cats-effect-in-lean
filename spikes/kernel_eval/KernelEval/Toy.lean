/-
Toy fiber interpreter for the kernel-evaluation spike (Phase 0 step 3).

This is NOT a model of Cats Effect. It has the same shape as the planned
model (small-step, explicit scheduler, fuel), so that we can measure how far
kernel evaluation (`decide`, `decide +kernel`, `rfl`, `decide_cbv`) goes.

Design rules tested here:
- `step` is not recursive. One call does one transition.
- `run`, `forallSched`, `findSched` use structural recursion on a `Nat`
  (fuel or depth). No well-founded recursion. No `partial def`.
- Data is plain inductives with derived `DecidableEq`. No `String`, no `Float`,
  no `Array`, no `HashMap`.
- User code (`Code.kont`, `Code.user`) is a parameter.
-/
namespace KernelEval

inductive Val where
  | unit
  | nat (n : Nat)
  | bool (b : Bool)
  deriving DecidableEq, Repr, Inhabited

inductive Prog where
  | pure (v : Val)
  | raise (e : Nat)
  /-- run user function `f` (it can read and write the one `Ref` cell) -/
  | delay (f : Nat)
  /-- `p.flatMap (kont k)` -/
  | flatMap (p : Prog) (k : Nat)
  /-- toy `uncancelable` without `poll`: mask counter + 1 -/
  | uncancelable (p : Prog)
  | onCancel (p : Prog) (fin : Prog)
  | cede
  | start (p : Prog)
  | join (fib : Nat)
  | cancel (fib : Nat)
  deriving DecidableEq, Repr, Inhabited

inductive Outcome where
  | succeeded (v : Val)
  | errored (e : Nat)
  | canceled
  deriving DecidableEq, Repr

def Outcome.toVal : Outcome → Val
  | .succeeded v => v
  | .errored e => .nat (1000 + e)
  | .canceled => .bool false

inductive Ctl where
  | eval (p : Prog)
  | ret (v : Val)
  | err (e : Nat)
  deriving DecidableEq, Repr

inductive Frame where
  | bind (k : Nat)
  | unmask
  | popFin
  /-- remaining finalizers to run after the current one -/
  | fins (rest : List Prog)
  deriving DecidableEq, Repr

structure Fiber where
  ctl : Ctl
  stack : List Frame := []
  mask : Nat := 0
  cancelReq : Bool := false
  fins : List Prog := []
  outcome : Option Outcome := none
  deriving DecidableEq, Repr

structure State where
  fibers : List Fiber
  ref : Val
  deriving DecidableEq, Repr

/-- User code: continuations and `delay` bodies. A parameter of the model. -/
structure Code where
  kont : Nat → Val → Prog
  /-- input: current `Ref` value; output: result and new `Ref` value, or an error -/
  user : Nat → Val → Except Nat (Val × Val)

/-- Which fiber steps, and whether it observes a pending cancel now. -/
structure Choice where
  fib : Nat
  obs : Bool
  deriving DecidableEq, Repr

def modifyAt (g : α → α) : List α → Nat → List α
  | [], _ => []
  | x :: xs, 0 => g x :: xs
  | x :: xs, n + 1 => x :: modifyAt g xs n

def nth? : List α → Nat → Option α
  | [], _ => none
  | x :: _, 0 => some x
  | _ :: xs, n + 1 => nth? xs n

def Fiber.finish (f : Fiber) (o : Outcome) : Fiber :=
  { f with outcome := some o, stack := [], ctl := .ret .unit }

/-- Pop one frame with a result (`ret` or `err`). -/
def stepRet (code : Code) (f : Fiber) (r : Ctl) : Fiber :=
  match f.stack with
  | [] =>
    match r with
    | .ret v => f.finish (.succeeded v)
    | .err e => f.finish (.errored e)
    | .eval _ => f
  | .bind k :: st =>
    match r with
    | .ret v => { f with ctl := .eval (code.kont k v), stack := st }
    | _ => { f with stack := st }
  | .unmask :: st => { f with mask := f.mask - 1, stack := st }
  | .popFin :: st => { f with fins := f.fins.tail, stack := st }
  | .fins rest :: st =>
    match rest with
    | [] => f.finish .canceled
    | p :: ps => { f with ctl := .eval p, stack := .fins ps :: st }

/-- Start running finalizers after a cancel was observed.
`bug = true` is a deliberate defect: the mask is not raised and the finalizer
list is not cleared, so a second observation runs the finalizers again. -/
def beginCancel (bug : Bool) (f : Fiber) : Fiber :=
  match f.fins with
  | [] => f.finish .canceled
  | p :: ps =>
    if bug then { f with ctl := .eval p, stack := [.fins ps] }
    else { f with ctl := .eval p, stack := [.fins ps], mask := 1, fins := [] }

/-- One transition of fiber `c.fib`. Not recursive. -/
def step (code : Code) (bug : Bool) (s : State) (c : Choice) : State :=
  match nth? s.fibers c.fib with
  | none => s
  | some f =>
    if f.outcome.isSome then s else
    let upd (g : Fiber) : List Fiber := modifyAt (fun _ => g) s.fibers c.fib
    if f.cancelReq && f.mask == 0 && c.obs then
      { s with fibers := upd (beginCancel bug f) }
    else
    match f.ctl with
    | .ret _ => { s with fibers := upd (stepRet code f f.ctl) }
    | .err _ => { s with fibers := upd (stepRet code f f.ctl) }
    | .eval p =>
      match p with
      | .pure v => { s with fibers := upd { f with ctl := .ret v } }
      | .raise e => { s with fibers := upd { f with ctl := .err e } }
      | .delay u =>
        match code.user u s.ref with
        | .ok (v, r') => { fibers := upd { f with ctl := .ret v }, ref := r' }
        | .error e => { s with fibers := upd { f with ctl := .err e } }
      | .flatMap q k => { s with fibers := upd { f with ctl := .eval q, stack := .bind k :: f.stack } }
      | .uncancelable q =>
        { s with fibers := upd { f with ctl := .eval q, mask := f.mask + 1, stack := .unmask :: f.stack } }
      | .onCancel q fin =>
        { s with fibers := upd { f with ctl := .eval q, fins := fin :: f.fins, stack := .popFin :: f.stack } }
      | .cede => { s with fibers := upd { f with ctl := .ret .unit } }
      | .start q =>
        { s with fibers := upd { f with ctl := .ret (.nat s.fibers.length) } ++ [{ ctl := .eval q }] }
      | .join n =>
        match nth? s.fibers n with
        | none => { s with fibers := upd { f with ctl := .err 99 } }
        | some g =>
          match g.outcome with
          | some o => { s with fibers := upd { f with ctl := .ret o.toVal } }
          | none => s  -- blocked
      | .cancel n =>
        { s with fibers := modifyAt (fun g => { g with cancelReq := true }) (upd { f with ctl := .ret .unit }) n }

def allDone (s : State) : Bool := s.fibers.all (fun f => f.outcome.isSome)

inductive Result where
  | done (s : State)
  | outOfFuel (s : State)
  | schedEnd (s : State)
  deriving DecidableEq, Repr

/-- Fuel-bounded run. Structural on the fuel. "Out of fuel" is its own result. -/
def run (code : Code) (bug : Bool) : Nat → List Choice → State → Result
  | 0, _, s => if allDone s then .done s else .outOfFuel s
  | n + 1, cs, s =>
    if allDone s then .done s else
    match cs with
    | [] => .schedEnd s
    | c :: cs => run code bug n cs (step code bug s c)

/-- Run a schedule to its end (no fuel; structural on the list). -/
def exec (code : Code) (bug : Bool) : List Choice → State → State
  | [], s => s
  | c :: cs, s => exec code bug cs (step code bug s c)

/-- Check `P` on every state reachable in at most `k` steps, over all choices
in `cs`. Structural on `k`. Explores `|cs|^k` paths (fewer if fibers end). -/
def forallSched (code : Code) (bug : Bool) (cs : List Choice) (P : State → Bool) :
    Nat → State → Bool
  | 0, s => P s
  | k + 1, s => P s && cs.all (fun c => forallSched code bug cs P k (step code bug s c))

/-- Same as `forallSched` but stops a path as soon as all fibers are done. -/
def forallSchedCut (code : Code) (bug : Bool) (cs : List Choice) (P : State → Bool) :
    Nat → State → Bool
  | 0, s => P s
  | k + 1, s =>
    P s && (allDone s || cs.all (fun c => forallSchedCut code bug cs P k (step code bug s c)))

/-- Remove duplicates (keeps the first copy). Structural; uses derived `DecidableEq`. -/
def dedup [DecidableEq α] : List α → List α → List α
  | [], acc => acc.reverse
  | x :: xs, acc => if x ∈ acc then dedup xs acc else dedup xs (x :: acc)

/-- Breadth-first variant of `forallSched`: check `P` on each level of reachable
states, and remove duplicate states between levels. Cost grows with the number
of distinct states, not with the number of schedules. -/
def forallLevels (code : Code) (bug : Bool) (cs : List Choice) (P : State → Bool) :
    Nat → List State → Bool
  | 0, ss => ss.all P
  | k + 1, ss =>
    ss.all P &&
      forallLevels code bug cs P k (dedup (ss.flatMap (fun s => cs.map (step code bug s))) [])

/-- Search for a schedule (length ≤ k) that reaches a state with `P`. -/
def findSched (code : Code) (bug : Bool) (cs : List Choice) (P : State → Bool) :
    Nat → State → Option (List Choice)
  | 0, s => if P s then some [] else none
  | k + 1, s =>
    if P s then some [] else
    cs.findSome? (fun c => (findSched code bug cs P k (step code bug s c)).map (c :: ·))

def init (p : Prog) : State := { fibers := [{ ctl := .eval p }], ref := .nat 0 }

/-! ## Example user code -/

/-- `chain n`: `n` increments of the `Ref`, each followed by a `cede`. -/
def chain : Nat → Prog
  | 0 => .pure .unit
  | n + 1 => .flatMap (.delay 0) (2 * n + 1)  -- kont (2n+1) = cede >> chain n

def incr : Val → Val
  | .nat n => .nat (n + 1)
  | v => v

/-- `spin n`: `n` cedes, then `pure unit`. Uses kont ids `4000 + i`. -/
def spin : Nat → Prog
  | 0 => .pure .unit
  | n + 1 => .flatMap .cede (4000 + n)

/-- Continuation table (ids are small `Nat`s, so programs keep `DecidableEq`).
- `0`: `pure unit`; `1000`: finalizer tail (`cede`)
- `2000..2002`: main of `cancelProg`; `3001` and `5000 + n`: main of `twoChains n`;
  `6000 + n`: main of `threeChains n`
- `4000 + n`: `spin n`
- odd `2n+1`: `cede.flatMap (2n+2)`; even `2n+2`: `chain n`
-/
def kont (k : Nat) (_v : Val) : Prog :=
  if k == 0 then .pure .unit
  else if k == 1000 then .cede
  else if k == 2000 then .flatMap .cede 2001
  else if k == 2001 then .flatMap (.cancel 1) 2002
  else if k == 2002 then .join 1
  else if k == 3001 then .join 1
  else if 6000 ≤ k then .flatMap (.start (chain (k - 6000))) (5000 + (k - 6000))
  else if 5000 ≤ k then .flatMap (chain (k - 5000)) 3001
  else if 4000 ≤ k then spin (k - 4000)
  else if k % 2 == 1 then .flatMap .cede (k + 1)
  else chain (k / 2 - 1)

def user : Nat → Val → Except Nat (Val × Val)
  | 0, r => .ok (incr r, incr r)  -- increment the Ref
  | 1, _ => .error 7
  | _, r => .ok (r, r)            -- read the Ref

def code : Code := { kont := kont, user := user }

/-- Finalizer: increment the `Ref`, then `cede`. -/
def fin : Prog := .flatMap (.delay 0) 1000

/-- Main: start a child (`onCancel (cede chain) fin`), cede, cancel it, join. -/
def cancelProg (childLen : Nat) : Prog :=
  .flatMap (.start (.onCancel (spin childLen) fin)) 2000

/-- Two fibers, each running `chain n`; main joins the child at the end. -/
def twoChains (n : Nat) : Prog :=
  .flatMap (.start (chain n)) (5000 + n)

/-- Three fibers: main starts two children with `chain n`, runs `chain n`, joins child 1. -/
def threeChains (n : Nat) : Prog :=
  .flatMap (.start (chain n)) (6000 + n)

/-- Summary of a run: the final `Ref` value if all fibers finished. -/
def summary : Result → Option Val
  | .done s => some s.ref
  | _ => none

/-- The witness schedule for the buggy finalizer (found by hand, 15 steps). -/
def doubleFinSched : List Choice :=
  [⟨0, false⟩, ⟨0, false⟩, ⟨1, false⟩, ⟨0, false⟩, ⟨0, false⟩, ⟨0, false⟩, ⟨0, false⟩,
   ⟨0, false⟩, ⟨0, false⟩, ⟨1, true⟩, ⟨1, false⟩, ⟨1, false⟩, ⟨1, true⟩, ⟨1, false⟩,
   ⟨1, false⟩]

def finRuns (s : State) : Nat :=
  match s.ref with
  | .nat n => n
  | _ => 0

/-- Invariant: the finalizer ran at most once. -/
def atMostOnce (s : State) : Bool := finRuns s ≤ 1

/-- Round-robin schedule over `k` fibers, `n` steps, always observe cancel. -/
def roundRobin (k n : Nat) : List Choice :=
  (List.range n).map (fun i => { fib := i % k, obs := true })

def choices2 : List Choice := [⟨0, false⟩, ⟨1, false⟩, ⟨0, true⟩, ⟨1, true⟩]
def choices2NoObs : List Choice := [⟨0, true⟩, ⟨1, true⟩]
def choices3NoObs : List Choice := [⟨0, true⟩, ⟨1, true⟩, ⟨2, true⟩]

end KernelEval
