# python-formalization: list of all bug records (id, priority, kind, title)

> Source: https://github.com/Broyojo/python-formalization/tree/main/bugs
> Collected: 2026-11-10
> Published: 2026-11-09

Generated from bugs/*.yaml (436 records; 18 are 3.14.7-only, listed in coverage/gone-in-3.15.txt). Titles truncated to 160 chars. Sorted by priority.

| id | P | kind | title |
|---|---|---|---|
| bytecode-gen-close-clears-running-frame | P1 | crash | gen_close's fast path does not check FRAME_EXECUTING: close() during the RESUME of a running generator frees its frame, a use-after-free reachable from __del__, |
| bytesobj-bytearray-strip-release-uaf | P1 | memory-safety | bytearray.strip/lstrip/rstrip copy from self after the argument's __release_buffer__ ran: use after free |
| bytesobj-memoryview-eq-released-by-buffer | P1 | memory-safety | m == w reads released memory when w.__buffer__ releases m (use after free) |
| bytesobj-memoryview-setitem-c-released | P1 | memory-safety | m[key] = b'x' with format 'c' writes through a view released by key.__index__ (use after free) |
| corelibs-partial-setstate-phcount | P1 | crash | partial.__setstate__ counts placeholders on a tuple subclass's storage and keeps its iteration, so a call reads and writes out of bounds |
| corelibs-partial-vectorcall-stale-kw-count | P1 | memory-corruption | partial_vectorcall trusts a keyword count taken before a key's __eq__ can run, and writes past its stack and tuple |
| datetime-subclass-arith-result-type-confusion | P1 | memory-safety | datetime.astimezone() and utctimetuple() read a datetime subclass's __new__ result as a datetime struct (segfault, garbage struct_time) |
| datetime-zoneinfo-clear-cache-reentrant-free | P1 | memory-safety | zoneinfo: ZoneInfo.clear_cache() frees strong-cache nodes while the cache head still points at them; a key's __del__ that creates a ZoneInfo makes it walk freed |
| datetime-zoneinfo-non-datetime-crash | P1 | memory-safety | _zoneinfo: utcoffset()/dst()/tzname() read the fold byte of a non-datetime argument (segfault) |
| datetime-zoneinfo-strong-cache-eq-reentry | P1 | memory-safety | zoneinfo: a cache key whose __eq__ calls ZoneInfo.clear_cache() makes find_in_strong_cache walk freed nodes (segfault); duplicate of gh-142782 |
| dictset-fromkeys-gc-track-non-gc | P1 | memory-safety | dict.fromkeys on a subclass whose __new__ returns a non-GC object GC-tracks that object, corrupting memory (segfault in gc.collect) |
| dictset-setdefault-split-null | P1 | null-dereference | dict.setdefault segfaults on an instance __dict__ when a str-subclass key names a shared key this instance has no value for |
| operator-methodcaller-reduce-shares-kwargs | P1 | memory-safety | operator.methodcaller: __reduce__ hands the methodcaller's private kwargs dict to functools.partial, so writing to partial.keywords changes the methodcaller (st |
| pyio-buffered-reentrant-init-free | P1 | memory-safety | io.BufferedReader: calling __init__ from inside a raw stream callback frees the buffer and lock the running method holds (abort: PyMutex_Unlock on an unlocked m |
| pyio-buffered-reentrant-init-size0 | P1 | crash | io.BufferedReader/Writer: a failed __init__(raw, 0) re-entered from a raw callback leaves buffer_size 0: SIGFPE in read, endless loop in write |
| sequences-array-ins1-stale-size | P1 | memory-safety | array.append/insert/extend: ins1 resizes to a size read before __index__/__float__ ran, so an item conversion that clears the array exposes uninitialised memory |
| textlibs-etree-slice-backward-dup | P1 | memory-safety | Element slice assignment with step 1 and start > stop duplicates a child without a reference and drops another (use-after-free) |
| typeobj-exc-eg-repr-args-oob | P1 | crash | repr() of an exception group reads args[1] out of bounds after args is replaced (segfault) |
| typeobj-exc-oserror-str-borrowed-free | P1 | memory-safety | OSError.__str__ formats borrowed attribute pointers; an errno/strerror __str__ that clears filename frees it before %R reads it (segfault) — duplicate of gh-1 |
| bytecode-eg-match-split-items-unchecked | P2 | crash | except* installs whatever an ExceptionGroup subclass's split() returns as the handled exception: split() returning (1, None) makes sys.exception() return 1, and |
| bytecode-flineno-iter-index-as-object | P2 | crash | f_lineno jump analysis treats the second slot of GET_ITER as an object, so a jump out of a `for` loop to the middle of a multi-line expression crashes (regressi |
| bytecode-flineno-null-on-stack | P2 | crash | f_lineno jump analysis treats a NULL slot (LOAD_SPECIAL/PUSH_NULL self_or_null) as an object, so a jump into a `with` body leaves NULL where an object is read ( |
| bytecode-flineno-stack-swap-truncation | P2 | crash | f_lineno jump analysis: stack_swap() truncates the modelled stack to 32 bits, so a jump into a deeply nested block corrupts the stack (crash on 3.15.2 and main) |
| bytecode-gen-close-deep-chain-stack-overflow | P2 | crash | gen_close and _gen_throw recurse along a yield-from chain with no stack guard: close() or dropping the generator segfaults at the default recursion limit |
| bytecode-gen-throw-attr-lookup-unguarded | P2 | crash | _gen_throw looks up the sub-iterator's throw attribute before marking the generator running: a throw property can close it, and the cleared frame is linked into |
| bytecode-kwonly-defaults-borrowed-dict | P2 | memory-safety | initialize_locals passes a borrowed func->func_kwdefaults to PyDict_GetItemRef; a key whose __eq__ resets f.__kwdefaults__ frees the dict mid-lookup (use after  |
| bytesobj-bytearray-init-iterator-ignores-start | P2 | duplicate-open-upstream | bytearray.__init__ from an iterator tests capacity without ob_start: an iterator that shrinks the front gets a heap write past the buffer |
| corelibs-inplace-mul-heap-left | P2 | wrong-exception | x *= [1] raises TypeError where x * [1] works, when x is an instance of a Python class with __index__ |
| corelibs-lru-evicted-hit-gc-hang | P2 | hang | A hit on the link being evicted, from a raising __eq__, leaves a cycle in lru_cache's list, and gc.collect() never returns |
| datetime-pep495-delta-cmp-none | P2 | memory-safety | datetime == reads Py_None as a timedelta in pep495_eq_exception when utcoffset() is None for one fold only |
| dictset-fromkeys-frozendict-rewritten | P2 | immutability-violation | frozendict.fromkeys of a subclass hands an untracked frozendict to Python code, and a later fromkeys fills that frozendict in place |
| itertools-count-reentrant-step-double-ref | P2 | memory-safety | itertools.count hands the same long_cnt reference to two callers when the step's __radd__ re-enters next() (duplicate of gh-154670) |
| itertools-groupby-eq-reentry-null-currkey | P2 | crash | itertools.groupby segfaults: a re-entrant key __eq__ can clear currkey, and groupby_next then does Py_INCREF(NULL) |
| itertools-islice-reentrant-input-uaf | P2 | memory-safety | itertools.islice pulls from a freed iterator when the input's __next__ re-enters the islice and exhausts it (duplicate of gh-142732) |
| pygrammar-check-none-in-list-segfault | P2 | crash | compile() segfaults on a hand-built AST with None in any of 11 list fields: handlers, patterns, keys, kwd_attrs, type_params, Global.names |
| pyio-buffered-reentrant-detach-crash | P2 | crash | io.BufferedReader.read crashes when the raw stream's closed property detaches the buffered object |
| sequences-array-e-ins1-overflow-keeps-slot | P2 | duplicate-open-upstream | array('e').append(65536.0) raises OverflowError but keeps a new item holding uninitialised memory |
| sequences-array-fromlist-restore-stale | P2 | memory-safety | array.fromlist: after an item's __index__ clears the array, the error path's array_resize(self, old_size) re-grows it, exposing old_size items of uninitialised  |
| sequences-array-tofile-reentrant-write | P2 | memory-safety | array.tofile() reads past the array (NULL + 65536 after clear()) when the file's write() empties or shrinks the array |
| textlibs-csv-reader-reentrant-null-fields | P2 | crash | csv.reader segfaults when its input iterator re-enters the reader and the input ends inside a quoted field |
| textlibs-email-msgid-no-fold-literal-space | P2 | crash | email: Message-ID '<a@[ x]>' raises UnboundLocalError (the gh-134152 fix covers only an empty literal) |
| textlibs-struct-reinit-memory-safety | P2 | memory-safety | Calling Struct.__init__ on a live Struct reaches freed and out-of-bounds memory from pure Python |
| textlibs-textwrap-indent-hang | P2 | hang | DUPLICATE of #158979: textwrap.wrap never returns when an indent is wider than width |
| typeobj-exc-getstate-borrowed-dict | P2 | memory-safety | AttributeError/ImportError __reduce__ copy the instance dict through a borrowed pointer; a key's __eq__ that replaces e.__dict__ frees it while PyDict_Copy stil |
| typeobj-set-class-reentrant-slot-eq | P2 | crash | __class__ assignment decrefs a stale old type when a str-subclass __slots__ name's __eq__ reassigns __class__: the old class is freed while still in use (segfau |
| typeobj-set-mro-error-borrowed-mro | P2 | memory-safety | MRO conflict message reads freed memory: set_mro_error hashes candidate classes while to_merge holds borrowed base MROs, and a metaclass __hash__ that reassigns |
| typeobj-structseq-mutable-size-attrs | P2 | memory-safety | Struct sequences trust n_fields, n_sequence_fields and n_unnamed_fields, which Python code can rebind: copy.replace, __reduce__ and a constructor whose argument |
| typeobj-super-uninitialized-get | P2 | crash | super.__new__(super).__get__(1) segfaults: super_descr_get calls supercheck with su->type NULL, and supercheck reads type->tp_name for its error |
| binary64-complex-abs-stale-errno | P3 | stale-state | abs(complex(nan, 1)) raises OverflowError when errno is left over from an earlier overflow |
| binary64-complex-pow-stray-edom | P3 | wrong-exception | complex ** raises ZeroDivisionError with a nonzero base when the phase is infinite |
| binary64-format-precision-near-int-max | P3 | integer-overflow | Float formatting with a precision near INT_MAX wraps a C int and prints the wrong value |
| bytecode-anext-default-restarts-await | P3 | behaviour-mismatch | anext(aiter, default): awaiting the result restarts __await__ on every resume, so a custom awaitable from __anext__ never finishes (3.14 and 3.15; fixed on main |
| bytecode-attr-frame-recursion | P3 | specialization-mismatch | LOAD_ATTR_PROPERTY and LOAD_ATTR_GETATTRIBUTE_OVERRIDDEN push the getter's frame with no recursion check, so a recursive property or __getattribute__ passes the |
| bytecode-call-ex-kw-bound-recursion | P3 | specialization-mismatch | CALL_EX_PY and CALL_KW_BOUND_METHOD push the callee's frame with no recursion check, so f(*args) and m(k=v) recursion passes the recursion limit once the site h |
| bytecode-gen-athrow-awaitable-reusable | P3 | state-corruption | A finished athrow() awaitable that went through an await stays reusable: send() resumes the generator with ag_running False |
| bytecode-gen-athrow-bad-args-stuck-running | P3 | state-corruption | athrow() with a bad argument count leaves ag_running stuck True: the async generator is unusable after a TypeError |
| bytecode-gen-throw-created-skips-pep479 | P3 | assertion-failure | throw(StopIteration) into a just-created generator skips PEP 479 and fails the asserts in gen_send_ex2 (debug abort); athrow(StopAsyncIteration) likewise |
| bytecode-posonly-keyword-borrowed-qualname | P3 | memory-safety | positional_only_passed_as_keyword formats a borrowed func->func_qualname after running a str subclass's __eq__, which can reassign f.__qualname__ and free it (u |
| bytecode-push-frame-gen-recursion | P3 | specialization-mismatch | SEND_GEN and FOR_ITER_GEN push a generator frame with no recursion check, so a chain of delegating generators passes the recursion limit once its site has speci |
| bytesobj-bytearray-iadd-self | P3 | duplicate-open-upstream | b += b raises BufferError for a bytearray, while b.extend(b) and b[len(b):] = b work |
| bytesobj-bytearray-init-codec-steal | P3 | bug | bytearray(str, encoding) with a Python codec installs the encoded bytes over what the codec did to self: a leak, and storage replaced under an export |
| bytesobj-bytearray-shrink-failure-start | P3 | duplicate-open-upstream | del b[:k] whose shrinking realloc fails leaves ob_start before the buffer: MemoryError, then out-of-bounds reads and writes |
| bytesobj-list-reversed-keeps-list | P3 | regression | An exhausted reversed(list) iterator keeps the list alive, unlike iter(list) |
| bytesobj-memoryview-buffer-noformat-itemsize | P3 | invariant-violation | m.__buffer__(flags) without PyBUF_FORMAT gives a view with format 'B' and the old itemsize, whose items are wrong |
| bytesobj-memoryview-empty-step-not-contiguous | P3 | inconsistency | An empty memoryview slice with a step is reported non-contiguous, so cast, join and hashlib reject it |
| calstat-statistics-sqrtprod-partial-underflow | P3 | wrong-result | statistics._sqrtprod loses accuracy when x*y is subnormal, so correlation() of exactly linear data is far from 1 |
| corelibs-dataclasses-asdict-counter | P3 | silent-wrong-result | dataclasses.asdict and astuple turn a Counter field into a Counter of (key, count) pairs |
| corelibs-enum-name-override | P3 | logic-error | enum.unique and verify(UNIQUE) report every member as a duplicate when the class defines its own name |
| corelibs-enum-value-alias-unhashable | P3 | logic-error | Enum._add_value_alias_ does not keep its ValueError for an unhashable value |
| corelibs-exitstack-context-cycle-hang | P3 | hang | ExitStack can create a __context__ cycle that nested with statements cannot, and its own while 1 loop then never ends |
| corelibs-lru-stacked-parameters | P3 | logic-error | A cache around a cached function reports the inner cache's cache_parameters, and in pure Python its cache_info too |
| corelibs-partial-flattens-subclass-call | P3 | logic-error | functools.partial flattens a partial subclass, so the subclass's __call__ never runs |
| corelibs-random-cli-positional-int-fallback | P3 | logic-error | python -m random 0 prints a float, and python -m random -5 a negative float, where --integer raises |
| corelibs-random-unseeded-subclass | P3 | regression | A random.Random subclass whose __init__ does not call super().__init__() silently returns 0.0 forever |
| corelibs-singledispatch-register-annotation | P3 | wrong-result | @f.register registers the first annotation found, which can be the return type or a later parameter |
| corelibs-singledispatch-union-abc-stale-cache | P3 | logic-error | singledispatch keeps a stale dispatch after ABC.register when the ABC was registered through a union |
| corelibs-statistics-mean-intenum-valueerror | P3 | crash | statistics.mean and variance raise ValueError for IntEnum data when the result is not a member |
| corelibs-suppress-group-virtual-subclass | P3 | sibling-mismatch | contextlib.suppress honours __subclasscheck__ and unions for a bare exception but not inside an ExceptionGroup |
| corelibs-userdict-missing-pop-setdefault | P3 | sibling-mismatch | UserDict subclasses with __missing__: pop(k, default) raises KeyError, setdefault stores nothing, items() contains absent keys |
| corelibs-userstring-replace-count-keyword | P3 | sibling-mismatch | UserString.replace(old, new, count=n) raises TypeError: the parameter is named maxsplit |
| corelibs-warnings-catch-enter-leak | P3 | missing-cleanup | warnings.catch_warnings(action=...): a bad action leaves the module patched; with record=True every later warning is swallowed |
| corelibs-warnings-filter-lineno-overflow | P3 | missing-validation | warnings: filterwarnings(lineno=2**63) is accepted, then every warning raises OverflowError |
| corelibs-warnings-option-escape | P3 | missing-error-check | warnings: some invalid -W / PYTHONWARNINGS options make 'import warnings' fail instead of being ignored |
| corelibs-warnings-registry-version-systemerror | P3 | missing-error-check | warnings: a registry 'version' outside C long makes warn_explicit leak an OverflowError (SystemError) |
| datetime-astimezone-mutates-subclass-result | P3 | correctness | datetime.astimezone() writes tzinfo in place into whatever datetime a subclass's __new__ returned (a cached instance changes, its hash goes stale) |
| datetime-c-fromisoformat-fraction-without-decimal-mark | P3 | c-python-divergence | C time/datetime.fromisoformat() reads digits after HHMMSS as a fraction with no decimal mark |
| datetime-c-fromisoformat-nul-after-z | P3 | c-python-divergence | C fromisoformat() ignores everything after 'Z' when the next character is NUL |
| datetime-date-fromisoformat-ignores-trailing-chars | P3 | missing-validation | date.fromisoformat() ignores the last two characters of a 10-character basic-format string |
| datetime-fromisoformat-midnight-day-zero | P3 | missing-validation | datetime.fromisoformat() accepts day 00 and year 0000 when the time is 24:00 |
| datetime-pydatetime-date-sub-datetime | P3 | twin-mismatch | _pydatetime date - datetime returns a timedelta where C raises TypeError |
| datetime-zoneinfo-fromutc-fold-last-transition | P3 | twin-divergence | zoneinfo: pure-Python fromutc() misses the fold of the last explicit transition |
| datetime-zoneinfo-load-data-not-valueerror | P3 | doc-mismatch | zoneinfo: from_file() raises struct.error or AssertionError for truncated TZif data |
| datetime-zoneinfo-zero-based-day | P3 | spec-violation | zoneinfo: the zero-based TZ rule `n` is evaluated one day early in both twins |
| decimal-c-context-inherits-flags | P3 | wrong-result | _decimal's Context() copies the flags set on DefaultContext, although flags=None is documented to clear them |
| decimal-c-format-spec-nul | P3 | wrong-result | _decimal's Decimal.__format__ ignores everything after an embedded NUL in the format spec |
| decimal-c-signaldict-eq-raw-bits | P3 | wrong-result | _decimal's Context.flags compares unequal to its own copy after InvalidOperation: SignalDict == compares raw status bits, not items |
| dictset-odict-stale-fast-nodes | P3 | null-dereference | After dict.popitem(od), od.popitem() and od.pop(k) segfault, and iterating od never ends |
| dictset-set-lookup-table-aba | P3 | memory-safety | set lookup and add trust `table == so->table` after __eq__; a smaller table at the old address makes discard free a key the set no longer holds and add store a  |
| ipaddress-address-exclude-scoped-assertion | P3 | crash-on-valid-input | ipaddress: IPv6Network.address_exclude raises AssertionError for a contained network with a scope id |
| ipaddress-exploded-ipv4-mapped-truncates | P3 | wrong-result | ipaddress: exploded of an IPv4-mapped IPv6 address or interface loses the scope id and the prefix |
| ipaddress-exploded-scoped-network-raises | P3 | crash-on-valid-input | ipaddress: IPv6Network.exploded raises AddressValueError for a network with a scope id |
| ipaddress-netmask-cache-history | P3 | wrong-exception | ipaddress: whether IPv4Network(('10.0.0.0', 8.0)) works depends on earlier calls; otherwise it leaks AttributeError |
| ipaddress-scoped-address-ordering | P3 | wrong-result | ipaddress: IPv6Address ordering ignores the scope id while == compares it, so subnet_of and summarize_address_range misjudge scoped addresses |
| ipaddress-subnets-host-network-skips-validation | P3 | missing-validation | subnets() on a /32 or /128 network ignores invalid prefixlen_diff / new_prefix instead of raising ValueError |
| ipaddress-supernet-zero-prefix-skips-validation | P3 | missing-validation | supernet() on a /0 network ignores invalid prefixlen_diff / new_prefix instead of raising ValueError |
| itertools-islice-step-overflow | P3 | silent-wrong-result | itertools.islice with stop=None yields an extra item when start + step overflows Py_ssize_t |
| json-encoder-notes-twins | P3 | twin-mismatch | json: C and pure-Python encoders print different exception notes and key-type messages (original vs converted key, %T vs __name__) |
| json-py-raw-decode-negative-index | P3 | twin-mismatch | json: pure-Python raw_decode() accepts a negative idx and returns garbage (C raises ValueError('idx cannot be negative')) |
| json-scanstring-error-twins | P3 | twin-mismatch | json: C and pure-Python decoders report invalid escapes at different positions (and both string errors with different messages) |
| json-separator-str-subclass | P3 | twin-mismatch | json: the C encoder writes str() of str-subclass separators and custom-encoder results (gh-148241 fixed only the values) |
| longobj-complex-abs-stale-errno | P3 | wrong-exception | abs() of a complex with a NaN part raises OverflowError if an earlier C call left errno = ERANGE |
| longobj-complex-pow-infinite-phase-edom | P3 | wrong-exception | (1+1j) ** float('inf') raises ZeroDivisionError: zero to a negative or complex power |
| longobj-complex-pow-underflow-zero-division | P3 | wrong-exception | complex(1e-200) ** -2 raises ZeroDivisionError: zero to a negative or complex power, for a nonzero base |
| longobj-str-digits-limit-pylong-path | P3 | wrong-result | str(int) can return more digits than sys.set_int_max_str_digits allows when the limit is 9000 or more |
| mathint-cmath-log-base-errno | P3 | missing-error-check | cmath.log(0, base) returns (-inf+nanj) instead of raising ValueError: the second c_log() call clears errno |
| pygrammar-check-namedexpr-target | P3 | missing-validation | _PyAST_Validate does not validate NamedExpr.target: Name('None') passes and reaches an assert in codegen_nameop; the Load and Del contexts pass too |
| pygrammar-lex-tokenize-memoryerror | P3 | crash-on-valid-input | tokenize raises MemoryError on valid source: stale last_expr_size in the readline tokenizer gives a negative decode size |
| pygrammar-unparse-format-spec-escapes | P3 | wrong-result | ast.unparse corrupts f-string format specs holding braces or control characters written as escapes: output is invalid or means something else |
| pyio-bufferedrandom-failed-seek-duplicates | P3 | sibling-mismatch | _pyio.BufferedRandom: after a seek() that fails, tell() is wrong and read() returns data twice |
| pyio-bufferedreader-readinto-valueerror | P3 | sibling-mismatch | _pyio.BufferedReader.readinto raises ValueError when refilled data exceeds the space left in the buffer |
| pyio-bufferedreader-uninitialized-read | P3 | memory-disclosure | io.BufferedReader returns uninitialized heap memory when raw.readinto() reports bytes it did not store |
| pyio-bytesio-stale-shared-hash | P3 | wrong-result | io.BytesIO.getvalue() can return bytes with a stale cached hash (duplicate of gh-160181) |
| pyio-readlines-hint-stops-early | P3 | sibling-mismatch | readlines(hint) stops one line early in io.BytesIO and all of _pyio, unlike every other C stream and the docs |
| pyio-stringio-newline-embedded-nul | P3 | nul-terminator-assumption | io.StringIO accepts a newline argument with an embedded NUL and silently truncates it at the NUL |
| pyio-stringio-newline-none-split-crlf | P3 | twin-mismatch | io.StringIO(newline=None) turns a \\r\\n split across two writes into two newlines |
| pyio-stringio-truncate-index-close-crash | P3 | crash | io.StringIO.truncate crashes the interpreter when __index__ closes a stream still accumulating |
| pyio-textio-tell-after-next-stale-snapshot | P3 | wrong-result | io.TextIOWrapper.tell() after next() and flush() returns a position past the end, reading past its stale snapshot |
| rangeslice-pyslice-getindices-success-with-exception | P3 | wrong-error-contract | PySlice_GetIndices() returns 0 (success) with OverflowError set when a slice index does not fit in Py_ssize_t |
| sequences-array-extended-slice-empty-deletes | P3 | doc-violation | a[i:j:k] = array() with k != 1 deletes the slice instead of raising ValueError like list |
| sequences-array-float-narrowing | P3 | twin-mismatch | array('e') rounds a double twice (through a C float), so it stores a different half than struct.pack('e'); 'e', 'f' and 'Zf' disagree with struct at the overflo |
| sequences-array-fromfile-partial-item | P3 | doc-mismatch | array.fromfile() raises ValueError and inserts nothing when the file ends inside an item, though the docs promise EOFError with the available items inserted |
| sequences-array-mformat-utf-sizes | P3 | wrong-constant | array._array_reconstructor rejects odd-length unicode arrays in the other byte order: mformat_descriptors has UTF sizes 4 and 8 |
| sequences-array-w-fromunicode-empty | P3 | internal-error-leak | array('w').fromunicode('') raises SystemError: PyUnicode_AsUCS4 refuses the NULL buffer and the failure is ignored |
| sequences-array-w-tounicode-bom | P3 | round-trip | array('w').tounicode() and repr() drop a leading U+FEFF and raise UnicodeDecodeError on surrogates, because they decode UTF-32 with byteorder 0 |
| textlibs-binascii-qp-line-length | P3 | spec-violation | binascii.b2a_qp writes lines longer than its own MAXLINESIZE of 76 before a line ending |
| textlibs-csv-num-fields-int-overflow | P3 | data-loss | csv.writer silently drops delimiters after 2**31 fields, because num_fields is a C int |
| textlibs-csv-skipinitialspace-round-trip | P3 | data-loss | csv.writer does not quote a leading space under skipinitialspace=True, so the reader silently drops it |
| textlibs-csv-sniffer-unusable-dialect | P3 | invariant-violation | csv.Sniffer.sniff returns a dialect with delimiter equal to quotechar, which reader rejects |
| textlibs-difflib-get-opcodes-empty-cache | P3 | wrong-result | SequenceMatcher.get_opcodes caches an empty list before computing, so after an exception the next call returns [] |
| textlibs-difflib-grouped-opcodes-mutates-cache | P3 | wrong-result | SequenceMatcher.get_grouped_opcodes overwrites the cached opcodes, so later calls give wrong results |
| textlibs-difflib-unified-diff-nonstr-lines | P3 | regression | difflib.unified_diff formats non-str lines since the f-strings of color, the garbling _check_types exists to stop |
| textlibs-email-display-name-only-cfws | P3 | crash | email: group display name that is only a comment raises IndexError in DisplayName.display_name (duplicate of gh-151857) |
| textlibs-email-nested-comment-recursion | P3 | uncaught-exception | email: reading a header with a few hundred nested comments raises RecursionError (policy.default, HeaderRegistry) |
| textlibs-email-param-extended-marker-at-end | P3 | crash | email: Content-Type parameter ending in '*' raises IndexError in get_parameter (duplicate of gh-151857) |
| textlibs-etree-copy-shares-attrib | P3 | twin-divergence | copy.copy of a C Element shares its attrib dict with the original (and drops the subclass) |
| textlibs-etree-elementpath-errors | P3 | internal-error-leak | ElementPath leaks KeyError, TypeError and ValueError for invalid paths, and iterfind returns None for an empty one |
| textlibs-etree-py-twin-setitem | P3 | twin-divergence | Pure-Python Element.__setitem__ consumes an iterator before storing it, so slice assignment from a generator inserts nothing |
| textlibs-etree-setstate-attrib-systemerror | P3 | internal-error-leak | Element.__setstate__ stores a non-dict attrib, after which get/set/keys/items raise SystemError |
| textlibs-html-unescape-digit-limit | P3 | internal-error | DUPLICATE of #158719 (closed, not planned): html.unescape raises ValueError on a long decimal reference |
| textlibs-path-ntpath-normpath-drive | P3 | wrong-result | DUPLICATE of #100162: ntpath.normpath turns the relative path .\\c:\\x into the absolute c:\\x |
| textlibs-plist-binary-datetime-max | P3 | exception-on-read | plistlib: a binary plist written from datetime.max cannot be read back (InvalidFileException) |
| textlibs-re-backref-extra-cases | P3 | twin-disagreement | DUPLICATE of #156513: an IGNORECASE backreference ignores the characters a literal matches |
| textlibs-re-match-endpos-before-pos | P3 | spec-violation | DUPLICATE of #160316: Pattern.match finds a match when endpos is less than pos |
| textlibs-re-possessive-min-count-not-atomic | P3 | spec-violation | re: x{m,n}+ with m >= 2 is not equivalent to (?>x{m,n}), as the docs say it is |
| textlibs-simplequeue-get-timeout | P3 | twin-divergence | SimpleQueue.get(timeout=inf) raises OverflowError even with an item ready (C), and the twins disagree on NaN and tiny negative timeouts |
| textlibs-struct-le-complex-float-overflow | P3 | internal-inconsistency | struct: 'F' overflows silently to inf in native and little-endian order, but raises OverflowError big-endian |
| textlibs-urllib-userinfo-brackets | P3 | wrong-exception | DUPLICATE of #77523: urlsplit rejects brackets in the userinfo by validating the plain host as an IP literal |
| textlibs-zoneinfo-before-first-transition | P3 | twin-divergence | zoneinfo: C and Python pick different local times before the first transition when every type is DST |
| typeobj-copydata-shape-mismatch | P3 | memory-safety | PyObject_CopyData compares only total byte lengths, then walks the source's indices over the destination: wrong data, and writes outside the destination view, w |
| typeobj-exc-except-star-drops-notes | P3 | logic-error | A note added in an except* handler is lost on re-raise: is_same_exception_metadata compares an unused field |
| typeobj-exc-split-sets-suppress-context | P3 | self-inconsistency | split() and subgroup() set __suppress_context__ on their results, which hides __context__ in tracebacks |
| typeobj-imul-sequence-fallback | P3 | self-inconsistency | x *= seq raises TypeError for instances of Python classes although x * seq works: the sq_repeat fallback in PyNumber_InPlaceMultiply tests tp_as_sequence, which |
| typeobj-property-subclass-doc-lost | P3 | self-inconsistency | property subclass: .setter/.getter/.deleter drop an explicit doc=, because property_copy reads prop_doc, which __init__ leaves NULL for subclasses |
| typeobj-structseq-repr-unnamed-labels | P3 | wrong-result | structseq_repr labels visible item i with tp_members[i].name, which skips unnamed fields: os.stat_result prints st_atime=<int slot 7>, and a named field after a |
| unicodeobj-codecs-namereplace-pua-names | P3 | doc-mismatch | namereplace writes names for Plane 15 private-use characters, taken from unicodedata's hidden alias and named-sequence slots |
| unicodeobj-codec-unicode-escape-octal-chunks | P3 | wrong-result | The unicode_escape incremental decoder splits an octal escape at a chunk boundary and gives a different string |
| unicodeobj-fromformat-negative-precision | P3 | crash | PyUnicode_FromFormat with a negative '.*' precision copies a negative count and corrupts memory, for every object conversion |
| unicodeobj-text-dedent-negative-memcpy | P3 | crash | _PyUnicode_Dedent calls memcpy with a negative length when the last line is blank, shorter than the margin and has no newline |
| accel-bisect-hi-minus-one | P4 | twin-mismatch | bisect: C treats hi=-1 as len(a) while bisect.py searches an empty range; negative hi breaks the documented partition |
| accel-bisect-negative-lo-message | P4 | twin-mismatch | bisect: a negative lo raises ValueError with different messages in C and in bisect.py since 3.15 |
| accel-bisect-ssize-bounds | P4 | twin-mismatch | bisect: lo/hi outside Py_ssize_t raise OverflowError in C but return lo / raise ValueError or IndexError in bisect.py |
| accel-heapq-empty-error-message | P4 | twin-mismatch | heapq: heappop/heapreplace (and _max) on an empty heap raise IndexError with different messages in C and Python |
| accel-heapq-py-twin-fallible-compare | P4 | twin-divergence | heapq: the pure-Python heap functions lose an item when a comparison raises, and have no list-changed-size guard, unlike _heapq |
| accel-heapq-select-trusts-len | P4 | regression | heapq.nsmallest and nlargest return more than n items when len(iterable) is below the item count, since 3.15 |
| binary64-complex-pow-intermediate-overflow | P4 | wrong-exception | complex ** overflows or gives nan+nanj in pow(/a/, b.real) when the true power is finite (duplicate of gh-60200) |
| binary64-floordiv-not-exact-floor | P4 | accuracy | float // and divmod miss the exact floor for quotients above about 2**51, in both directions |
| binary64-fromhex-overflow-before-trailing-garbage | P4 | validation-order | float.fromhex raises OverflowError instead of ValueError for a malformed string with a large exponent |
| binary64-struct-f-le-quiets-snan | P4 | regression | struct.unpack('<f') quiets a signaling NaN on a little-endian host, while struct.unpack('>f') keeps it |
| bytecode-call-alloc-abstract | P4 | specialization-mismatch | CALL_ALLOC_AND_ENTER_INIT instantiates an abstract class, bypassing object.__new__'s ABC check |
| bytecode-gen-throw-bad-arg-kills-delegator | P4 | validation-order | throw() with an invalid argument leaves a plain generator alone but kills a delegating one: the arguments are validated only at the end of the yield-from chain |
| bytesobj-bytearray-buffer-flags-systemerror | P4 | wrong-exception | bytearray().__buffer__(inspect.BufferFlags.READ) raises SystemError (bad argument to internal function) |
| bytesobj-bytes-contains-index-error-masked | P4 | wrong-exception | x in b replaces an exception raised by x.__index__ with 'a bytes-like object is required' |
| bytesobj-list-length-hint-overestimate | P4 | inconsistency | list(x) raises MemoryError for an over-estimating __length_hint__, and overflows Py_ssize_t at sys.maxsize |
| bytesobj-list-sizeof-during-sort | P4 | wrong-result | list.__sizeof__() returns 32, less than an empty list, while the list is being sorted |
| bytesobj-memoryview-cast-format-embedded-nul | P4 | validation | memoryview.cast accepts a format with an embedded NUL: 'B\\0anything' is taken for 'B' |
| bytesobj-memoryview-slice-stride-overflow | P4 | undefined-behaviour | m[::k] with a huge step overflows Py_ssize_t in init_slice; m.strides reports a wrapped value |
| bytesobj-tuple-capi-stale-hash | P4 | wrong-result | PyTuple_SetItem() and _PyTuple_Resize() keep a cached hash: a tuple hashed before the change keeps the old hash |
| calstat-statistics-decimal-sqrt-tie | P4 | wrong-result | statistics._decimal_sqrt_of_frac rounds an exact halfway root down to an odd digit, so stdev/pstdev of Decimals is not half-even |
| calstat-statistics-quantiles-inclusive-outside-range | P4 | wrong-result | statistics.quantiles(method='inclusive') gives cut points above the maximum of constant float data |
| corelibs-cmp-to-key-twin-operands | P4 | twin-mismatch | cmp_to_key twins differ on a right operand with .obj, and on != when mycmp returns an object |
| corelibs-copy-method-aliasing | P4 | wrong-result | copy.deepcopy of a bound method whose __self__ refers back to it makes two copies of the method |
| corelibs-copy-reduce-six-tuple | P4 | logic-error | copy.copy and copy.deepcopy raise TypeError on a __reduce__ result with a state_setter, which pickle accepts |
| corelibs-dataclasses-asdict-dataclass-key | P4 | crash-on-valid-input | dataclasses.asdict raises TypeError on a dict field keyed by a frozen dataclass, where astuple works |
| corelibs-dataclasses-initvar-init-false | P4 | crash-on-valid-input | An InitVar with init=False makes every instantiation raise NameError in generated code |
| corelibs-enumdict-auto-no-generate | P4 | crash-on-valid-input | EnumDict used directly has no _generate_next_value, so auto() fails, and update then stores the wrong keys |
| corelibs-enum-flag-contains-conform | P4 | logic-error | Any int is `in` a CONFORM Flag class, whose own value it is not |
| corelibs-enum-flag-iter-none | P4 | sibling-mismatch | Iterating a Flag alias with unnamed bits yields None, or raises AttributeError when the members are not in value order |
| corelibs-enum-flag-len-counts-unknown-bits | P4 | doc-mismatch | len(flag) counts bits outside the class, so it disagrees with iteration under KEEP and for IntFlag |
| corelibs-enum-strict-unnamed-bit | P4 | logic-error | A STRICT Flag accepts a value made only of bits that exist inside a multi-bit member, then rejects it in combinations |
| corelibs-enum-value-alias-repr-typeerror | P4 | logic-error | Enum._add_value_alias_ silently accepts a value linked to another member when a repr raises TypeError |
| corelibs-exitstack-lookup-special-metaclass | P4 | wrong-result | ExitStack.enter_context and push use a metaclass's __enter__/__exit__ on an instance, which the with statement refuses |
| corelibs-generator-close-drops-return-value | P4 | twin-mismatch | collections.abc.Generator.close discards the value that builtin generator.close() returns |
| corelibs-itemsview-contains-unpack | P4 | twin-mismatch | ItemsView.__contains__ raises for non-pairs and accepts lists, unlike dict_items; set operators inherit the crash |
| corelibs-lru-cache-maxsize-overflow | P4 | twin-mismatch | lru_cache(maxsize=2**63) raises OverflowError with the C wrapper and works with the Python wrapper |
| corelibs-lru-cache-noncallable | P4 | twin-mismatch | lru_cache(1)(5) raises TypeError with the C wrapper and is accepted by the Python wrapper |
| corelibs-lru-currsize-exceeds-maxsize | P4 | invariant | lru_cache holds maxsize + 1 entries for good after a key's __eq__ re-enters the cache during the store |
| corelibs-lru-failed-delete-none | P4 | silent-wrong-result | After a failed del in the pure Python lru_cache, a hit on the old key returns None |
| corelibs-lru-failed-store-stale-link | P4 | twin-mismatch | pure-Python lru_cache: a failed cache[key] store leaves a ring link, and a later unrelated call raises KeyError |
| corelibs-lru-reentrant-eq-keyerror | P4 | twin-divergence | With a re-entrant __eq__, the pure Python lru_cache raises KeyError from its own del, where C keeps going |
| corelibs-make-key-metaclass | P4 | twin-mismatch | The pure Python lru_cache raises TypeError on an instance of a class with an unhashable metaclass, and C does not |
| corelibs-namedtuple-nfkc-field-names | P4 | missing-validation | namedtuple validates field names as raw strings but compiles them after NFKC normalisation |
| corelibs-operator-concat-skips-radd | P4 | twin-mismatch | operator.concat(a, b) is not a + b when b defines __radd__: the C function never tries it |
| corelibs-operator-twin-corners | P4 | twin-mismatch | operator twins differ on index, on attrgetter with a str subclass, and on a getter holding itself |
| corelibs-partial-cycle-hang | P4 | hang | partial.__setstate__ can make a partial its own func, and inspect then hangs on it |
| corelibs-partial-repr-exception-order | P4 | twin-mismatch | repr(partial) raises a different exception in the twins when two reprs fail |
| corelibs-partial-twin-corners | P4 | twin-mismatch | partial twins differ on an object claiming to be a partial, on a repr that grows keywords, and in __setstate__ on subclasses |
| corelibs-pysimplequeue-nonblocking-timeout | P4 | twin-mismatch | _PySimpleQueue.get(block=False, timeout=...) raises ValueError; the docstring and _queue.SimpleQueue ignore timeout |
| corelibs-random-init-subclass-super | P4 | logic-error | random.Random.__init_subclass__ never calls super().__init_subclass__(**kwargs): later mixin hooks are skipped and class keywords are swallowed |
| corelibs-random-nan-parameters | P4 | missing-validation | NaN parameters hang gammavariate, betavariate and vonmisesvariate, and trip an assert in binomialvariate |
| corelibs-random-sample-negative-counts | P4 | missing-validation | random.sample accepts negative counts when their total is not negative, and then skews the selection |
| corelibs-random-setstate-gauss-next | P4 | partial-state-change | A rejected Random.setstate still replaces gauss_next |
| corelibs-reduce-iter-typeerror | P4 | twin-mismatch | functools.reduce in C replaces a TypeError raised by a user's __iter__ with its own message |
| corelibs-singledispatch-compose-repeat | P4 | logic-error | _compose_mro can list an ABC twice, and singledispatch then raises RuntimeError: Inconsistent hierarchy |
| corelibs-singledispatchmethod-callable-no-get | P4 | wrong-exception | singledispatchmethod accepts a callable without __get__ and fails with AttributeError on the first call |
| corelibs-singledispatch-register-stopiteration | P4 | wrong-exception | @f.register on a function whose __annotate__ yields nothing raises a bare StopIteration |
| corelibs-statistics-coerce-set-order | P4 | nondeterminism | statistics._sum folds _coerce over a set, so the result depends on the addresses of the types |
| corelibs-statistics-correlation-constant-undetected | P4 | wrong-result | statistics.correlation and linear_regression miss constant input when the rounded mean differs from it |
| corelibs-statistics-correlation-out-of-range | P4 | wrong-result | statistics.correlation returns values outside [-1, 1] on exactly proportional data |
| corelibs-statistics-quantiles-method-unchecked | P4 | validation-order | statistics.quantiles accepts an unknown method when the data has one point |
| corelibs-userdict-not-reversible | P4 | sibling-mismatch | reversed(UserDict(...)) raises TypeError although dict is reversible |
| corelibs-userdict-popitem-fifo | P4 | duplicate-already-fixed | UserDict.popitem is FIFO, dict.popitem is LIFO (fixed on main, present in 3.14) |
| corelibs-userstring-no-format | P4 | sibling-mismatch | format(UserString(...), spec) and f-strings with a spec raise TypeError |
| corelibs-userstring-unwrap-siblings | P4 | sibling-mismatch | UserString.partition, split, strip and the pad methods reject UserString arguments that count, find and replace accept |
| corelibs-warnings-class-read | P4 | twin-divergence | _py_warnings.warn and warn_explicit read message.__class__ (isinstance), C uses the exact type: a str subclass can change the category or raise |
| corelibs-warnings-once-per-module | P4 | twin-divergence | warnings 'once' shows a warning once per module in C (duplicate of gh-159792) |
| corelibs-warnings-py-twin | P4 | twin-divergence | _py_warnings.warn_explicit differs from C: line-0 warnings vanish under 'module', UnboundLocalError for an unknown default action, and nine smaller differences |
| corelibs-warnings-py-twin-warn | P4 | twin-divergence | _py_warnings.warn and the Python defaults differ from C: stacklevel <= 0, skip_file_prefixes, huge stacklevel, non-str __name__, the '__main__' default filter |
| corelibs-warnings-show-import | P4 | twin-divergence | C warn_explicit imports warnings for every shown warning: an import hook that raises makes the warning raise (the Python twin shows it) |
| corelibs-warnings-simplefilter-category | P4 | missing-validation | warnings.simplefilter accepts any category, then every warning raises TypeError (duplicate of gh-125893) |
| corelibs-weakref-deepcopy-memo | P4 | wrong-result | deepcopy of a WeakKeyDictionary or WeakValueDictionary that refers to itself makes two copies of it |
| corelibs-wraps-placeholder | P4 | twin-mismatch | functools.wraps(Placeholder) raises TypeError, where update_wrapper(f, Placeholder) works |
| datetime-fromisocalendar-overflow-class | P4 | twin-mismatch | date.fromisocalendar raises OverflowError in C and ValueError in Python for components outside C int |
| datetime-pydatetime-astimezone-local-target | P4 | twin-mismatch | _pydatetime astimezone() takes the target local zone from self before converting, C from the UTC result |
| datetime-pydatetime-astimezone-unchecked-offset | P4 | twin-mismatch | _pydatetime datetime.astimezone() does not validate tzinfo.utcoffset() and calls it before the identity shortcut |
| datetime-pydatetime-fold-ordinal-no-index | P4 | twin-mismatch | _pydatetime does not apply operator.index to fold and to date.fromordinal's argument, unlike C |
| datetime-pydatetime-fromisoformat-trailing-separator | P4 | c-python-divergence | Pure-Python datetime.fromisoformat() accepts a date followed by a bare separator |
| datetime-pydatetime-none-as-omitted | P4 | twin-mismatch | _pydatetime treats an explicit None (or tzinfo=True) as an omitted argument in replace and combine |
| datetime-pydatetime-pep495-eager-flip | P4 | twin-mismatch | _pydatetime asks for the flipped-fold utcoffset on every inter-zone ==, so an exception there breaks comparisons C answers |
| datetime-pydatetime-str-isoformat-alias | P4 | twin-mismatch | str() of a date or time subclass overriding isoformat: C calls the override, _pydatetime does not |
| datetime-pydatetime-timedelta-float-precision | P4 | twin-mismatch | _pydatetime timedelta() rounds large float arguments before splitting off the fraction, unlike C |
| datetime-reduce-ex-protocol-int-converter | P4 | twin-mismatch | time/datetime.__reduce_ex__(protocol): C rejects a protocol outside C int or without __index__, _pydatetime accepts it |
| datetime-strftime-bare-colon | P4 | twin-mismatch | strftime: a %: not followed by z differs between the C and Python implementations |
| datetime-strptime-oy-day-without-year | P4 | wrong-error | strptime rejects %d with %Oy as 'without a year directive', though %Oy is the year |
| datetime-timedelta-mul-int-subclass | P4 | twin-mismatch | timedelta * n for an int subclass: C runs n.__mul__ on the microseconds, _pydatetime uses int arithmetic |
| datetime-time-pickle-falsy-tzinfo | P4 | twin-mismatch | _pydatetime time(state, tzinfo) accepts any falsy tzinfo where C raises TypeError |
| datetime-time-subminute-offset | P4 | twin-mismatch | datetime.time comparison and hash mishandle sub-minute UTC offsets (3.15.2; fixed on main) |
| datetime-zoneinfo-cache-eq-raises | P4 | twin-divergence | zoneinfo: with a key whose __eq__ raises, C ZoneInfo(key) and clear_cache(only_keys=...) raise while the pure-Python twin succeeds |
| datetime-zoneinfo-dstoff-int-narrowing | P4 | silent-wraparound | _zoneinfo: load_timedelta() narrows a long DST offset to int |
| datetime-zoneinfo-footer-nul | P4 | twin-divergence | _zoneinfo: a TZ footer with an embedded NUL is cut at the NUL |
| datetime-zoneinfo-fromutc-static-footer | P4 | twin-divergence | zoneinfo: pure-Python fromutc() adds the last transition's offset instead of the footer's after the last transition (two or more transitions, fixed-offset foote |
| datetime-zoneinfo-get-weak-cache-fallback | P4 | twin-divergence | zoneinfo: a deleted or replaced Sub._weak_cache makes C Sub(key) raise (AttributeError, RuntimeError) where the pure-Python twin falls back or returns the store |
| datetime-zoneinfo-init-subclass | P4 | twin-divergence | zoneinfo: C ZoneInfo.__init_subclass__ silently accepts class keywords and imports weakref anew; the pure-Python twin rejects keywords and uses its bound weakre |
| datetime-zoneinfo-isdst-sum | P4 | twin-divergence | zoneinfo: pure-Python dst() is 0 for DST types when an isdst byte is neither 0 nor 1 |
| datetime-zoneinfo-subclass-lookup | P4 | twin-divergence | zoneinfo: for datetime subclasses C narrows toordinal() to int, so utcoffset()/fromutc() pick a different offset than the pure-Python twin |
| datetime-zoneinfo-subclass-strong-cache | P4 | twin-divergence | zoneinfo: a ZoneInfo subclass has a strong LRU cache in the pure-Python twin and none in C |
| datetime-zoneinfo-transition-int64-wrap | P4 | silent-wraparound | _zoneinfo: ts_to_local() and fromutc() wrap int64_t for transition times near the ends of the range |
| decimal-c-context-ignores-default-capitals | P4 | wrong-result | _decimal's Context() and IEEEContext() ignore DefaultContext.capitals and always use 1 |
| decimal-c-format-surrogate-fill | P4 | wrong-exception | _decimal's Decimal.__format__ raises UnicodeEncodeError for a lone surrogate fill character |
| decimal-pydecimal-floordiv-no-finalize | P4 | twin-disagreement | _pydecimal's // and divmod return the quotient without _fix, so it can exceed Emax with no Overflow, unlike _decimal |
| decimal-pydecimal-int-max-str-digits | P4 | known-limitation | _pydecimal raises ValueError (int string-conversion limit) for decimals with more than 4300 digits: constructor, hash, floor/ceil/round, as_integer_ratio, +, -, |
| decimal-pydecimal-parser-unicode-casefold | P4 | twin-disagreement | _pydecimal.Decimal accepts 'ınf', 'İnfinity' and 'ſNaN' through re.IGNORECASE Unicode case folding; _decimal rejects them |
| decimal-pydecimal-pow10-float-misfire | P4 | wrong-result | _pydecimal's _is_less_than_pow10a_use_str (new in 3.15) calls a quotient that fits too large, so //, % and divmod raise DivisionImpossible at prec 355861594 |
| decimal-pydecimal-signal-dict-tuple-message | P4 | wrong-message | _pydecimal formats a tuple operand with '%s' % x in its TypeError messages, so Context().plus(()), Context().traps = (), Context().rounding = () and Decimal.fro |
| decimal-pydecimal-tuple-bool-digits | P4 | invalid-state | _pydecimal.Decimal((0, (True,), 0)) builds a corrupt Decimal('True'); the tuple constructor also ignores the coefficient of an infinity |
| dictset-setiter-negative-length-hint | P4 | missing-check | A set iterator's __length_hint__ goes negative after same-size mutation, so list(it) raises ValueError |
| fractions-format-e-int-max-str-digits | P4 | crash-on-valid-input | format(Fraction, '.2e') raises ValueError (int string-conversion limit) for values with more than 4300-digit numerator or denominator |
| fractions-zero-denominator-huge-numerator-valueerror | P4 | wrong-exception | Fraction(n, 0) raises ValueError instead of ZeroDivisionError when n has more than 4300 digits |
| getargs-snprintf-cut-utf8-decode | P4 | wrong-exception | A non-ASCII type name cut by snprintf turns argument and MRO TypeErrors into UnicodeDecodeError |
| itertools-batched-n-prealloc | P4 | resource-exhaustion | itertools.batched preallocates an n-item tuple per batch: MemoryError for large n even on short or empty input |
| itertools-combinatorics-r-prealloc | P4 | resource-exhaustion | combinations/permutations/combinations_with_replacement allocate r indices even when the result is empty (MemoryError instead of an empty iterator) |
| itertools-count-add-before-yield | P4 | doc-mismatch | itertools.count computes the next value before returning the current one: a failing add loses a value the documented equivalent yields |
| itertools-count-int-subclass-fast-path | P4 | doc-mismatch | itertools.count's fast path drops int subclasses: count(True) gives 1 where count(True, 2) gives True, and __add__ of a subclass is not called |
| itertools-doc-combinatorics-negative-r | P4 | doc-mismatch | Docs: the combinations/permutations/combinations_with_replacement equivalents yield a tuple for negative r instead of raising ValueError |
| itertools-groupby-reentrant-key-drops-item | P4 | wrong-result | itertools.groupby: a key function (or input) that advances the groupby from inside a group silently drops the new group's first item |
| itertools-islice-step-message | P4 | misleading-error-message | islice rejects a step above sys.maxsize with 'Step for islice() must be a positive integer or None.' |
| itertools-product-empty-pool-null-tuple | P4 | invalid-state | itertools.product with an empty pool keeps a half-filled result tuple with NULL items, reachable through gc.get_referents (segfault on access) |
| itertools-product-repeat-zero-skips-iterables | P4 | doc-mismatch | itertools.product with repeat=0 ignores its positional arguments: non-iterables are accepted and raising iterables are never read |
| itertools-ssize-arguments | P4 | doc-mismatch | itertools arguments are limited to Py_ssize_t while the documented equivalents accept any int (known, won't fix) |
| json-container-subclass-twins | P4 | twin-mismatch | json: C and pure-Python encoders treat list and dict subclasses differently (known) |
| json-indent-recursion-memory | P4 | resource-use | json: dumps(cyclic, check_circular=False, indent=1) with the C encoder uses gigabytes before RecursionError (quadratic in depth) |
| json-roundtrip-surrogate-pair | P4 | round-trip | json: loads(dumps(s)) != s when s contains a high surrogate followed by a low surrogate (ensure_ascii=True) |
| json-twins-recursion-limit | P4 | twin-mismatch | json: the C and pure-Python twins stop at different nesting depths (C stack limit vs sys.getrecursionlimit()) |
| listsort-stack-comment-log2 | P4 | doc-mismatch | listobject.c: the MAX_MERGE_PENDING comment understates the stack depth powersort can need |
| longobj-complex-float-subclass-dunder-float | P4 | twin-disagreement | complex(x) ignores __float__ on a float subclass, while complex(x, 0) and float(x) call it |
| longobj-complex-pow-infinite-base-overflow | P4 | wrong-exception | complex('inf') ** 1 raises OverflowError: complex exponentiation |
| longobj-complex-quot-finite-over-infinite-nan | P4 | wrong-result | complex(1e308, 1e308) / complex(inf, inf) is nan+0j, not 0j |
| longobj-complex-rc-quot-inf-dividend | P4 | twin-disagreement | float('inf') / (1e308+1e308j) is nan+nanj, but complex('inf') / (1e308+1e308j) is inf-infj |
| mathint-cmath-phase-underflow | P4 | twin-mismatch | cmath.phase(z) raises OverflowError('math range error') when atan2 underflows, unlike math.atan2 |
| mathint-nextafter-steps-zero-sign | P4 | twin-mismatch | math.nextafter(x, y) and math.nextafter(x, y, steps=1) return zeros of opposite sign when the step lands on y's zero |
| pickle-c-batch-encoding | P4 | twin-mismatch | pickle: C and Python picklers batch lists, dicts and sets differently (last batch of one, empty trailing batch) |
| pickle-c-empty-batch-no-type-check | P4 | twin-mismatch | _pickle: APPENDS and ADDITEMS with no items accept any target; pickle.py raises AttributeError |
| pickle-c-frame-chunk-straddle | P4 | twin-mismatch | pickle: a BINBYTES or BYTEARRAY8 payload may run past its frame when the frame ends on a chunk boundary, unlike Python for BINBYTES (new in 3.15) |
| pickle-c-int-bool-spelling | P4 | twin-mismatch | _pickle: INT opcode returns a bool for any 3-byte line that strtol reads as 0 or 1 (' 1', '+1', '-0') |
| pickle-c-int-digit-limit | P4 | twin-mismatch | _pickle: INT opcode skips the 4300-digit limit when the value fits a C long |
| pickle-c-long4-untrimmed-size | P4 | twin-mismatch | _pickle: save_long checks the LONG4 size before trimming the sign byte, so it refuses an int that fits |
| pickle-c-memo-dict-unsynced | P4 | twin-mismatch | pickle: C Unpickler's memo_dict is unknown to MEMOIZE, memo.copy() and the memo setter (new in 3.15) |
| pickle-c-nul-in-text-args | P4 | twin-mismatch | _pickle: INT, LONG, GET and PUT stop at an embedded NUL and ignore the rest of the line |
| pickle-c-put-index-ssize | P4 | twin-mismatch | _pickle: PUT with an index of 2**63 or more raises OverflowError; the pickle.py memo is a dict |
| pickle-protocol-float | P4 | twin-mismatch | pickle: pickle._dumps accepts a float protocol and truncates it, pickle.dumps raises TypeError |
| pickle-protocol-long-overflow | P4 | twin-mismatch | pickle: a protocol outside C long raises OverflowError in C, while pickle.py accepts huge negatives and raises ValueError for huge positives |
| pickle-py-oversize-struct-error | P4 | twin-mismatch | pickle.py: bytes over 4 GiB at protocol 3 raise a bare struct.error where C explains the limit with OverflowError |
| pickle-py-truncated-frame | P4 | twin-mismatch | pickle.py: a FRAME longer than the remaining data is accepted; _pickle reports truncation |
| pickle-py-unpickler-raw-exceptions | P4 | twin-mismatch | pickle.py: malformed streams raise raw IndexError, KeyError and struct.error where _pickle raises UnpicklingError |
| pickle-tools-dis-mark-indexerror | P4 | internal-error | pickletools.dis: IndexError instead of ValueError when an opcode that does not expect a mark consumes one |
| pickle-tools-noescape-decodes-escapes | P4 | twin-mismatch | pickletools: read_stringnl_noescape undoes escapes, so GLOBAL and PERSID arguments differ from what pickle reads, and valid pickles are rejected |
| pickle-twins-recursion-limit | P4 | twin-mismatch | pickle: the C and pure-Python picklers stop at different nesting depths (C stack vs sys.getrecursionlimit()) |
| pygrammar-check-debug-in-pattern | P4 | semantic-mismatch | __debug__ in a match value pattern or mapping key is not folded, so it ignores compile(..., optimize=N) |
| pygrammar-check-trystar-handlers | P4 | missing-validation | _PyAST_Validate checks ExceptHandler positions and names for Try but not for TryStar, and lets a bare except* through to an internal 'Invalid CFG' error |
| pygrammar-format-spec-constant | P4 | ast-shape | A format spec with a \\N{...} escape followed by more text is a Constant in the AST, not a JoinedStr |
| pygrammar-fstring-escape-warning-line | P4 | diagnostic | An invalid escape in a multi-line f-string or t-string is warned about on the wrong line |
| pygrammar-grammar-invalid-first-pass | P4 | doc-mismatch | Grammar comment says invalid_ rules are not used in the first pass, but dict calls invalid_double_starred_kvpairs unguarded |
| pygrammar-lex-cookie-cr | P4 | twin-disagreement | tokenize.detect_encoding and the compiler read different encodings from a source with bare CR line endings |
| pygrammar-lex-debug-text-escaped-quote | P4 | wrong-result | f'{expr=}' prints the wrong text, and Interpolation.str is wrong, when a string in expr has an escaped quote and a '#' and the field has a comment |
| pygrammar-lex-untokenize-continuation | P4 | wrong-result | tokenize.untokenize loses the indentation of a block indented through a backslash continuation, breaking its round-trip guarantee on valid source |
| pygrammar-peg-format-spec-decode-error | P4 | wrong-exception | A bad escape in an f-string format spec escapes compile() as UnicodeDecodeError, not SyntaxError |
| pygrammar-unparse-c-fstring-repr | P4 | wrong-result | Stringified annotations misquote f-strings: Python/ast_unparse.c applies repr() to a body holding source text, so nested strings and quotes change or do not par |
| pyio-buffered-init-inquiry-truthy | P4 | sibling-mismatch | io.Buffered* constructors refuse a raw whose readable()/writable()/seekable() returns a truthy non-bool; _pyio accepts it |
| pyio-buffered-pyio-reentrant-deadlock | P4 | sibling-mismatch | _pyio.BufferedReader/Writer deadlock on a re-entrant call where io raises RuntimeError |
| pyio-bytesio-getbuffer-blocks-overwrite | P4 | twin-mismatch | With a live getbuffer() view, io.BytesIO refuses every write; _pyio.BytesIO refuses only resizes |
| pyio-bytesio-truncate-index-deadlock | P4 | hang | _pyio.BytesIO.truncate deadlocks when __index__ touches the stream, because it holds self._lock across the call |
| pyio-bytesio-twin-argument-handling | P4 | twin-mismatch | io and _pyio BytesIO/StringIO differ on arguments outside Py_ssize_t, non-int arguments, check order and error messages |
| pyio-bytesio-write-near-maxsize-systemerror | P4 | duplicate-already-fixed | io.BytesIO.write ending exactly at sys.maxsize raises SystemError |
| pyio-stringio-pyio-byte-positions | P4 | twin-mismatch | _pyio.StringIO positions are UTF-8 byte offsets: writing over non-ASCII text corrupts the stream |
| pyio-stringio-pyio-newlines-attributeerror | P4 | twin-mismatch | _pyio.TextIOWrapper.newlines raises AttributeError once a non-universal stream has been read, and is None before the first read where C reports the written newl |
| pyio-stringio-pyio-tell-after-readlines | P4 | twin-mismatch | tell() raises OSError after readlines(hint) stops early (_pyio.StringIO and every TextIOWrapper) |
| pyio-stringio-pyio-write-after-read | P4 | twin-mismatch | _pyio.StringIO: write and truncate after a read act on the read-ahead position, not the logical one |
| rangeslice-iter-setstate-fast-slow-mismatch | P4 | fast-slow-path-mismatch | range_iterator.__setstate__ raises OverflowError for big states while longrange_iterator.__setstate__ clips them |
| sequences-array-repr-complex-names | P4 | doc-mismatch | repr() of a 'Zd' or 'Zf' array with an infinite or NaN imaginary part is not eval()-able: it contains infj and nanj |
| sequences-deque-imul-maxlen-memoryerror | P4 | fast-slow-path-mismatch | deque *= n / deque * n raise MemoryError for a bounded deque of 2+ items although the result has at most maxlen items |
| sequences-insert-huge-index-vs-slice | P4 | doc-violation | list.insert(i, x) raises OverflowError for /i/ >= 2**63 although it is documented as equivalent to s[i:i] = [x], which clips |
| strsearch-empty-sub-past-slice-end | P4 | doc-mismatch | find/count/startswith with an empty substring disagree with the same call on s[start:end] when start lies past end |
| textlibs-base64-decode-per-line | P4 | twin-disagreement | base64.decode raises on input that base64.decodebytes accepts, when a group spans a line break |
| textlibs-binascii-alphabet-cache-subclass-key | P4 | wrong-result | binascii: the reverse-table cache is keyed by the alphabet object, so a bytes subclass can get another alphabet's table |
| textlibs-binascii-base32-ignored-pad-counts | P4 | spec-violation | binascii.a2b_base32: with '=' in ignorechars, an ignored '=' before data still counts as padding |
| textlibs-csv-dialect-subclass-reinit | P4 | wrong-result | csv.reader, csv.writer and register_dialect run a _csv.Dialect subclass's __init__ again, with the instance as its argument |
| textlibs-csv-lineterminator-null | P4 | invariant-violation | _csv.Dialect.lineterminator returns NULL with no exception on a half-built instance |
| textlibs-csv-round-trip-documented-limits | P4 | documented-limitation | NOT FOR FILING: the csv round trip does not hold past two documented limits |
| textlibs-email-mime-version-nondecimal-digit | P4 | crash | email: MIME-Version '²' raises ValueError from int() in parse_mime_version (duplicate of gh-158708) |
| textlibs-email-ptext-had-qp | P4 | wrong-defect | email: _get_ptext_to_endchars sets had_qp only for '\\\\', so get_dtext misses the obsolete quoted-pair defect for '[a\\b]' |
| textlibs-email-quoted-string-reparse | P4 | round-trip | email: str() of a quoted string drops the quoted pair that kept '=?...?=' literal, so reparsing decodes it |
| textlibs-email-section-nondecimal-digit | P4 | crash | email: RFC 2231 section number '²' raises ValueError from int() in get_section (duplicate of gh-87112) |
| textlibs-html-parser-entity-chunking | P4 | twin-disagreement | HTMLParser with convert_charrefs=False reports a different entity name depending on where the feed splits |
| textlibs-path-join-pathlike-error | P4 | wrong-error | os.path.join calls an os.PathLike object not a path, and hides what __fspath__ raised |
| textlibs-plist-binary-negative-zero | P4 | wrong-result | plistlib: the binary writer turns -0.0 into 0.0 when 0.0 was written first |
| textlibs-quopri-mixed-line-ends | P4 | wrong-result | DUPLICATE of #64320: b2a_qp rewrites line ends, so mixed text does not round-trip |
| textlibs-quopri-py-soft-break-escape | P4 | wrong-result | DUPLICATE of #158739 (closed, not planned): quopri's pure-Python encoder splits =XY at a soft break |
| textlibs-quopri-twins-disagree | P4 | twin-disagreement | DUPLICATE of #62222 and #60677: quopri's pure-Python bodies differ from binascii |
| textlibs-re-conditional-stale-end-mark | P4 | wrong-result | re: a conditional inside the group it tests sees the end mark of a failed path |
| textlibs-re-int-digit-limit | P4 | wrong-exception | re: a number past the int/str digit limit raises a bare ValueError instead of the error a smaller number gets |
| textlibs-re-scanner-drops-flags | P4 | wrong-result | re.Scanner compiles str phrases without UNICODE and ignores their inline flags |
| textlibs-shlex-quote-false-objects | P4 | wrong-result | DUPLICATE of #149280: shlex.quote returns '' for any false object, past its own type check |
| textlibs-struct-native-float-snan | P4 | internal-inconsistency | struct: unpack quiets a signalling NaN in some modes and preserves it in others |
| textlibs-struct-void-p-index-overflow | P4 | internal-inconsistency | struct: 'P' lets OverflowError escape for __index__ objects but raises struct.error for the equal int |
| textlibs-textwrap-indent-over-width | P4 | doc-bug | DUPLICATE of bugforge textwrap-c1: lines exceed width when an indent leaves no room |
| textlibs-textwrap-placeholder-check-first | P4 | wrong-exception | DUPLICATE of #160043: textwrap.shorten raises for text that fits, when the placeholder does not |
| textlibs-urllib-nofrag-slash | P4 | wrong-result | urlunsplit(urlsplit(u, allow_fragments=False, missing_as_none=True)) inserts a '/' before a '#' path |
| typeobj-exc-memoryerror-freelist-state | P4 | state-leak | MemoryError freelist keeps __suppress_context__ from the previous object and drops __new__ arguments |
| typeobj-exc-nameerror-name-not-pickled | P4 | self-inconsistency | NameError.name is lost by pickle and copy, unlike AttributeError.name and ImportError.name |
| typeobj-structseq-inittype2-dangling-members | P4 | memory-safety | PyStructSequence_InitType2 frees tp_members after PyType_Ready has created the member descriptors, so a failure leaves the (immortal, sometimes ready) type with |
| typeobj-structseq-negative-size-no-exception | P4 | missing-error-check | A negative n_fields, n_sequence_fields or n_unnamed_fields makes PyStructSequence_New, the constructor, __reduce__ and __replace__ return NULL with no exception |
| typeobj-structseq-newtype-nseq-past-fields | P4 | validation-order | PyStructSequence_NewType and PyStructSequence_InitType2 do not validate their desc: n_in_sequence = #fields + 4 (InitType2: + 1 to + 4) reads past the field arr |
| typeobj-too-many-positional-negative-bound | P4 | wrong-message | TypeError for too many arguments can report a negative minimum: 'takes from -2 to 1 positional arguments' |
| unicodeobj-codecs-normalize-encoding-nul | P4 | regression | encodings.normalize_encoding drops everything after an embedded NUL since 3.15 ('utf\\x008' gives 'utf') |
| unicodeobj-format-frac-separator-unchecked | P4 | missing-validation | A separator after the precision is silently ignored by str and the integer types, which refuse it after the width |
| unicodeobj-format-grouping-width-loop | P4 | hang | format(1, '0<huge>,') spins in an uninterruptible loop proportional to the width before it can raise MemoryError |
| unicodeobj-format-nul-type | P4 | twin-divergence | format(float/complex, spec) accepts a literal NUL as the presentation type, unlike int, str, Fraction and _pydecimal |
| unicodeobj-text-dedent-isspace-blank-lines | P4 | twin-mismatch | python -c does not dedent when a blank line holds \\r or \\f, unlike the textwrap.dedent it is documented to match |
| unicodeobj-writer-rollback-noncanonical | P4 | invariant-violation | A failed PyUnicodeWriter_WriteUTF8 leaves the buffer widened, and Finish returns a non-canonical str |
| accel-heapq-heapify-order-raising | P5 | twin-divergence | heapq: above 2500 items C heapify compares in a different order, so a raising comparison gives a different exception than Python (and than 2500 items) |
| accel-heapq-list-subclass-overrides | P5 | twin-divergence | heapq: _heapq ignores a list subclass's overridden methods and rejects non-lists, while heapq.py honours and accepts them |
| accel-heapq-merge-staticmethod-next | P5 | uncaught-exception | heapq.merge raises AttributeError for a valid iterator whose __next__ is a staticmethod, once it is the last input left |
| accel-heapq-merge-swallows-stopiteration | P5 | wrong-result | heapq.merge: a StopIteration raised by the key (or by __lt__) is taken for an exhausted input, which is silently dropped |
| bytesobj-bytearray-size-null-doc | P5 | doc-mismatch | Docs say PyByteArray_Size checks for a NULL pointer; the body only asserts, so NULL crashes a release build |
| bytesobj-format-int-fast-slow-int-max | P5 | inconsistency | b'%x' % n succeeds but b'%5x' % n raises 'string too large in _PyUnicode_FormatLong' once the text passes INT_MAX |
| bytesobj-seq-repeat-specialized-overflow-message | P5 | wrong-exception | bytes, tuple and str times a huge int change their OverflowError message once the BINARY_OP site is specialized |
| calstat-statistics-from-samples-not-fmean-stdev | P5 | documentation | NormalDist.from_samples is documented as using fmean() and stdev() but uses neither |
| corelibs-asyncgenerator-aclose-message | P5 | twin-mismatch | collections.abc.AsyncGenerator.aclose says 'asynchronous generator ignored GeneratorExit', builtin aclose() says 'async generator ignored GeneratorExit' |
| corelibs-callable-reduce-nested-list | P5 | round-trip | collections.abc.Callable[[[int]], str] does not survive copy or pickle: __reduce__ skips the re-listing for a list first argument |
| corelibs-count-elements-twins | P5 | twin-mismatch | _count_elements: the C fast path ignores an instance `get` and reports unhashable elements without the dict message |
| corelibs-enum-verify-name-first | P5 | validation-order | verify(...)(x) reads x.__name__ before its type check, so a non-class gets AttributeError or issubclass's TypeError, not verify's |
| corelibs-operator-length-hint-descriptor | P5 | twin-mismatch | operator.length_hint twins bind __length_hint__ differently: a staticmethod or a property gives the hint in C and the default in Python |
| corelibs-operator-twin-lookups | P5 | twin-mismatch | operator twins differ where the pure twin does a Python-level lookup: index on an int subclass, length_hint on a metaclass and with a bool default, methodcaller |
| corelibs-operator-twin-str-subclass | P5 | twin-mismatch | operator twins differ on str-subclass names: attrgetter looks up and prints a different object, and methodcaller reprs its name at the other end |
| corelibs-warnings-show-sysmodules-none | P5 | twin-divergence | With sys.modules['warnings'] = None, C warnings bypass catch_warnings(record=True) and print to stderr |
| corelibs-weakref-wvd-pop-arity | P5 | api-inconsistency | WeakValueDictionary.pop accepts any number of defaults and silently uses the first |
| datetime-ctor-fold-overflow-class | P5 | twin-mismatch | time() and datetime() raise OverflowError in C and ValueError in Python for fold outside C int |
| datetime-date-pickle-test-month-none | P5 | twin-mismatch | date(state, None) unpickles in _pydatetime and is a TypeError in C |
| datetime-pydatetime-isoformat-int-sep | P5 | twin-mismatch | _pydatetime's datetime.isoformat accepts an int sep ('%c' % sep), C requires a one-character str |
| datetime-pydatetime-mktime-leap-second | P5 | twin-mismatch | In a leap-second time zone, _pydatetime's naive timestamp()/astimezone() raise ValueError where C returns a value |
| datetime-pydatetime-reduce-dispatches-reduce-ex | P5 | twin-mismatch | time/datetime.__reduce__(): _pydatetime calls self.__reduce_ex__(2), so a subclass override runs; C does not look it up |
| datetime-pydatetime-replace-fold-keyword | P5 | twin-mismatch | _pydatetime replace() always passes fold= to a subclass constructor; C passes it only when nonzero |
| datetime-pydatetime-rsub-negate-overflow | P5 | twin-mismatch | _pydatetime timedelta.__rsub__ negates first and overflows where C does not |
| datetime-pydatetime-tzinfo-reduce-truthiness | P5 | twin-mismatch | _pydatetime's tzinfo.__reduce__ tests __getinitargs__ for truth; C calls whatever it finds |
| datetime-repr-fold-tzinfo-order | P5 | twin-mismatch | repr(datetime) with fold=1 and a tzinfo: C prints fold before tzinfo, _pydatetime after |
| datetime-repr-qualname-vs-tp-name | P5 | twin-mismatch | repr of a nested date subclass: _pydatetime prints __qualname__, C prints tp_name |
| datetime-strftime-ignores-utcoffset-override | P5 | twin-mismatch | strftime %z/%:z/%Z: _pydatetime calls a subclass's utcoffset()/tzname() override, C reads the tzinfo member |
| datetime-timedelta-float-ratio-not-tuple | P5 | twin-mismatch | timedelta * float subclass: _pydatetime unpacks any as_integer_ratio() result, C demands a 2-tuple of ints |
| datetime-timespec-non-str-class | P5 | twin-mismatch | isoformat(timespec=...) refuses non-str, NUL and surrogate timespecs differently in _pydatetime and C |
| dictset-set-hash-failure-mutates | P5 | documented-limitation | NOT FOR FILING: a failed hash does not leave a set unchanged when __hash__ changed it first |
| ipaddress-mask-rule-hostmask-first-field | P5 | doc-mismatch | ipaddress: a dotted mask starting with a non-zero field is accepted as a hostmask, against the documented rule |
| json-encoder-call-indent-level | P5 | twin-mismatch | json: c_make_encoder(...)(o, level) builds the indent for `level` before encoding, so a scalar fails at a huge level where _make_iterencode returns |
| json-encoder-flag-truth-twins | P5 | twin-mismatch | json: a sort_keys, skipkeys or allow_nan whose __bool__ raises fails every C encode, but only the Python encode that reads it |
| mathint-cmath-isclose-nan-inf-tol | P5 | doc-mismatch | cmath.isclose calls a number with a NaN part close when the other part's difference overflows and a tolerance is infinite |
| pygrammar-async-with-type-comment | P5 | sibling-mismatch | With type_comments=True, a parenthesized `async with` followed by a type comment is a SyntaxError or parses as one tuple item; the gh-111420 fix covered only `w |
| pygrammar-genexp-star-precedence | P5 | grammar-inconsistency | PEP 798: `(*a or b for x in y)` parses but `[*a or b for x in y]` and `{*a or b for x in y}` are SyntaxErrors; the reference says generator expressions have lis |
| pygrammar-import-as-name-target | P5 | diagnostic | `import a as b <anything but , ) ; NEWLINE>` says 'cannot use name as import target' about the valid target `b` (duplicate of gh-146492) |
| pygrammar-lazy-import-diagnostics | P5 | diagnostic | `lazy import` with no names, or `lazy import a.b from c`, gets 'invalid syntax' instead of the messages `import` gets |
| pygrammar-tstring-format-spec-fstring-message | P5 | diagnostic | A malformed replacement field nested in a t-string's format spec is reported as an 'f-string:' error |
| sequences-deque-extend-reinit-maxlen | P5 | reentrancy | deque.extend/extendleft keep applying the old maxlen after the iterator re-initialises the deque, leaving len(d) > d.maxlen for good |
| sequences-dequeiter-new-ignores-kwargs | P5 | argument-validation | type(iter(deque))() and type(reversed(deque))() silently ignore keyword arguments |
| textlibs-plist-deep-nesting-recursion | P5 | documented-limitation | NOT FOR FILING: plistlib reads binary plists only as deeply nested as the recursion limit allows |
| textlibs-struct-cache-str-subclass-key | P5 | wrong-result | struct: a str-subclass format poisons the module cache, so later plain formats get another format's Struct |
| textlibs-struct-pack-into-alias | P5 | wrong-result | struct: pack_into('4s', ba, 0, ba) writes zeros: the argument is read after the memset of its target |
| textlibs-struct-std-longlong-index-overflow | P5 | internal-inconsistency | struct: '>q'/'>Q' let an OverflowError from __index__ escape where '<q'/'<Q' raise struct.error |
| textlibs-toml-escape-eof-pos | P5 | doc-mismatch | tomllib: TOMLDecodeError.pos is one past the end of the document for a trailing backslash in a basic string |
| textlibs-toml-nesting-recursion-limit | P5 | documented-limitation | NOT FOR FILING: tomllib parses nested arrays only as deep as the recursion limit allows |
| typeobj-structseq-twin-offset-member-names | P5 | twin-mismatch | A struct sequence field named __dictoffset__, __weaklistoffset__ or __vectorcalloffset__ makes PyStructSequence_NewType raise SystemError, while PyStructSequenc |
| unicodeobj-codec-charmap-build-fffe | P5 | twin-mismatch | codecs.charmap_build maps U+FFFE in its dict branch, though the trie branch treats it as unmapped |
| unicodeobj-codecs-getencoder-raw-tuple | P5 | twin-mismatch | codecs.getencoder and friends raise AttributeError for a codec registered as a plain 4-tuple, where codecs.encode and the C API work |
| unicodeobj-codecs-reraise-subclasscheck | P5 | scope-record | strict and the surrogate handlers raise what a metaclass __subclasscheck__ raises (scope record, not a bug) |
| unicodeobj-codecs-surrogate-handlers-systemerror | P5 | internal-error | surrogateescape and surrogatepass raise SystemError on a UnicodeError subclass that lacks the exception flag |
| unicodeobj-codec-surrogateescape-error-span | P5 | twin-mismatch | surrogateescape reports a different error span inline than through the callback path |
| unicodeobj-format-nul-conversion | P5 | validation | str.format accepts a NUL as a conversion and treats it as no conversion |
| unicodeobj-format-nul-presentation-type | P5 | validation | format(1.5, '\\x00') succeeds: float and complex take an explicit NUL for 'no presentation type' |
| unicodeobj-text-final-sigma-cased-ignorable | P5 | doc-mismatch | str.lower() picks the wrong sigma next to characters that are both cased and case-ignorable |
| unicodeobj-text-translate-stateful-table | P5 | twin-mismatch | str.translate looks a table up a different number of times on ASCII and non-ASCII strings |
