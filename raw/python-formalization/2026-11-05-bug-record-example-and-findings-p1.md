# python-formalization example bug record and triage format (verbatim)

> Source: https://github.com/Broyojo/python-formalization/blob/main/bugs/bytesobj-bytearray-strip-release-uaf.yaml
> Collected: 2026-11-10
> Published: 2026-11-05

## bugs/bytesobj-bytearray-strip-release-uaf.yaml

````yaml
id: bytesobj-bytearray-strip-release-uaf
title: "bytearray.strip/lstrip/rstrip copy from self after the argument's __release_buffer__ ran: use after free"
priority: P1
kind: memory-safety
module: bytesobj
files: [Objects/bytearrayobject.c]
functions: ["bytearray_strip_impl_helper", "bytearray_strip_impl", "bytearray_lstrip_impl", "bytearray_rstrip_impl"]
summary: |
  bytearray_strip_impl_helper takes the argument's buffer (:2440), reads `myptr = PyByteArray_AS_STRING(self)`
  and `mysize` (:2445-2446), finds `left` and `right`, then calls PyBuffer_Release(&vbytes) (:2460-2461) and
  only then copies `right - left` bytes from `myptr + left` (:2462). For an argument whose class defines
  __release_buffer__ (PEP 688) the release runs Python code while `self` is not exported, so it can resize
  `self`: `self.clear()` frees the storage `myptr` points into, and the copy reads freed memory. With a large
  bytearray the process dies with SIGSEGV. Without a resize, an in-place write in __release_buffer__ changes
  the bytes that are copied after the bounds were computed, so the result is not stripped:
  `bytearray(b" a ").strip(B())` gives `bytearray(b" ")`.
  The other methods of this file that take a buffer of their argument either raise ob_exports first
  (find, split, join, hex, %) or release only after the copy (translate, setslice, +=, +, comparison).
  Lean: StripCopiesScanned (the copy reads the bytes the loops scanned) is refuted on `b" a "` with an
  in-place write in __release_buffer__ (strip_rewritten), and strip_freed shows the read of freed storage
  for `self.clear()`. StripNoRelAgrees, for arguments whose release runs no Python code, is proven: the
  result is then the strip of the contents as __buffer__ left them.
likelihood: |
  Low: it needs an argument class with __release_buffer__ that mutates the bytearray being stripped. It is
  reachable from pure Python since PEP 688 (3.12) and gives an out-of-bounds read of freed heap memory.
maybe_intended: |
  No. The same file raises ob_exports around every other callback that could resize self (gh-142560,
  gh-142557, gh-143195), and the copy does not need the argument's buffer, which is released too early.
reproducer: |
  import subprocess, sys
  crash = '''
  ba = bytearray(b"x" * (1 << 22))
  class S:
      def __buffer__(self, flags):
          return memoryview(b" ")
      def __release_buffer__(self, view):
          ba.clear()
  ba.strip(S())
  '''
  codes = []
  for m in ("strip", "lstrip", "rstrip"):
      r = subprocess.run([sys.executable, "-I", "-c", crash.replace(".strip(", "." + m + "(")],
                         capture_output=True, text=True)
      codes.append(r.returncode)
  print("clear() in __release_buffer__: exit status", codes)
  s = bytearray(b" a ")
  class B:
      def __buffer__(self, flags):
          return memoryview(b" ")
      def __release_buffer__(self, view):
          s[1] = 0x20
  r = s.strip(B())
  print("in-place write in __release_buffer__:", r)
  if r == bytearray(b" ") or any(c < 0 for c in codes):
      print("REPRODUCED bytesobj-bytearray-strip-release-uaf")
expected: |
  The bytes are copied before the argument's buffer is released (or ob_exports is raised around the
  helper), so `b" a ".strip(B())` is `bytearray(b"a")` and nothing reads freed memory.
observed: |
  python3 3.15.2: exit status [-11, -11, -11] (SIGSEGV for strip, lstrip and rstrip), and the in-place
  case gives bytearray(b' '). REPRODUCED.
  main (python.exe 3.16.0a1+dev heads/main:ef1fce0): the same. REPRODUCED.
promised_by: |
  Invariant: no read of freed memory from pure Python. Doc/library/stdtypes.rst bytearray.strip: the
  result has the leading and trailing bytes of the set removed.
cause: |
  Objects/bytearrayobject.c:2460-2462: PyBuffer_Release(&vbytes), which can run __release_buffer__, comes
  before PyByteArray_FromStringAndSize(myptr + left, right - left), which reads through the pointer taken
  at :2445.
possible_fix: |
  Create the result before releasing the argument's buffer (swap :2460-2461 and :2462), or raise
  self->ob_exports around the helper as bytearray_split_impl does.
duplicates:
  issues: []
  related:
    - {number: 143195, state: closed, relation: "same class of bug in bytearray.hex (sep.__len__), fixed by raising ob_exports"}
    - {number: 142560, state: closed, relation: "re-entrant __index__ in bytearray search methods, fixed by _bytearray_with_buffer"}
  queries: ["bytearray strip __release_buffer__", "bytearray strip use-after-free", "bytearray release_buffer",
    "bytearray strip crash", "bytearray lstrip", "bytearray rstrip", "__release_buffer__ use after free",
    "bytearray __buffer__ use-after-free", "bytearray re-entrant buffer", "bytearray use after free",
    "bytearray UAF", "bytearray segfault", "bytearray strip buffer", "strip __buffer__",
    "bytearray_strip_impl_helper", "lstrip use-after-free", "strip use-after-free", "bytearray strip reentrant",
    "release_buffer bytearray clear", "PyBuffer_Release bytearray", "use-after-free bytearray"]
  bugforge: "no entry for bytearray strip (vendor/bugforge-results/README.md)"
lean:
  property: PyLean.BytesObj.Bytes.StripCopiesScanned
  theorem: PyLean.BytesObj.Bytes.stripCopiesScanned_refuted
````

## reports/triage.tsv (header + first 5 rows of 436)

````
id	module	priority	kind	proposed_action	reason	title
accel-bisect-hi-minus-one	accel	P4	twin-mismatch	ask-in-group	record says probably intended; ask in the module issue	bisect: C treats hi=-1 as len(a) while bisect.py searches an empty range; negative hi breaks the documented partition
accel-bisect-negative-lo-message	accel	P4	twin-mismatch	group:accel	bundle with this module's other findings	bisect: a negative lo raises ValueError with different messages in C and in bisect.py since 3.15
accel-bisect-ssize-bounds	accel	P4	twin-mismatch	group:accel	bundle with this module's other findings	bisect: lo/hi outside Py_ssize_t raise OverflowError in C but return lo / raise ValueError or IndexError in bisect.py
accel-heapq-empty-error-message	accel	P4	twin-mismatch	group:accel	bundle with this module's other findings	heapq: heappop/heapreplace (and _max) on an empty heap raise IndexError with different messages in C and Python
accel-heapq-heapify-order-raising	accel	P5	twin-divergence	group:accel	bundle with this module's other findings	heapq: above 2500 items C heapify compares in a different order, so a raising comparison gives a different exception than Python (and than 2500 items)
````

## FINDINGS.md (header + P1 table; P2-P5 omitted)

````
# Findings

Generated by `scripts/gen_findings.py`. Nothing here has been filed. Priorities are the
recording agent's; a person decides what goes upstream. `yes` means the reproducer fired.

418 records reproduce on 3.15.2, the target. 18 others do not and are left out.

## P1

| record | kind | 3.15.2 | main | duplicate of | title |
|---|---|---|---|---|---|
| `bytesobj-bytearray-strip-release-uaf` | memory-safety | yes | yes |  | bytearray.strip/lstrip/rstrip copy from self after the argument's __release_buffer__ ran: use after free |
| `bytesobj-memoryview-eq-released-by-buffer` | memory-safety | yes | yes |  | m == w reads released memory when w.__buffer__ releases m (use after free) |
| `bytesobj-memoryview-setitem-c-released` | memory-safety | yes | yes |  | m[key] = b'x' with format 'c' writes through a view released by key.__index__ (use after free) |
| `corelibs-partial-setstate-phcount` | crash | yes | yes |  | partial.__setstate__ counts placeholders on a tuple subclass's storage and keeps its iteration, so a call reads and writes out of bounds |
| `corelibs-partial-vectorcall-stale-kw-count` | memory-corruption | yes | yes |  | partial_vectorcall trusts a keyword count taken before a key's __eq__ can run, and writes past its stack and tuple |
| `datetime-subclass-arith-result-type-confusion` | memory-safety | yes | yes |  | datetime.astimezone() and utctimetuple() read a datetime subclass's __new__ result as a datetime struct (segfault, garbage struct_time) |
| `datetime-zoneinfo-clear-cache-reentrant-free` | memory-safety | yes | yes |  | zoneinfo: ZoneInfo.clear_cache() frees strong-cache nodes while the cache head still points at them; a key's __del__ that creates a ZoneInfo makes it walk freed memory (segfault) |
| `datetime-zoneinfo-non-datetime-crash` | memory-safety | yes | yes | #125318 #111306 | _zoneinfo: utcoffset()/dst()/tzname() read the fold byte of a non-datetime argument (segfault) |
| `datetime-zoneinfo-strong-cache-eq-reentry` | memory-safety | yes | yes | #142782 | zoneinfo: a cache key whose __eq__ calls ZoneInfo.clear_cache() makes find_in_strong_cache walk freed nodes (segfault); duplicate of gh-142782 |
| `dictset-fromkeys-gc-track-non-gc` | memory-safety | yes | yes |  | dict.fromkeys on a subclass whose __new__ returns a non-GC object GC-tracks that object, corrupting memory (segfault in gc.collect) |
| `dictset-setdefault-split-null` | null-dereference | yes | yes |  | dict.setdefault segfaults on an instance __dict__ when a str-subclass key names a shared key this instance has no value for |
| `operator-methodcaller-reduce-shares-kwargs` | memory-safety | yes | yes |  | operator.methodcaller: __reduce__ hands the methodcaller's private kwargs dict to functools.partial, so writing to partial.keywords changes the methodcaller (stale calls; a non-str key segfaults repr) |
| `pyio-buffered-reentrant-init-free` | memory-safety | yes | yes |  | io.BufferedReader: calling __init__ from inside a raw stream callback frees the buffer and lock the running method holds (abort: PyMutex_Unlock on an unlocked mutex) |
| `pyio-buffered-reentrant-init-size0` | crash | yes | yes |  | io.BufferedReader/Writer: a failed __init__(raw, 0) re-entered from a raw callback leaves buffer_size 0: SIGFPE in read, endless loop in write |
| `sequences-array-ins1-stale-size` | memory-safety | yes | yes |  | array.append/insert/extend: ins1 resizes to a size read before __index__/__float__ ran, so an item conversion that clears the array exposes uninitialised memory and one that grows it loses items |
| `textlibs-etree-slice-backward-dup` | memory-safety | yes | yes |  | Element slice assignment with step 1 and start > stop duplicates a child without a reference and drops another (use-after-free) |
| `typeobj-exc-oserror-str-borrowed-free` | memory-safety | yes | no | #160773 | OSError.__str__ formats borrowed attribute pointers; an errno/strerror __str__ that clears filename frees it before %R reads it (segfault) — duplicate of gh-160773, fixed after 3.15.2 |

## P2
[...omitted: P2-P5 tables, ~400 rows...]
````
