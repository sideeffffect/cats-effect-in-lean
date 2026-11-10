import CatsEffectInLean.Model.SchedP

/-!
# Frame lemmas for the run loop and the preemptive scheduler (Phase 6, track P)

Facts F1 and F2 of the race invariant design
(`raw/cats-effect/2026-11-10-race-invariant-track-p-notes.md`). They hold for every
micro-step of `Sched.tickP`, for all user code and all schedules, with no hypothesis:

* **F1 (`ContState` owners are stable).** The `ContState` table only grows, and the owner
  fiber (`ContState.fiber`) of a cell never changes. Every write to a cell is
  `{ st with value := ... }` (or `wasFinalizing`) of the cell itself; `IOCont` appends a cell.
* **F2 (tables grow).** The fiber table only grows, and the `CallbackStack` handle counter
  (`Heap.handles`) never goes down. So a handle that `joinReg`/`deferredReg` push is at least
  the start value `1`; slot 0 stays the constructor callback.

`Frame x y` is the relation for one `Exec` transition. `SFrame s t` is the same relation on
the live heap and the live fiber table of two scheduler states. Main results:
`tickP_sframe`, `runSchedStateP_sframe`, and `owner_stable` (the owner of a `ContState` cell
is the same in every later state).
-/

namespace CatsEffectInLean.Proofs.Lemmas.Frame

open CatsEffectInLean.Model

variable {M : Type}

/-- The owner fibers of the `ContState` cells. -/
def owners (h : Heap) : List Nat := h.conts.map (·.fiber)

/-- One `Exec` transition keeps F1 and F2. -/
structure Frame (x y : Exec M) : Prop where
  conts : owners x.heap <+: owners y.heap
  fibers : x.fibers.length ≤ y.fibers.length
  handles : x.heap.handles ≤ y.heap.handles

theorem Frame.refl (x : Exec M) : Frame x x := ⟨List.prefix_refl _, Nat.le_refl _, Nat.le_refl _⟩

theorem Frame.trans {x y z : Exec M} (a : Frame x y) (b : Frame y z) : Frame x z :=
  ⟨a.conts.trans b.conts, Nat.le_trans a.fibers b.fibers, Nat.le_trans a.handles b.handles⟩

/-- A transition that keeps the cells, the fiber count and the handle counter. -/
theorem Frame.of_eq {x y : Exec M} (hc : owners y.heap = owners x.heap)
    (hf : y.fibers.length = x.fibers.length) (hh : y.heap.handles = x.heap.handles) : Frame x y :=
  ⟨hc ▸ List.prefix_refl _, hf ▸ Nat.le_refl _, hh ▸ Nat.le_refl _⟩

theorem list_set_self {α : Type} (l : List α) (i : Nat) (a : α) (h : l[i]? = some a) :
    l.set i a = l := by
  obtain ⟨hi, rfl⟩ := List.getElem?_eq_some_iff.mp h
  exact List.set_getElem_self hi

theorem owners_setCont (h : Heap) (s : Nat) (st st' : ContState) (hs : h.conts[s]? = some st)
    (hf : st'.fiber = st.fiber) : (h.conts.set s st').map (·.fiber) = owners h := by
  rw [List.map_set, hf]
  apply list_set_self
  simp [List.getElem?_map, hs]

/-! ## Primitive `Exec` operations -/

@[simp] theorem frame_setFib (x : Exec M) (t : Nat) (f : Fiber M) : Frame x (x.setFib t f) := by
  unfold Exec.setFib
  split
  · exact Frame.of_eq rfl rfl rfl
  · exact Frame.of_eq rfl (by simp) rfl

theorem frame_setFib_right {x y : Exec M} (h : Frame x y) (t : Nat) (f : Fiber M) :
    Frame x (y.setFib t f) := h.trans (frame_setFib y t f)

theorem frame_enqueue_right {x y : Exec M} (h : Frame x y) (t : Task) : Frame x (y.enqueue t) :=
  h.trans (Frame.of_eq rfl rfl rfl)

theorem frame_markBroken_right {x y : Exec M} (h : Frame x y) (a : Abort) :
    Frame x (y.markBroken a) := by
  unfold Exec.markBroken
  split
  · exact h
  · exact h.trans (Frame.of_eq rfl rfl rfl)

theorem frame_log_right {x y : Exec M} (h : Frame x y) (e : TraceEv) : Frame x (y.log e) :=
  h.trans (Frame.of_eq rfl rfl rfl)

theorem frame_setContState {x : Exec M} {s : Nat} {st st' : ContState}
    (hs : x.heap.conts[s]? = some st) (hf : st'.fiber = st.fiber) :
    Frame x (x.setContState s st') :=
  Frame.of_eq (owners_setCont x.heap s st st' hs hf) rfl rfl

@[simp] theorem setFib_heap (x : Exec M) (t : Nat) (f : Fiber M) : (x.setFib t f).heap = x.heap := by
  unfold Exec.setFib; split <;> rfl

@[simp] theorem setFib_fibers_length (x : Exec M) (t : Nat) (f : Fiber M) :
    (x.setFib t f).fibers.length = x.fibers.length := by
  unfold Exec.setFib; split <;> simp

@[simp] theorem enqueue_heap_conts (x : Exec M) (t : Task) : (x.enqueue t).heap.conts = x.heap.conts := rfl
@[simp] theorem enqueue_heap_handles (x : Exec M) (t : Task) :
    (x.enqueue t).heap.handles = x.heap.handles := rfl
@[simp] theorem enqueue_fibers (x : Exec M) (t : Task) : (x.enqueue t).fibers = x.fibers := rfl
@[simp] theorem setDeferred_heap_conts (x : Exec M) (d : Nat) (c : DeferredCell) :
    (x.setDeferred d c).heap.conts = x.heap.conts := rfl
@[simp] theorem setDeferred_heap_handles (x : Exec M) (d : Nat) (c : DeferredCell) :
    (x.setDeferred d c).heap.handles = x.heap.handles := rfl
@[simp] theorem setDeferred_fibers (x : Exec M) (d : Nat) (c : DeferredCell) :
    (x.setDeferred d c).fibers = x.fibers := rfl

theorem frame_setContState' {x : Exec M} {s : Nat} {st' : ContState}
    (hs : (x.heap.conts[s]?).map (·.fiber) = some st'.fiber) :
    Frame x (x.setContState s st') := by
  cases h : x.heap.conts[s]? with
  | none => simp [h] at hs
  | some st => simp [h] at hs; exact frame_setContState h hs.symm

/-- Close a goal `Frame x (op (op ... y))` from `Frame x y` in context. -/
macro "frame_tac" : tactic => `(tactic| (
  (repeat (first
    | apply frame_enqueue_right
    | apply frame_setFib_right
    | apply frame_markBroken_right
    | apply frame_log_right)) <;>
  first | assumption | exact Frame.refl _))

/-! ## `contCallback` -/

theorem frame_contCallback (mm : MaskModel M) (s : Nat) (r : Val) (x : Exec M) :
    Frame x (contCallback mm s r x) := by
  unfold contCallback
  split
  · frame_tac
  · next st hs =>
    have h1 := fun v => frame_setContState (x := x) (st' := { st with value := v }) hs rfl
    split
    · exact Frame.refl _
    · exact h1 _
    · have hy := h1 (.result r)
      generalize x.setContState s { st with value := .result r } = y at hy ⊢
      simp only []
      repeat' split
      all_goals frame_tac

theorem frame_contCallback_right (mm : MaskModel M) {x y : Exec M} (h : Frame x y) (s : Nat)
    (r : Val) : Frame x (contCallback mm s r y) := h.trans (frame_contCallback mm s r y)

theorem frame_setObj_right {x y : Exec M} (h : Frame x y) (o : List ObjEntry) :
    Frame x (y.setObj o) := h.trans (Frame.of_eq rfl rfl rfl)

/-- `frame_tac` with `contCallback`, `setObj`, and a final field check. -/
macro "frame_tac2" : tactic => `(tactic| (
  (repeat (first
    | apply frame_enqueue_right
    | apply frame_setFib_right
    | apply frame_markBroken_right
    | apply frame_log_right
    | apply frame_contCallback_right
    | apply frame_setObj_right)) <;>
  first | assumption | exact Frame.refl _ | exact Frame.of_eq rfl rfl rfl))

theorem frame_setDeferred_right {x y : Exec M} (h : Frame x y) (d : Nat) (c : DeferredCell) :
    Frame x (y.setDeferred d c) := h.trans (Frame.of_eq rfl rfl rfl)

theorem frame_foldl_contCallback (mm : MaskModel M) (r : Val) :
    ∀ (l : List (Nat × Nat)) (x : Exec M),
      Frame x (l.foldl (fun x p => contCallback mm p.2 r x) x)
  | [], x => Frame.refl x
  | p :: l, x => (frame_contCallback mm p.2 r x).trans (frame_foldl_contCallback mm r l _)

/-! ## `rtCall` -/

theorem frame_rtCall (mm : MaskModel M) (k : RtFn) (arg : Val) (x : Exec M) :
    ∀ o y, rtCall mm k arg x = .ok (o, y) → Frame x y := by
  intro o y h
  unfold rtCall at h
  simp only [Exec.freshHandle] at h
  repeat' (split at h <;> try simp only [] at h)
  all_goals first
    | (simp only [reduceCtorEq] at h)
    | (simp only [Except.ok.injEq, Prod.mk.injEq] at h
       obtain ⟨-, rfl⟩ := h)
  all_goals first
    | frame_tac
    | exact frame_setContState' (by simp_all)
    | exact (frame_setDeferred_right (Frame.refl _) _ _).trans (frame_foldl_contCallback _ _ _ _)
    | (refine ⟨?_, ?_, ?_⟩ <;> first
        | exact List.prefix_refl _
        | exact Nat.le_refl _
        | (simp [owners]; done)
        | skip)

/-! ## User calls -/

theorem frame_applyEffects (mm : MaskModel M) :
    ∀ (es : List UserEffect) (x : Exec M), Frame x (applyEffects mm es x)
  | [], x => Frame.refl x
  | e :: es, x => by
    cases e <;> simp only [applyEffects] <;> first
      | exact (frame_contCallback mm _ _ x).trans (frame_applyEffects mm es _)
      | (refine Frame.trans ?_ (frame_applyEffects mm es _); exact Frame.of_eq rfl rfl rfl)

theorem frame_callUser (mm : MaskModel M) (env : UserEnv) (f : Fn) (arg : Val) (x : Exec M) :
    ∀ o y, callUser mm env f arg x = .ok (o, y) → Frame x y := by
  intro o y h
  unfold callUser at h
  split at h
  · exact frame_rtCall mm _ arg x o y h
  · simp only [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨-, rfl⟩ := h
    exact frame_applyEffects mm _ x

/-- `Frame x` for every `Exec` that a `TryRes` holds. -/
def TryOK (x : Exec M) : TryRes M → Prop
  | .ok _ y | .caught _ y | .fatal _ y => Frame x y
  | .abort _ => True

theorem frame_tryUser (mm : MaskModel M) (env : UserEnv) (f : Fn) (arg : Val) (x : Exec M) :
    TryOK x (tryUser mm env f arg x) := by
  unfold tryUser
  split
  · trivial
  · next o y h =>
    have := frame_callUser mm env f arg x _ y h
    split <;> exact this
  · next o y _ h => exact frame_callUser mm env f arg x _ y h

theorem TryOK.trans {x y : Exec M} (h : Frame x y) {r : TryRes M} (hr : TryOK y r) : TryOK x r := by
  cases r <;> simp only [TryOK] at hr ⊢ <;> first | trivial | exact h.trans hr

theorem frame_tryUser2 (mm : MaskModel M) (env : UserEnv) (thunk f : Fn) (x : Exec M) :
    TryOK x (tryUser2 mm env thunk f x) := by
  unfold tryUser2
  have h1 := frame_tryUser mm env thunk .unit x
  split
  · next r y h => rw [h] at h1; exact TryOK.trans h1 (frame_tryUser mm env f r y)
  · trivial
  · next r _ => exact h1

/-! ## `done` and the cancelation helpers -/

theorem frame_runOutcomeCb (mm : MaskModel M) (oc : Outcome) (x : Exec M) (cb : OutcomeCb) :
    Frame x (runOutcomeCb mm oc x cb) := by
  cases cb <;> first | exact Frame.refl _ | exact frame_contCallback mm _ _ x

theorem frame_foldl_outcomeCb (mm : MaskModel M) (oc : Outcome) :
    ∀ (l : List (Nat × OutcomeCb)) (x : Exec M),
      Frame x (l.foldl (fun x p => runOutcomeCb mm oc (x.log (.outcomeCb p.2 oc)) p.2) x)
  | [], x => Frame.refl x
  | p :: l, x =>
    ((frame_log_right (Frame.refl x) _).trans (frame_runOutcomeCb mm oc _ p.2)).trans
      (frame_foldl_outcomeCb mm oc l _)

theorem frame_foldl_outcomeCb_right (mm : MaskModel M) (oc : Outcome) {x y : Exec M}
    (h : Frame x y) (l : List (Nat × OutcomeCb)) :
    Frame x (l.foldl (fun x p => runOutcomeCb mm oc (x.log (.outcomeCb p.2 oc)) p.2) y) :=
  h.trans (frame_foldl_outcomeCb mm oc l y)

theorem frame_mk_right {x y : Exec M} (h : Frame x y) (f : Fiber M) :
    Frame x { fib := f, heap := y.heap, fibers := y.fibers } := h.trans (Frame.of_eq rfl rfl rfl)

theorem frame_done (cfg : Config) (mm : MaskModel M) (x : Exec M) (oc : Outcome) :
    Frame x (done cfg mm x oc) := by
  unfold done
  simp only []
  apply frame_mk_right
  repeat' split
  all_goals (try apply frame_log_right)
  all_goals (apply frame_foldl_outcomeCb_right; exact Frame.of_eq rfl rfl rfl)

theorem frame_prepare (cfg : Config) (mm : MaskModel M) (x : Exec M) (cb : Option Nat) :
    Frame x (prepareFiberForCancelation cfg mm x cb).1 := by
  unfold prepareFiberForCancelation
  split
  · exact Frame.of_eq rfl rfl rfl
  · cases cb with
    | none => exact frame_done cfg mm x _
    | some s =>
      exact (frame_contCallback_right mm (frame_log_right (Frame.refl x) _) s _).trans
        (frame_done cfg mm _ _)

theorem frame_cancelationLoopSuccessK (cfg : Config) (mm : MaskModel M) (x : Exec M) :
    Frame x (cancelationLoopSuccessK cfg mm x).1 := by
  unfold cancelationLoopSuccessK
  split
  · exact Frame.of_eq rfl rfl rfl
  · split
    · next cb os _ =>
      have h0 : Frame x (x.setObj os) := Frame.of_eq rfl rfl rfl
      cases cb with
      | none => exact h0.trans (frame_done cfg mm _ _)
      | some s =>
        exact (frame_contCallback_right mm (frame_log_right h0 _) s _).trans
          (frame_done cfg mm _ _)
    · exact Frame.refl _

theorem frame_of_tryRes {x y : Exec M} {r : TryRes M} (hr : TryOK x r) :
    (∀ o, r = .ok o y → Frame x y) ∧ (∀ e, r = .caught e y → Frame x y) ∧
      (∀ e, r = .fatal e y → Frame x y) := by
  refine ⟨?_, ?_, ?_⟩ <;> (intro _ h; subst h; exact hr)

/-! ## `succeeded` and `failed` -/

theorem frame_unwind (cfg : Config) (mm : MaskModel M) (env : UserEnv) :
    ∀ cs : List ContK,
      (∀ (x : Exec M) r d, Frame x (succeeded cfg mm env x r d cs).1) ∧
      (∀ (x : Exec M) e d, Frame x (failed cfg mm env x e d cs).1)
  | [] => ⟨fun x _ _ => by simp only [succeeded]; exact Frame.refl x,
           fun x _ _ => by simp only [failed]; exact Frame.refl x⟩
  | k :: rest => by
    obtain ⟨ihS, ihF⟩ := frame_unwind cfg mm env rest
    constructor
    · intro x r d
      simp only [succeeded]
      have h0 : Frame x (x.setConts rest) := Frame.of_eq rfl rfl rfl
      generalize x.setConts rest = x1 at h0 ⊢
      cases k <;> simp only []
      case mapK | flatMapK =>
        split
        · next f os _ =>
          have h1 : Frame x (x1.setObj os) := h0.trans (Frame.of_eq rfl rfl rfl)
          have ht := TryOK.trans h1 (frame_tryUser mm env f r (x1.setObj os))
          generalize tryUser mm env f r (x1.setObj os) = t at ht ⊢
          cases t with
          | ok o y =>
            simp only [TryOK] at ht
            cases o <;> simp only [] <;> (try split) <;>
              first | exact ht | exact ht.trans (ihS _ _ _) | exact ht.trans (ihF _ _ _)
          | caught e y =>
            simp only [TryOK] at ht
            simp only []
            (try split) <;>
              first | exact ht | exact ht.trans (ihS _ _ _) | exact ht.trans (ihF _ _ _)
          | fatal e y => exact ht
          | abort a => exact Frame.refl x |>.trans (by exact h1)
        · exact h0
      case cancelationLoopK => exact h0.trans (frame_cancelationLoopSuccessK cfg mm x1)
      case runTerminusK => exact h0.trans (frame_done cfg mm x1 _)
      case evalOnK => exact h0
      case handleErrorWithK =>
        split
        · exact h0.trans (by refine Frame.trans ?_ (ihS _ _ _); exact Frame.of_eq rfl rfl rfl)
        · exact h0
      case onCancelK => exact h0.trans (by refine Frame.trans ?_ (ihS _ _ _); exact Frame.of_eq rfl rfl rfl)
      case uncancelableK => exact h0.trans (by refine Frame.trans ?_ (ihS _ _ _); exact Frame.of_eq rfl rfl rfl)
      case unmaskK => exact h0.trans (by refine Frame.trans ?_ (ihS _ _ _); exact Frame.of_eq rfl rfl rfl)
      case attemptK => exact h0.trans (ihS _ _ _)
    · intro x e d
      simp only [failed]
      have h0 : Frame x (x.setConts rest) := Frame.of_eq rfl rfl rfl
      generalize x.setConts rest = x1 at h0 ⊢
      cases k <;> simp only []
      case mapK | flatMapK =>
        split
        · exact h0.trans (by refine Frame.trans ?_ (ihF _ _ _); exact Frame.of_eq rfl rfl rfl)
        · exact h0
      case cancelationLoopK =>
        exact h0.trans ((frame_log_right (Frame.refl x1) _).trans
          (frame_cancelationLoopSuccessK cfg mm _))
      case runTerminusK => exact h0.trans (frame_done cfg mm x1 _)
      case evalOnK => exact h0
      case handleErrorWithK =>
        split
        · next f os _ =>
          have h1 : Frame x (x1.setObj os) := h0.trans (Frame.of_eq rfl rfl rfl)
          have ht := TryOK.trans h1 (frame_tryUser mm env f (.err e) (x1.setObj os))
          generalize tryUser mm env f (.err e) (x1.setObj os) = t at ht ⊢
          cases t with
          | ok o y =>
            simp only [TryOK] at ht
            cases o <;> simp only [] <;> first | exact ht
          | caught e y =>
            simp only [TryOK] at ht
            exact ht.trans (ihF _ _ _)
          | fatal e y => exact ht
          | abort a => exact h1
        · exact h0
      case onCancelK => exact h0.trans (by refine Frame.trans ?_ (ihF _ _ _); exact Frame.of_eq rfl rfl rfl)
      case uncancelableK => exact h0.trans (by refine Frame.trans ?_ (ihF _ _ _); exact Frame.of_eq rfl rfl rfl)
      case unmaskK => exact h0.trans (by refine Frame.trans ?_ (ihF _ _ _); exact Frame.of_eq rfl rfl rfl)
      case attemptK => exact h0.trans (ihS _ _ _)

section Run
variable (cfg : Config) (mm : MaskModel M) (env : UserEnv)

theorem frame_succK (x : Exec M) (r : Val) (d : Nat) : Frame x (succeededK cfg mm env x r d).1 :=
  (frame_unwind cfg mm env x.fib.conts).1 x r d

theorem frame_failK (x : Exec M) (e : Err) (d : Nat) : Frame x (failedK cfg mm env x e d).1 :=
  (frame_unwind cfg mm env x.fib.conts).2 x e d

theorem frame_raised (x : Exec M) (e : Err) : Frame x (raised cfg mm env x e).1 := by
  unfold raised; split
  · exact Frame.refl x
  · exact frame_failK cfg mm env x e 0

theorem frame_afterValue (x : Exec M) (r : TryRes M) (h : TryOK x r) :
    Frame x (afterValue cfg mm env x r).1 := by
  unfold afterValue
  split <;> simp only [TryOK] at h
  · exact h.trans (frame_succK cfg mm env _ _ _)
  · exact h.trans (frame_failK cfg mm env _ _ _)
  · exact h
  · exact h
  · exact Frame.refl x

theorem frame_afterProg (x : Exec M) (r : TryRes M) (h : TryOK x r) :
    Frame x (afterProg cfg mm env x r).1 := by
  unfold afterProg
  split <;> simp only [TryOK] at h
  · exact h
  · exact h.trans (frame_failK cfg mm env _ _ _)
  · exact h
  · exact h
  · exact Frame.refl x

theorem map_set_fiber (l : List ContState) (s : Nat) (st st' : ContState)
    (hs : l[s]? = some st) (hf : st'.fiber = st.fiber) :
    (l.set s st').map (·.fiber) = l.map (·.fiber) := by
  rw [List.map_set, hf]
  apply list_set_self
  simp [List.getElem?_map, hs]

/-- Close `Frame x y` when `y` is `x` after field updates of `fib`, the ready list, the trace,
or a `ContState` write that keeps the owner (hypothesis `hs` in context). -/
macro "frame_fields" : tactic => `(tactic| (
  refine ⟨?_, ?_, ?_⟩ <;>
  simp (config := { failIfUnchanged := false }) [owners, Exec.setContState, Exec.pushCont,
    Exec.setConts, Exec.setObj, Exec.setMask, Exec.enqueue, Exec.log] <;>
  first
    | exact List.prefix_refl _
    | exact Nat.le_refl _
    | (rw [map_set_fiber _ _ _ _ (by assumption) rfl])
    | (simp; done)))

theorem frame_contGet (x : Exec M) (s : Nat) : Frame x (contGet cfg mm env x s).1 := by
  unfold contGet
  split
  · exact Frame.refl x
  · next st hs =>
    simp only []
    split
    · split
      · refine Frame.trans ?_ (frame_prepare cfg mm _ _)
        refine ⟨?_, ?_, ?_⟩ <;>
          simp [owners, Exec.setContState, Exec.pushCont, Exec.setConts, List.map_set, hs, list_set_self,
            List.getElem?_map]
      · refine ⟨?_, ?_, ?_⟩ <;>
          simp [owners, Exec.setContState, Exec.pushCont, Exec.setConts, List.map_set, hs, list_set_self,
            List.getElem?_map]
    · frame_fields
    · split
      · split
        · refine Frame.trans ?_ (frame_failK cfg mm env _ _ _); frame_fields
        · refine Frame.trans ?_ (frame_succK cfg mm env _ _ _); frame_fields
        · frame_fields
      · split
        · refine Frame.trans ?_ (frame_prepare cfg mm _ _); frame_fields
        · frame_fields

/-- The `Exec` that a `StepResult` holds. -/
def stepEx : StepResult M → Exec M
  | .continue l => l.exec
  | .yielded x | .suspended x | .done _ x | .fatal _ x | .uncaught _ x | .aborted _ x => x

@[simp] theorem toStep_ex (l : Loop M) (r : Exec M × Flow) (nc na : Nat) :
    stepEx (toStep l r nc na) = r.1 := by
  unfold toStep; split <;> rfl

theorem tryOK_ok {x y : Exec M} {f : Fn} {a : Val} {o : UserOut}
    (h : tryUser mm env f a x = .ok o y) : Frame x y := by
  have := frame_tryUser mm env f a x; rw [h] at this; exact this

theorem tryOK_caught {x y : Exec M} {f : Fn} {a : Val} {e : Err}
    (h : tryUser mm env f a x = .caught e y) : Frame x y := by
  have := frame_tryUser mm env f a x; rw [h] at this; exact this

theorem tryOK_fatal {x y : Exec M} {f : Fn} {a : Val} {e : Err}
    (h : tryUser mm env f a x = .fatal e y) : Frame x y := by
  have := frame_tryUser mm env f a x; rw [h] at this; exact this

theorem frame_pushCont_right {x y : Exec M} (h : Frame x y) (k : ContK) :
    Frame x (y.pushCont k) := h.trans (Frame.of_eq rfl rfl rfl)

theorem frame_fib_right {x y : Exec M} (h : Frame x y) (f : Fiber M) :
    Frame x { y with fib := f } := h.trans (Frame.of_eq rfl rfl rfl)

theorem callOK {x y : Exec M} {f : Fn} {a : Val} {o : UserOut}
    (h : callUser mm env f a x = .ok (o, y)) : Frame x y := frame_callUser mm env f a x o y h

theorem prepOK {x y : Exec M} {cb : Option Nat} {fin : IO}
    (h : prepareFiberForCancelation cfg mm x cb = (y, fin)) : Frame x y := by
  have := frame_prepare cfg mm x cb; rw [h] at this; exact this

/-- Peel known transitions off the right side of a `Frame` goal, then check the fields. -/
macro "frame_peel" : tactic => `(tactic| (
  (repeat (first
    | (refine Frame.trans ?_ (frame_succK _ _ _ _ _ _))
    | (refine Frame.trans ?_ (frame_failK _ _ _ _ _ _))
    | (refine Frame.trans ?_ (frame_raised _ _ _ _ _))
    | (refine Frame.trans ?_ (frame_prepare _ _ _ _))
    | (refine Frame.trans ?_ (frame_contGet _ _ _ _ _))
    | (refine Frame.trans ?_ (frame_afterValue _ _ _ _ _ (frame_tryUser _ _ _ _ _)))
    | (refine Frame.trans ?_ (frame_afterValue _ _ _ _ _ (frame_tryUser2 _ _ _ _ _)))
    | (refine Frame.trans ?_ (frame_afterProg _ _ _ _ _ (frame_tryUser _ _ _ _ _)))
    | (refine Frame.trans ?_ (frame_afterProg _ _ _ _ _ (frame_tryUser2 _ _ _ _ _)))
    | (refine Frame.trans ?_ (tryOK_ok _ _ (by assumption)))
    | (refine Frame.trans ?_ (tryOK_caught _ _ (by assumption)))
    | (refine Frame.trans ?_ (tryOK_fatal _ _ (by assumption)))
    | (refine Frame.trans ?_ (callOK _ _ (by assumption)))
    | (refine Frame.trans ?_ (prepOK _ _ (by assumption)))
    | apply frame_pushCont_right
    | apply frame_enqueue_right
    | (refine Frame.trans ?_ (frame_fib_right (callOK _ _ (by assumption)) _)))) <;>
  first | exact Frame.refl _ | frame_fields))

theorem frame_dispatch (l : Loop M) (nc na : Nat) :
    Frame l.exec (stepEx (dispatch cfg mm env l nc na)) := by
  unfold dispatch
  simp only []
  generalize l.exec = x
  repeat' split
  all_goals simp (config := { failIfUnchanged := false }) only [toStep_ex]
  all_goals frame_peel

theorem frame_flush (l : Loop M) : Frame l.exec l.flush.exec := by
  unfold Loop.flush; split
  · exact Frame.of_eq rfl rfl rfl
  · exact Frame.refl _

theorem frame_step (observe : Bool) (l : Loop M) :
    Frame l.exec (stepEx (step cfg mm env observe l)) := by
  unfold step
  split
  · split
    · exact Frame.refl _
    · exact frame_flush l
  · simp only []
    generalize hl' : (if observe = true then l.flush else l) = l'
    have h1 : Frame l.exec l'.exec := by
      subst hl'; split
      · exact frame_flush l
      · exact Frame.refl _
    have h2 := h1.trans (frame_flush l')
    split
    · split
      · simp only [stepEx]
        exact frame_enqueue_right (frame_fib_right h2 _) _
      · split
        · simp only [stepEx]; exact h2.trans (frame_prepare cfg mm _ _)
        · exact h2.trans (frame_dispatch cfg mm env _ _ _)
    · split
      · simp only [stepEx]; exact h1.trans (frame_prepare cfg mm _ _)
      · exact h1.trans (frame_dispatch cfg mm env _ _ _)

@[simp] theorem stepEx_freshLoop (r : Exec M × Flow) : stepEx (freshLoop cfg r) = r.1 := by
  simp [freshLoop]

theorem frame_resume (x : Exec M) : Frame x (stepEx (resume cfg mm env x)) := by
  unfold resume
  split
  all_goals repeat' split
  all_goals simp (config := { failIfUnchanged := false }) only [stepEx_freshLoop]
  all_goals simp (config := { failIfUnchanged := false }) only [stepEx]
  all_goals first
    | exact frame_done cfg mm _ _
    | frame_peel

end Run

/-! ## The scheduler -/

/-- F1 and F2 between two scheduler states, on the live heap and the live fiber table. -/
structure SFrame (s t : Sched M) : Prop where
  conts : owners s.liveHeap <+: owners t.liveHeap
  fibers : s.liveFibers.length ≤ t.liveFibers.length
  handles : s.liveHeap.handles ≤ t.liveHeap.handles

theorem SFrame.refl (s : Sched M) : SFrame s s := ⟨List.prefix_refl _, Nat.le_refl _, Nat.le_refl _⟩

theorem SFrame.trans {s t u : Sched M} (a : SFrame s t) (b : SFrame t u) : SFrame s u :=
  ⟨a.conts.trans b.conts, Nat.le_trans a.fibers b.fibers, Nat.le_trans a.handles b.handles⟩

/-- Lift an `Exec` frame to the scheduler. -/
theorem SFrame.of_exec {s t : Sched M} {x y : Exec M} (h : Frame x y)
    (hs : s.liveHeap = x.heap) (hsf : s.liveFibers.length = x.fibers.length)
    (ht : t.liveHeap = y.heap) (htf : t.liveFibers.length = y.fibers.length) : SFrame s t :=
  ⟨hs ▸ ht ▸ h.conts, hsf ▸ htf ▸ h.fibers, hs ▸ ht ▸ h.handles⟩

/-- The owners, the fiber count and the handle counter are all that `SFrame` sees. -/
theorem SFrame.of_live {s t u : Sched M} (h : SFrame s t)
    (hh : owners u.liveHeap = owners t.liveHeap ∧ u.liveHeap.handles = t.liveHeap.handles)
    (hf : u.liveFibers.length = t.liveFibers.length) : SFrame s u :=
  ⟨hh.1 ▸ h.conts, hf ▸ h.fibers, hh.2 ▸ h.handles⟩

section Sched
variable (cfg : Config) (mm : MaskModel M) (env : UserEnv)

@[simp] theorem liveHeap_stop (s : Sched M) (h : Summary) : (s.stop h).liveHeap = s.liveHeap := by
  unfold Sched.stop; split <;> rfl

@[simp] theorem liveFibers_stop (s : Sched M) (h : Summary) :
    (s.stop h).liveFibers = s.liveFibers := by
  unfold Sched.stop; split <;> rfl

@[simp] theorem liveHeap_checkBroken (s : Sched M) : s.checkBroken.liveHeap = s.liveHeap := by
  unfold Sched.checkBroken; split <;> simp

@[simp] theorem liveFibers_checkBroken (s : Sched M) : s.checkBroken.liveFibers = s.liveFibers := by
  unfold Sched.checkBroken; split <;> simp

@[simp] theorem liveHeap_finish (s : Sched M) (x : Exec M) : (s.finish x).liveHeap = x.heap := rfl

@[simp] theorem liveFibers_finish_length (s : Sched M) (x : Exec M) :
    (s.finish x).liveFibers.length = x.fibers.length := by
  simp [Sched.finish, Sched.liveFibers]

theorem liveHeap_after (s : Sched M) (r : StepResult M) : (s.after r).liveHeap = (stepEx r).heap := by
  cases r <;> simp only [Sched.after, stepEx, liveHeap_stop, liveHeap_finish] <;> rfl

theorem liveFibers_after_length (s : Sched M) (r : StepResult M) :
    (s.after r).liveFibers.length = (stepEx r).fibers.length := by
  cases r <;> simp only [Sched.after, stepEx, liveFibers_stop, liveFibers_finish_length] <;>
    simp [Sched.liveFibers]

/-- One run-loop iteration or one task start. -/
theorem sframe_after_exec {s : Sched M} {x : Exec M} (r : StepResult M) (h : Frame x (stepEx r))
    (hs : s.liveHeap = x.heap) (hsf : s.liveFibers.length = x.fibers.length) (t : Sched M) :
    SFrame s (t.after r).checkBroken :=
  SFrame.of_exec h hs hsf (by simp [liveHeap_after]) (by simp [liveFibers_after_length])

theorem sframe_preemptRun (s : Sched M) : SFrame s s.preemptRun := by
  unfold Sched.preemptRun
  split
  · next l hl =>
    split
    · exact SFrame.refl s
    · refine SFrame.of_exec (x := l.exec) (frame_enqueue_right (frame_fib_right (frame_flush l) _) _)
        (by simp [Sched.liveHeap, hl]) (by simp [Sched.liveFibers, hl]) rfl (by simp)
  · exact SFrame.refl s

theorem sframe_finish_cb (s : Sched M) (hc : s.cur = none) (f : Fiber M) (st : Nat) (r : Val) :
    SFrame s (s.finish (contCallback mm st r { fib := f, heap := s.heap, fibers := s.fibers })).checkBroken :=
  SFrame.of_exec (frame_contCallback mm st r { fib := f, heap := s.heap, fibers := s.fibers })
    (by simp [Sched.liveHeap, hc])
    (by simp [Sched.liveFibers, hc]) (by simp) (by simp)

theorem sframe_runTask (s0 s : Sched M) (h0 : SFrame s0 s) (hc : s.cur = none) (t : Task) :
    SFrame s0 (s.runTask cfg mm env t) := by
  have hh : s.liveHeap = s.heap := by simp [Sched.liveHeap, hc]
  have hf : s.liveFibers = s.fibers := by simp [Sched.liveFibers, hc]
  unfold Sched.runTask
  repeat' split
  all_goals first
    | (refine h0.of_live ?_ ?_ <;> simp <;> done)
    | (refine h0.of_live ⟨?_, ?_⟩ ?_ <;> simp <;> done)
    | (refine h0.trans (sframe_after_exec _ (frame_resume cfg mm env _) hh ?_ s); rw [hf])
    | exact h0.trans (sframe_finish_cb mm s hc _ _ _)

theorem sframe_advance (s : Sched M) (hc : s.cur = none) : SFrame s s.advance := by
  unfold Sched.advance
  split
  · exact SFrame.refl s
  · refine (SFrame.refl s).of_live ?_ ?_ <;> simp [owners, Sched.liveHeap, Sched.liveFibers, hc]

theorem sframe_pick (s : Sched M) (hc : s.cur = none) (r : List Task) (n : Nat)
    (lg : List LogEntry) (t : Task) :
    SFrame s (Sched.runTask cfg mm env
      ({ s with heap := { s.heap with ready := r }, tasks := n, log := lg } : Sched M) t) := by
  refine sframe_runTask cfg mm env s _ ?_ (by simp [hc]) t
  refine (SFrame.refl s).of_live ?_ ?_ <;> simp [owners, Sched.liveHeap, Sched.liveFibers, hc]

theorem sframe_cancel (s : Sched M) (hc : s.cur = none) (cf : Fiber M) (n : Nat)
    (lg : List LogEntry) :
    SFrame s (({ s with fibers := s.fibers ++ [cf], tasks := n, log := lg } : Sched M).after
      (resume cfg mm env { fib := cf, heap := s.heap, fibers := s.fibers ++ [cf] })).checkBroken := by
  have h0 : Frame { fib := cf, heap := s.heap, fibers := s.fibers }
      { fib := cf, heap := s.heap, fibers := s.fibers ++ [cf] } :=
    ⟨List.prefix_refl _, by simp, Nat.le_refl _⟩
  exact sframe_after_exec _ (h0.trans (frame_resume cfg mm env _)) (by simp [Sched.liveHeap, hc])
    (by simp [Sched.liveFibers, hc]) _

theorem sframe_tick (s : Sched M) (maxTasks : Nat) (cs : List RChoice) :
    SFrame s (s.tick cfg mm env maxTasks cs).1 := by
  unfold Sched.tick
  split
  · next l hl =>
    exact sframe_after_exec _ (frame_step cfg mm env true l)
      (by simp [Sched.liveHeap, hl]) (by simp [Sched.liveFibers, hl]) s
  · next hc =>
    have hh : s.liveHeap = s.heap := by simp [Sched.liveHeap, hc]
    have hf : s.liveFibers = s.fibers := by simp [Sched.liveFibers, hc]
    repeat' split
    all_goals try dsimp only
    all_goals (try split) <;> try dsimp only
    all_goals first
      | (refine (SFrame.refl s).of_live ?_ ?_ <;>
          (try simp only [liveHeap_stop, liveFibers_stop]) <;>
          (try simp [owners, Sched.liveHeap, Sched.liveFibers, Sched.advance, hc]) <;> done)
      | exact sframe_advance s hc
      | exact sframe_pick cfg mm env s hc _ _ _ _
      | exact sframe_cancel cfg mm env s hc _ _ _
    all_goals (rw [hh]; exact List.prefix_refl _)

theorem sframe_norm (s : Sched M) : SFrame s s.norm := (SFrame.refl s).of_live ⟨rfl, rfl⟩ rfl

/-- F1 and F2 for one micro-step of the preemptive scheduler. -/
theorem sframe_tickP (s : Sched M) (c : PChoice) : SFrame s (s.tickP cfg mm env c) := by
  cases c with
  | preempt => exact sframe_preemptRun s
  | pick n =>
    simp only [Sched.tickP]
    exact (sframe_tick cfg mm env s _ _).trans (sframe_norm _)

/-- F1 and F2 for every run of the preemptive scheduler. -/
theorem sframe_runSchedStateP :
    ∀ (fuel : Nat) (cs : List PChoice) (s : Sched M),
      SFrame s (runSchedStateP cfg mm env fuel cs s)
  | 0, _, s => SFrame.refl s
  | fuel + 1, cs, s => by
    simp only [runSchedStateP]
    split
    · exact SFrame.refl s
    · exact (sframe_tickP cfg mm env s _).trans (sframe_runSchedStateP fuel _ _)

/-- F1: the owner fiber of a `ContState` cell never changes. If cell `i` belongs to fiber `r`
in a state, it belongs to `r` in every later state of every run. -/
theorem owner_stable (fuel : Nat) (cs : List PChoice) (s : Sched M) (i r : Nat)
    (h : (s.liveHeap.conts[i]?).map (·.fiber) = some r) :
    ((runSchedStateP cfg mm env fuel cs s).liveHeap.conts[i]?).map (·.fiber) = some r := by
  have hp := (sframe_runSchedStateP cfg mm env fuel cs s).conts
  simp only [owners, ← List.getElem?_map] at h hp ⊢
  obtain ⟨t, ht⟩ := hp
  rw [← ht]
  have hi : i < (List.map (·.fiber) s.liveHeap.conts).length :=
    (List.getElem?_eq_some_iff.mp h).1
  rw [List.getElem?_append_left hi, h]

end Sched

end CatsEffectInLean.Proofs.Lemmas.Frame
