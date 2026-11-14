import CatsEffectInLean.Model.WellFormed

/-!
# Harness privacy (decision 56): the one shared module

A test of an invariant (release runs once, finalizer runs once, ...) counts harness events in a
cell that only the harness writes. User code must not be able to make a harness event happen in
another position. Review batches 4-6 found a new forgery each time a single path was closed. This
module gives the construction that closes the whole class.

## The construction

1. **Tokens.** The harness program first allocates its own cells (`Ref`s). Their handles are the
   *tokens*. The root starts with an empty heap, so the harness cells are cells `0 .. n-1`, and
   every later cell (user or library) gets a larger id: no allocation can give user code a token.
   The harness never passes a token to user code (as an argument, a captured value or a readable
   cell).
2. **Harness events capture a token.** A harness event is a harness closure (an odd id outside
   the statement's `Lib`) whose closure value holds a token, and it writes a token cell. So:
   * user code cannot write the cell (`WellFormed` clause 5: a write needs the held handle);
   * user code cannot name the event closure (`WellFormed` clause 3: an odd id must be in the
     `Lib`, and its captured handles must be held);
   * user code cannot forward it through a library closure field: `WF.captured` follows the
     function fields of library closures (`Lib.fields`, decision 56, review batch 6 track G);
3. **Harness codes are token names.** Some mirrors reach harness programs through *codes*
   (numbers or values that the library looks up, for example the acquire and release codes of
   `Resource.make`, a `Resource` code, a `Bind` code). A harness code must be a *token name*: a
   value that holds a token, or a number whose closure value (`Codec.cloOfId`) holds one,
   recursively (`tokFreeV` is `false`).
4. **The one restriction on user code: it cannot name a token.** Every result of user code (its
   effects, its returned value or program) is token-free (`tokFreeR`); so are the user parts of a
   library environment (`Bind` results, other acquire/release programs, other resources). There
   is no escape clause: a number that user code got from the runtime (the clock, a size, a
   counter) is user data; if it happens to be a token name, user code may not output it.

Why this closes the class: a harness event runs only if a program term or a library lookup names
it. A program term built by user code names only token-free values (4), or `WellFormed` rejects a
held-handle violation (2). A library lookup uses a code from a closure field or a value; those
come from user code (token-free, so not a harness code, 3-4), from the runtime (data, never a
lookup key), or from the harness itself (the harness position). So the only harness events are
the ones in the harness positions, for every user code and every schedule.

`tokFreeV` decodes every number (data numbers too) as a possible closure id. This is not an extra
restriction: a number that decodes to a token-holding closure *is* a name of a token. The decoding
depth is bounded by `WF.capDepth`; at the bound the answer is "not free" (conservative). A code is
much larger than the numbers in it (`valToNat` of `nat 0` is 98), so a chain of depth `d` needs a
number with more than `2 ^ d` bits: the bound is never reached by a value that exists.
-/

namespace CatsEffectInLean.Props.Phase6.HarnessPrivacy

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec

/-- One level: the structure of a value; a handle in `toks` is not free; a number is decoded and
its closure value checked by `dec`. -/
def freeAux (toks : List Handle) (dec : Val → Bool) : Val → Bool
  | .nat j =>
    match cloOfId j with
    | some c => dec c
    | none => true
  | .pair a b => freeAux toks dec a && freeAux toks dec b
  | .left a | .right a | .some a | .ocSucceeded a => freeAux toks dec a
  | v => v.handles.all (fun h => !toks.contains h)

/-- `v` names no token, to decode depth `d` (`false` at depth 0: conservative). Structural, so the
kernel evaluates it. -/
def freeD (toks : List Handle) : Nat → Val → Bool
  | 0, _ => false
  | d + 1, v => freeAux toks (freeD toks d) v

/-- `v` is token-free. -/
def tokFreeV (toks : List Handle) (v : Val) : Bool := freeD toks WF.capDepth v

mutual
/-- A program is token-free: all its values and function ids. -/
def tokFreeIO (toks : List Handle) : IO → Bool
  | .pure v => tokFreeV toks v
  | .delay f | .uncancelable f | .ioCont f | .local f | .blocking _ f => tokFreeFn toks f
  | .map a f | .flatMap a f | .handleErrorWith a f => tokFreeIO toks a && tokFreeFn toks f
  | .attempt a | .start a | .unmaskRunLoop a _ _ | .evalOn a _ => tokFreeIO toks a
  | .onCancel a b | .racePair a b => tokFreeIO toks a && tokFreeIO toks b
  | _ => true
def tokFreeFn (toks : List Handle) : Fn → Bool
  | .user id => tokFreeV toks (.nat id)
  | .rt k => tokFreeRt toks k
def tokFreeRt (toks : List Handle) : RtFn → Bool
  | .racePairBody a b | .racePairUnc a b _ | .racePairRegister a b _ => tokFreeIO toks a && tokFreeIO toks b
  | .deferredComplete _ v => tokFreeV toks v
  | .cancel t | .join t | .joinUnc t _ | .joinReg t _ | .joinSel t _ _ _ | .joinClear t _
  | .cancelAsync t | .cancelAsyncUnc t _ | .cancelAsyncK t _ => tokFreeV toks (.fiber t)
  | .deferredDefer d | .deferredFlatten d | .deferredAwait d | .deferredUnc d _ | .deferredReg d _
  | .deferredSel d _ _ _ | .deferredClear d _ => tokFreeV toks (.deferred d)
  | _ => true
end

/-- An effect is token-free: its value, and the cell that it writes. -/
def tokFreeEff (toks : List Handle) : UserEffect → Bool
  | .writeRef i v => !toks.contains (.ref i) && tokFreeV toks v
  | .invokeCb _ v | .deferCb _ v | .emit v | .allocRef v => tokFreeV toks v
  | .allocDeferred | .report _ => true

/-- A user result is token-free (effects and output). -/
def tokFreeR (toks : List Handle) (r : UserResult) : Bool :=
  r.effects.all (tokFreeEff toks) &&
    match r.out with
    | .ret v => tokFreeV toks v
    | .prog p => tokFreeIO toks p
    | .throw _ => true

/-- User code cannot name a token: every result of user function `id` (even ids) is token-free,
for every argument and every view. -/
def UserPrivate (env : UserEnv) (toks : List Handle) : Prop :=
  ∀ id, id % 2 = 0 → ∀ (a : Val) (v : View), tokFreeR toks (env.callV id a v) = true

end CatsEffectInLean.Props.Phase6.HarnessPrivacy
