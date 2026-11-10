# julia-in-lean artefact samples: bug YAML, registry, coverage and memsafety TSVs, Audit.lean, scripts

> Source: https://github.com/MilesCranmer/julia-in-lean/tree/de862b5/julia-base
> Collected: 2026-11-10
> Published: 2026-11-07

[...omitted: the full set is 689 bugs/*.yaml, 740 repro files, 202 coverage/methods/*.tsv, 85 coverage/review/*.tsv, 6 memsafety/sites-*.tsv (~290 KB). Only samples below. Full data at the Source URL / ~/Projects/julia-in-lean...]

## bugs/ranges-operations-reverse-typemin.yaml (verbatim)
```yaml
id: ranges-operations-reverse-typemin
title: "Reversing a StepRange with a typemin step can return an empty range"
priority: P2
kind: wrong-result
area: Ranges
files: [base/range.jl, base/multidimensional.jl]
functions: ["reverse(::OrdinalRange)", "sort(::AbstractRange)", "reverse(::CartesianIndices)", "reverse(::CartesianIndices; dims)"]
summary: |
  Reversing the two-element range Int8(0):typemin(Int8):typemin(Int8)
  produces an empty range. The returned step remains negative.
  Sorting Int8(127):typemin(Int8):Int8(-1) also returns empty, because the
  descending-range sort at base/range.jl:1453 calls reverse.
  CartesianIndices inherits the same loss through all four reverse dispatch forms.
likelihood: |
  Rare, but reachable when a fixed-width step equals typemin. The same failure
  occurs with Int64 and Int128 typemin steps, so this is not confined to byte types.
maybe_intended: |
  The reversed positive step cannot fit the original signed step type. Widening
  or throwing would be defensible; silently returning an empty range loses data.
reproducer: |
  r = Int8(0):typemin(Int8):typemin(Int8)
  s = reverse(r)
  @assert length(r) == 2 && isempty(s)
  @assert reverse(collect(r)) == Int8[-128, 0]
  println("REPRODUCED ranges-operations-reverse-typemin")
output:
  release: |
    REPRODUCED ranges-operations-reverse-typemin
    multidimensional-reverse-region-all: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-all
    multidimensional-reverse-region-dimension: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-dimension
    multidimensional-reverse-region-single-tuple: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-single-tuple
    multidimensional-reverse-region-dimensions: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-dimensions
  nightly: |
    REPRODUCED ranges-operations-reverse-typemin
    multidimensional-reverse-region-all: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-all
    multidimensional-reverse-region-dimension: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-dimension
    multidimensional-reverse-region-single-tuple: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-single-tuple
    multidimensional-reverse-region-dimensions: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-dimensions
reproduced: {release: true, nightly: true}
expected: "A reversed range has the same two elements, in order [-128, 0], or reports an unrepresentable step."
promised_by: |
  "Return a copy of v reversed from start to stop" (reverse documentation,
  base/array.jl). Reversal preserves the number of elements.
cause: |
  base/range.jl:1435 reconstructs last(r):negate(step(r)):first(r).
  Signed negate uses wrapping unary minus (base/int.jl:96), so -typemin
  remains negative and the constructor sees incompatible endpoint direction.
  base/multidimensional.jl:547-570 delegates each CartesianIndices reversal to component-range reversal.
possible_fix: |
  Detect an unrepresentable signed step negation and widen the step or throw
  rather than constructing a range with the wrong direction.
duplicates:
  issues: []
  queries: ["issues: reverse range typemin", "issues: reverse StepRange overflow", "PRs: reverse range typemin"]
  search_notes: |
    No related issue or PR is known.
lean:
  property: JuliaLean.Ranges.reverseCardinalityProp
  theorem: JuliaLean.Ranges.reverseCardinalityRefuted
covers: [multidimensional-reverse-region-all, multidimensional-reverse-region-dimension, multidimensional-reverse-region-single-tuple, multidimensional-reverse-region-dimensions]
current:
  commit: f755f49a9e41380d7da126b3c1db9fe7f83dd027
  reproduced: true
  output: |
    REPRODUCED ranges-operations-reverse-typemin
    multidimensional-reverse-region-all: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-all
    multidimensional-reverse-region-dimension: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-dimension
    multidimensional-reverse-region-single-tuple: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-single-tuple
    multidimensional-reverse-region-dimensions: source length = 2; reverse length = 0
    REPRODUCED multidimensional-reverse-region-dimensions
```

## registry.tsv (first 8 lines)
```
strings-reverse-malformed	refuted	1	base/strings/stringview.jl	none found (queries: reverse invalid UTF-8, reverse malformed char, reverse string invalid)	collect(reverse(s)) == reverse(collect(s)) for every byte string s.
parseprint-tryparse-nothing-iff-parse-throws	proven	4	base/parse.jl		For every BitInteger type, byte string and valid base, tryparse returns nothing exactly when parse throws, and otherwise both return the same value.
parseprint-parse-overflow-detected	proven	4	base/parsers/ints.jl		For every BitInteger type and base 10 or 16, parsing the spelling of any integer within 16 of typemin, typemax, ±2^64 or ±2^128 returns that integer if it fits and throws otherwise; no wrapped value is returned.
parseprint-ryu-compact-lost-digit	refuted	1	base/ryu/shortest.jl	none found; related #33185 (closed, different compact rounding regression). Searched issues: compact show float digits; compact float printing; compact 1e16; Ryu compact; maxsignif; reduce_shortest; PRs: compact float; Ryu shortest; writeshortest	Compact display of a finite nonzero Float64 is within half a unit in the sixth significant digit of the value (plus the first rounding to shortest).
parseprint-ryu-compact-tie-even	refuted	3	base/ryu/shortest.jl	none found. Searched issues: compact tie even; round half even compact; compact float printing; Ryu compact; PRs: compact float; Ryu shortest; writeshortest	Compact display rounds an exact seven-digit tie k*10^e (last digit 5) to the even six-digit neighbour, as reduce_shortest does for smaller values.
parseprint-ryu-precision-pow10-overflow	refuted	3	base/ryu/shortest.jl	none found. Searched issues: writeshortest precision; Ryu precision; writeshortest 1e19; Ryu precision exponent form; PRs: writeshortest; writeshortest precision	writeshortest with precision p uses fixed notation for x = 10^k exactly whenever k < p.
parseprint-round-digits-overflow-zero	refuted	2	base/floatfuncs.jl	none found; open #63105 rewrites round with digits but keeps this branch. Searched issues: round sigdigits floatmax; round digits overflow zero; round floatmax; _round_step; PRs: round sigdigits; _round_step; round digits overflow	round(x; digits=-k) of a finite x >= 10^k is never zero (the nearest multiple of 10^k is at least 10^k).
arrayops-insert	proven	5	base/array.jl		insert!(a, i, x) for an index of any integer type puts x at index i for 1 <= i <= length(a)+1, and otherwise throws BoundsError (InexactError when Int(i) fails) leaving a unchanged.
```

## coverage/methods/int.tsv (first 8 lines)
```
file	line	endline	name	signature	status	entry	note
base/int.jl	73	73	signed	signed(::Type{Bool})	modelled	int-signed-bool-size	
base/int.jl	74	74	signed	signed(::Type{UInt8})	modelled	int-rem-unsigned-signed	
base/int.jl	75	75	signed	signed(::Type{UInt16})	modelled	int-rem-unsigned-signed	
base/int.jl	76	76	signed	signed(::Type{UInt32})	modelled	int-rem-unsigned-signed	
base/int.jl	77	77	signed	signed(::Type{UInt64})	modelled	int-rem-unsigned-signed	
base/int.jl	78	78	signed	signed(::Type{UInt128})	modelled	int-rem-unsigned-signed	
base/int.jl	79	79	signed	signed(::Type{T}) where {T<:Signed}	modelled	int-rem-unsigned-signed,floatintcov-int-signed-types,int-signed-bool-size	Reviewed line by line against pinned f755f49 source.
```

## coverage/review/int.tsv (first 8 lines + sample HOLLOW rows)
```
line	name	verdict	mirror	property	settled	reason
73	signed	FAITHFUL	yes	yes	yes	The model returns Int64 for Bool exactly as the 64-bit Julia method does, and the proven proposition covers its only input.
74	signed	FAITHFUL	yes	yes	yes	The model returns Int8 for UInt8 exactly as the source method does, and the proposition is proven.
75	signed	FAITHFUL	yes	yes	yes	The model returns Int16 for UInt16 exactly as the source method does, and the proposition is proven.
76	signed	FAITHFUL	yes	yes	yes	The model returns Int32 for UInt32 exactly as the source method does, and the proposition is proven.
77	signed	FAITHFUL	yes	yes	yes	The model returns Int64 for UInt64 exactly as the source method does, and the proposition is proven.
78	signed	FAITHFUL	yes	yes	yes	The model returns Int128 for UInt128 exactly as the source method does, and the proposition is proven.
79	signed	FAITHFUL	yes	yes	yes	The identity model covers every signed fixed-width type and states the documented same-type result in a proven proposition.
86	_dropdims	HOLLOW	no	yes	yes	The model replaces the method's dimension loop and its range, singleton-axis, and duplicate checks with an unconstrained validate callback.
196	conj!	HOLLOW	no	no	yes	The model hides foreach(conj!, A) behind an unconstrained one-argument callback, so it neither mirrors the conj! call nor states that every element is conjugated.
498	pad	HOLLOW	no	yes	yes	The model evaluates the fill value and Val(maximum length) once and reuses them, while the Julia body constructs both separately for each fill_to_length call.
502	pad	HOLLOW	no	yes	yes	The model evaluates the fill value and Val(maximum length) once and reuses them, while the Julia body constructs all three separately for the three fill_to_length calls.
559	repeat_outer	HOLLOW	no	yes	yes	The model computes only each block's starting row and column, omitting the source body's row-end and column-end arithmetic and range construction.
583	repeat_outer	HOLLOW	no	yes	yes	The model iterates repetition targets outside source indices, reversing the Julia body's outer source loop and inner repetition loop.
599	repeat_inner	HOLLOW	no	yes	yes	The model iterates inner-copy targets outside source indices, reversing the Julia body's outer source loop and inner copy loop.
5	_broadcast_preserving_zero_d	HOLLOW	yes	no	yes	The proposition only unfolds the wrapper to the same opaque broadcast call and proves no independent zero-dimensional broadcasting behavior.
```

## memsafety/sites-1.tsv (first 5 lines)
```
site	file	line	kind	group	status	entry	note	code
Base_compiler:25	base/Base_compiler.jl	25	memoryref	1	todo		Pending target-source proof or review; previous: Base_compiler:25 proven memsafety-base-compiler-bootstrap	Core.memoryrefset!(Core.memoryref(_included_files.ref, lenp1), (mod, ccall(:jl_prepend_cwd, Any, (Any,), path)), :not_atomic, true)
Base_compiler:200	base/Base_compiler.jl	200	unsafe_copyto!	1	todo		Pending target-source proof or review; previous: Base_compiler:200 proven memsafety-base-compiler-bootstrap	unsafe_copyto!(out_ptr, unsafe_convert(Ptr{UInt8}, x), Core.sizeof(x))
Base_compiler:201	base/Base_compiler.jl	201	unsafe_copyto!	1	todo		Pending target-source proof or review; previous: Base_compiler:201 proven memsafety-base-compiler-bootstrap	unsafe_copyto!(out_ptr + Core.sizeof(x), unsafe_convert(Ptr{UInt8}, y), Core.sizeof(y))
abstractarraymath:194	base/abstractarraymath.jl	194	@inbounds	1	todo		Pending target-source proof or review; previous: abstractarraymath:194 proven memsafety-abstractarraymath-broadcast-repeat	conj!(A::AbstractArray{<:Number}) = (@inbounds broadcast!(conj, A, A); A)
```

## Audit.lean (verbatim)
```
import JuliaLean
import JuliaLean.Registry.Audit

/-!
Audit of the property registry. Run with `lake env lean Audit.lean`; any failure
raises an error, so the command exits nonzero. Open `todo` entries are listed as
`TODO <id>` lines and counted, but do not fail the audit.

Checks, for every registry entry:
* ids are unique;
* `prop` is a closed, universe-monomorphic `Prop` constant;
* `thm` is a theorem whose type is `prop` (proven) or `¬ prop` (refuted);
* `thm` depends only on `propext`, `Classical.choice`, and `Quot.sound`;
* refuted entries record a duplicate-issue search result in `issue`.

It prints `REFUTED <id>` lines used by the reproducer runner for Base runtime
refutations (`scripts/run-repros.sh`).
-/

#eval auditEntries JuliaLean.Registry.all
```

## scripts/audit.sh (verbatim)
```
#!/usr/bin/env bash
# Build the Lean project, reject forbidden proof escapes, and audit the C runtime
# and Base registries.
# Run from the package root. Writes .lake/audit.out.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

python3 scripts/check-hoist.py

LEAN_NUM_THREADS=2 lake build JuliaLean JuliaLean.Registry.Audit

python3 scripts/check-proof-escapes.py

lake env lean CRuntimeAudit.lean
lake env lean Audit.lean | tee .lake/audit.out
```

## scripts/run-repros.sh (verbatim)
```
#!/usr/bin/env bash
# Run the reproducer of every refuted registry entry with one Julia binary.
#
#   JULIA=/path/to/julia scripts/run-repros.sh      (default: julia on PATH)
#
# Reads the `REFUTED <id>` lines that scripts/audit.sh writes to .lake/audit.out,
# runs repro/<target>.jl for each, where scripts/repro-target.sh names the target
# (the id itself, or the bug whose `covers` list names it), and prints
# `<id> REPRODUCED` when the output contains the line `REPRODUCED <target>`, else
# `<id> not-reproduced`. Ends with `REPROS <n> FAILURES <k>` and exits nonzero
# when any reproducer failed.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
JULIA=${JULIA:-julia}

if [[ ! -s .lake/audit.out ]]; then
    echo "FAIL missing .lake/audit.out; run scripts/audit.sh first" >&2
    exit 1
fi

count=0 failures=0
while read -r id; do
    count=$((count + 1))
    if target=$(bash scripts/repro-target.sh "$id") &&
        grep -qx "REPRODUCED $target" <<<"$("$JULIA" --startup-file=no --history-file=no "repro/$target.jl" </dev/null 2>&1)"; then
        echo "$id REPRODUCED"
    else
        echo "$id not-reproduced"
        failures=$((failures + 1))
    fi
done < <(sed -n 's/^REFUTED //p' .lake/audit.out)

echo "REPROS $count FAILURES $failures"
[[ $failures -eq 0 ]]
```

## scripts/check-bugs.sh (verbatim)
```
#!/bin/bash
# Validate bugs/*.yaml (runs on the Mac; plain Python, no Julia or Lean).
exec uv run --no-project --quiet --with pyyaml python "$(dirname "${BASH_SOURCE[0]}")/check_bugs.py" "$@"
```

## repro/float-differential.jl (first 40 lines)
```julia
const words = UInt64[0,1,2,0x000ffffffffffffe,0x000fffffffffffff,0x0010000000000000,0x0010000000000001,0x3fdfffffffffffff,0x3fe0000000000000,0x3fe0000000000001,0x3ff0000000000000,0x3ff0000000000001,0x3ff7ffffffffffff,0x3ff8000000000000,0x4004000000000000,0x433fffffffffffff,0x4340000000000000,0x7feffffffffffffe,0x7fefffffffffffff,0x7ff0000000000000,0x7ff0000000000001,0x7ff8000000000000,0x7fffffffffffffff]
append!(words,words .| 0x8000000000000000)
for k in [7,8,15,16,31,32,63,64,127,128]
    b = reinterpret(UInt64,2.0^k)
    for j in -2:2
        push!(words,b+UInt64(j % UInt64))
        push!(words,(b+UInt64(j % UInt64)) | 0x8000000000000000)
    end
end
let state=UInt64(0x243f6a8885a308d3)
    for _ in 1:2048
        state=state*UInt64(6364136223846793005)+UInt64(1442695040888963407)
        push!(words,state)
    end
end
out(x::Float64)=isnan(x) ? "nan" : string(reinterpret(UInt64,x))
out(x::Bool)=x ? "true" : "false"
out(x::Integer)=string(x)
out(x::Tuple)=join(out.(x),",")
function emit(i,op,f)
    try
        println(i," ",op," ",out(f()))
    catch e
        e isa Union{InexactError,DomainError,MethodError} || rethrow()
        println(i," ",op," ",e isa InexactError ? "inexact" : e isa DomainError ? "domain" : "method")
    end
end
const modes=[RoundNearest,RoundNearestTiesAway,RoundUp,RoundDown,RoundToZero]
const types=[Int8,Int16,Int32,Int64,Int128,UInt8,UInt16,UInt32,UInt64,UInt128]
const scales=[-2200,-1075,-1074,-1022,-53,-1,0,1,52,1023,1074,2200]
const steps=[-10000,-2,-1,0,1,2,10000]
println("0 floatmin ",out(floatmin(Float64)))
println("0 floatmax ",out(floatmax(Float64)))
for (i,b) in enumerate(words)
    x=reinterpret(Float64,b)
    y=reinterpret(Float64,words[mod(17*(i-1)+7,length(words))+1])
    z=reinterpret(Float64,words[mod(31*(i-1)+11,length(words))+1])
    for (name,f) in [("neg",()->-x),("abs",()->abs(x)),("sqrt",()->sqrt(x)),("signbit",()->signbit(x)),("isnan",()->isnan(x)),("isinf",()->isinf(x)),("isfinite",()->isfinite(x)),("next",()->nextfloat(x)),("prev",()->prevfloat(x)),("eps",()->eps(x)),("exponent",()->exponent(x)),("significand",()->significand(x)),("frexp",()->frexp(x)),("int",()->Int(x)),("ldexp",()->ldexp(x,scales[mod(i-1,length(scales))+1])),("nextn",()->nextfloat(x,steps[mod(i-1,length(steps))+1])),("prevn",()->prevfloat(x,steps[mod(i-1,length(steps))+1]))]
        emit(i,name,f)
    end
```
