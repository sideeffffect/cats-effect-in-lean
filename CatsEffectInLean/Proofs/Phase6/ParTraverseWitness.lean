import CatsEffectInLean.Props.Phase6.ParTraverse
import CatsEffectInLean.Model.EnumP

/-!
# Satisfiability witnesses of the `parTraverseN` statements (decision 53)

For each statement: one concrete input that meets all hypotheses together, and one run (fuel and
`PChoice` list, kernel-checked) that reaches the interesting case.

* `parTraverseNOrder_satisfiable`: `n = 2`, inputs `[1, 2]`, `f = _ => IO.pure(0)`: a run ends
  `Succeeded([(1, 0), (2, 0)])` (two actions in parallel, results in input order).
* `parTraverseNPureSucceeds_satisfiable`: the same `f` with `g = _ => 0`, `n = 1`, inputs `[1, 2]`.
* `parTraverseNErrorAborts_satisfiable`: `n = 2`, inputs `[1, 2]`, `f(1)` raises `E5`, `f(2)` is
  `IO.never`: a run ends `Errored(E5)` (the never-ending action is canceled).
* `parTraverseNCancelAborts_satisfiable`: the same with `f(1) = IO.canceled`: a run ends `Canceled`.
* `parTraverseNSucceedsGen_satisfiable`: `n = 2`, five inputs `[1..5]` (the supervision set
  becomes a `HashSet`), `HashSet` order `List.reverse`, `f(a) = IO.cede.replicateA_(a % 2).as(a)`:
  a run ends `Succeeded([1, 2, 3, 4, 5])`.
* `parTraverseNErrorAbortsGen_satisfiable`: `n = 1`, inputs `[1, 2, 3]`, `f(1)` cedes once and
  gives `0`, `f(2)` cedes twice and raises `E5`, `f(3)` never completes: `f(2)` starts only after
  `f(1)` completes; a run ends `Errored(E5)`.
* `parTraverseNCancelAbortsGen_satisfiable`: the same with `f(2)` canceled: a run ends `Canceled`.
-/

namespace CatsEffectInLean.Proofs.Phase6.ParTraverseWitness

open CatsEffectInLean.Model
open CatsEffectInLean.Model.Codec
open CatsEffectInLean.Model.ParTraverse
open CatsEffectInLean.Props.Phase6.ParTraverse

/-- The `HashSet` order of the runs below (none of them reaches 5 elements, except where noted). -/
def idOrd : List Val → List Val := fun xs => xs

theorem idOrd_perm (xs : List Val) : (idOrd xs).Perm xs := List.Perm.refl _

/-! ## Constant user code: id 2 is `_ => IO.pure(0)` -/

def cR : Nat → UserResult
  | 1 => { out := .prog (.pure (.nat 0)) }
  | _ => { out := .throw { code := 0 } }

def cu : UserEnv where
  call id _ _ := cR (id / 2)

theorem env_even (ord : List Val → List Val) (u : UserEnv) (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (env ord u).callV id a v = u.callV id a v := by
  have h1 : PT.ofId? id = none := by simp [PT.ofId?, isLibId, hid]
  have h2 : Bracket.BLam.ofId? id = none := Bracket.BLam.ofId?_even hid
  have h3 : Race.ofId? id = none := by
    unfold Race.ofId?; simp [isLibId, hid]
  show ParTraverse.dispatch ord u id a v = _
  simp [ParTraverse.dispatch, h1, h2, h3, isLibId, hid]

theorem tagged_even (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) :
    (tagged cu).callV id a v = cR (id / 2) := by
  have h : TL.ofId? id = none := by simp [TL.ofId?, isLibId, hid]
  simp [tagged, h, cu]

theorem cR_ok (n : Nat) (R : Handle → Prop) (v : View) : WF.ResultOK ptIsLib R v (cR n) := by
  match n with
  | 0 | 1 => simp [cR, WF.ResultOK, WF.EffectsOK, WF.OutOK, WF.progOK, WF.sub, Val.handles]
  | _ + 2 => simp [cR, WF.ResultOK, WF.EffectsOK, WF.OutOK]

theorem constOpaque (e : UserEnv) (he : ∀ id, id % 2 = 0 → ∀ a v, e.callV id a v = cR (id / 2)) :
    WF.PollOpaque e := by
  refine WF.pollOpaque_of_const e (fun id => cR (id / 2)) [2] { out := .throw { code := 0 } }
    (fun id arg v hid => he id hid arg v) (by decide +kernel) ?_ ?_ (fun _ _ => rfl)
  · intro id hid hk
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
    obtain h | h : id / 2 = 0 ∨ 2 ≤ id / 2 := by omega
    · simp only [h]; rfl
    · obtain ⟨k, hk⟩ := Nat.exists_eq_add_of_le h
      simp only [hk, show 2 + k = k + 2 by omega]; rfl
  · intro σ _ k hk
    simp only [List.mem_cons, List.not_mem_nil, or_false] at hk
    subst hk; rfl

theorem wfConst (e : UserEnv) (he : ∀ id, id % 2 = 0 → ∀ a v, e.callV id a v = cR (id / 2)) (p : IO)
    (hp : WF.progOK ptIsLib (fun h => ([] : List Handle).contains h) p = true) :
    WellFormed ptIsLib [] e p :=
  ⟨hp, fun id hid arg v => ⟨fun w _ => by rw [he id hid, he id hid], by rw [he id hid]; exact cR_ok _ _ _⟩,
    constOpaque e he⟩

theorem exists_of_map {o? : Option Obs} {p : Obs → Bool} (h : o?.map p = some true) :
    ∃ o, o? = some o ∧ p o = true := by
  cases o? with
  | none => cases h
  | some o => exact ⟨o, rfl, by simpa using h⟩

/-! ## Statement 1 -/

def orderRun : Option Obs :=
  runObsP {} counterMaskModel (env idOrd (tagged cu)) 3000 [] (parTraverseNIO 2 [.nat 1, .nat 2] (TL.tag 2).id)

theorem orderRun_ok : orderRun.map (fun o =>
    o.summary == .done (.succeeded (listV [.pair (.nat 1) (.nat 0), .pair (.nat 2) (.nat 0)]))) = some true := by
  decide +kernel

theorem parTraverseNOrder_satisfiable :
    ∃ (ord : List Val → List Val) (u : UserEnv) (n : Nat) (as : List Val) (f : Nat),
      (∀ xs, (ord xs).Perm xs) ∧ 1 ≤ n ∧ f % 2 = 0 ∧
      WellFormed ptIsLib [] (env ord (tagged u)) (parTraverseNIO n as (TL.tag f).id) ∧
      ∃ o, outcomesP {} counterMaskModel (env ord (tagged u)) (parTraverseNIO n as (TL.tag f).id) o ∧
        o.summary = .done (.succeeded (listV [.pair (.nat 1) (.nat 0), .pair (.nat 2) (.nat 0)])) := by
  obtain ⟨o, ho, hp⟩ := exists_of_map orderRun_ok
  refine ⟨idOrd, cu, 2, [.nat 1, .nat 2], 2, idOrd_perm, by decide, rfl,
    wfConst _ (fun id hid a v => by rw [env_even _ _ id hid, tagged_even id hid]) _ (by decide +kernel),
    o, ⟨3000, [], ho⟩, by simpa using hp⟩

/-! ## Statement 2 -/

def pureRun : Option Obs :=
  runObsP {} counterMaskModel (env idOrd cu) 3000 [] (parTraverseNIO 1 [.nat 1, .nat 2] 2)

theorem pureRun_ok : pureRun.map (fun o =>
    o.summary == .done (.succeeded (listV [.nat 0, .nat 0]))) = some true := by
  decide +kernel

theorem cu_even (id : Nat) (hid : id % 2 = 0) (a : Val) (v : View) : (env idOrd cu).callV id a v = cR (id / 2) := by
  rw [env_even _ _ id hid]; rfl

theorem parTraverseNPureSucceeds_satisfiable :
    ∃ (ord : List Val → List Val) (u : UserEnv) (n : Nat) (as : List Val) (f : Nat) (g : Val → Val),
      (∀ xs, (ord xs).Perm xs) ∧ 1 ≤ n ∧ f % 2 = 0 ∧
      (∀ a v, u.callV f a v = { out := .prog (.pure (g a)) }) ∧
      WellFormed ptIsLib [] (env ord u) (parTraverseNIO n as f) ∧
      ∃ o, outcomesP {} counterMaskModel (env ord u) (parTraverseNIO n as f) o ∧
        o.summary = .done (.succeeded (listV (as.map g))) := by
  obtain ⟨o, ho, hp⟩ := exists_of_map pureRun_ok
  refine ⟨idOrd, cu, 1, [.nat 1, .nat 2], 2, fun _ => .nat 0, idOrd_perm, by decide, rfl, fun _ _ => rfl,
    wfConst _ cu_even _ (by decide +kernel), o, ⟨3000, [], ho⟩, by simpa using hp⟩

/-! ## Statements 3 and 4: `f(1)` raises (or cancels), `f(2)` never completes -/

/-- User code: id 2 is `a => if (a == 1) x else IO.never`. -/
def aR (x : IO) (id : Nat) (a : Val) : UserResult :=
  if id / 2 = 1 then { out := .prog (if a = .nat 1 then x else Timeout.neverIO) }
  else { out := .throw { code := 0 } }

def au (x : IO) : UserEnv where
  call id a _ := aR x id a

theorem rnVal_eq_nat (σ : WF.PollRen) (a : Val) (k : Nat) : WF.rnVal σ a = .nat k ↔ a = .nat k := by
  cases a <;> simp [WF.rnVal]

theorem neverFn (σ : WF.PollRen) : WF.rnFn σ Timeout.TLam.neverBody.fn = Timeout.TLam.neverBody.fn :=
  WF.rnFn_user_of_all σ _ (by decide +kernel)

/-- The id of the `IO.never` body closure. -/
def neverId : Nat := 2 * valToNat Timeout.TLam.neverBody.toVal + 1

theorem neverCaptured : WF.captured neverId = [] := by decide +kernel

theorem neverLib : ptIsLib neverId = true := by decide +kernel

theorem neverOK (mem : Handle → Bool) : WF.progOK ptIsLib mem Timeout.neverIO = true := by
  have h : Timeout.neverIO = .ioCont (.user neverId) := rfl
  rw [h]
  simp [WF.progOK, WF.fnOK, neverCaptured, neverLib, WF.sub]

theorem aOpaque (x : IO) (hx : ∀ σ : WF.PollRen, WF.rnIO σ x = x) : WF.PollOpaque (env idOrd (au x)) := by
  intro σ hσ id hid arg v
  have hid' : WF.rnId σ id % 2 = 0 := by rw [WF.rnId_mod_two]; exact hid
  rw [env_even _ _ _ hid', env_even _ _ _ hid]
  show aR x (WF.rnId σ id) (WF.rnVal σ arg) = WF.rnResult σ (aR x id arg)
  have h2 : (cloOfId 2).all (fun c => !WF.hasPoll c) = true := by decide +kernel
  by_cases hk : id = 2
  · subst hk
    rw [WF.rnId_of_noPoll σ 2 (fun c hc => by
      have := h2; rw [hc] at this; simpa using this)]
    have hn : WF.rnIO σ Timeout.neverIO = Timeout.neverIO := by
      simp [Timeout.neverIO, WF.rnIO, neverFn]
    by_cases ha : arg = .nat 1
    · subst ha; simp [aR, WF.rnVal, WF.rnResult, hx]
    · have : WF.rnVal σ arg ≠ .nat 1 := fun h => ha ((rnVal_eq_nat σ arg 1).mp h)
      simp [aR, ha, this, WF.rnResult, hn]
  · have hne : WF.rnId σ id ≠ 2 := by
      intro h
      exact hk (WF.eq_of_rnId_eq σ (fun c hc => by have := h2; rw [hc] at this; simpa using this) h)
    have h1 : id / 2 ≠ 1 := by omega
    have h1' : WF.rnId σ id / 2 ≠ 1 := by omega
    simp [aR, h1, h1', WF.rnResult]

theorem aCall (x : IO) (n : Nat) (R : Handle → Prop) (v : View) (a : Val)
    (hx : WF.progOK ptIsLib (WF.memOf R) x = true) :
    WF.ResultOK ptIsLib R v (aR x n a) := by
  unfold aR
  split
  · split
    · simp [WF.ResultOK, WF.EffectsOK, WF.OutOK, hx]
    · simp only [WF.ResultOK, WF.EffectsOK, WF.OutOK]; exact neverOK _
  · simp [WF.ResultOK, WF.EffectsOK, WF.OutOK]

theorem aWf (x : IO) (hx : ∀ R, WF.progOK ptIsLib (WF.memOf R) x = true)
    (hrn : ∀ σ : WF.PollRen, WF.rnIO σ x = x) (p : IO)
    (hp : WF.progOK ptIsLib (fun h => ([] : List Handle).contains h) p = true) :
    WellFormed ptIsLib [] (env idOrd (au x)) p := by
  refine ⟨hp, fun id hid arg v => ⟨fun w _ => ?_, ?_⟩, aOpaque x hrn⟩
  · rw [env_even _ _ _ hid, env_even _ _ _ hid]; rfl
  · rw [env_even _ _ _ hid]; exact aCall x id _ v arg (hx _)

def errRun : Option Obs :=
  runObsP {} counterMaskModel (env idOrd (au (.error { code := 5 }))) 3000 [] (parTraverseNIO 2 [.nat 1, .nat 2] 2)

theorem errRun_ok : errRun.map (fun o => o.summary == .done (.errored { code := 5 })) = some true := by
  decide +kernel

theorem parTraverseNErrorAborts_satisfiable :
    ∃ (ord : List Val → List Val) (u : UserEnv) (n : Nat) (as : List Val) (f : Nat) (a0 : Val) (e : Err),
      (∀ xs, (ord xs).Perm xs) ∧ 1 ≤ n ∧ f % 2 = 0 ∧ a0 ∈ as.take n ∧ e.kind = .nonFatal ∧
      (∀ a v, u.callV f a v = { out := .prog (if a = a0 then .error e else Timeout.neverIO) }) ∧
      WellFormed ptIsLib [] (env ord u) (parTraverseNIO n as f) ∧
      ∃ o, outcomesP {} counterMaskModel (env ord u) (parTraverseNIO n as f) o ∧
        o.summary = .done (.errored e) := by
  obtain ⟨o, ho, hp⟩ := exists_of_map errRun_ok
  refine ⟨idOrd, au (.error { code := 5 }), 2, [.nat 1, .nat 2], 2, .nat 1, { code := 5 }, idOrd_perm,
    by decide, rfl, by decide, rfl, fun a v => by simp [au, aR], ?_, o, ⟨3000, [], ho⟩, by simpa using hp⟩
  exact aWf _ (fun _ => rfl) (fun _ => rfl) _ (by decide +kernel)

def canRun : Option Obs :=
  runObsP {} counterMaskModel (env idOrd (au .canceled)) 3000 [] (parTraverseNIO 2 [.nat 1, .nat 2] 2)

theorem canRun_ok : canRun.map (fun o => o.summary == .done .canceled) = some true := by
  decide +kernel

theorem parTraverseNCancelAborts_satisfiable :
    ∃ (ord : List Val → List Val) (u : UserEnv) (n : Nat) (as : List Val) (f : Nat) (a0 : Val),
      (∀ xs, (ord xs).Perm xs) ∧ 1 ≤ n ∧ f % 2 = 0 ∧ a0 ∈ as.take n ∧
      (∀ a v, u.callV f a v = { out := .prog (if a = a0 then .canceled else Timeout.neverIO) }) ∧
      WellFormed ptIsLib [] (env ord u) (parTraverseNIO n as f) ∧
      ∃ o, outcomesP {} counterMaskModel (env ord u) (parTraverseNIO n as f) o ∧ o.summary = .done .canceled := by
  obtain ⟨o, ho, hp⟩ := exists_of_map canRun_ok
  refine ⟨idOrd, au .canceled, 2, [.nat 1, .nat 2], 2, .nat 1, idOrd_perm, by decide, rfl, by decide,
    fun a v => by simp [au, aR], ?_, o, ⟨3000, [], ho⟩, by simpa using hp⟩
  exact aWf _ (fun _ => rfl) (fun _ => rfl) _ (by decide +kernel)

/-! ## Statements 5-7: the behaviour harness -/

def bhOk : Val → Nat × Base
  | .nat k => (k % 2, .ok (.nat k))
  | _ => (0, .ok .unit)

def ins5 : List Val := [.nat 1, .nat 2, .nat 3, .nat 4, .nat 5]

def okRun : Option Obs :=
  runObsP {} counterMaskModel (env List.reverse (behaved bhOk)) 8000 [] (parTraverseNIO 2 ins5 BL.body.id)

theorem okRun_ok : okRun.map (fun o => o.summary == .done (.succeeded (listV ins5))) = some true := by
  decide +kernel

theorem parTraverseNSucceedsGen_satisfiable :
    ∃ (ord : List Val → List Val) (n : Nat) (as : List Val) (bh : Val → Nat × Base),
      (∀ xs, (ord xs).Perm xs) ∧ 1 ≤ n ∧ (∀ a ∈ as, ∃ v, (bh a).2 = .ok v) ∧
      ∃ o, outcomesP {} counterMaskModel (env ord (behaved bh)) (parTraverseNIO n as BL.body.id) o ∧
        o.summary = .done (.succeeded (listV (as.map fun a => (bh a).2.okVal))) := by
  obtain ⟨o, ho, hp⟩ := exists_of_map okRun_ok
  refine ⟨List.reverse, 2, ins5, bhOk, fun xs => List.reverse_perm xs, by decide, ?_, o, ⟨8000, [], ho⟩, ?_⟩
  · intro a ha; simp [ins5] at ha; rcases ha with h | h | h | h | h <;> subst h <;> exact ⟨_, rfl⟩
  · simpa [ins5, bhOk, Base.okVal] using hp

/-- `f(1)`: one `cede`, then `0`; `f(2)`: two `cede`s, then `x`; other inputs: `IO.never`. -/
def bhAbort (x : Base) : Val → Nat × Base
  | .nat 1 => (1, .ok (.nat 0))
  | .nat 2 => (2, x)
  | _ => (0, .never)

def ins3 : List Val := [.nat 1, .nat 2, .nat 3]

def errGenRun : Option Obs :=
  runObsP {} counterMaskModel (env idOrd (behaved (bhAbort (.err { code := 5 })))) 3000 []
    (parTraverseNIO 1 ins3 BL.body.id)

theorem errGenRun_ok : errGenRun.map (fun o => o.summary == .done (.errored { code := 5 })) = some true := by
  decide +kernel

theorem parTraverseNErrorAbortsGen_satisfiable :
    ∃ (ord : List Val → List Val) (n : Nat) (as : List Val) (bh : Val → Nat × Base),
      (∀ xs, (ord xs).Perm xs) ∧ 1 ≤ n ∧ (∀ a ∈ as, (bh a).2 ≠ .canc) ∧
      (∀ a ∈ as, ∀ e, (bh a).2 = .err e → e.kind = .nonFatal) ∧
      (∃ i, ∃ h : i < as.length, (∃ e, (bh as[i]).2 = .err e) ∧ nevers bh (as.take i) < n) ∧
      ∃ o, outcomesP {} counterMaskModel (env ord (behaved bh)) (parTraverseNIO n as BL.body.id) o ∧
        ∃ a ∈ as, ∃ e, (bh a).2 = .err e ∧ o.summary = .done (.errored e) := by
  obtain ⟨o, ho, hp⟩ := exists_of_map errGenRun_ok
  refine ⟨idOrd, 1, ins3, bhAbort (.err { code := 5 }), idOrd_perm, by decide, ?_, ?_,
    ⟨1, by decide, ⟨_, rfl⟩, by decide⟩, o, ⟨3000, [], ho⟩, .nat 2, by simp [ins3], _, rfl, by simpa using hp⟩
  · intro a ha; simp [ins3] at ha; rcases ha with h | h | h <;> subst h <;> simp [bhAbort]
  · intro a ha e he; simp [ins3] at ha
    rcases ha with h | h | h <;> subst h <;> simp [bhAbort] at he; subst he; rfl

def canGenRun : Option Obs :=
  runObsP {} counterMaskModel (env idOrd (behaved (bhAbort .canc))) 3000 [] (parTraverseNIO 1 ins3 BL.body.id)

theorem canGenRun_ok : canGenRun.map (fun o => o.summary == .done .canceled) = some true := by
  decide +kernel

theorem parTraverseNCancelAbortsGen_satisfiable :
    ∃ (ord : List Val → List Val) (n : Nat) (as : List Val) (bh : Val → Nat × Base),
      (∀ xs, (ord xs).Perm xs) ∧ 1 ≤ n ∧ (∀ a ∈ as, ∀ e, (bh a).2 ≠ .err e) ∧
      (∃ i, ∃ h : i < as.length, (bh as[i]).2 = .canc ∧ nevers bh (as.take i) < n) ∧
      ∃ o, outcomesP {} counterMaskModel (env ord (behaved bh)) (parTraverseNIO n as BL.body.id) o ∧
        o.summary = .done .canceled := by
  obtain ⟨o, ho, hp⟩ := exists_of_map canGenRun_ok
  refine ⟨idOrd, 1, ins3, bhAbort .canc, idOrd_perm, by decide, ?_, ⟨1, by decide, rfl, by decide⟩,
    o, ⟨3000, [], ho⟩, by simpa using hp⟩
  intro a ha e; simp [ins3] at ha; rcases ha with h | h | h <;> subst h <;> simp [bhAbort]

end CatsEffectInLean.Proofs.Phase6.ParTraverseWitness
