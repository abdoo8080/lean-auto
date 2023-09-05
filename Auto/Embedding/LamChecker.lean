import Auto.Embedding.LamConv
import Auto.Lib.BinTree

namespace Auto.Embedding.Lam

-- An entry of RTable
inductive REntry where
  -- Well-formed formulas, with types
  -- We do not import well-formedness facts because
  --   we have `LamWF.ofLamCheck?`
  | wf      : List LamSort → LamSort → LamTerm → REntry
  -- Valid propositions
  -- The initial formulas in the `valid` table will be
  --   imported from `ImportTable`
  | valid   : List LamSort → LamTerm → REntry
  deriving Inhabited, Hashable, BEq, Lean.ToExpr

def REntry.repr : REntry → String
| .wf ss s t => s!"Auto.Embedding.Lam.REntry.wf {reprPrec ss 1} {reprPrec s 1} {reprPrec t 1}"
| .valid ss t => s!"Auto.Embedding.Lam.REntry.valid {reprPrec ss 1} {reprPrec t 1}"

instance : Repr REntry where
  reprPrec := fun re _ => re.repr

def REntry.toString : REntry → String
| .wf ss s t => s!"wf {ss} {s} {t}"
| .valid ss t => s!"valid {ss} {t}"

instance : ToString REntry where
  toString := REntry.toString

-- Table of valid propositions and well-formed formulas
-- Note that `Auto.BinTree α` is equivalent to `Nat → Option α`,
--   which means that `.some` entries may be interspersed
--   with `.none` entries
abbrev RTable := Auto.BinTree REntry

def REntry.correct (lval : LamValuation.{u}) : REntry → Prop
| .wf lctx s t => LamThmWFP lval lctx s t
| .valid lctx t => LamThmValid lval lctx t

def RTable.addEntry (r : RTable) (n : Nat) (re : REntry) : RTable :=
  r.insert n re

-- Invariant of `RTable`
def RTable.inv (lval : LamValuation.{u}) (r : RTable) :=
  r.allp (fun re => re.correct lval)

theorem RTable.wfInv_get
  {r : RTable} (inv : RTable.inv lval r) (h : BinTree.get? r n = Option.some (.wf lctx s t)) :
  LamThmWF lval lctx s t := by
  have inv' := inv n; rw [h] at inv'; exact LamThmWF.ofLamThmWFP inv'

theorem RTable.validInv_get
  {r : RTable} (inv : RTable.inv lval r) (h : BinTree.get? r n = Option.some (.valid lctx t)) :
  LamThmValid lval lctx t := by
  have inv' := inv n; rw [h] at inv'; exact inv'

-- The meta code of the checker will prepare this `ImportTable`
abbrev ImportTable (lval : LamValuation.{u}) :=
  Auto.BinTree (@PSigma LamTerm (fun p => (LamTerm.interpAsProp lval dfLCtxTy (dfLCtxTerm _) p).down))

-- Used by the meta code of the checker to build `ImportTable`
abbrev importTablePSigmaβ (lval : LamValuation.{u}) (p : LamTerm) :=
  (LamTerm.interpAsProp lval dfLCtxTy (dfLCtxTerm _) p).down

abbrev importTablePSigmaMk (lval : LamValuation.{u}) :=
  @PSigma.mk LamTerm (importTablePSigmaβ lval)

abbrev importTablePSigmaDefault (lval : LamValuation.{u}) :
  @PSigma LamTerm (fun p => (LamTerm.interpAsProp lval dfLCtxTy (dfLCtxTerm _) p).down) :=
  ⟨.base .trueE, True.intro⟩

def ImportTable.importFacts (it : ImportTable lval) : RTable :=
  it.mapOpt (fun ⟨p, _⟩ =>
    match p.lamCheck? lval.toLamTyVal dfLCtxTy with
    | .some (.base .prop) =>
      match p.maxLooseBVarSucc with
      | 0 => .some (.valid [] (p.resolveImport lval.toLamTyVal))
      | _ + 1 => .none
    | _                   => .none)

theorem ImportTable.importFacts_correct (it : ImportTable lval) :
  RTable.inv lval (importFacts it) := by
  dsimp [RTable.inv, importFacts]; rw [BinTree.mapOpt_allp]
  intro n; apply Option.allp_uniform;
  intro ⟨p, validp⟩; dsimp
  cases h₁ : LamTerm.lamCheck? lval.toLamTyVal dfLCtxTy p <;> try exact True.intro
  case a.some s =>
    cases s <;> try exact True.intro
    case base b =>
      cases b <;> try exact True.intro
      dsimp
      cases h₂ : p.maxLooseBVarSucc <;> try exact True.intro
      dsimp [Option.allp]
      apply LamThmValid.resolveImport
      apply LamThmValid.ofInterpAsProp _ _ h₁ validp h₂    

inductive ChkStep where
  -- Adds `⟨lctx, t, t.lamCheck!⟩` to `rtable.wf`
  | nop : ChkStep
  | wfOfCheck (lctx : List LamSort) (t : LamTerm) : ChkStep
  | wfOfAppend (ex : List LamSort) (pos : Nat) : ChkStep
  | wfOfPrepend (ex : List LamSort) (pos : Nat) : ChkStep
  | wfOfTopBeta (pos : Nat) : ChkStep
  | validOfIntro1F (pos : Nat) : ChkStep
  | validOfIntro1H (pos : Nat) : ChkStep
  | validOfIntros (pos idx : Nat) : ChkStep
  | validOfTopBeta (pos : Nat) : ChkStep
  -- `t₁ → t₂` and `t₁` implies `t₂`
  | validOfImp (p₁₂ : Nat) (p₁ : Nat) : ChkStep
  -- `t₁ → t₂ → ⋯ → tₖ → s` and `t₁, t₂, ⋯, tₖ` implies `s`
  | validOfImps (imp : Nat) (ps : List Nat) : ChkStep
  | validOfInstantiate1 (pos : Nat) (arg : LamTerm) : ChkStep
  | validOfInstantiate (pos : Nat) (args : List LamTerm) : ChkStep
  | validOfInstantiateRev (pos : Nat) (args : List LamTerm) : ChkStep
  deriving Lean.ToExpr

def ChkStep.toString : ChkStep → String
| .nop => s!"nop"
| .wfOfCheck lctx t => s!"wfOfCheck {lctx} {t}"
| .wfOfAppend ex pos => s!"wfOfAppend {ex} {pos}"
| .wfOfPrepend ex pos => s!"wfOfPrepend {ex} {pos}"
| .wfOfTopBeta pos => s!"wfOfTopBeta {pos}"
| .validOfIntro1F pos => s!"validOfIntro1F {pos}"
| .validOfIntro1H pos => s!"validOfIntro1H {pos}"
| .validOfIntros pos idx => s!"validOfIntros {pos} {idx}"
| .validOfTopBeta pos => s!"validOfTopBeta {pos}"
| .validOfImp p₁₂ p₁ => s!"validOfImp {p₁₂} {p₁}"
| .validOfImps imp ps => s!"validOfImps {imp} {ps}"
| .validOfInstantiate1 pos arg => s!"validOfInstantiate1 {pos} {arg}"
| .validOfInstantiate pos args => s!"validOfInstantiate {pos} {args}"
| .validOfInstantiateRev pos args => s!"validOfInstantiateRev {pos} {args}"

instance : ToString ChkStep where
  toString := ChkStep.toString

def ChkStep.evalValidOfImps (r : RTable) (lctx : List LamSort) (t : LamTerm)
  : (ps : List Nat) → Option REntry
  | .nil => .some (.valid lctx t)
  | .cons p₁ ps' =>
    match r.get? p₁ with
    | .some (.valid lctx₂ t₁) =>
      match lctx.beq lctx₂ with
      | true =>
        match LamTerm.impApp? t t₁ with
        | .some t₂ => evalValidOfImps r lctx t₂ ps'
        | .none => .none
      | false => .none
    | .some (.wf _ _ _) => .none
    | .none => .none

def ChkStep.evalValidOfIntros (lctx : List LamSort) (t : LamTerm)
  : (idx : Nat) → Option REntry
  | 0 => .some (.valid lctx t)
  | .succ idx =>
    match t.intro1? with
    | .some (s, t') => evalValidOfIntros (s :: lctx) t' idx
    | .none => .none

def ChkStep.evalValidOfInstantiate (ltv : LamTyVal) (lctx : List LamSort) (t : LamTerm)
  : (args : List LamTerm) → Option REntry
  | .nil => .some (.valid lctx t)
  | .cons arg args =>
    match lctx with
    | .nil => .none
    | .cons argTy lctx =>
      match arg.lamThmWFCheck? ltv lctx with
      | .some s =>
        match s.beq argTy with
        | true => evalValidOfInstantiate ltv lctx (LamTerm.instantiate1 arg t) args
        | false => .none
      | .none => .none

def ChkStep.eval (ltv : LamTyVal) (r : RTable) : (cs : ChkStep) → Option REntry
| .nop => .none
| .wfOfCheck lctx t =>
  match LamTerm.lamThmWFCheck? ltv lctx t with
  | .some rty => .some (.wf lctx rty t)
  | .none => .none
| .wfOfAppend ex pos =>
  match r.get? pos with
  | .some (.wf lctx s t) => .some (.wf (lctx ++ ex) s t)
  | .some (.valid _ _) => .none
  | .none => .none
| .wfOfPrepend ex pos =>
  match r.get? pos with
  | .some (.wf lctx s t) => .some (.wf (ex ++ lctx) s (t.bvarLifts ex.length))
  | .some (.valid _ _) => .none
  | .none => .none
| .wfOfTopBeta pos =>
  match r.get? pos with
  | .some (.wf lctx s t) => .some (.wf lctx s t.topBeta)
  | .some (.valid _ _) => .none
  | .none => .none
| .validOfIntro1F pos =>
  match r.get? pos with
  | .some (.valid lctx t) =>
    match t.intro1F? with
    | .some (s, p) => .some (.valid (s :: lctx) p)
    | .none => .none
  | .some (.wf _ _ _) => .none
  | .none => .none
| .validOfIntro1H pos =>
  match r.get? pos with
  | .some (.valid lctx t) =>
    match t.intro1H? with
    | .some (s, p) => .some (.valid (s :: lctx) p)
    | .none => .none
  | .some (.wf _ _ _) => .none
  | .none => .none
| .validOfIntros pos idx =>
  match r.get? pos with
  | .some (.valid lctx t) => evalValidOfIntros lctx t idx
  | .some (.wf _ _ _) => .none
  | .none => .none
| .validOfTopBeta pos =>
  match r.get? pos with
  | .some (.valid lctx t) => .some (.valid lctx t.topBeta)
  | .some (.wf _ _ _) => .none
  | .none => .none
| .validOfImp p₁₂ p₁ =>
  match r.get? p₁₂ with
  | .some (.valid lctx₁ t₁₂) =>
    match r.get? p₁ with
    | .some (.valid lctx₂ t₁) =>
      match lctx₁.beq lctx₂ with
      | true =>
        match LamTerm.impApp? t₁₂ t₁ with
        | .some t₂ => .some (.valid lctx₁ t₂)
        | .none => .none
      | false => .none
    | .some (.wf _ _ _) => .none
    | .none => .none
  | .some (.wf _ _ _) => .none
  | .none => .none
| .validOfImps imp ps =>
  match r.get? imp with
  | .some (.valid lctx t) => evalValidOfImps r lctx t ps
  | .some (.wf _ _ _) => .none
  | .none => .none
| .validOfInstantiate1 pos arg =>
  match r.get? pos with
  | .some (.valid lctx t) =>
    match lctx with
    | .nil => .none
    | .cons argTy lctx =>
      match arg.lamThmWFCheck? ltv lctx with
      | .some s =>
        match s.beq argTy with
        | true => .some (.valid lctx (LamTerm.instantiate1 arg t))
        | false => .none
      | .none => .none
  | .some (.wf _ _ _) => .none
  | .none => .none
| .validOfInstantiate pos args =>
  match r.get? pos with
  | .some (.valid lctx t) => evalValidOfInstantiate ltv lctx t args
  | .some (.wf _ _ _) => .none
  | .none => .none
| .validOfInstantiateRev pos args =>
  match r.get? pos with
  | .some (.valid lctx t) => evalValidOfInstantiate ltv lctx t args.reverse
  | .some (.wf _ _ _) => .none
  | .none => .none

theorem ChkStep.evalValidOfImps_correct (lval : LamValuation)
  (impV : LamThmValid lval lctx t) (r : RTable) (inv : r.inv lval) :
  Option.allp (REntry.correct lval) (evalValidOfImps r lctx t ps) := by
  revert lctx t; induction ps <;> intros lctx t impV
  case nil => exact impV
  case cons p₁ ps' IH =>
    dsimp [evalValidOfImps]
    match h₁ : BinTree.get? r p₁ with
    | .some (.valid lctx₂ t₁) =>
      dsimp
      match h₂ : List.beq lctx lctx₂ with
      | true =>
        dsimp
        match h₃ : LamTerm.impApp? t t₁ with
        | .some t₂ =>
          cases (List.beq_eq LamSort.beq_eq _ _ h₂)
          have h₁' := RTable.validInv_get inv h₁
          apply IH; apply LamThmValid.impApp impV h₁' h₃
        | .none => exact True.intro
      | false => exact True.intro
    | .some (.wf _ _ _) => exact True.intro
    | .none => exact True.intro

theorem ChkStep.evalValidOfIntros_correct (lval : LamValuation)
  (tV : LamThmValid lval lctx t) :
  Option.allp (REntry.correct lval) (evalValidOfIntros lctx t idx) := by
  revert lctx t; induction idx <;> intros lctx t tV
  case zero => exact tV
  case succ idx IH =>
    dsimp [evalValidOfIntros]
    match h : t.intro1? with
    | .some (s, t') =>
      apply IH; apply LamThmValid.intro1 tV h
    | .none => exact True.intro

theorem ChkStep.evalValidOfInstantiate_coorect (lval : LamValuation)
  (tV : LamThmValid lval lctx t) :
  Option.allp (REntry.correct lval) (evalValidOfInstantiate lval.toLamTyVal lctx t args) := by
  revert lctx t; induction args <;> intros lctx t tV
  case nil =>
    unfold evalValidOfInstantiate; exact tV
  case cons arg args IH =>
    unfold evalValidOfInstantiate;
    match lctx with
    | .nil => exact True.intro
    | .cons argTy lctx =>
      dsimp
      match h₁ : LamTerm.lamThmWFCheck? lval.toLamTyVal lctx arg with
      | .some s =>
        dsimp
        match h₂ : s.beq argTy with
        | true =>
          dsimp; apply IH
          cases (LamSort.beq_eq _ _ h₂)
          have h₁' := LamThmWF.ofLamThmWFCheck? h₁
          apply LamThmValid.instantiate1 h₁' tV
        | false => exact True.intro
      | .none => exact True.intro

theorem ChkStep.eval_correct
  (lval : LamValuation.{u}) (r : RTable) (inv : r.inv lval) :
  (cs : ChkStep) → Option.allp (REntry.correct lval) (cs.eval lval.toLamTyVal r)
| .nop => True.intro
| .wfOfCheck lctx t => by
  dsimp [eval]
  cases h : LamTerm.lamThmWFCheck? lval.toLamTyVal lctx t <;> try exact True.intro
  case some s =>
    dsimp [REntry.correct]; apply LamThmWFP.ofLamThmWF
    exact LamThmWF.ofLamThmWFCheck? h
| .wfOfAppend ex pos => by
  dsimp [eval]
  cases h : BinTree.get? r pos <;> try exact True.intro
  case some lctxst =>
    match lctxst with
    | .wf lctx s t =>
      apply LamThmWFP.ofLamThmWF;
      apply LamThmWF.append (RTable.wfInv_get inv h)
    | .valid _ _ => exact True.intro
| .wfOfPrepend ex pos => by
  dsimp [eval]
  cases h : BinTree.get? r pos <;> try exact True.intro
  case some lctxst =>
    match lctxst with
    | .wf lctx s t =>
      apply LamThmWFP.ofLamThmWF;
      apply LamThmWF.prepend (RTable.wfInv_get inv h)
    | .valid _ _ => exact True.intro
| .wfOfTopBeta pos => by
  dsimp [eval]
  cases h : BinTree.get? r pos <;> try exact True.intro
  case some lctxst =>
    match lctxst with
    | .wf lctx s t =>
      apply LamThmWFP.ofLamThmWF;
      apply LamThmWF.topBeta (RTable.wfInv_get inv h)
    | .valid _ _ => exact True.intro
| .validOfIntro1F pos => by
  dsimp [eval]
  cases h₁ : BinTree.get? r pos <;> try exact True.intro
  case some lctxt =>
    match lctxt with
    | .wf _ _ _ => exact True.intro
    | .valid lctx t =>
      dsimp
      match h₂ : t.intro1F? with
      | .some (s, p) =>
        apply LamThmValid.intro1F (RTable.validInv_get inv h₁) h₂
      | .none => exact True.intro
| .validOfIntro1H pos => by
  dsimp [eval]
  cases h₁ : BinTree.get? r pos <;> try exact True.intro
  case some lctxt =>
    match lctxt with
    | .wf _ _ _ => exact True.intro
    | .valid lctx t =>
      dsimp
      match h₂ : t.intro1H? with
      | .some (s, p) =>
        apply LamThmValid.intro1H (RTable.validInv_get inv h₁) h₂
      | .none => exact True.intro
| .validOfIntros pos idx => by
  dsimp [eval]
  cases h : BinTree.get? r pos <;> try exact True.intro
  case some lctxt =>
    match lctxt with
    | .wf _ _ _ => exact True.intro
    | .valid lctx t =>
      have h' := RTable.validInv_get inv h
      apply ChkStep.evalValidOfIntros_correct _ h'
| .validOfTopBeta pos => by
  dsimp [eval]
  cases h : BinTree.get? r pos <;> try exact True.intro
  case some lctxt =>
    match lctxt with
    | .wf _ _ _ => exact True.intro
    | .valid lctx t =>
      apply LamThmValid.topBeta (RTable.validInv_get inv h)
| .validOfImp p₁₂ p₁ => by
  dsimp [eval]
  match h₁ : BinTree.get? r p₁₂ with
  | .some (.valid lctx₁ t₁₂) =>
    dsimp
    match h₂ : BinTree.get? r p₁ with
    | .some (.valid lctx₂ t₁) =>
      dsimp
      match h₃ : List.beq lctx₁ lctx₂ with
      | true =>
        dsimp
        match h₄ : LamTerm.impApp? t₁₂ t₁ with
        | .some t₂ =>
          cases (List.beq_eq LamSort.beq_eq _ _ h₃)
          have h₁' := RTable.validInv_get inv h₁
          have h₂' := RTable.validInv_get inv h₂
          apply LamThmValid.impApp h₁' h₂' h₄
        | .none => exact True.intro
      | false => exact True.intro
    | .some (.wf _ _ _) => exact True.intro 
    | .none => exact True.intro
  | .some (.wf _ _ _) => exact True.intro
  | .none => exact True.intro
| .validOfImps imp ps => by
  dsimp [eval]
  match h : BinTree.get? r imp with
  | .some (.valid lctx t) =>
    dsimp
    have h' := RTable.validInv_get inv h
    apply ChkStep.evalValidOfImps_correct <;> assumption
  | .some (.wf _ _ _) => exact True.intro
  | .none => exact True.intro
| .validOfInstantiate1 pos arg => by
  dsimp [eval]
  match h₁ : r.get? pos with
  | .some (.valid lctx t) =>
    dsimp
    match lctx with
    | .nil => exact True.intro
    | .cons argTy lctx =>
      dsimp
      match h₂ : LamTerm.lamThmWFCheck? lval.toLamTyVal lctx arg with
      | .some s =>
        dsimp
        match h₃ : s.beq argTy with
        | true =>
          dsimp [Option.allp, REntry.correct]
          cases (LamSort.beq_eq _ _ h₃)
          have h₁' := LamThmWF.ofLamThmWFCheck? h₂
          have h₂' := RTable.validInv_get inv h₁
          apply LamThmValid.instantiate1 h₁' h₂'
        | false => exact True.intro
      | .none => exact True.intro
  | .some (.wf _ _ _) => exact True.intro
  | .none => exact True.intro
| .validOfInstantiate pos args => by
  dsimp [eval]
  match h : r.get? pos with
  | .some (.valid lctx t) =>
    let h' := RTable.validInv_get inv h
    apply ChkStep.evalValidOfInstantiate_coorect _ h'
  | .some (.wf _ _ _) => exact True.intro
  | .none => exact True.intro
| .validOfInstantiateRev pos args => by
  dsimp [eval]
  match h : r.get? pos with
  | .some (.valid lctx t) =>
    let h' := RTable.validInv_get inv h
    apply ChkStep.evalValidOfInstantiate_coorect _ h'
  | .some (.wf _ _ _) => exact True.intro
  | .none => exact True.intro

-- The first `ChkStep` specifies the checker step
-- The second `Nat` specifies the position to insert the resulting term
-- Note that
--   1. All entries `(x : ChkStep × Nat)` that insert result into the
--      `wf` table should have distinct second component
--   2. All entries `(x : ChkStep × Nat)` that insert result into the
--      `valid` table should have distinct second component
-- Note that we decide where (`wf` or `valid`) to insert the resulting
--   term by looking at `(c : ChkStep).eval`
abbrev ChkSteps := BinTree (ChkStep × Nat)

def ChkStep.run (ltv : LamTyVal) (r : RTable) (c : ChkStep) (n : Nat) : RTable :=
  match ChkStep.eval ltv r c with
  | .none => r
  | .some re => r.insert n re

theorem ChkStep.run_correct
  (lval : LamValuation.{u}) (r : RTable) (inv : r.inv lval) (c : ChkStep) (n : Nat) :
  (ChkStep.run lval.toLamTyVal r c n).inv lval := by
  dsimp [ChkStep.run]
  have eval_correct := ChkStep.eval_correct lval r inv c; revert eval_correct
  cases h : eval lval.toLamTyVal r c <;> intro eval_correct
  case none => exact inv
  case some re =>
    cases re
    case wf lctx s t =>
      dsimp [RTable.inv]; rw [BinTree.allp_insert]; dsimp
      apply And.intro
      case left => exact eval_correct
      case right => intros; apply inv
    case valid lctx t =>
      dsimp [RTable.inv]; rw [BinTree.allp_insert]; dsimp
      apply And.intro
      case left => exact eval_correct
      case right => intros; apply inv

def ChkSteps.run (ltv : LamTyVal) (r : RTable) (cs : ChkSteps) : RTable :=
  BinTree.foldl (fun r (c, n) => ChkStep.run ltv r c n) r cs

theorem ChkSteps.run_correct
  (lval : LamValuation.{u}) (r : RTable) (inv : r.inv lval) (cs : ChkSteps) :
  (ChkSteps.run lval.toLamTyVal r cs).inv lval := by
  dsimp [ChkSteps.run]; apply BinTree.foldl_inv (RTable.inv lval) inv
  intro r (c, n) inv'; exact ChkStep.run_correct lval r inv' c n

def ChkSteps.runFromBeginning (lval : LamValuation.{u}) (it : ImportTable lval) (cs : ChkSteps) :=
  ChkSteps.run lval.toLamTyVal it.importFacts cs

theorem Checker
  (lval : LamValuation.{u}) (it : ImportTable lval) (cs : ChkSteps) :
  (ChkSteps.runFromBeginning lval it cs).inv lval := by
  apply ChkSteps.run_correct; apply ImportTable.importFacts_correct

end Auto.Embedding.Lam