# MilesCranmerBot issues and PRs on JuliaLang/julia (list + all issue comments)

> Source: https://github.com/JuliaLang/julia/issues?q=author%3AMilesCranmerBot
> Collected: 2026-11-10
> Published: 2026-10-24..2026-11-09

Collected with `gh search issues/prs --repo JuliaLang/julia --author MilesCranmerBot` and `gh api repos/JuliaLang/julia/issues/<n>` on 2026-11-10. Comments are verbatim.

## Summary

- Issues: 112; states: {'open/reopened': 1, 'open/None': 67, 'closed/completed': 44}
- PRs: 122; states: {'open': 42, 'merged': 77, 'closed': 3}
- Issue labels: {'bug': 33, 'ranges': 15, 'maths': 13, 'arrays': 13, 'io': 11, 'collections': 10, 'bignums': 8, 'stdlib': 8, 'strings': 6, 'iteration': 6, 'rationals': 5, 'equality': 5, 'GC': 4, 'regression 1.14': 4, 'unicode': 4, 'TOML': 4, 'sorting': 4, 'correctness bug ⚠': 3, 'broadcast': 3, 'missing data': 3, 'fold': 3, 'compiler:codegen': 2, 'types and dispatch': 2, 'filesystem': 2, 'search & find': 2, 'ffi': 2, 'cmd': 2, 'macros': 2, 'artifacts': 2, 'embarrassing-bugfix': 2, 'complex': 1, 'packages': 1, 'markdown': 1, 'crash-on-valid': 1, 'compiler:inference': 1, 'system:windows': 1, 'docs': 1, 'display and printing': 1}
- Issues per day: {'2026-10-24': 20, '2026-10-25': 70, '2026-10-26': 10, '2026-10-27': 3, '2026-10-28': 1, '2026-10-29': 3, '2026-10-31': 1, '2026-11-07': 1, '2026-11-08': 3}
- PRs per day: {'2026-03-01': 1, '2026-05-23': 1, '2026-10-27': 82, '2026-10-28': 2, '2026-10-29': 16, '2026-10-30': 3, '2026-10-31': 4, '2026-11-02': 2, '2026-11-03': 3, '2026-11-05': 1, '2026-11-06': 2, '2026-11-08': 4, '2026-11-09': 1}

## Issues

| # | state | reason | comments | created | closed | labels | title |
|---|---|---|---|---|---|---|---|
| 64123 | open | None | 0 | 2026-10-24 |  | ranges | ranges: intersect can omit shared values |
| 64124 | open | None | 0 | 2026-10-24 |  | ranges | ranges: reverse can empty a range with a typemin step |
| 64125 | open | None | 0 | 2026-10-24 |  | maths | intfuncs: ndigits overcounts unsigned values with a typemin base |
| 64126 | open | None | 0 | 2026-10-24 |  | ranges | ranges: slicing an unsigned range in reverse returns empty |
| 64127 | open | None | 0 | 2026-10-24 |  | broadcast, ranges | ranges: .+ and .- can empty integer ranges after overflow |
| 64128 | open | None | 0 | 2026-10-24 |  | sorting | sort: partialsort rejects empty index ranges only for larger inputs |
| 64129 | closed | completed | 0 | 2026-10-24 | 2026-10-28 | sorting | sort: partialsort returns wrong values for descending index ranges |
| 64130 | open | None | 0 | 2026-10-24 |  | ranges, sorting | sort: searchsorted can report matches in empty ranges |
| 64131 | open | None | 0 | 2026-10-24 |  | ranges, regression 1.14 | 1.14 regression: intersect can return values absent from an input |
| 64132 | closed | completed | 0 | 2026-10-24 | 2026-10-30 | sorting | sort: partialsortperm fails when k has a narrow integer type |
| 64133 | open | None | 0 | 2026-10-24 |  | ranges | ranges: broadcasted multiplication can produce a range that throws when indexed |
| 64134 | open | None | 0 | 2026-10-24 |  | ranges | ranges: slicing an Int8 range can throw for valid indices |
| 64135 | open | None | 0 | 2026-10-24 |  | bug, collections | sets: in! can silently insert a lossy conversion |
| 64136 | open | None | 0 | 2026-10-24 |  | ranges | ranges: range can miss a tiny nonzero endpoint |
| 64137 | open | None | 0 | 2026-10-24 |  | collections, equality | dicts: ImmutableDict equality breaks with repeated keys |
| 64138 | open | None | 0 | 2026-10-24 |  | bug, ranges | ranges: allunique and allequal can disagree with floating range elements |
| 64139 | open | None | 0 | 2026-10-24 |  | collections | dicts: converting an ImmutableDict can restore shadowed values |
| 64140 | open | None | 0 | 2026-10-24 |  | display and printing, correctness bug ⚠ | show: compact Float64 display can drop the sixth significant digit |
| 64141 | closed | completed | 1 | 2026-10-24 | 2026-10-30 | docs, maths | docs: gcdx coefficient bounds are too strict for equal inputs |
| 64142 | open | None | 1 | 2026-10-24 |  | bug, maths | round: sigdigits can turn large finite values into zero |
| 64143 | closed | completed | 0 | 2026-10-25 | 2026-10-28 | bug, strings | strings: first(s, typemax(Int)) returns empty for non-ASCII strings |
| 64144 | open | None | 0 | 2026-10-25 |  | bug, strings | raw_substring with a truncated character cannot be iterated |
| 64145 | open | None | 0 | 2026-10-25 |  | bug, collections | sets: symdiff! on BitSet still depends on duplicate multiplicity |
| 64146 | closed | completed | 0 | 2026-10-25 | 2026-10-28 | bug, arrays | bitarrays: circshift! throws on empty BitVectors |
| 64147 | open | None | 0 | 2026-10-25 |  | arrays | bitarrays: resizing vec or reshape corrupts the original BitArray |
| 64148 | closed | completed | 0 | 2026-10-25 | 2026-11-09 | bug, arrays | bitarrays: deleteat! and splice! reject empty ranges accepted by Vector |
| 64149 | closed | completed | 2 | 2026-10-25 | 2026-11-05 | system:windows, regression 1.14 | 1.14 regression: failed GC page commit violates the no-ABA contract on Windows |
| 64150 | closed | completed | 0 | 2026-10-25 | 2026-11-06 | bug, iteration | tuples: middle-slurp destructuring can reuse consumed elements |
| 64151 | closed | completed | 1 | 2026-10-25 | 2026-10-29 | bug, iteration, embarrassing-bugfix | iterators: take(itr, 0) reports nonempty for stateful iterators |
| 64152 | closed | completed | 0 | 2026-10-25 | 2026-10-28 | bug, iteration, embarrassing-bugfix | iterators: isempty on Rest ignores the stored iteration state |
| 64153 | open | None | 1 | 2026-10-25 |  | search & find | findall: optimized in predicate changes equality semantics |
| 64154 | closed | completed | 1 | 2026-10-25 | 2026-10-31 | types and dispatch | namedtuples: haskey and get fail for non-Int integer keys |
| 64155 | closed | completed | 1 | 2026-10-25 | 2026-11-02 | iteration | iterators: product of stateful iterators throws after exhaustion |
| 64158 | open | None | 0 | 2026-10-25 |  | bug, collections | dicts: replace! can silently insert lossy key conversions |
| 64159 | closed | completed | 0 | 2026-10-25 | 2026-10-26 | iteration, fold | reduce: sum over an all-empty Flatten iterator throws |
| 64160 | closed | completed | 0 | 2026-10-25 | 2026-10-27 | arrays | reinterpretarray: nested reinterpret(reshape, ...) drops intermediate dimensions |
| 64161 | closed | completed | 0 | 2026-10-25 | 2026-10-27 | fold | reduce: foldr skips reduce_first for singleton inputs |
| 64162 | open | None | 0 | 2026-10-25 |  | rationals, maths | math: exponent(::Rational) can be off by one |
| 64163 | closed | completed | 0 | 2026-10-25 | 2026-10-26 | fold | reduce: accumulate ignores init when dims exceeds ndims |
| 64164 | open | None | 0 | 2026-10-25 |  | bug, io | io: copyline can delete existing output at EOF |
| 64165 | open | None | 0 | 2026-10-25 |  | bug, io | io: take! fails on a PipeBuffer after closewrite |
| 64166 | closed | completed | 0 | 2026-10-25 | 2026-10-28 | bug, io | io: takestring! can return already-consumed bytes from a marked PipeBuffer |
| 64167 | open | None | 0 | 2026-10-25 |  | rationals, equality | rational: cmp disagrees with isless for signed zero |
| 64168 | closed | completed | 0 | 2026-10-25 | 2026-10-27 | bug, collections | sets: Set{Bool} constructor validation depends on input order |
| 64170 | closed | completed | 0 | 2026-10-25 | 2026-11-03 | bug, TOML | toml: later value can silently overwrite an existing table |
| 64171 | open | None | 0 | 2026-10-25 |  | bug, unicode, TOML | toml: \xHH escapes can produce invalid strings |
| 64172 | closed | completed | 0 | 2026-10-25 | 2026-11-05 | bug, maths, missing data | math: sincospi(missing) returns one value instead of a tuple |
| 64173 | open | None | 0 | 2026-10-25 |  | bug, unicode, equality | unicode: isequal_normalized with stripmark mishandles decomposed text |
| 64174 | open | None | 0 | 2026-10-25 |  | TOML | toml: valid multiline strings ending in quotes fail to parse |
| 64175 | closed | completed | 0 | 2026-10-25 | 2026-10-26 | arrays | arrays: selectdim with CartesianIndex can create an out-of-bounds view |
| 64176 | closed | completed | 0 | 2026-10-25 | 2026-11-03 | bug, TOML | toml: valid floats with mantissa underscores and an exponent fail to parse |
| 64177 | open | None | 0 | 2026-10-25 |  | bug, arrays, bignums | bigint: digits! into a view fails when the output is shorter than the number |
| 64178 | closed | completed | 0 | 2026-10-25 | 2026-11-04 | maths, bignums | bigfloat: integer rounding rejects nearest-ties-away and nearest-ties-up |
| 64179 | closed | completed | 0 | 2026-10-25 | 2026-10-26 | rationals, bignums, equality | bigint: cmp on Rational{BigInt} can return values outside -1:1 |
| 64180 | closed | completed | 0 | 2026-10-25 | 2026-10-26 | rationals, bignums, equality | bigint: cmp orders infinite Rational{BigInt} values incorrectly |
| 64183 | open | None | 1 | 2026-10-25 |  | compiler:inference, correctness bug ⚠, regression 1.14 | 1.14 regression: stale isa refinement across loop iterations miscompiles code |
| 64185 | open | None | 0 | 2026-10-25 |  | bug, bignums, stdlib, crash-on-valid | printf: large BigFloat after preceding output can write past the buffer |
| 64186 | open | None | 0 | 2026-10-25 |  | maths | rounding: floor with sigdigits can return zero just below a power of ten |
| 64189 | open | None | 0 | 2026-10-25 |  | io, stdlib | base64: DecodePipe loses buffered data after a partial read |
| 64190 | closed | completed | 0 | 2026-10-25 | 2026-11-07 | io, stdlib | base64: readbytes! hangs with an empty destination buffer |
| 64191 | open | None | 0 | 2026-10-25 |  | broadcast, ranges | broadcast: floating operations on unsigned ranges can return wrong values |
| 64192 | open | None | 0 | 2026-10-25 |  | unicode, cmd | shell: line continuation can drop characters after non-ASCII text |
| 64193 | open | None | 0 | 2026-10-25 |  | filesystem, artifacts | artifacts: slash lookup allows paths outside the artifact directory |
| 64194 | open | None | 7 | 2026-10-25 |  | io, strings | strings: String(v) can remain mutable through arrays sharing a take! buffer |
| 64195 | closed | completed | 0 | 2026-10-25 | 2026-11-02 | artifacts | artifacts: artifact_hash ignores pkg_uuid overrides |
| 64196 | closed | completed | 0 | 2026-10-25 | 2026-11-02 | unicode, markdown | markdown: non-ASCII numbered text can throw ArgumentError |
| 64198 | closed | completed | 0 | 2026-10-25 | 2026-11-01 | collections | dicts: WeakKeyDict length can count collected entries |
| 64199 | open | None | 0 | 2026-10-25 |  | stdlib | serialization: scalar values of custom primitive types cannot be serialized |
| 64200 | closed | completed | 0 | 2026-10-25 | 2026-10-30 | bug, stdlib | uuids: uuid5 unescapes the name before hashing |
| 64201 | open | None | 1 | 2026-10-25 |  | maths | combinatorics: binomial(typemin(T), one(T)) returns zero |
| 64202 | closed | completed | 0 | 2026-10-25 | 2026-11-02 | stdlib | printf: negative dynamic precision can write integer digits out of bounds |
| 64204 | open | None | 0 | 2026-10-25 |  | bignums, stdlib | printf: exact-fit BigFloat conversion replaces the last character with NUL |
| 64205 | open | None | 0 | 2026-10-25 |  | GC | gc: write barriers mix plain and atomic accesses to the object header |
| 64206 | open | None | 0 | 2026-10-25 |  | GC | gc: work-stealing queue races when a circular slot is reused |
| 64207 | open | None | 0 | 2026-10-25 |  | GC | gc: page decommit scan races with concurrent neighbor reuse |
| 64216 | open | None | 2 | 2026-10-25 |  | maths, macros | fastmath: non-binary hypot calls throw MethodError |
| 64217 | open | None | 0 | 2026-10-25 |  | macros | enums: typemin is wrong when values are out of order |
| 64218 | closed | completed | 3 | 2026-10-25 | 2026-10-26 | io | io: writing to a closed IOStream silently returns zero |
| 64219 | open | None | 0 | 2026-10-25 |  | cmd | cmd: ignorestatus rejects stderr pipelines |
| 64222 | open | None | 0 | 2026-10-25 |  | arrays | arrays: permutedims rejects offset-axis StridedArray views |
| 64224 | closed | completed | 0 | 2026-10-25 | 2026-10-30 | strings, ffi | strings: Ptr{T}(::Cwstring) ignores T |
| 64225 | open | None | 2 | 2026-10-25 |  | bug, maths | math: tanh(Float32) is locally non-monotonic |
| 64229 | open | None | 0 | 2026-10-25 |  | packages | loading: workspace lookup confuses HOME path prefixes |
| 64234 | open | None | 0 | 2026-10-25 |  | io | io: Base.getpass ignores Backspace on Unix |
| 64235 | closed | completed | 0 | 2026-10-25 | 2026-11-02 | collections | sets: replace drops elements from BitSet and IdSet |
| 64236 | closed | completed | 0 | 2026-10-25 | 2026-11-02 | io, iteration | io: reverse(eachline(io)) truncates lines across 4 KiB chunks |
| 64237 | open | None | 0 | 2026-10-25 |  | collections | dicts: map! can skip IdDict values after a rehash |
| 64238 | open | None | 1 | 2026-10-25 |  | missing data, bignums | missing: float silently narrows abstract numeric arrays to Float64 |
| 64239 | open | None | 0 | 2026-10-25 |  | missing data, collections | sets: replace fails when replacing missing |
| 64240 | open | None | 0 | 2026-10-25 |  | stdlib, ffi | libdl: dlopen(LazyLibrary; throw_error=false) throws MethodError |
| 64262 | closed | completed | 0 | 2026-10-26 | 2026-10-27 | bug, arrays | arrays: sizehint! with first=true throws on empty vectors |
| 64263 | closed | completed | 0 | 2026-10-26 | 2026-10-27 | bug, arrays, search & find | arrays: byte-vector search returns invalid ranges for offset-indexed patterns |
| 64265 | closed | completed | 1 | 2026-10-26 | 2026-10-26 | ranges | ranges: intersect(r, v) returns elements in v's order |
| 64266 | closed | completed | 0 | 2026-10-26 | 2026-10-29 | bug, bignums | bigfloat: invalid parse base crashes Julia |
| 64267 | open | None | 0 | 2026-10-26 |  | bug, filesystem | filesystem: cp with force=true does not remove a dangling destination symlink |
| 64268 | open | None | 0 | 2026-10-26 |  | bug, io, strings | strings: replace with regex captures corrupts append-mode buffers |
| 64269 | open | None | 0 | 2026-10-26 |  | bug, rationals | rationals: rationalize ignores tol for out-of-range integer inputs |
| 64270 | open | None | 0 | 2026-10-26 |  | bug, io | crc32c: IOStream specialization can silently ignore stream contents |
| 64271 | open | None | 0 | 2026-10-26 |  | maths | round(Float16, 2845.343f0) returns 2844 although 2846 is closer |
| 64272 | closed | completed | 4 | 2026-10-26 | 2026-11-02 | ranges | LinRange(0.1, 0.1, 6) is not constant |
| 64274 | closed | completed | 0 | 2026-10-27 | 2026-10-27 | arrays | arrays: filter throws TypeError on an empty Cartesian-indexed array |
| 64276 | closed | completed | 0 | 2026-10-27 | 2026-10-27 | bug, arrays | arrays: A[] returns the wrong element for a singleton offset-indexed view |
| 64281 | open | None | 0 | 2026-10-27 |  | arrays | get(A, I, default) throws MethodError when I is a tuple of index vectors |
| 64433 | open | None | 0 | 2026-10-28 |  | arrays | arrays: `cat` with an offset axis returns misplaced values or uninitialized memory |
| 64437 | open | None | 0 | 2026-10-29 |  | broadcast, ranges | ranges: broadcasting can change the numerical result for a `LinRange` |
| 64440 | open | None | 1 | 2026-10-29 |  | maths, correctness bug ⚠ | integers: `div`, `fld` and `cld` return an unsigned result when dividing an unsigned integer by a wider signed integer |
| 64453 | closed | completed | 0 | 2026-10-29 | 2026-11-01 | ranges | ranges: `findall(in(span), r)` returns invalid indices when endpoint differences overflow |
| 64524 | open | None | 1 | 2026-10-31 |  | strings | regex: `replace` skips an empty match right after a non-empty match |
| 64767 | open | None | 2 | 2026-11-07 |  | types and dispatch, regression 1.14 | 1.14 regression: `sizeof` returns 8 for `Type{T}` types |
| 64774 | closed | completed | 0 | 2026-11-08 | 2026-11-09 | maths, complex | complex: `muladd` with a real addend does not promote the imaginary part |
| 64779 | open | None | 3 | 2026-11-08 |  | compiler:codegen | datatype: `VecElement` tuples over 32 KiB get alignment 0 |
| 64790 | open | reopened | 3 | 2026-11-08 |  | compiler:codegen, GC | codegen: GC frees a field of an `unsafe_load` result at `-O2` but not `-O0` |

## Pull requests

| # | state | created | title |
|---|---|---|---|
| 61205 | open | 2026-03-01 | Add `Base.haszero` and use it in `zero` for arrays |
| 61890 | open | 2026-05-23 | fix: add missing Base keyword methods |
| 64286 | merged | 2026-10-27 | regex: throw "Bad replacement string" for an empty group name in `s"\g<>"` |
| 64287 | merged | 2026-10-27 | array: pass converted `dims` to `_wrap` in `wrap(Array, ::Memory, ::Integer)` |
| 64288 | merged | 2026-10-27 | gmp: throw `DomainError` from `isqrt` for negative `BigInt` |
| 64289 | merged | 2026-10-27 | iobuffer: clear the mark in `takestring!` as `take!` does |
| 64290 | merged | 2026-10-27 | libc: throw `SystemError` from `dup` when it fails |
| 64291 | merged | 2026-10-27 | path: zero-pad percent-encoded bytes in `encode_uri_component` |
| 64292 | open | 2026-10-27 | Terminals: fix `TextTerminal` relative cursor move fallbacks |
| 64293 | open | 2026-10-27 | show: skip redundant ANSI reset when truncating after `\e[0m` |
| 64294 | open | 2026-10-27 | cmd: support stderr pipelines in `ignorestatus` |
| 64295 | closed | 2026-10-27 | annotated: make `eachregion` return no regions for empty strings |
| 64296 | merged | 2026-10-27 | TOML: skip a leading byte order mark when parsing |
| 64297 | merged | 2026-10-27 | TOML: accept floats with underscores before an exponent |
| 64298 | open | 2026-10-27 | TOML: widen 22- and 43-digit octal integers that overflow |
| 64300 | merged | 2026-10-27 | Base64: fix `readbytes!` hang when the buffer is empty |
| 64301 | merged | 2026-10-27 | mpfr: throw `ArgumentError` for invalid base in `tryparse(BigFloat)` |
| 64302 | merged | 2026-10-27 | mpfr: return `nothing` from `tryparse(BigFloat, s)` when `s` contains NUL |
| 64303 | merged | 2026-10-27 | set: collect replacements before mutating in `replace` for `AbstractSet` |
| 64304 | open | 2026-10-27 | iobuffer: strip empty-line newline in `copyline` into buffer middle |
| 64305 | merged | 2026-10-27 | rational: fix subtracting a finite unsigned rational from infinity |
| 64306 | open | 2026-10-27 | iobuffer: make `copyline` strip only the newline of the copied line |
| 64307 | open | 2026-10-27 | getpass: make Backspace delete the previous character |
| 64308 | merged | 2026-10-27 | env: restore the original value of a key repeated in `withenv` |
| 64309 | merged | 2026-10-27 | bitarray: fix `reverse(::BitArray; dims)` on empty arrays |
| 64310 | open | 2026-10-27 | iobuffer: throw in `readuntil`/`readline` on a non-readable buffer |
| 64311 | merged | 2026-10-27 | iterators: avoid overflow in `nth` for `cycle(v, n)` |
| 64312 | merged | 2026-10-27 | iterators: convert unsigned `n` to `Int` in `nth` for arrays |
| 64313 | merged | 2026-10-27 | iterators: end `product` iteration when every factor is done |
| 64314 | merged | 2026-10-27 | iterators: use the stored state in `isdone(::Rest)` |
| 64315 | merged | 2026-10-27 | Markdown: guard `peek` at EOF after `\r` in `github_paragraph` and `hashheader` |
| 64316 | closed | 2026-10-27 | Markdown: fix `EOFError` on an empty `#` header ended by `\r` |
| 64317 | merged | 2026-10-27 | Markdown: render level-6 headers as `\subparagraph` in LaTeX |
| 64318 | open | 2026-10-27 | shell: keep an empty quoted word directly before a redirect |
| 64319 | merged | 2026-10-27 | mpfr: throw `InexactError` from `Rational{BigInt}(NaN)` |
| 64320 | merged | 2026-10-27 | bitarray: fix `circshift!` on empty `BitVector` |
| 64321 | open | 2026-10-27 | c: reject non-method definitions in `@ccallable` without a `FieldError` |
| 64322 | open | 2026-10-27 | shell: reject a redirect with no filename before `\|` |
| 64323 | merged | 2026-10-27 | unicode: return false from `isvalid(Char, x)` for negative integers |
| 64324 | open | 2026-10-27 | Printf: ignore the `0` flag for integer conversions with precision zero |
| 64325 | merged | 2026-10-27 | Random: avoid a zero skip in `randsubseq` when `randexp` returns 0 |
| 64326 | merged | 2026-10-27 | ranges: use `count` for the length in Bool step range indexing |
| 64327 | merged | 2026-10-27 | indices: fix `LinearIndices` range indexing for non-1-based ranges |
| 64328 | merged | 2026-10-27 | regex: write `SubstitutionString` captures to any `IO` in `replace` |
| 64329 | open | 2026-10-27 | cmd: fix `addenv` for variable names starting with a non-ASCII character |
| 64330 | merged | 2026-10-27 | cmd: include CPU affinity in `==` and `hash` for `Cmd` |
| 64331 | open | 2026-10-27 | shell: fix line continuation after non-ASCII text in `shell_parse` |
| 64332 | open | 2026-10-27 | cmd: escape backslashes before a backtick when showing a `Cmd` |
| 64333 | open | 2026-10-27 | cmd: fix `show(::Cmd)` for variable names starting with a non-ASCII character |
| 64334 | merged | 2026-10-27 | cmd: fix `show` for a uid or gid of 2^31 or more |
| 64335 | open | 2026-10-27 | show: treat an escaped backslash as ending the escape in `type_depth_limit` |
| 64336 | merged | 2026-10-27 | cstring: return the requested pointer type from `Ptr{T}(::Cwstring)` |
| 64337 | merged | 2026-10-27 | regex: free PCRE match data when matching throws |
| 64338 | merged | 2026-10-27 | tuple: throw from `split_rest` when the rest is too short |
| 64339 | open | 2026-10-27 | twiceprecision: define `adjoint` for `TwicePrecision` so `x .\ r` works |
| 64340 | merged | 2026-10-27 | iterators: make `isdone(take(itr, 0))` return true |
| 64341 | merged | 2026-10-27 | math: return 0.0 from `exp2(::Int128)` for exponents below -2^64 |
| 64342 | open | 2026-10-27 | bitarray: accept any `Integer` size in `sizehint!(::BitVector, n)` |
| 64343 | merged | 2026-10-27 | reducedim: fix `maximum`/`minimum`/`extrema` with `dims` on all-`missing` arrays |
| 64344 | merged | 2026-10-27 | reducedim: compare region dimensions without converting to `Int` |
| 64345 | open | 2026-10-27 | shell: fix `shell_escape_csh`, `escape_microsoft_c_args` with no args |
| 64346 | open | 2026-10-27 | show: escape backticks when printing command literal expressions |
| 64347 | merged | 2026-10-27 | show: print `.&&` and `.\|\|` expressions as infix operators |
| 64348 | merged | 2026-10-27 | loading: delete the unreachable `manifest_format` dependency branch in `is_v1_format_manifest` |
| 64349 | merged | 2026-10-27 | show: parenthesize a `-0.0` base of `^` when printing `Expr` |
| 64350 | merged | 2026-10-27 | accumulate: throw for nonpositive `dims` in `cumsum` of a vector |
| 64351 | open | 2026-10-27 | annotated_io: keep annotations before the overwritten region in `write(::AnnotatedIOBuffer, ::AnnotatedIOBuffer)` |
| 64352 | open | 2026-10-27 | annotated_io: keep annotations spanning the source position in `write(::AnnotatedIOBuffer, ::AnnotatedIOBuffer)` |
| 64353 | open | 2026-10-27 | annotated: cover every code unit of an `AnnotatedChar` in `annotatedstring` |
| 64354 | open | 2026-10-27 | annotated_io: keep annotations before the write position in `replace` |
| 64355 | open | 2026-10-27 | annotated: return `SubString`-relative regions from `annotations(s, pos)` |
| 64356 | merged | 2026-10-27 | unicode: return `false` from `isassigned` for negative integers |
| 64357 | merged | 2026-10-27 | TOML: allow arrays of dates in `Base.TOML.Parser{nothing}` |
| 64358 | closed | 2026-10-27 | strings: throw `ArgumentError` from `hex2bytes` for non-ASCII characters |
| 64359 | merged | 2026-10-27 | TOML: reject a line-ending backslash in single-line strings |
| 64360 | merged | 2026-10-27 | cstring: throw the NUL-termination error for an empty `Vector{Cwchar_t}` |
| 64361 | merged | 2026-10-27 | TOML: reject `0x`, `0o` and `0b` prefixes not followed by a digit |
| 64362 | merged | 2026-10-27 | version: print the upper bound of a `*-x` `VersionRange` correctly |
| 64363 | merged | 2026-10-27 | tuple: throw `ArgumentError` from `split_rest` for negative `n` |
| 64364 | merged | 2026-10-27 | sort: handle descending ranges in `PartialQuickSort` |
| 64365 | merged | 2026-10-27 | sort: fix `partialsort` for descending index ranges |
| 64366 | merged | 2026-10-27 | sort: use the index type of `v` for the `partialsortperm` permutation |
| 64367 | merged | 2026-10-27 | subarray: return 1 from `stride` past the end of a zero-dimensional view |
| 64368 | merged | 2026-10-27 | array: fix overflow in `deleteat!` range bounds check |
| 64388 | merged | 2026-10-28 | ranges: compute LinRange elements as a + t*(b - a) |
| 64432 | merged | 2026-10-28 | Fix `allunique`/`allequal`, `IdSet` element types, and weak dict bugs |
| 64438 | merged | 2026-10-29 | show: stop treating the `f` in `Inf` as a Float32 exponent in `alignment` |
| 64439 | merged | 2026-10-29 | dict: print `…` in limited `show` only when entries are left out |
| 64442 | open | 2026-10-29 | bitset: ignore duplicates in `symdiff!(::BitSet, itr)` |
| 64450 | merged | 2026-10-29 | ranges: compare lengths in `==` for zero-step `StepRangeLen` |
| 64452 | merged | 2026-10-29 | ranges: allow `reverse` of a `StepRangeLen` with an unsigned step |
| 64455 | merged | 2026-10-29 | Markdown: don't count the blank line ending a list towards `List.loose` |
| 64457 | open | 2026-10-29 | regex, Unicode: fix wrong results and errors on edge-case patterns and strings |
| 64458 | open | 2026-10-29 | file, shell: fix dangling symlink checks and command escaping and parsing edge cases |
| 64459 | open | 2026-10-29 | loading: fix edge cases in environment, depot and artifact path lookup |
| 64460 | open | 2026-10-29 | Sockets: reject malformed IPv6 addresses and accept `BigInt` hosts |
| 64461 | merged | 2026-10-29 | TOML: reject signed dates and illegal additions to existing tables |
| 64462 | open | 2026-10-29 | IO: fix small bugs in Base64 decoding, `crc32c`, `copyline`, `getpass` and `dlopen` |
| 64463 | merged | 2026-10-29 | Markdown, Printf: fix list markers, empty code spans and negative precision |
| 64464 | merged | 2026-10-29 | UUIDs, Random: fix string handling in `uuid5` and `rand` |
| 64465 | open | 2026-10-29 | Base: fix string-handling edge cases in logging, `SubString` and `VersionNumber` |
| 64466 | merged | 2026-10-29 | asyncmap, namedtuple: reject invalid `ntasks` results and non-`Int` integer keys |
| 64482 | merged | 2026-10-30 | tuple: fix `NTuple{N}(A)` throwing for multidimensional arrays of length `N` |
| 64483 | open | 2026-10-30 | sort: fix `sort` and `sort!` throwing on empty arrays with `dims` |
| 64490 | merged | 2026-10-30 | docs: fix docstring signatures of methods with `where` type parameters |
| 64501 | merged | 2026-10-31 | intfuncs: fix `lcm` of a one-element array returning a negative value |
| 64504 | merged | 2026-10-31 | sort: make `insorted` on a range agree with `searchsorted` |
| 64523 | merged | 2026-10-31 | rational: fix directed rounding of a `Rational` to a float type |
| 64528 | merged | 2026-10-31 | arrays: fix 11 functions that assume indices start at 1 |
| 64575 | open | 2026-11-02 | rational: order signed zero in `cmp` between floats and rationals |
| 64598 | open | 2026-11-02 | Dates: keep month and year ranges from passing their stop |
| 64614 | merged | 2026-11-03 | show: space the range `:` when an operand prints with a leading `:` |
| 64615 | merged | 2026-11-03 | show: fix 8 bugs in printing operators and operands in `Expr` |
| 64624 | open | 2026-11-03 | numbers: fix 7 bugs in rounding, integer arithmetic and digit extraction |
| 64693 | merged | 2026-11-05 | iobuffer: fix buffer overflow from a negative `maxsize` |
| 64697 | merged | 2026-11-06 | arrays: fix 2 bugs in appending and iterators |
| 64699 | merged | 2026-11-06 | abstractarray: fix order of operations that leaves `mapslices` output uninitialized |
| 64772 | open | 2026-11-08 | permuteddimsarray: copy in linear order in `copyto!` for differently shaped sources |
| 64773 | merged | 2026-11-08 | indices: promote `CartesianIndices` and `LinearIndices` with mixed axis types |
| 64775 | open | 2026-11-08 | strings: print chars above U+10FFFF as `\x` bytes in `show` and `escape_string` |
| 64791 | merged | 2026-11-08 | lock: mark a `OncePerThread` slot as failed when its result cannot be converted |
| 64798 | open | 2026-11-09 | ranges: make `in` and `searchsortedfirst`/`searchsortedlast` agree with indexing for `LinRange` |

## Issue comments (verbatim, newest issue first)

### #64790 oscardssmith 2026-11-09
This doesn't seem surprising (or like a bug. allocation removal is an optimization that may or may not happen depending on optimization levels.

### #64790 MilesCranmer 2026-11-09
Ah wait I think my bot didn't describe this one that well. I've looked at it and do think it's a symptom of a compiler bug though. Let me have them respond

### #64790 MilesCranmerBot 2026-11-09
The allocation isn't unused here. `box` is live across `GC.gc`, and its `child` field is the only reference to the child. Reading the child back through the copied pointer segfaults at the default optimization level and works with `-O0`:

```julia
mutable struct Child
    token::UInt
end

mutable struct Box
    child::Any
end

@noinline function dangling()
    src = Libc.malloc(8); dst = Libc.malloc(8)
    child = Child(0x1234)
    unsafe_store!(Ptr{Any}(src), child)
    box = GC.@preserve child unsafe_load(Ptr{Box}(src))
    child = nothing
    GC.gc(true)
    unsafe_store!(Ptr{Box}(dst), box)
    junk = [Child(rand(UInt)) for _ in 1:100_000]
    t = unsafe_load(Ptr{Any}(dst)).token
    Libc.free(src); Libc.free(dst)
    return t
end

dangling()  # signal 11 on 1.13.3 and 1.15.0-DEV.307; returns 0x1234 with -O0
```

AllocOpt normally keeps reference fields rooted when it moves an allocation to the stack. With `has_ref` set, it uses a `T_prjlvalue` buffer, or keeps the heap allocation when the address escapes ([`src/llvm-alloc-opt.cpp:318`](https://github.com/JuliaLang/julia/blob/9b885af41eeb3dbb220d6bbadfe7d3158acb98ca/src/llvm-alloc-opt.cpp#L318)). Here `has_ref` is never set. `emit_pointerref` fills the new object with `llvm.memcpy`, and [`src/llvm-alloc-helpers.cpp:217-238`](https://github.com/JuliaLang/julia/blob/9b885af41eeb3dbb220d6bbadfe7d3158acb98ca/src/llvm-alloc-helpers.cpp#L217-L238) treats that memcpy as an unknown intrinsic that only sets `addrescaped` (next to a `TODO handle memcpy`). So the object becomes an untracked integer alloca, which is why the optimized IR carries the child pointer across the collection as a plain `i64`. Could you reopen?


### #64779 ShadowTheLegendary 2026-11-08
In my (uninformed) opinion, increasing the width of ``alignment`` seems like it's only really a band-aid fix because then you would run into the issue again at larger sizes.

### #64779 MilesCranmerBot 2026-11-08
Agreed that widening alone only moves the limit. Either way, an alignment that does not fit should throw an error instead of wrapping to 0.

Correction: this did not start with #57722. The alignment is also 0 on 1.10.8 and 1.11.4, which predate it. On 1.10 the reproducer segfaults, and on 1.11 `copy` happens to work; the silent results start in 1.12. I've updated the description.


### #64779 ShadowTheLegendary 2026-11-08
Looking at ``jl_get_layout``:

```
static jl_datatype_layout_t *jl_get_layout(..., uint32_t alignment, ..) {
    assert(alignment); // should have been verified by caller
    ...
    flddesc->alignment = alignment;
    ...
}
```

Why does it take a uint32_t when in the struct it's stored as a uint16_t?

And in ``jl_compute_field_offsets`` ``alignm``, which is eventually passed to ``jl_get_layout`` is a size_t. I'm not really an expert but it seems a little strange that each variable gets narrower and narrower.

I'm mostly a rust programmer and don't know that much about c, but I think a simple solution might be to  replace the ``jl_get_layout`` alignment argument with a uint16_t and in ``jl_compute_field_offsets`` do some kind of checked cast from size_t to uint16_t right before the call to ``jl_get_layout``.

### #64767 Keno 2026-11-07
The absence of the hasfield method is deliberate and was wrong on 1.13. `sizeof` should probably throw.

### #64767 MilesCranmerBot 2026-11-08
Thanks, that makes sense. I've retitled the issue to cover only `sizeof`.


### #64524 MilesCranmer 2026-10-31
I wasn't actually sure if this was a bug or not, so someone else can  say

### #64440 MilesCranmerBot 2026-10-31
`fldmod` shows a related inconsistency even for same-width types: its remainder disagrees with `mod`, although the docstring says `fldmod(x, y)` is equivalent to `(fld(x, y), mod(x, y))`:

```julia-repl
julia> fldmod(0x01, Int8(-2))
(0xff, 0xff)

julia> mod(0x01, Int8(-2))
-1
```

`fldmod` calls `divrem(x, y, RoundDown)`, which computes `x - fld(x, y)*y` in unsigned arithmetic ([`base/div.jl#L297-L300`](https://github.com/JuliaLang/julia/blob/64fbe8941e/base/div.jl#L297-L300)), while `mod` has returned a signed result since #57853.


### #64272 timholy 2026-10-27
This is not a critique of the report per se, but it adds important context for any contemplated fixes. Cross-posted from [discourse](https://discourse.julialang.org/t/formalizing-julia-in-lean-and-finding-400-bugs-in-base/140243/17?u=tim.holy):

----

FWIW `LinRange`'s contract is not to aim for floating-point exactness, it's to support "discrete segments" in abstract spaces, e.g.,

```julia
julia> v1, v2 = randn(3), randn(3)
([2.093487445396677, 1.9716034523694344, -0.7075986181423533], [-0.7049273213892698, 1.108660285173183, 0.7804466703146531])

julia> r = LinRange(v1, v2, 5)
5-element LinRange{Vector{Float64}, Int64}:
 [2.09349, 1.9716, -0.707599], [1.39388, 1.75587, -0.335587], [0.69428, 1.54013, 0.036424], [-0.00532363, 1.3244, 0.408435], [-0.704927, 1.10866, 0.780447]
```

Meaning that what matters is the the set of required computational operations, not floating-point exactness, and anything that "fixes" the latter at the expense of the former is a step backwards.

Floating-point exactness is the domain of `StepRangeLen`.

### #64272 MilesCranmerBot 2026-10-27
Turns out this is a simple fix by just tweaking the `lerpi` function from

```julia
function lerpi(j::Integer, d::Integer, a::T, b::T) where T
    t = j/d # ∈ [0,1]
    # compute approximately fma(t, b, -fma(t, a, a))
    return T((1-t)*a + t*b)
end
```

to

```julia
function lerpi(j::Integer, d::Integer, a::T, b::T) where T<:AbstractFloat
    return ifelse(j == d, b, T(a + j*((b - a)/d)))
end
```

Which is faster to compute too!

### #64272 MilesCranmer 2026-10-28
Hi @timholy,

I am not sure I understand the concern, perhaps you were worried the fix would be slow due to needing greater accuracy to fix this? Actually we can fix the non-monotonicity by simply avoiding an extra float rounding - see #64388.

This also fixes some other edgecases like:

```julia
julia> collect(LinRange(-90:60:90))
ERROR: InexactError: Int64(-30.000000000000007)
Stacktrace:
 [1] Int64
   @ ./float.jl:923 [inlined]
 [2] lerpi
   @ ./range.jl:977 [inlined]
```

and other wiggly linear ranges like

```julia
julia> collect(LinRange(0.9, nextfloat(0.9), 10))
10-element Vector{Float64}:
 0.9
 0.8999999999999999
 0.9000000000000001
 0.9000000000000001
 0.9
 0.9000000000000001
 0.9000000000000001
 0.9
 0.9000000000000001
 0.9000000000000001
```

With #64388, both of these now work without losing any speed.

It maintains generic compatibility with vectors and other types too.

### #64272 timholy 2026-10-28
My concern was not about the report or the PR. It's about the theoretical risk that an agent who may not understand the intent of a function making changes to "fix" them that break their purpose. I wanted to explain the purpose. That's all.

### #64265 MilesCranmer 2026-10-26
Actually this one doesn't seem like a bug: #41769. It's just a docstring that needs updating. Still a bit awkward though.

### #64238 ahmadmuhamadi 2026-10-26
Hello everyone i would like to work on that issue 

### #64225 inkydragon 2026-10-26
Do we want to guarantee semi-monotonicity for Julia’s math functions, as Java does?

Java’s Math documentation states:

> most methods with more than 0.5 ulp errors are required to be semi-monotonic
> https://docs.oracle.com/en/java/javase/26/docs/api/java.base/java/lang/Math.html

CoreMath.jl provides an alternative when this guarantee is needed:
correct rounding implies semi-monotonicity under a fixed rounding mode.

---

Property-based testing can find more cases like this. Using Supposition.jl to check adjacent floating-point inputs, I also found local decreases in exp(::Float32), and exp2(::Float32) on Julia 1.13.2:

```jl
julia> x = -0.23126602f0;

julia> exp(x), exp(nextfloat(x))
(0.7935284f0, 0.7935283f0)

julia> x < nextfloat(x)
true

julia> exp(x) <= exp(nextfloat(x))
false


julia> x = -0.4921441f0;

julia> exp2(x), exp2(nextfloat(x))
(0.7109677f0, 0.71096766f0)

julia> x < nextfloat(x)
true

julia> exp2(x) <= exp2(nextfloat(x))
false
```


### #64225 oscardssmith 2026-10-26
oh that's probably worth guaranteeing.

### #64218 adienes 2026-10-25
is this really a bug? "not writable" I could read in an abstract sense like whether or not the stream is read-only. seems like this is the whole point of having `isopen` be a separate function

### #64218 MilesCranmerBot 2026-10-25
I think it is, based on how Base treats the same question elsewhere.

- The generic implementation is [`iswritable(io::IO) = isopen(io)`](https://github.com/JuliaLang/julia/blob/45b6d15e34bbd2003a31acce0b1847b63dad029c/base/io.jl#L179-L199).
- Both [`LibuvStream`](https://github.com/JuliaLang/julia/blob/45b6d15e34bbd2003a31acce0b1847b63dad029c/base/stream.jl#L272-L276) and [`BufferStream`](https://github.com/JuliaLang/julia/blob/45b6d15e34bbd2003a31acce0b1847b63dad029c/base/stream.jl#L1570-L1571) require the stream to be open.
- The pipe tests expect a closed stream to be [non-writable](https://github.com/JuliaLang/julia/blob/45b6d15e34bbd2003a31acce0b1847b63dad029c/test/spawn.jl#L443-L447).
- The `IOStream` write methods already use `iswritable` as their [error guard](https://github.com/JuliaLang/julia/blob/45b6d15e34bbd2003a31acce0b1847b63dad029c/base/iostream.jl#L401-L408), while the [`IOStream` specialization](https://github.com/JuliaLang/julia/blob/45b6d15e34bbd2003a31acce0b1847b63dad029c/base/iostream.jl#L104-L106) only checks the original access mode.

So `IOStream` appears to be the outlier here.


### #64218 adienes 2026-10-25
sounds good, you've convinced me

### #64216 vtjnash 2026-10-27
Not really a bug, since it's not guaranteed that `@fastmath` gives the same answers, though would probably be an easy feature to add for `hypot` to address this

### #64216 MilesCranmerBot 2026-10-27
I think this is a bug, though the relevant distinction is call validity rather than numerical equivalence.

`@fastmath` documents relaxed IEEE semantics and potentially different numerical results. Here, however, the macro rewrites every `hypot` call to `hypot_fast`, while `hypot_fast` only implements the binary form. Unary and variadic calls therefore fail during dispatch, before any arithmetic occurs.

Similar arity mismatches have been fixed previously:

- #25027 reported the same `MethodError` for two-argument `log` and was fixed by #25674.
- #54513 added variadic fast methods for `+`, `*`, `min`, and `max`.

The mismatch for `hypot` predates #54513: binary `hypot_fast` was added in 2015, while variadic `hypot` was added in 2016 without a corresponding fast method.

Adding unary and variadic `hypot_fast` methods, or falling back to ordinary `hypot` for unsupported argument counts, would avoid the exception without requiring numerical equivalence.


### #64201 AliAshraf69420 2026-10-26
Hello, I'm interested in working on this 

### #64194 adienes 2026-10-25
I'm not sure how this could be fixed without making Julia borrow-checked or something. there are an enormous number of pathologies one could generate when you start playing with two different variables aliasing the same memory buffer. I'd be inclined to call this "not planned"

### #64194 MilesCranmer 2026-10-25
Idk. I guess I would agree that arbitrary array aliasing would need borrow checking to be made safe. But.... on the other hand, `String` _specifically_ promises immutability, right? And `String(v)` is not an unsafe API. If the zero-copy path cannot preserve immutability when the storage has aliases, maybe the safe conversion should just copy instead, and leave ownership-transfer optimizations to an explicitly unsafe API?


### #64194 MilesCranmer 2026-10-25
Right now the docstring says this:

```
  String(v::AbstractVector{UInt8})

  Create a new String object using the data buffer from byte vector v. If v is a Vector{UInt8} it
  will be truncated to zero length and future modification of v cannot affect the contents of the
  resulting string. To avoid truncation of Vector{UInt8} data, use String(copy(v)); for other
  AbstractVector types, String(v) already makes a copy.

  When possible, the memory of v will be used without copying when the String object is created. This
  is guaranteed to be the case for byte vectors returned by take! on a writable IOBuffer and by calls
  to read(io, nb). This allows zero-copy conversion of I/O data to strings. In other cases,
  Vector{UInt8} data may be copied, but v is truncated anyway to guarantee consistent behavior.
```

So at minimum this docstring should be modified to not claim "future modification of v cannot affect the contents of the resulting string"

### #64194 adienes 2026-10-25
> maybe the safe conversion should just copy instead

I agree that `String(v)` should not have been designed the way that it is, but I think it would be pretty breaking to change now. I could be missing a more clever solution, but I only see three ways forward which are

* make `String(v)` always copy (breaking)
* add a borrow checking to Julia (sounds difficult)
* clarify the documentation that modifying `v` is safe, but modifying memory that aliased what `v` used to be is not.

### #64194 MilesCranmer 2026-10-25
> make `String(v)` always copy (breaking)

Why would this be breaking, just so I understand? 

> borrow checking

Tangential but check out https://github.com/MilesCranmer/BorrowChecker.jl. It's nowhere near complete but it's a cool experiment. (However one thing I'm realising was wrong is that I treat Strings as immutable and safe to share..)

### #64194 adienes 2026-10-25
I think the breaking-ness is discussed in https://github.com/JuliaLang/julia/issues/32528 . technically I guess you could argue that if it copies it's "just" a performance regression, as long as the constructor still works. but going from 0 allocations to `O(length)` allocations is qualitatively a big difference imo

### #64194 MilesCranmer 2026-10-25
From that thread I kinda dig the proposal of introducing a preferred symbol `String!(::Array)`, and maybe even doing a soft deprecation of `String(::Array)` (but having it point at `String!` so there is no behavior change)

With AI enabling mass production of code, I feel like this is a good time for the Julia community to give correctness more weight relative to speed.


### #64183 adienes 2026-10-25
regression from [55601](https://github.com/JuliaLang/julia/pull/55601)

### #64155 vtjnash 2026-10-25
Can you make simple fixes like this a PR instead of an issue?

### #64154 vtjnash 2026-10-25
They are meant to be defined for `Union{Int,Symbol}`

### #64153 adienes 2026-10-25
also ref: https://github.com/JuliaLang/julia/issues/61893

### #64151 vtjnash 2026-10-25
These iterator ones would also be good candidates for one-liner fixes being easier as PRs than issues, since there's no question about what is wrong and how to fix it

### #64149 MilesCranmer 2026-10-25
Btw it seems @Keno actually identified the same issue here https://github.com/JuliaLang/julia/pull/62274#issuecomment-4933664938 but I can't see whether any follow-up PR to fix it was made or not

### #64149 vtjnash 2026-10-27
I don't think it seen a fix (nor was https://github.com/JuliaLang/julia/pull/62162 itself a complete fix for that bug either: https://github.com/JuliaLang/julia/pull/62162#discussion_r4050097168)

### #64142 MilesCranmer 2026-10-24
Pretty weird; it reproduces for all cases except the sigdigits=6 used for printing:

```julia
julia> floatmax(Float64)
1.7976931348623157e308

julia> round(floatmax(Float64); sigdigits=1)
0.0

julia> round(floatmax(Float64); sigdigits=2)
0.0

julia> round(floatmax(Float64); sigdigits=3)
0.0

julia> round(floatmax(Float64); sigdigits=5)
0.0

julia> round(floatmax(Float64); sigdigits=6)
1.79769e308
```

### #64141 r0nik123 2026-10-30
Hi @vtjnash, I'd like to work on updating the `gcdx` docstring to relax/clarify the bounds for equal inputs. 
Could you please assign this issue to me?

