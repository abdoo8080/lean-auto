import Auto.Tactic
import Mathlib.Data.Set.Intervals.Basic
import Mathlib.Data.Real.Basic
import Mathlib.Data.Set.Lattice
import Mathlib.Data.Set.Function
import Mathlib.Order.Basic

set_option auto.prep.redMode "reducible"
set_option trace.auto.mono true
set_option trace.auto.tactic true
set_option trace.auto.lamReif.printResult true

set_option trace.auto.lamReif.printValuation true
set_option maxHeartbeats 20000 in
example (a b c d : ℝ) (h1 : a < b) : Set.Icc a b ⊆ Set.Ico c d ↔ c ≤ a ∧ b < d := by
  auto [Set.subset_def, Set.mem_Icc, Set.mem_Ico,
        @le_trans, @le_total, @lt_iff_not_le, DenselyOrdered.dense a b, h1]

set_option trace.auto.printLemmas true in
set_option trace.auto.mono.printLemmaInst true in
example : f '' s ⊆ v ↔ s ⊆ f ⁻¹' v := by
  auto [Set.subset_def, Set.mem_image, Set.mem_preimage]

set_option trace.auto.mono.printLemmaInst true in
example (h : Function.Injective f) : f ⁻¹' (f '' s) ⊆ s := by
  auto [Set.subset_def, Set.mem_preimage, Function.Injective.mem_set_image]

set_option trace.auto.mono.printLemmaInst true in
example : f '' (f ⁻¹' u) ⊆ u := by
  auto [Set.subset_def, Set.mem_image, Set.mem_preimage]

set_option trace.auto.mono.printLemmaInst true in
set_option auto.mono.saturationThreshold 200 in
example (h : Function.Surjective f) : u ⊆ f '' (f ⁻¹' u) := by
  auto [Set.subset_def, Function.Surjective, Set.mem_image, Set.mem_preimage]
