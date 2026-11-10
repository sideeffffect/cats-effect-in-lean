import CatsEffectInLean.Proofs.Lemmas.CertP
import Std.Data.HashMap

/-!
# Certificate generator for `Proofs/Lemmas/CertP.lean` (untrusted tool)

Depth-first search over the preemptive scheduler from `Sched.init mm io`. It writes the tree
instructions and the successor table that `CertP.certExact` checks in the kernel. This code is
outside the trusted base: a wrong certificate only makes the kernel check `false`.

Encoding of one instruction (`encodeInstr`): `0` = pop, `1` = `some preempt`,
`n + 2` = `some (pick n)`. `CertP.decodeInstr` is the inverse.

Use: write a small `main` that calls `CertGen.writeCert` for the program and run it with
`lake env lean --run <file>` (see `tools/CertGen/RaceLaw.lean`).
-/

namespace CertGen

open CatsEffectInLean.Model

structure St (M : Type) where
  states : Array (Sched M) := #[]
  index : Std.HashMap UInt64 (List Nat) := {}
  instrs : Array Nat := #[]

def encodeInstr : Option PChoice → Nat
  | none => 0
  | some .preempt => 1
  | some (.pick n) => n + 2

variable {M : Type} [DecidableEq M]

def choicesOf (s : Sched M) : List PChoice :=
  .preempt :: (List.range (max 1 s.heap.ready.length)).map .pick

def keyHash (s : Sched M) : UInt64 := hash s.key

def find? (st : St M) (t : Sched M) : Option Nat :=
  (st.index.getD (keyHash t) []).find? fun i => st.states[i]? == some t

def add (st : St M) (t : Sched M) : St M :=
  let i := st.states.size
  { st with states := st.states.push t,
            index := st.index.insert (keyHash t) (i :: st.index.getD (keyHash t) []) }

partial def dfs (cfg : Config) (mm : MaskModel M) (env : UserEnv) (st : St M) (s : Sched M) :
    St M :=
  if s.halt.isSome then st
  else
    (choicesOf s).foldl (fun st c =>
      let t := s.tickP cfg mm env c
      match find? st t with
      | some _ => st
      | none =>
        let st := add st t
        let st := { st with instrs := st.instrs.push (encodeInstr (some c)) }
        let st := dfs cfg mm env st t
        { st with instrs := st.instrs.push 0 }) st

/-- The certificate of `io`: instructions and successor table. -/
def gen (cfg : Config) (mm : MaskModel M) (env : UserEnv) (io : IO) : Array Nat × Array (List Nat) :=
  let s0 := Sched.init mm io
  let st := dfs cfg mm env (add {} s0) s0
  let succ := st.states.map fun s =>
    if s.halt.isSome then []
    else (choicesOf s).map fun c => ((find? st (s.tickP cfg mm env c)).getD 999999999)
  (st.instrs, succ)

def chunks {α : Type} (l : List α) (n : Nat) : List (List α) :=
  if n = 0 then [l] else
  let rec go (l : List α) (fuel : Nat) : List (List α) :=
    match fuel with
    | 0 => []
    | f + 1 => if l.isEmpty then [] else l.take n :: go (l.drop n) f
  go l (l.length / n + 1)

def renderList (name : String) (ty : String) (elems : List String) : String := Id.run do
  let cs := chunks elems 400
  let mut out := ""
  let mut names : List String := []
  for i in [0:cs.length] do
    let nm := s!"{name}_{i}"
    names := names ++ [nm]
    out := out ++ s!"def {nm} : List {ty} := [{", ".intercalate cs[i]!}]\n\n"
  out := out ++ s!"def {name} : List {ty} :=\n  " ++
    (if names.isEmpty then "[]" else " ++\n  ".intercalate names) ++ "\n"
  return out

/-- Write the certificate of `io` as Lean source (`instrs : List Nat`,
`succ : List (List Nat)`) into `path`, in namespace `ns`. Returns the state count. -/
def writeCert (cfg : Config) (mm : MaskModel M) (env : UserEnv) (io : IO)
    (path : System.FilePath) (header ns : String) : _root_.IO Nat := do
  let (instrs, succ) := gen cfg mm env io
  let body :=
    renderList "instrs" "Nat" (instrs.toList.map toString) ++ "\n" ++
    renderList "succ" "(List Nat)" (succ.toList.map fun l => toString l)
  IO.FS.writeFile path (header ++ s!"\nnamespace {ns}\n\n" ++ body ++ s!"\nend {ns}\n")
  return succ.size

end CertGen
