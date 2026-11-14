import CatsEffectInLean.Model.Codec

/-!
# Harness names: user code must not name the test harness (decision 54)

A test of an invariant puts markers in harness positions (for example "emit `R` when release
starts"). User code must not run a marker in another position. A marker is reached through a
*name*: a function id (`Fn.user k`), an `REnv` index, an acquire/release code, a resource code.

Why not only a captured handle: library closures keep function ids in their fields as plain
`Val.nat` (for example `Bracket.BLam.thenUse use a`, `ResourceUse.ULam.allocFn (.user idx)`,
`Resource.Clo.makePair rel`). `WellFormed` sees only handle values (`Val.handles`), not numbers.
So a user program can forward any id that it can write down, through such a closure, without a
handle (review batch 5). A handle in the marker's own id does not help: the forwarding closure
holds the id as a number.

So the check here looks at every number. `mentionsV bad v` is true if `v` contains a value of
`bad` as a subterm, or a `Val.nat j` whose closure value (`Codec.cloOfId j`) mentions `bad`
(recursively: a closure field can be the id of another closure). Every number is decoded,
also a plain data number (conservative). The decoding depth is bounded by `decodeDepth`; at the
bound the answer is "mentions" (conservative: the check can say "mentions" too often, never too
rarely). The codec makes nested numbers much smaller than the id that holds them (`valToNat` of
`nat 0` is 98), so real chains are short. Programs (`IO`), runtime closures, resources, effects and user
results are checked through all their values and function ids.

A harness statement then assumes that user code never *introduces* a harness name: if a user
result mentions one, its argument mentions one too (user code may pass on what it got). The
statements check that the library never gives a harness name to user code.
-/

namespace CatsEffectInLean.Props.Phase6.HarnessNames

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- One level of the check: the structure of `v`; a number `j` is decoded (`Codec.cloOfId`) and
its closure value checked by `dec`. -/
def scanAux (bad : List Val) (dec : Val → Bool) : Val → Bool
  | v@(.nat j) => bad.contains v ||
    match cloOfId j with
    | some c => dec c
    | none => false
  | v@(.pair a b) => bad.contains v || scanAux bad dec a || scanAux bad dec b
  | v@(.left a) | v@(.right a) | v@(.some a) | v@(.ocSucceeded a) => bad.contains v || scanAux bad dec a
  | v => bad.contains v

/-- Does `v` mention a value of `bad`? `fuel` bounds the depth of nested closure decoding; at
`0` the answer is "mentions" (conservative). Structural recursion, so the kernel evaluates it. -/
def scanV (bad : List Val) : (fuel : Nat) → Val → Bool
  | 0, _ => true
  | n + 1, v => scanAux bad (scanV bad n) v

/-- Decode depth of `mentionsV` (a nested id is a closure field of a closure field ...). -/
def decodeDepth : Nat := 64

/-- `v` mentions a harness name of `bad`. -/
def mentionsV (bad : List Val) (v : Val) : Bool := scanV bad decodeDepth v

mutual
/-- A program mentions a harness name (in a value or a function id). -/
def mentionsIO (bad : List Val) : IO → Bool
  | .pure v => mentionsV bad v
  | .delay f | .uncancelable f | .ioCont f | .local f | .blocking _ f => mentionsFn bad f
  | .map a f | .flatMap a f | .handleErrorWith a f => mentionsIO bad a || mentionsFn bad f
  | .attempt a | .start a | .unmaskRunLoop a _ _ | .evalOn a _ => mentionsIO bad a
  | .onCancel a b | .racePair a b => mentionsIO bad a || mentionsIO bad b
  | _ => false
/-- A function mentions a harness name: its id, or the program inside a runtime closure. -/
def mentionsFn (bad : List Val) : Fn → Bool
  | .user id => mentionsV bad (.nat id)
  | .rt k => mentionsRt bad k
/-- Runtime closures: only `racePair` holds programs, only `deferredComplete` a value. -/
def mentionsRt (bad : List Val) : RtFn → Bool
  | .racePairBody a b | .racePairUnc a b _ | .racePairRegister a b _ => mentionsIO bad a || mentionsIO bad b
  | .deferredComplete _ v => mentionsV bad v
  | _ => false
end

/-- An effect mentions a harness name. -/
def mentionsEff (bad : List Val) : UserEffect → Bool
  | .writeRef _ v | .invokeCb _ v | .deferCb _ v | .emit v | .allocRef v => mentionsV bad v
  | .allocDeferred | .report _ => false

/-- A user result mentions a harness name (effects and output). -/
def mentionsR (bad : List Val) (r : UserResult) : Bool :=
  r.effects.any (mentionsEff bad) ||
    match r.out with
    | .ret v => mentionsV bad v
    | .prog p => mentionsIO bad p
    | .throw _ => false

end CatsEffectInLean.Props.Phase6.HarnessNames
