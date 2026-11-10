# Formalizing CPython (blog post, full text)

> Source: https://broyojo.com/python-formalization/
> Collected: 2026-11-10
> Published: 2026-11-09

Note: converted from HTML (identical to docs/index.html in the repo, commit 17bf78a9 per page footer). The hero side-by-side code block lost its line breaks in conversion; interactive charts are reduced to their text labels.

David Andrews

# Formalizing CPython

AI agents wrote 613,318 lines of Lean that copy Python's internals line by line, tested every piece against the real Python, had a computer check every proof, and turned up 418 bug reports in Python along the way.

David Andrews (https://broyojo.com/) and Chao Zhang (https://chaozhang.org/)9 November 2026Code and data (https://github.com/Broyojo/python-formalization)

CPython · Objects/rangeobject.c

```
static unsigned longget_len_of_range(long lo, long hi, long step){    assert(step != 0);    if (step > 0 && lo < hi)        return 1UL + (hi - 1UL - lo) / step;    else if (step < 0 && lo > hi)        return 1UL + (lo - 1UL - hi) / (0UL - step);    else        return 0UL;}
```

Lean copy · RangeSlice/Model.lean

```
def getLenOfRange (lo hi step : Int) : Int :=  if step > 0 ∧ lo < hi then    uadd 1 (usub (usub (toU hi) 1) (toU lo) / toU step)  else if step < 0 ∧ lo > hi then    uadd 1 (usub (usub (toU lo) 1) (toU hi)              / usub 0 (toU step))  else 0 -- step ≠ 0 is assumed by every proof-- uadd, usub: C's unsigned arithmetic,-- which wraps around past 2^64
```
A function from CPython's C source (left) and the Lean copy an agent wrote of it (right). Hover over a line to see its counterpart.

## TL;DR
- We pointed Opus 5.5 at CPython, the program that runs almost all Python code, and had it rewrite its functions in Lean (https://lean-lang.org), a language for writing machine-checked proofs.
- Each rewrite copies the original line by line and is tested against real Python on tens of thousands of inputs before anyone tries to prove anything about it.
- A function only counts once a second agent, which didn't write it, checks the work and agrees it holds up. 4,071 functions have passed that check so far.
- The result is 613,318 lines of Lean across 1,539 files, with 18,898 theorems and lemmas, all checked by Lean's proof checker on every build.
- Along the way the proofs turned up 418 bug reports. Most are small, but about 55 can crash the interpreter or corrupt memory from ordinary Python code.

Checked and acceptedWritten, not yet acceptedNot started
- All of CPython16%
- Interpreter core10%
- Built-in types35%
- C modules19%
- Parser31%
- Grammar rules100%
- Standard library9%How much of each part of CPython 3.15.2 has been copied, tested, proved and accepted by review. Code with nothing to check, such as memory bookkeeping, is left out.

## Why bother

Python doesn't have a precise written definition. There is a reference manual, but in practice "Python" means whatever CPython does, and CPython is hundreds of thousands of lines of C plus a large standard library. The manual covers normal use. It says little about the odd cases, and that's where bugs hide: an object that changes a dictionary while that dictionary is searching for it, an error thrown halfway through an update, a number one past the largest the C code was written for.

Writing a proof about a function forces you to say exactly what it does in all of those cases. You can't leave anything vague, because the proof checker won't accept it. That makes proofs a good way to find the places where the code doesn't do what everyone assumes.

We wanted to see how far this goes on a code base as large and old as CPython, and whether the results stay trustworthy when most of the work is done by AI.

## How it works

Every function goes through the same four steps.

- CopyRewrite the function in Lean, following the original code line by line, including its error messages and its odd corners.
- TestRun the copy and the real Python side by side on at least 50,000 tricky inputs. Any disagreement means the copy is wrong.
- ProveState something that should always be true and have the computer check the proof. If it's actually false, prove that instead.
- CheckA second agent that didn't do the work reviews it against the original and tries to break it. Only what survives counts.

The code at the top of this page is step one for a small piece of CPython: the C function that works out how many numbers are in a `range`, next to its Lean copy. The copy keeps the C code's exact arithmetic, including how its numbers wrap around when they get too big. The proof about it shows that this function, the slower version CPython uses for very large numbers, and the code that chooses between them always give the same, correct count.

## Proofs that prove nothing

The hardest part wasn't getting AI agents to write proofs. It was getting proofs that actually mean something.

Our first attempt asked the agents for breadth: copy every function and prove at least one thing about each. They did. Then a separate review found that fewer than half of the functions it checked held up, and in one file only 21%. The proofs were all correct. They just didn't say anything useful. For example, "if this function returns a number, the number is at least zero" is true, but a function that always crashes also satisfies it.

So the reviewer now asks one question about every proof: could a broken version of the function pass it too?

| Version of the function | "If it returns, the answer is ≥ 0" | "It always returns the right count" |
| The real one | passes | passes |
| Always crashes | passes | caught |
| Returns 0 for very large numbers | passes | caught |
| Off by one when counting down | passes | caught | Two true statements about the same function. The first one lets every broken version through, so a function whose only proof looks like it doesn't count.

Fixing a weak proof usually means going back and making the copy more realistic, for example letting a user's code throw an error in the middle of a function. The charts below show how that went for ten files. Each point is one round of review. The lines sometimes go down: when a reviewer finds that an accepted proof is wrong about real Python, everything that relied on it is taken back out.

Functions accepted

`Objects/typeobject.c`135 of 142 accepted · 5 reviews

`Objects/genobject.c`56 of 56 accepted · 5 reviews

`Objects/setobject.c`46 of 46 accepted · 7 reviews

`Modules/_json.c`45 of 48 accepted · 5 reviews

`Lib/enum.py`37 of 39 accepted · 9 reviews

`Lib/random.py`37 of 38 accepted · 3 reviews

`Objects/abstract.c`41 of 43 accepted · 2 reviews

`Objects/rangeobject.c`33 of 33 accepted · 2 reviews

`Lib/pickletools.py`31 of 33 accepted · 2 reviews

`Modules/binascii.c`35 of 40 accepted · 2 reviews

Rounds of review →Share of each file's reviewed functions accepted after each round of review, taken from the project's history. Each point is one review; the scale is the same in every chart, from 0% to all of the functions reviewed in that file. Accepted functions include ones the reviewer confirmed have nothing to check, such as memory bookkeeping.

## When a correct proof is wrong anyway

A checked proof guarantees that a statement follows from the copy. It doesn't guarantee the copy matches real Python, and testing only covers the inputs you thought to try. So every accepted statement is also run against real Python. That caught several proofs that were valid and still wrong.

### The 16-terabyte string

The copy of Python's fast JSON encoder assumed memory requests always succeed. So it "proved" the encoder could build its indentation strings for any nesting depth, including one that needs 16 terabytes of memory. Real Python runs out of memory. The fixed copy now treats every memory request as something that can fail.

### Nine extra steps, just once

A proof said Python's pickle module never goes deeper than a certain number of nested calls. That turned out true except in a brand-new Python process. There, the first time it encodes a string, it quietly loads a text codec, and that load uses nine more nested calls. Our tests never saw it, because the test harness had already loaded the codec.

### Error types have families

In Python, catching a `TypeError` also catches any more specific error built on top of it. Three separate copies checked an error's exact name instead. All three had proofs that a custom error type could break.

### Memory that comes back

The copy of Python's `set` assumed that once memory is freed, the same address never comes back. Real memory allocators reuse addresses all the time. CPython uses a "did the address change?" check to notice when user code has swapped out the set's internals. With reuse, that check can be fooled. Fixing the copy turned an accepted proof into a real memory bug, now one of our bug reports.

## What we found

When a proof fails because Python itself is wrong, and not the copy, we write it up as a bug report. Each report includes a short script that shows the bug on Python 3.15.2 (for most, also on the development version), a search for duplicates already reported, and an honest rating of how much it matters.

- C and Python versions disagree129
- Other122
- Wrong result56
- Crash28
- Memory corruption27
- Doesn't match the docs26
- Wrong error or message18
- Missing input check12418 bug reports by type. "C and Python versions disagree" means a module has two implementations, a fast one in C and a backup in Python, and they give different answers to the same call.

Most are small: an error message that's wrong, an edge case that behaves differently from the documentation, two versions of a function that disagree. About 55 are more serious and can crash Python or corrupt its memory using nothing but normal Python code, usually by having user code change a container while C code is in the middle of using it. Python doesn't treat running hostile Python code as a security boundary, so these are ordinary bugs. The ones not already on CPython's tracker are being reported to the project, starting with this post. Six small examples of different kinds:

Crash

### A dictionary call that crashes Python

Calling `setdefault` on an object's attribute dictionary with a `StrEnum` key crashes the interpreter, if another object of the same class has that attribute and this one doesn't.

```
class Key(StrEnum):
    NAME = "name"
class User: pass
a = User(); a.name = "ada"
b = User(); b.age = 36
vars(b).setdefault(Key.NAME, "anon")
# Segmentation fault
```

Memory corruption

### An XML edit that corrupts memory

Assigning to a backwards slice of an ElementTree element should insert, as it does for a list. Instead it duplicates one child without taking a reference and loses another.

```
e = ET.Element("root")
e[:] = [ET.Element(f"a{i}") for i in range(7)]
e[5:2] = [ET.Element("X")]
[c.tag for c in e]
# 'a2' appears twice, 'a4' is gone
```

Wrong error

### An email header that breaks the parser

A Message-ID with a space inside square brackets makes Python's email parser fail with an internal error. The header comes from whoever sent the email.

```
msg = email.message_from_string(
    "Message-ID: <a@[ x]>\n\nhi\n",
    policy=policy.default)
msg["Message-ID"]
# UnboundLocalError
```

Silently wrong result

### Base32 padding that depends on position

New in Python 3.15, the base32 decoder can ignore chosen characters. If `=` is one of them, where it appears still changes the result.

```
a2b_base32(b"AAAAAAA",  ignorechars=b"=")
# Error: Incorrect padding
a2b_base32(b"AAAA=AAA", ignorechars=b"=")
# b'\x00\x00\x00\x00'
```

Missing error

### An enum error that disappears

Giving an enum value to a second member should raise an error. If the class's `__repr__` is broken, the error is swallowed and the call quietly does nothing.

```
class W(Enum):
    A = 1; B = 2
    def __repr__(self): return 5
W.B._add_value_alias_(3)
W.A._add_value_alias_(3)  # returns None
```

C and Python disagree

### Two picklers, two limits

Python has a C pickler and a pure-Python one. They give up at different nesting depths. This difference was first reported in 2008 and is still open.

```
v = []
for _ in range(400): v = [v]
pickle.dumps(v, 5)    # works
pickle._dumps(v, 5)   # RecursionError
```

Every report, with its script, is in the repository (https://github.com/Broyojo/python-formalization/tree/main/bugs).

## Do this for your own project

None of this is specific to Python. It works for anything with source code you can read and a working version you can run: another language, a library, a file format, a compiler. What made the difference for us:
- Pick one exact version and stick to it. Every copy points at specific lines in that version.
- List everything first. Count progress against the full list, so nothing gets skipped quietly.
- Copy the code, not the documentation. A copy written from the docs agrees with the docs, and the bugs are where the code and the docs disagree.
- Let user code misbehave. Model callbacks that throw errors or change things mid-operation. That's where the worst bugs were.
- Test before you prove. Proving things about a wrong copy wastes time.
- When something is false, keep the counterexample. Don't water the statement down until it becomes provable.
- Check proved statements against the real thing. A valid proof about a wrong copy is the most misleading result you can get.
- Count only what an independent reviewer accepts, and have that reviewer ask whether a broken version would pass.

The instructions our agents worked from are in the repository and meant to be reused: AGENTS.md (https://github.com/Broyojo/python-formalization/blob/main/AGENTS.md) for the agents doing the work, REVIEW_PROMPT.md (https://github.com/Broyojo/python-formalization/blob/main/coverage/REVIEW_PROMPT.md) for the reviewers, and the full list of functions with their status in coverage/methods (https://github.com/Broyojo/python-formalization/tree/main/coverage/methods).

## Related work

The closest project is julia-in-lean, which did this for the Julia language and directly inspired this one1. It modelled Julia's standard library in Lean, tested the models against Julia, recorded about 400 bugs and filed 75. Its finding that 128 of 130 quick proofs had quietly assumed away the hard case shaped our review rules. A recent paper models NVIDIA's PTX GPU instruction set in Lean to prove GPU kernels correct2, building on earlier formal work on PTX's memory model3.

For Python specifically, λπ4 and a K framework semantics of Python 3.35 described the language mathematically; this project copies CPython's actual code instead. Similar efforts exist for JavaScript6,7 and WebAssembly8, and CompCert9 and seL410 remain the high bar for fully verified software. Comparing two implementations on the same inputs, the testing half of this project, goes back decades11,12.

## Where it stands

The project started on 29 October 2026. 4,071 of the 26,004 functions worth checking (15.7%) have been copied, tested, proved and accepted by review. The Lean code is 613,318 lines in 1,539 files, containing 18,898 theorems and lemmas; 3,834 of the top-level properties are proved and 588 are proved false with a counterexample. Most of Python is still ahead, especially the large part of the standard library written in Python itself. Multithreading is out of scope for now. In these 57 files, every function copied so far has passed review. The 30 with the most accepted functions:
- `Python/bytecodes.c`310
- `Grammar/python.gram`278
- `Lib/collections/__init__.py`184
- `Lib/_pydecimal.py`160
- `Lib/_pydatetime.py`150
- `Modules/_struct.c`122
- `Objects/longobject.c`119
- `Objects/listobject.c`114
- `Objects/memoryobject.c`107
- `Objects/dictobject.c`104
- `Objects/bytesobject.c`100
- `Objects/exceptions.c`97
- `Objects/unicodeobject.c`94
- `Objects/bytearrayobject.c`93
- `Modules/arraymodule.c`84
- `Lib/_collections_abc.py`81
- `Modules/_operator.c`73
- `Modules/itertoolsmodule.c`72
- `Modules/_collectionsmodule.c`64
- `Python/codecs.c`61
- `Lib/operator.py`59
- `Lib/_pyio.py`58
- `Objects/typeobject.c`57
- `Lib/weakref.py`54
- `Objects/genobject.c`46
- `Lib/urllib/parse.py`46
- `Parser/action_helpers.c`43
- `Modules/_zoneinfo.c`43
- `Objects/floatobject.c`38
- `Objects/tupleobject.c`37

The project is open, and help is welcome. Most of CPython is still unmodelled: pick a file whose functions are still marked `todo` in `coverage/methods`, follow `AGENTS.md`, and send a pull request. Independent reviews of existing work count as much as new models. See CONTRIBUTING.md (https://github.com/Broyojo/python-formalization/blob/main/CONTRIBUTING.md).

## Cite

```
@misc{andrews2026formalizing,
  author       = {Andrews, David and Zhang, Chao},
  title        = {Formalizing {CPython}: A Lean Model of {CPython} 3.15.2},
  year         = {2026},
  howpublished = {\url{https://broyojo.com/python-formalization/}},
  note         = {Code: \url{https://github.com/Broyojo/python-formalization}}
}
```

## References
- M. Cranmer. Formalizing Julia in Lean (and finding 400+ bugs in Base) (https://discourse.julialang.org/t/formalizing-julia-in-lean-and-finding-400-bugs-in-base/140243). Julia Discourse, 2026. Code: MilesCranmer/julia-in-lean (https://github.com/MilesCranmer/julia-in-lean).
- L. Koska, T. Koska, B. Koska. Formalizing PTX in Lean to Prove GPU Kernel Correctness (https://arxiv.org/abs/2611.04447). arXiv:2611.04447, 2026.
- D. Lustig, S. Sahasrabuddhe, O. Giroux. A Formal Analysis of the NVIDIA PTX Memory Consistency Model (https://doi.org/10.1145/3297858.3304043). ASPLOS 2019.
- J. G. Politz, A. Martinez, M. Milano, S. Warren, D. Patterson, J. Li, A. Chitipothu, S. Krishnamurthi. Python: The Full Monty. A Tested Semantics for the Python Programming Language (https://doi.org/10.1145/2509136.2509536). OOPSLA 2013.
- D. Guth. A Formal Semantics of Python 3.3 (https://ideals.illinois.edu/items/45257). M.S. thesis, University of Illinois at Urbana-Champaign, 2013. Code: runtimeverification/python-semantics (https://github.com/runtimeverification/python-semantics).
- M. Bodin, A. Charguéraud, D. Filaretti, P. Gardner, S. Maffeis, D. Naudziuniene, A. Schmitt, G. Smith. A Trusted Mechanised JavaScript Specification (https://doi.org/10.1145/2535838.2535876). POPL 2014.
- D. Park, A. Ştefănescu, G. Roşu. KJS: A Complete Formal Semantics of JavaScript (https://doi.org/10.1145/2737924.2737991). PLDI 2015.
- C. Watt. Mechanising and Verifying the WebAssembly Specification (https://doi.org/10.1145/3167082). CPP 2018.
- X. Leroy. Formal Verification of a Realistic Compiler (https://doi.org/10.1145/1538788.1538814). Communications of the ACM 52(7), 2009.
- G. Klein, K. Elphinstone, G. Heiser, J. Andronick, et al. seL4: Formal Verification of an OS Kernel (https://doi.org/10.1145/1629575.1629596). SOSP 2009.
- W. M. McKeeman. Differential Testing for Software. Digital Technical Journal 10(1):100–107, 1998.
- X. Yang, Y. Chen, E. Eide, J. Regehr. Finding and Understanding Bugs in C Compilers (https://doi.org/10.1145/1993498.1993532). PLDI 2011.Every number and chart on this page is generated from the project's repository (commit `17bf78a9`).
