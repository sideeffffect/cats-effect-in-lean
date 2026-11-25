import CatsEffectInLean.Props.Phase7.Dispatcher

/-!
# `Dispatcher`: shared lemmas of the witnesses and the battery (Phase 7, track P7D)

Light module. The user programs of the witnesses are closed: `IO.pure(())` (`p`), `IO.cede`
(`c`), `IO.sleep(1)`. There is no user function: every even id throws (`u`). The kernel runs are
in the heavy modules `Proofs/Phase7/DispatcherRun*.lean` (one run each, decision 55).
-/

namespace CatsEffectInLean.Proofs.Phase7.DispatcherCommon

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Props.Phase7.Dispatcher

/-- No user function: every user call throws. -/
def userR : UserResult := { out := .throw { code := 0 } }

def u : UserEnv := { call := fun _ _ _ => userR }

/-- `IO.pure(())`. -/
def p : IO := .pure .unit

/-- `IO.cede`. -/
def c : IO := .cede

theorem callV_even (ho : List Val → List Val) (x : Inp) (id : Nat)
    (hid : id % 2 = 0) (a : Val) (v : View) : (env ho x u).callV id a v = userR := by
  have h1 : isLibId id = false := by simp [isLibId, hid]
  simp [env, CatsEffectInLean.Std.Dispatcher.env, CatsEffectInLean.Std.Dispatcher.DL.ofId?,
    CatsEffectInLean.Std.Supervisor.env, CatsEffectInLean.Std.Supervisor.dispatch,
    CatsEffectInLean.Std.Supervisor.dispatch.go, CatsEffectInLean.Std.Supervisor.SLam.ofId?,
    Bracket.BLam.ofId?, Race.ofId?, CatsEffectInLean.Std.Dispatcher.dispatchD, h1, harnessed,
    HLam.ofId?, u]

/-- `WellFormed` for a closed program that calls no user code. -/
theorem wf (ho : List Val → List Val) (x : Inp) (q : IO)
    (hq : WF.progOK dispLib (fun h => ([] : List Handle).contains h) q = true) :
    WellFormed dispLib [] (env ho x u) q := by
  refine ⟨hq, fun id hid arg v => ⟨fun w _ => ?_, ?_⟩, ?_⟩
  · rw [callV_even ho x id hid, callV_even ho x id hid]
  · rw [callV_even ho x id hid]; simp [userR, WF.ResultOK, WF.EffectsOK, WF.OutOK]
  · refine WF.pollOpaque_of_const (env ho x u) (fun _ => userR) [] userR
      (fun id arg v hid => callV_even ho x id hid arg v) (by decide) (fun _ _ _ => rfl) ?_ (fun _ _ => rfl)
    intro σ _ k hk
    simp at hk

theorem p_ok : WF.progOK dispLib (fun h => ([] : List Handle).contains h) p = true := by decide +kernel
theorem c_ok : WF.progOK dispLib (fun h => ([] : List Handle).contains h) c = true := by decide +kernel
theorem sl_ok : WF.progOK dispLib (fun h => ([] : List Handle).contains h) (.sleep 1) = true := by
  decide +kernel

theorem isOrder_id : IsOrder id := fun es => List.Perm.refl es

/-- `AllWF` for programs that each pass `progOK`. -/
theorem allWF_of (ho : List Val → List Val) (x : Inp)
    (h : ∀ q ∈ x.b :: x.c :: x.ws, WF.progOK dispLib (fun h => ([] : List Handle).contains h) q = true) :
    AllWF ho x u := fun q hq => wf ho x q (h q hq)

/-- The closed programs of the witnesses. -/
def Closed (q : IO) : Prop := q = p ∨ q = c ∨ q = .sleep 1

instance : DecidablePred Closed := fun q => inferInstanceAs (Decidable (q = p ∨ q = c ∨ q = .sleep 1))

theorem closed_ok (q : IO) (h : Closed q) :
    WF.progOK dispLib (fun h => ([] : List Handle).contains h) q = true := by
  rcases h with rfl | rfl | rfl
  · exact p_ok
  · exact c_ok
  · exact sl_ok

/-- `Hyp` for an input whose programs are closed (`p`, `c`, `sleep 1`), with modes ≤ 1 and
submitters 0, 1 or `late`, and lengths that match (all by `decide`). -/
theorem hyp_of (x : Inp) (n : Nat) (hn : 1 ≤ n) (hc : ∀ q ∈ x.b :: x.c :: x.ws, Closed q)
    (hm : ∀ m ∈ x.ms, m ≤ 1) (hp : ∀ q ∈ x.ps, q = 0 ∨ q = 1 ∨ q = late)
    (hl1 : x.ms.length = x.ws.length) (hl2 : x.ps.length = x.ws.length) : Hyp id n x u :=
  ⟨isOrder_id, hn, allWF_of id x (fun q hq => closed_ok q (hc q hq)), hm, hp, hl1, hl2⟩

/-! ## Chunks of a run (kernel memory, decision 55)

A long run is checked in chunks: the state after `a` micro-steps is written out as a literal
(`Proofs/Phase7/DispatcherState*.lean`, generated from `Repr`), one kernel check shows that the
run reaches it, and the next chunk starts from it. -/

section
variable {M : Type} (cfg : Config) (mm : MaskModel M) (e : UserEnv)

theorem runP_halted : ∀ (fuel : Nat) (cs : List PChoice) (s : Sched M), s.halt.isSome →
    runSchedStateP cfg mm e fuel cs s = s
  | 0, _, _, _ => rfl
  | fuel + 1, cs, s, h => by
    cases hs : s.halt with
    | none => simp [hs] at h
    | some _ => simp [runSchedStateP, hs]

theorem runP_add : ∀ (a b : Nat) (cs : List PChoice) (s : Sched M),
    runSchedStateP cfg mm e (a + b) cs s =
      runSchedStateP cfg mm e b (cs.drop a) (runSchedStateP cfg mm e a cs s)
  | 0, b, cs, s => by simp [runSchedStateP]
  | a + 1, b, cs, s => by
    rw [show a + 1 + b = (a + b) + 1 by omega]
    cases hs : s.halt with
    | some _ =>
      simp only [runSchedStateP, hs]
      exact (runP_halted cfg mm e b _ s (by simp [hs])).symm
    | none =>
      simp only [runSchedStateP, hs]
      rw [runP_add a b cs.tail]
      cases cs <;> simp

end

/-- A pseudo-random schedule (the smoke tests' generator): `preempt` with probability 1/5,
else `pick k` with `k < 4`. -/
def nx (x : Nat) : Nat := (x * 1103515245 + 12345) % 2147483648

def schedAux : Nat → Nat → List PChoice
  | 0, _ => []
  | len + 1, x => let y := nx x; (if y % 5 == 0 then .preempt else .pick ((y / 7) % 4)) :: schedAux len y

def sched (seed len : Nat) : List PChoice := schedAux len (nx (seed + 17))

/-! ## Inputs of the witnesses -/

/-- One pure task from the body (`unsafeToFutureCancelable`). -/
def xs0 : Inp := pureInp [0] [0] [] p p
/-- One pure task from the body (`unsafeRunAndForget`). -/
def xs1 : Inp := pureInp [0] [1] [] p p
/-- One pure task, canceled by the body. -/
def xcn : Inp := pureInp [0] [0] [0] p p
/-- One pure task submitted after `use` returned. -/
def xlate : Inp := pureInp [late] [0] [] p p
/-- Two tasks `IO.cede` from the body. -/
def xce : Inp := { ws := [c, c], ps := [0, 0], ms := [0, 0], cn := [], c := p, b := p, sw := false }
/-- One task `sleep(1)`, body `IO.cede`. -/
def xsl : Inp := sleepInp [1] [0] c
/-- One task `sleep(1)`, canceled after it started (statement 8). -/
def xcan : Inp := cancelInp [1]
/-- Two pure tasks: one from the body, one from the concurrent fiber. -/
def x90 : Inp := pureInp [0, 1] [0, 0] [] p p

end CatsEffectInLean.Proofs.Phase7.DispatcherCommon
