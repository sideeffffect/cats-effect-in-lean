# python-formalization launch: LAUNCH.md, Discourse post, filed.tsv, drafts INDEX.md (verbatim)

> Source: https://github.com/Broyojo/python-formalization/blob/main/reports/LAUNCH.md
> Collected: 2026-11-10
> Published: 2026-11-09

## reports/LAUNCH.md

````
# Launch, 2026-11-09

- Repo made public, GitHub Pages on: https://broyojo.com/python-formalization/
- Homepage entry: https://broyojo.com/ (select projects)
- Issues filed on python/cpython (reports/filed.tsv): gh-161688, gh-161689, gh-161690, gh-161691, gh-161692, gh-161693
- gh-161690: sergey-miryanov offered to open the PR; we replied asking him to go ahead and offered to test the fix
- Discourse (Core Development): https://discuss.python.org/t/formalizing-cpython-in-lean-findings-from-a-machine-checked-model-and-how-youd-like-them/109978
- X thread: https://x.com/broyojo42/status/2119846041214206286

Held for later rounds: the 34 drafts marked `[~]` in reports/drafts/INDEX.md, pending maintainer feedback on Discourse.
````

## reports/discourse_post.md

````
<!-- Draft for discuss.python.org, category: Core Development. Post from your own account.
     Posted 2026-11-09: https://discuss.python.org/t/formalizing-cpython-in-lean-findings-from-a-machine-checked-model-and-how-youd-like-them/109978
     New accounts may post at most 2 links, so the issues are plain gh-NNNNNN references. -->

**Title:** Formalizing CPython in Lean: findings from a machine-checked model, and how you'd like them

Hi all,

Since late October I've been building a model of CPython 3.15.2 in Lean 4, a proof assistant. AI agents did most of the work (Claude Opus 5.5, with GPT-6.1 Sol in Codex helping in the final review of the reports), and I directed it and reviewed the results. Each model copies a C or Python function line by line and is tested against the real interpreter on at least 50,000 generated inputs. Only then do we prove properties about it. A second agent reviews every function, and only functions that pass review count. So far that's 4,071 functions, with 3,834 proved properties and 588 refuted ones.

When a refuted property turns out to be CPython's fault rather than the model's, we write it up with a plain Python reproducer. That has produced 418 reports that reproduce on 3.15.2. Most are small: C and pure-Python versions that disagree, wrong exception types, edge cases. About 55 are crashes or memory errors reachable from Python code, usually a callback that changes an object while C code is still using it.

I know the tracker was flooded with automated reports in October, and I don't want to repeat that. So today I've filed only six crash reports, each of which I've read and checked myself, and each reproduced on 3.15.2 and main:

- gh-161688: `bytearray.strip()` reads freed memory if the argument's `__release_buffer__` resizes the bytearray
- gh-161689: ElementTree slice assignment with start greater than stop duplicates a child without owning its second reference
- gh-161690: `dict.fromkeys()` GC-tracks a non-GC object returned by a subclass constructor (3.15 regression)
- gh-161691: memoryview: a view released by `__buffer__` or `__index__` in the middle of `==` or item assignment is still used
- gh-161692: `functools.partial`: changing `p.keywords` during the call's keyword merge overflows a stack buffer (new in 3.15)
- gh-161693: `dict.setdefault()` segfaults on an instance dict with an absent shared key passed as a str subclass

The rest are in the repository with reproducers, causes with line numbers, and a duplicate search; findings that duplicate existing issues link the existing issue instead of being refiled. How would you prefer to receive them, if at all: a few at a time, grouped by module for the relevant experts, or left in the repo for anyone to pick up? I can also send PRs for the ones with small, obvious fixes.

Everything is public:
- Write-up: https://broyojo.com/python-formalization/
- Code, models and all bug records: https://github.com/Broyojo/python-formalization

The project is open to contributors too: most of CPython is still unmodelled.

Thanks for reading, and for all your work on CPython.

David
````

## reports/filed.tsv

````
draft	title	url
single/bytearray-strip-release.md	bytearray.strip() reads freed memory if the argument's __release_buffer__ resizes the bytearray	https://github.com/python/cpython/issues/161688
single/etree-backward-slice.md	ElementTree slice assignment with start greater than stop duplicates a child without owning its second reference	https://github.com/python/cpython/issues/161689
single/fromkeys-gc-track.md	dict.fromkeys() GC-tracks a non-GC object returned by a subclass constructor (3.15 regression)	https://github.com/python/cpython/issues/161690
single/memoryview-released.md	memoryview: a view released by __buffer__ or __index__ in the middle of == or item assignment is still used	https://github.com/python/cpython/issues/161691
single/partial-vectorcall-kw.md	functools.partial: changing p.keywords during the call's keyword merge overflows a stack buffer (new in 3.15)	https://github.com/python/cpython/issues/161692
single/setdefault-split-null.md	dict.setdefault() segfaults on an instance dict with an absent shared key passed as a str subclass	https://github.com/python/cpython/issues/161693
````

## reports/drafts/INDEX.md

````
# Draft issues for python/cpython

Checked boxes record Codex's technical approval in the [prelaunch review](../prelaunch_review.md): **41 approved drafts (22 single, 19 grouped)**. The person filing must still read and be able to explain each draft, as required by this checklist. `python3 reports/file_issues.py` files only ticked drafts; no filing was performed during review.

Launch plan (2026-11-09): only the six `[x]` drafts are filed at launch. `[~]` marks a draft that passed technical review but is held for later rounds, after maintainers have seen the first batch (after the October bulk-filing closures, gh-158748 and gh-158786). Change `[~]` to `[x]` to file it in a later round.

## Single issues

- [ ]  [array('e'): append() or insert() of an out-of-range float raises OverflowError but still grows the array (new in 3.15)](single/array-e-overflow.md)
- [ ] P2 [array.fromlist() regrows a callback-cleared array on its error path, exposing uninitialized items](single/array-fromlist-restore.md)
- [ ] P1 [array.append/insert/extend use a size saved before item conversion, exposing uninitialized items after a callback clears the array](single/array-ins1-stale-size.md)
- [~] P2 [compile() segfaults on a small hand-built AST with None in Try.handlers](single/ast-none-list.md)
- [ ] P2 [BufferedReader.read() crashes if the raw stream's closed property detaches the reader](single/buffered-detach.md)
- [~] P1 [Reentrant BufferedReader/Writer initialization frees active storage or leaves an invalid buffer size](single/buffered-reinit-free.md)
- [ ] P1 [A reentrant BufferedReader/Writer.__init__(raw, 0) leaves a zero buffer size: division by zero or an endless write loop](single/buffered-reinit-size0.md)
- [x] P1 [bytearray.strip() reads freed memory if the argument's __release_buffer__ resizes the bytearray](single/bytearray-strip-release.md)
- [~] P2 [Reentrant __class__ assignment from a __slots__ name comparison decrefs the old class twice and crashes](single/class-assignment-slot-eq.md)
- [~] P2 [datetime == reads None as a timedelta when utcoffset() is None for only one fold](single/datetime-pep495-none.md)
- [~] P2 [except* crashes when an ExceptionGroup subclass's split() returns a non-exception](single/eg-match-split.md)
- [~] P2 [email: UnboundLocalError when a Message-ID's [domain literal] starts with a space](single/email-msgid-space.md)
- [x] P1 [ElementTree slice assignment with start greater than stop duplicates a child without owning its second reference](single/etree-backward-slice.md)
- [~] P2 [AttributeError and ImportError copy a borrowed instance dict during __reduce__, allowing it to be freed by a key comparison](single/exception-getstate-dict.md)
- [~] P2 [Setting frame.f_lineno can approve a jump to an incompatible stack and crash (three cases)](single/flineno-jumps.md)
- [~] P2 [frozendict.fromkeys() can expose an untracked frozendict and later mutate it after hashing](single/fromkeys-frozendict.md)
- [x] P1 [dict.fromkeys() GC-tracks a non-GC object returned by a subclass constructor (3.15 regression)](single/fromkeys-gc-track.md)
- [~] P2 [Closing a long chain of yield-from generators overflows the C stack](single/gen-close-chain.md)
- [~] P2 [x *= [1] raises TypeError for an int subclass, although x * [1] works](single/inplace-mul.md)
- [~] P2 [Use-after-free when a __kwdefaults__ key's __eq__ replaces __kwdefaults__ during a call](single/kwdefaults-uaf.md)
- [~] P2 [lru_cache: a cache hit from __eq__ during eviction corrupts the C cache's list, and the next gc.collect() hangs](single/lru-cache-cycle.md)
- [x] P1 [memoryview: a view released by __buffer__ or __index__ in the middle of == or item assignment is still used](single/memoryview-released.md)
- [ ] P1 [operator.methodcaller.__reduce__() exposes its private kwargs through partial.keywords, causing stale calls and a repr crash](single/methodcaller-shared-kwargs.md)
- [~] P2 [MRO conflict formatting reads a freed base MRO if metaclass __hash__ changes __bases__](single/mro-error-borrowed-tuples.md)
- [~] P1 [functools.partial.__setstate__ with a tuple subclass as args miscounts placeholders, then crashes when called](single/partial-setstate.md)
- [x] P1 [functools.partial: changing p.keywords during the call's keyword merge overflows a stack buffer (new in 3.15)](single/partial-vectorcall-kw.md)
- [x] P1 [dict.setdefault() segfaults on an instance dict with an absent shared key passed as a str subclass](single/setdefault-split-null.md)
- [ ] P2 [Reinitializing an active Struct lets iter_unpack read past its buffer or divide by zero](single/struct-reinit.md)
- [ ] P2 [Writable struct-sequence size attributes cause out-of-bounds access in copy.replace, __reduce__ and construction](single/structseq-size-attributes.md)
- [ ] P2 [Binding an uninitialized super object segfaults in supercheck](single/super-uninitialized.md)
- [~] P1 [ZoneInfo.clear_cache() crashes if a cache key's __del__ creates a ZoneInfo](single/zoneinfo-clear-cache.md)

## Still to write (0)

Each has a full record with a reproducer and the cause. Write the body as reports/issue_text/<name>.md (copy the three header lines of an existing one), then run this script again.


## Grouped issues (at most 8 findings each)

- [~] [Small inconsistencies in functools, enum, random and other core library modules found by a formal model (part 1 of 2)](group/corelibs-1.md)
- [~] [Small inconsistencies in functools, enum, random and other core library modules found by a formal model (part 2 of 2)](group/corelibs-2.md)
- [~] [Small inconsistencies in text and binary codecs found by a formal model (part 1 of 2)](group/textlibs-1.md)
- [~] [Small inconsistencies in text and binary codecs found by a formal model (part 2 of 2)](group/textlibs-2.md)
- [~] [Small inconsistencies in io and _pyio found by a formal model](group/pyio-1.md)
- [~] [Small inconsistencies in datetime found by a formal model](group/datetime-1.md)
- [~] [Small inconsistencies in type objects found by a formal model](group/typeobj-1.md)
- [~] [Small inconsistencies in bytes, bytearray and memoryview found by a formal model](group/bytesobj-1.md)
- [~] [Small inconsistencies in json found by a formal model](group/json-1.md)
- [~] [Small inconsistencies in array and collections found by a formal model](group/sequences-1.md)
- [~] [Small inconsistencies in decimal found by a formal model](group/decimal-1.md)
- [~] [Small inconsistencies in ipaddress found by a formal model](group/ipaddress-1.md)
- [~] [Small inconsistencies in the bytecode interpreter found by a formal model](group/bytecode-1.md)
- [~] [Small inconsistencies in the parser and grammar found by a formal model](group/pygrammar-1.md)
- [ ] [statistics._sqrtprod loses accuracy when x*y is subnormal, so correlation() of exactly linear data is far from 1](group/calstat-1.md)
- [ ] [After dict.popitem(od), od.popitem() and od.pop(k) segfault, and iterating od never ends](group/dictset-1.md)
- [~] [itertools.islice with stop=None yields an extra item when start + step overflows Py_ssize_t](group/itertools-1.md)
- [~] [str(int) can return more digits than sys.set_int_max_str_digits allows when the limit is 9000 or more](group/longobj-1.md)
- [~] [cmath.log(0, base) returns (-inf+nanj) instead of raising ValueError: the second c_log() call clears errno](group/mathint-1.md)
- [~] [PySlice_GetIndices() returns 0 (success) with OverflowError set when a slice index does not fit in Py_ssize_t](group/rangeslice-1.md)

## Held drafts (10)

| Draft | Reason |
|---|---|
| [single/array-e-overflow.md](single/array-e-overflow.md) | Confirmed duplicate of open gh-158345, which explicitly includes 3.15 e arrays; read-only GitHub check recorded in the YAML. |
| [single/array-fromlist-restore.md](single/array-fromlist-restore.md) | Reproduces; related to gh-152166 / PR gh-152167. Decide whether to add this error path to that report after reviewing its current patch. |
| [single/array-ins1-stale-size.md](single/array-ins1-stale-size.md) | Reproduces; gh-158345 / PR gh-158348 concerns the same helper and its proposed restructuring may cover this path. Needs related-report triage. |
| [single/buffered-detach.md](single/buffered-detach.md) | Reproduces; record explicitly marks it a duplicate of gh-154997. |
| [single/buffered-reinit-size0.md](single/buffered-reinit-size0.md) | Reproduces; both its reproducer and record link are now included in the approved buffered-reinit-free.md. Do not file twice. |
| [single/methodcaller-shared-kwargs.md](single/methodcaller-shared-kwargs.md) | Reproduces; record recommends coordinating with gh-155733 / PR gh-155779. Decide follow-up versus a new report after reviewing that patch. |
| [single/struct-reinit.md](single/struct-reinit.md) | Reproduces; overlaps the closed gh-158695 report and bugforge records. Needs related-report triage before a new filing. |
| [single/structseq-size-attributes.md](single/structseq-size-attributes.md) | Reproduces; same mutable-metadata cause as gh-155322 / PR gh-155361. Decide how to add the extra paths to that report. |
| [single/super-uninitialized.md](single/super-uninitialized.md) | Reproduces; confirmed duplicate in the record of gh-155376 / PR gh-155379. |
| [group/calstat-1.md](group/calstat-1.md) | Already filed as gh-161259 (3 November test run) and fixed on main by gh-161260. |
| [group/dictset-1.md](group/dictset-1.md) | Reproduces; its only finding bypasses OrderedDict with dict methods. The record acknowledges known desynchronization and the earlier gh-68914 closure; the expected supported behavior is insufficiently established for launch. |

## Previously waiting on main (37)

The saved `cb-main.log` confirms **27** and reports **10 not reproduced**. All 37 remain outside the launch checklist; confirmation alone does not approve a new draft. The per-record results are in the [review](../prelaunch_review.md#previously-waiting-on-main).

Do not file the 10 non-reproducing records: `bytecode-anext-default-restarts-await`, `bytecode-gen-athrow-awaitable-reusable`, `bytecode-posonly-keyword-borrowed-qualname`, `datetime-time-subminute-offset`, `longobj-complex-pow-infinite-base-overflow`, `longobj-complex-pow-infinite-phase-edom`, `pyio-bytesio-write-near-maxsize-systemerror`, `pyio-stringio-truncate-index-close-crash`, `sequences-array-float-narrowing`, `textlibs-csv-sniffer-unusable-dialect`.

## Not filed at launch (228 minor or possibly intended findings)

P4/P5 findings, and ones whose record says they are probably intended, stay in bugs/ and are offered in the Discourse post. Duplicates of existing issues and 3.14-only behaviour are not filed either; see reports/triage.tsv.
````

