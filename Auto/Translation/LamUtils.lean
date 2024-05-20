import Lean
import Auto.Lib.MetaState
import Auto.Embedding.LamBase
open Lean

namespace Auto

namespace LamCstrD

  abbrev Nat.modEq (n a b : Nat) := a % n = b % n
  abbrev Nat.ge (x y : Nat) := Nat.le y x
  abbrev Nat.gt (x y : Nat) := Nat.lt y x
  abbrev Nat.max (x y : Nat) : Nat := Max.max x y
  abbrev Nat.min (x y : Nat) : Nat := Min.min x y
  abbrev Int.modEq (n a b : Int) := a % n = b % n
  abbrev Int.ge (a b : Int) := Int.le b a
  abbrev Int.gt (a b : Int) := Int.lt b a
  abbrev Int.max (x y : Int) : Int := Max.max x y
  abbrev Int.min (x y : Int) : Int := Min.min x y
  abbrev String.ge (a b : String) : Prop := b = a ∨ b < a
  abbrev String.gt (a b : String) : Prop := b < a
  abbrev BitVec.uge (a b : BitVec n) : Bool := BitVec.ule b a
  abbrev BitVec.ugt (a b : BitVec n) : Bool := BitVec.ult b a
  abbrev BitVec.sge (a b : BitVec n) : Bool := BitVec.sle b a
  abbrev BitVec.sgt (a b : BitVec n) : Bool := BitVec.slt b a
  abbrev BitVec.propule (a b : BitVec n) : Prop := a.toFin <= b.toFin
  abbrev BitVec.propult (a b : BitVec n) : Prop := a.toFin < b.toFin
  abbrev BitVec.propsle (a b : BitVec n) : Prop := a.toInt <= b.toInt
  abbrev BitVec.propslt (a b : BitVec n) : Prop := a.toInt < b.toInt
  abbrev BitVec.propuge (a b : BitVec n) : Prop := BitVec.propule b a
  abbrev BitVec.propugt (a b : BitVec n) : Prop := BitVec.propult b a
  abbrev BitVec.propsge (a b : BitVec n) : Prop := BitVec.propsle b a
  abbrev BitVec.propsgt (a b : BitVec n) : Prop := BitVec.propslt b a
  abbrev BitVec.smtHshiftLeft (a : BitVec n) (b : BitVec m) := BitVec.shiftLeft a b.toNat
  abbrev BitVec.smtHushiftRight (a : BitVec n) (b : BitVec m) := BitVec.ushiftRight a b.toNat
  abbrev BitVec.smtHsshiftRight (a : BitVec n) (b : BitVec m) := BitVec.sshiftRight a b.toNat

end LamCstrD


namespace LamExportUtils

  open Embedding.Lam

  -- This section should only be used when exporting terms to external provers

  def exportError.ImpPolyLog :=
    "Import versions of polymorphic logical " ++
    "constants should have been eliminated"

  def collectLamSortAtoms : LamSort → HashSet Nat
  | .atom n => HashSet.empty.insert n
  | .base _ => HashSet.empty
  | .func a b => (collectLamSortAtoms a).insertMany (collectLamSortAtoms b)

  def collectLamSortsAtoms (ss : Array LamSort) : HashSet Nat :=
    ss.foldl (fun hs s => hs.insertMany (collectLamSortAtoms s)) HashSet.empty

  def collectLamSortBitVecLengths : LamSort → HashSet Nat
  | .base (.bv n) => HashSet.empty.insert n
  | .func a b => (collectLamSortBitVecLengths a).insertMany (collectLamSortBitVecLengths b)
  | _ => HashSet.empty

  def collectLamSortsBitVecLengths (ss : Array LamSort) : HashSet Nat :=
    ss.foldl (fun hs s => hs.insertMany (collectLamSortBitVecLengths s)) HashSet.empty

  /-- Collect type atoms in a LamBaseTerm -/
  def collectLamBaseTermAtoms (b : LamBaseTerm) : CoreM (HashSet Nat) := do
    let s? : Option LamSort ← (do
      match b with
      | .eqI _ => throwError ("collectAtoms :: " ++ exportError.ImpPolyLog)
      | .forallEI _ => throwError ("collectAtoms :: " ++ exportError.ImpPolyLog)
      | .existEI _ => throwError ("collectAtoms :: " ++ exportError.ImpPolyLog)
      | .iteI _ => throwError ("collectAtoms :: " ++ exportError.ImpPolyLog)
      | .eq s => return .some s
      | .forallE s => return .some s
      | .existE s => return .some s
      | .ite s => return .some s
      | _ => return none)
    if let .some s := s? then
      return collectLamSortAtoms s
    else
      return HashSet.empty

  /--
    The first hashset is the type atoms
    The second hashset is the term atoms
    The third hashset is the term etoms
    This function is called when we're trying to export terms
      from `λ` to external provers, e.g. Lean/Duper
    Therefore, we expect that `eqI, forallEI, existEI` and ``ite'`
      does not occur in the `LamTerm`
  -/
  def collectLamTermAtoms (lamVarTy : Array LamSort) (lamEVarTy : Array LamSort) :
    LamTerm → CoreM (HashSet Nat × HashSet Nat × HashSet Nat)
  | .atom n => do
    let .some s := lamVarTy[n]?
      | throwError "collectAtoms :: Unknown term atom {n}"
    return (collectLamSortAtoms s, HashSet.empty.insert n, HashSet.empty)
  | .etom n => do
    let .some s := lamEVarTy[n]?
      | throwError "collectAtoms :: Unknown etom {n}"
    return (collectLamSortAtoms s, HashSet.empty, HashSet.empty.insert n)
  | .base b => do
    return (← collectLamBaseTermAtoms b, HashSet.empty, HashSet.empty)
  | .bvar _ => pure (HashSet.empty, HashSet.empty, HashSet.empty)
  | .lam s t => do
    let (typeHs, termHs, etomHs) ← collectLamTermAtoms lamVarTy lamEVarTy t
    let sHs := collectLamSortAtoms s
    return (mergeHashSet typeHs sHs, termHs, etomHs)
  | .app _ t₁ t₂ => do
    let (typeHs₁, termHs₁, etomHs₁) ← collectLamTermAtoms lamVarTy lamEVarTy t₁
    let (typeHs₂, termHs₂, etomHs₂) ← collectLamTermAtoms lamVarTy lamEVarTy t₂
    return (mergeHashSet typeHs₁ typeHs₂,
            mergeHashSet termHs₁ termHs₂,
            mergeHashSet etomHs₁ etomHs₂)

  def collectLamTermsAtoms (lamVarTy : Array LamSort) (lamEVarTy : Array LamSort)
    (ts : Array LamTerm) : CoreM (HashSet Nat × HashSet Nat × HashSet Nat) :=
    ts.foldlM (fun (tyHs, aHs, eHs) t => do
      let (tyHs', aHs', eHs') ← collectLamTermAtoms lamVarTy lamEVarTy t
      return (mergeHashSet tyHs tyHs', mergeHashSet aHs aHs', mergeHashSet eHs eHs'))
      (HashSet.empty, HashSet.empty, HashSet.empty)

  def collectLamTermNatConsts : LamTerm → HashSet NatConst
  | .base (.ncst nc) => HashSet.empty.insert nc
  | .lam _ body => collectLamTermNatConsts body
  | .app _ fn arg => mergeHashSet (collectLamTermNatConsts fn) (collectLamTermNatConsts arg)
  | _ => HashSet.empty

  def collectLamTermsNatConsts (ts : Array LamTerm) : HashSet NatConst :=
    ts.foldl (fun hs t => mergeHashSet hs (collectLamTermNatConsts t)) HashSet.empty

  def collectLamTermIntConsts : LamTerm → HashSet IntConst
  | .base (.icst ic) => HashSet.empty.insert ic
  | .lam _ body => collectLamTermIntConsts body
  | .app _ fn arg => mergeHashSet (collectLamTermIntConsts fn) (collectLamTermIntConsts arg)
  | _ => HashSet.empty

  def collectLamTermsIntConsts (ts : Array LamTerm) : HashSet IntConst :=
    ts.foldl (fun hs t => mergeHashSet hs (collectLamTermIntConsts t)) HashSet.empty

  def collectLamTermStringConsts : LamTerm → HashSet StringConst
  | .base (.scst sc) => HashSet.empty.insert sc
  | .lam _ body => collectLamTermStringConsts body
  | .app _ fn arg => mergeHashSet (collectLamTermStringConsts fn) (collectLamTermStringConsts arg)
  | _ => HashSet.empty

  def collectLamTermsStringConsts (ts : Array LamTerm) : HashSet StringConst :=
    ts.foldl (fun hs t => mergeHashSet hs (collectLamTermStringConsts t)) HashSet.empty

  def collectLamTermBitvecs : LamTerm → HashSet BitVecConst
  | .base (.bvcst bvc) => HashSet.empty.insert bvc
  | .lam _ body => collectLamTermBitvecs body
  | .app _ fn arg => mergeHashSet (collectLamTermBitvecs fn) (collectLamTermBitvecs arg)
  | _ => HashSet.empty

  def collectLamTermsBitvecs (ts : Array LamTerm) : HashSet BitVecConst :=
    ts.foldl (fun hs t => mergeHashSet hs (collectLamTermBitvecs t)) HashSet.empty

  def collectLamTermIteSorts : LamTerm → HashSet LamSort
  | .base (.ite s) => HashSet.empty.insert s
  | .lam _ body => collectLamTermIteSorts body
  | .app _ fn arg => mergeHashSet (collectLamTermIteSorts fn) (collectLamTermIteSorts arg)
  | _ => HashSet.empty

  def collectLamTermsIteSorts (ts : Array LamTerm) : HashSet LamSort :=
    ts.foldl (fun hs t => mergeHashSet hs (collectLamTermIteSorts t)) HashSet.empty

end LamExportUtils


namespace Lam2D

  open Embedding Lam LamCstrD

  def interpLamBaseSortAsUnlifted : LamBaseSort → Expr
  | .prop    => .sort .zero
  | .bool    => .const ``Bool []
  | .nat     => .const ``Nat []
  | .int     => .const ``Int []
  | .isto0 p =>
    match p with
    | .xH => .const ``String []
    | .xO .xH => .const ``Empty []
    | _   => .const ``Empty []
  | .bv n    => .app (.const ``BitVec []) (.lit (.natVal n))

  def interpPropConstAsUnlifted : PropConst → CoreM Expr
  | .trueE      => return .const ``True []
  | .falseE     => return .const ``False []
  | .not        => return .const ``Not []
  | .and        => return .const ``And []
  | .or         => return .const ``Or []
  | .imp        => do
    let .some (.defnInfo impVal) := (← getEnv).find? ``ImpF
      | throwError "interpLamBaseTermAsUnlifted :: Unexpected error"
    return impVal.value.instantiateLevelParams impVal.levelParams [.zero, .zero]
  | .iff        => return .const ``Iff []

  def interpBoolConstAsUnlifted : BoolConst → CoreM Expr
  | .ofProp => return .const ``Bool.ofProp []
  | .trueb  => return .const ``true []
  | .falseb => return .const ``false []
  | .notb   => return .const ``not []
  | .andb   => return .const ``and []
  | .orb    => return .const ``or []

  def interpNatConstAsUnlifted : NatConst → CoreM Expr
  | .natVal n => return .lit (.natVal n)
  | .nadd     => return .const ``Nat.add []
  | .nsub     => return .const ``Nat.sub []
  | .nmul     => return .const ``Nat.mul []
  | .ndiv     => return .const ``Nat.div []
  | .nmod     => return .const ``Nat.mod []
  | .nle      => return .const ``Nat.le []
  | .nlt      => return .const ``Nat.lt []
  | .nmax     => return .const ``Nat.max []
  | .nmin     => return .const ``Nat.min []

  def interpIntConstAsUnlifted : IntConst → CoreM Expr
  | .iofNat   => return .const ``Int.ofNat []
  | .inegSucc => return .const ``Int.negSucc []
  | .ineg     => return .const ``Int.neg []
  | .iabs     => return .const ``Int.abs []
  | .iadd     => return .const ``Int.add []
  | .isub     => return .const ``Int.sub []
  | .imul     => return .const ``Int.mul []
  | .idiv     => return .const ``Int.div []
  | .imod     => return .const ``Int.mod []
  | .iediv    => return .const ``Int.ediv []
  | .iemod    => return .const ``Int.emod []
  | .ile      => return .const ``Int.le []
  | .ilt      => return .const ``Int.lt []
  | .imax     => return .const ``Int.max []
  | .imin     => return .const ``Int.min []

  def interpStringConstAsUnlifted : StringConst → CoreM Expr
  | .strVal s  => return .lit (.strVal s)
  | .slength   => return .const ``String.length []
  | .sapp      => return .const ``String.append []
  | .sle       => return .const ``String.le []
  | .slt       => return .const ``String.lt []
  | .sprefixof => return .const ``String.isPrefixOf []
  | .srepall   => return .const ``String.replace []

  def interpBitVecConstAsUnlifted : BitVecConst → CoreM Expr
  | .bvVal n i         => return mkApp2 (.const ``BitVec.ofNat []) (.lit (.natVal n)) (.lit (.natVal i))
  | .bvofNat n         => return .app (.const ``BitVec.ofNat []) (.lit (.natVal n))
  | .bvtoNat n         => return .app (.const ``BitVec.toNat []) (.lit (.natVal n))
  | .bvofInt n         => return .app (.const ``BitVec.ofInt []) (.lit (.natVal n))
  | .bvtoInt n         => return .app (.const ``BitVec.toInt []) (.lit (.natVal n))
  | .bvmsb n           => return .app (.const ``BitVec.msb []) (.lit (.natVal n))
  | .bvaOp n op =>
    match op with
    | .add             => return .app (.const ``BitVec.add []) (.lit (.natVal n))
    | .sub             => return .app (.const ``BitVec.sub []) (.lit (.natVal n))
    | .mul             => return .app (.const ``BitVec.mul []) (.lit (.natVal n))
    | .udiv            => return .app (.const ``BitVec.smtUDiv []) (.lit (.natVal n))
    | .urem            => return .app (.const ``BitVec.umod []) (.lit (.natVal n))
    | .sdiv            => return .app (.const ``BitVec.smtSDiv []) (.lit (.natVal n))
    | .srem            => return .app (.const ``BitVec.srem []) (.lit (.natVal n))
    | .smod            => return .app (.const ``BitVec.smod []) (.lit (.natVal n))
  | .bvneg n           => return .app (.const ``BitVec.neg []) (.lit (.natVal n))
  | .bvabs n           => return .app (.const ``BitVec.abs []) (.lit (.natVal n))
  | .bvcmp n prop? op  =>
    match prop? with
    | false =>
      match op with
      | .ult           => return .app (.const ``BitVec.ult []) (.lit (.natVal n))
      | .ule           => return .app (.const ``BitVec.ule []) (.lit (.natVal n))
      | .slt           => return .app (.const ``BitVec.slt []) (.lit (.natVal n))
      | .sle           => return .app (.const ``BitVec.sle []) (.lit (.natVal n))
    | true =>
      match op with
      | .ult           => return .app (.const ``BitVec.propult []) (.lit (.natVal n))
      | .ule           => return .app (.const ``BitVec.propule []) (.lit (.natVal n))
      | .slt           => return .app (.const ``BitVec.propslt []) (.lit (.natVal n))
      | .sle           => return .app (.const ``BitVec.propsle []) (.lit (.natVal n))
  | .bvand n           => return .app (.const ``BitVec.and []) (.lit (.natVal n))
  | .bvor n            => return .app (.const ``BitVec.or []) (.lit (.natVal n))
  | .bvxor n           => return .app (.const ``BitVec.xor []) (.lit (.natVal n))
  | .bvnot n           => return .app (.const ``BitVec.not []) (.lit (.natVal n))
  | .bvshOp n smt? op  =>
    match smt? with
    | false =>
      match op with
      | .shl           => return .app (.const ``BitVec.shiftLeft []) (.lit (.natVal n))
      | .lshr          => return .app (.const ``BitVec.ushiftRight []) (.lit (.natVal n))
      | .ashr          => return .app (.const ``BitVec.sshiftRight []) (.lit (.natVal n))
    | true =>
      match op with
      | .shl           => return mkApp2 (.const ``BitVec.smtHshiftLeft []) (.lit (.natVal n)) (.lit (.natVal n))
      | .lshr          => return mkApp2 (.const ``BitVec.smtHushiftRight []) (.lit (.natVal n)) (.lit (.natVal n))
      | .ashr          => return mkApp2 (.const ``BitVec.smtHsshiftRight []) (.lit (.natVal n)) (.lit (.natVal n))
  | .bvappend n m      => return mkApp2 (.const ``BitVec.append []) (.lit (.natVal n)) (.lit (.natVal m))
  | .bvextract n h l   => return mkApp3 (.const ``BitVec.extractLsb []) (.lit (.natVal n)) (.lit (.natVal h)) (.lit (.natVal l))
  | .bvrepeat w i      => return mkApp2 (.const ``BitVec.replicate []) (.lit (.natVal w)) (.lit (.natVal i))
  | .bvzeroExtend w v  => return mkApp2 (.const ``BitVec.zeroExtend []) (.lit (.natVal w)) (.lit (.natVal v))
  | .bvsignExtend w v  => return mkApp2 (.const ``BitVec.signExtend []) (.lit (.natVal w)) (.lit (.natVal v))

  /--
    Takes a `s : LamSort` and produces the `un-lifted` version of `s.interp`
      (note that `s.interp` is lifted)
  -/
  def interpLamSortAsUnlifted (tyVal : HashMap Nat Expr) : LamSort → CoreM Expr
  | .atom n => do
    let .some e := tyVal.find? n
      | throwError "interpLamSortAsUnlifted :: Cannot find fvarId assigned to type atom {n}"
    return e
  | .base b => return Lam2D.interpLamBaseSortAsUnlifted b
  | .func s₁ s₂ => do
    return .forallE `_ (← interpLamSortAsUnlifted tyVal s₁) (← interpLamSortAsUnlifted tyVal s₂) .default

  def interpOtherConstAsUnlifted (tyVal : HashMap Nat Expr) (oc : OtherConst) : MetaM Expr := do
    let .some (.defnInfo constIdVal) := (← getEnv).find? ``constId
      | throwError "interpOtherConstAsUnlifted :: Unexpected error"
    let constIdExpr := fun params => constIdVal.value.instantiateLevelParams constIdVal.levelParams params
    match oc with
    | .smtAttr1T _ sattr sterm => do
      let tyattr ← interpLamSortAsUnlifted tyVal sattr
      let sortattr ← Expr.normalizeType (← Meta.inferType tyattr)
      let Expr.sort lvlattr := sortattr
        | throwError "interpOtherConstAsUnlifted :: Unexpected sort {sortattr}"
      let tyterm ← interpLamSortAsUnlifted tyVal sterm
      let sortterm ← Expr.normalizeType (← Meta.inferType tyterm)
      let Expr.sort lvlterm := sortterm
        | throwError "interpOtherConstAsUnlifted :: Unexpected sort {sortterm}"
      return Lean.mkApp2 (constIdExpr [lvlattr, lvlterm]) tyattr tyterm

  def interpLamBaseTermAsUnlifted (tyVal : HashMap Nat Expr) : LamBaseTerm → MetaM Expr
  | .pcst pc    => Lam2D.interpPropConstAsUnlifted pc
  | .bcst bc    => Lam2D.interpBoolConstAsUnlifted bc
  | .ncst nc    => Lam2D.interpNatConstAsUnlifted nc
  | .icst ic    => Lam2D.interpIntConstAsUnlifted ic
  | .scst sc    => Lam2D.interpStringConstAsUnlifted sc
  | .bvcst bvc  => Lam2D.interpBitVecConstAsUnlifted bvc
  | .ocst oc    => interpOtherConstAsUnlifted tyVal oc
  | .eqI _      => throwError ("interpLamTermAsUnlifted :: " ++ LamExportUtils.exportError.ImpPolyLog)
  | .forallEI _ => throwError ("interpLamTermAsUnlifted :: " ++ LamExportUtils.exportError.ImpPolyLog)
  | .existEI _  => throwError ("interpLamTermAsUnlifted :: " ++ LamExportUtils.exportError.ImpPolyLog)
  | .iteI _     => throwError ("interpLamTermAsUnlifted :: " ++ LamExportUtils.exportError.ImpPolyLog)
  | .eq s       => do
    return ←  Meta.mkAppOptM ``Eq #[← interpLamSortAsUnlifted tyVal s]
  | .forallE s  => do
    let ty ← interpLamSortAsUnlifted tyVal s
    let sort ← Expr.normalizeType (← Meta.inferType ty)
    let Expr.sort lvl := sort
      | throwError "interpLamBaseTermAsUnlifted :: Unexpected sort {sort}"
    let .some (.defnInfo forallVal) := (← getEnv).find? ``forallF
      | throwError "interpLamBaseTermAsUnlifted :: Unexpected error"
    let forallFExpr := forallVal.value.instantiateLevelParams forallVal.levelParams [lvl, .zero]
    return mkAppN forallFExpr #[← interpLamSortAsUnlifted tyVal s]
  | .existE s  => do
    return ← Meta.mkAppOptM ``Exists #[← interpLamSortAsUnlifted tyVal s]
  | .ite s     => do
    return ← Meta.mkAppOptM ``Bool.ite' #[← interpLamSortAsUnlifted tyVal s]

  /--
    Takes a `t : LamTerm` and produces the `un-lifted` version of `t.interp`.
    `lctx` is for pretty printing

    Note that `etom`s generated by the verified checker do not directly correspond
    to Lean expressions. Therefore, we need to introduce new free variables to
    represent `etom`s.
  -/
  def interpLamTermAsUnlifted
    (tyVal : HashMap Nat Expr) (varVal : HashMap Nat Expr) (etomVal : HashMap Nat Expr)
    (lctx : Nat) : LamTerm → MetaM Expr
  | .atom n => do
    let .some e := varVal.find? n
      | throwError "interpLamTermAsUnlifted :: Cannot find fvarId assigned to term atom {n}"
    return e
  | .etom n => do
    let .some efvar := etomVal.find? n
      | throwError "interpLamSortAsUnlifted :: Cannot find fvarId assigned to etom {n}"
    return efvar
  | .base b => interpLamBaseTermAsUnlifted tyVal b
  | .bvar n => return .bvar n
  | .lam s t => do
    let sinterp ← interpLamSortAsUnlifted tyVal s
    let tinterp ← interpLamTermAsUnlifted tyVal varVal etomVal lctx.succ t
    let name := (`eb!).appendIndexAfter lctx
    return .lam name sinterp tinterp .default
  | .app _ fn arg => do
    let fninterp ← interpLamTermAsUnlifted tyVal varVal etomVal lctx fn
    let arginterp ← interpLamTermAsUnlifted tyVal varVal etomVal lctx arg
    return .app fninterp arginterp

end Lam2D
