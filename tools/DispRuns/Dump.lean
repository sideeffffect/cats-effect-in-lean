import CatsEffectInLean.Proofs.Phase7.DispatcherCommon

/-!
Dumper of the kernel runs of track P7D (decision 55, chunks). Not part of a library: run with
`lake env lean --run tools/DispRuns/Dump.lean <par> <aw> <input> <variant> <seed|-> <fuel> <chunk>`.
It prints `step <k>` lines for the chunk boundaries (between tasks, `cur = none`, about every
`<chunk>` micro-steps), each followed by the `Repr` of the state, then `end <n>` with the number
of micro-steps until the run stops (or `<fuel>`). `tools/DispRuns/gen.py` writes the modules.
-/

open CatsEffectInLean.Model CatsEffectInLean.Props.Phase7.Dispatcher
open CatsEffectInLean.Proofs.Phase7.DispatcherCommon

def inputOf : String → Inp
  | "xs0" => xs0 | "xs1" => xs1 | "xcn" => xcn | "xlate" => xlate | "xce" => xce
  | "xsl" => xsl | "xcan" => xcan | "x90" => x90 | "(pureInp [] [] [] p p)" => pureInp [] [] [] p p | _ => xs0

def main (args : List String) : IO Unit := do
  match args with
  | [par, aw, inp, v, seed, fuel, chunk] =>
    let x := inputOf inp
    let cs : List PChoice := if seed == "-" then [] else sched seed.toNat! 300
    let e := env id x u
    let mut s : Sched CounterMask :=
      Sched.init counterMaskModel (prog (par == "true") (aw == "true") 1 .unit x.ws.length v.toNat!)
    let mut c := cs
    let mut n := 0
    let mut last := 0
    for _ in [0:fuel.toNat!] do
      match s.halt with
      | some _ => break
      | none =>
        s := s.tickP {} counterMaskModel e (c.headD (.pick 0)); c := c.tail; n := n + 1
        if s.cur.isNone && s.halt.isNone && n - last ≥ chunk.toNat! && n + 20 < fuel.toNat! then
          IO.println s!"step {n}"
          IO.println (toString (repr s))
          last := n
    IO.println s!"end {n}"
  | _ => IO.eprintln "usage: Dump <par> <aw> <input> <variant> <seed|-> <fuel> <chunk>"
