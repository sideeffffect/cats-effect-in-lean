# Asynchronous Exceptions in Haskell (Marlow, Peyton Jones, Moran, Reppy; PLDI 2001) - text extracted from PDF

> Source: https://www.microsoft.com/en-us/research/wp-content/uploads/2016/07/asynch-exns.pdf
> Collected: 2026-11-10
> Published: 2001-06

_Text extracted with pdftotext (two-column layout; formulas of Fig. 4/5 are garbled by extraction). Kept first ~40 KB verbatim._

Asynchronous Exceptions in Haskell
Simon Marlow and Simon Peyton Jones
Microsoft Research, Cambridge

Andrew Moran
Oregon Graduate Institute

John Reppy
Bell Labs, Lucent Technologies

December 12, 2006
signalling must necessarily be truly asynchronous in
purely-functional languages like Concurrent Haskell.

Abstract
Asynchronous exceptions, such as timeouts, are important
for robust, modular programs, but are extremely difficult to
program with — so much so that most programming languages either heavily restrict them or ban them altogether.
We extend our earlier work, in which we added synchronous
exceptions to Haskell, to support asynchronous exceptions
too. Our design introduces scoped combinators for blocking
and unblocking asynchronous interrupts, along with a somewhat surprising semantics for operations that can suspend.
Uniquely, we also give a formal semantics for our system.
1

• We propose an extension to Concurrent Haskell that
supports asynchronous delivery of exceptions between
threads (Section 5). This mechanism allows one thread
to terminate another.
• Motivated by some subtle race conditions, we introduce a control mechanism for postponing the delivery
of asynchronous exceptions, based around two scoped
combinators, block and unblock (Section 5.1). It is
also necessary to allow indefinitely blocking operations
to be interrupted, we show how these mechanisms enable us to acquire and release locks safely in the presence of asynchronous exceptions (Section 5.3).

Introduction

An important goal of language design is to support modularity. For concurrent languages, this goal means language
support for localizing synchronization issues and support for
composing components without interference. One concurrent language feature that appears to be the antithesis of
modularity is the asynchronous signaling (or killing) of one
thread by another. Since, by definition, such signaling can
occur at any point in the target thread’s execution, locks
held by the target may not be properly released and invariants may not be maintained. For these reasons, few
concurrent languages or thread libraries support truly asynchronous signalling, and those that do have discouraged its
use.
There are situations, however, where allowing a thread
to asynchronously signal another thread is extremely useful.
For example, we might wish to provide a timeout operator
that limits the execution time of a computation or we might
wish to run two different computations in parallel taking
the first result and terminating the other. In this paper, we
present an extension to Concurrent Haskell [11] that supports true asynchronous signalling in a robust, modular way.
The principal contributions of the paper are as follows:
• We explain why a fully-asynchronous signalling is both
useful (as opposed to semi-asynchronous signalling)
and feasible (Section 2). In fact, while imperative
languages often use polling to implement a semiasynchronous signalling mechanism, we explain that

In Proc ACM Conference on Programming Languages
Design and Implementation, 2001.

• We give an operational semantics for Concurrent
Haskell (Section 6) and extend it with asynchronous
exceptions (Section 6.3). A precise specification of exactly what asynchronous exceptions do is crucial for
both programmers and implementors: asynchronous
exceptions are subtle beasts. We believe that this is
the first formalization of an asynchronous exception or
interrupt mechanism.
In addition, we give the definitions of some useful combinators built on top of the low-level exception primitives,
including a composable timeout combinator (Sections 7.4
and 7); and we outline an implementation of asynchronous
exceptions and the associated primitive operations (Section
8).
2

Asynchronous exceptions

Many high-level languages provide exceptions as a way to
support robust handling of error conditions. Errors are signaled by throwing an exception and are handled by catching the exception. When we say “exception,” we normally
mean “synchronous exception” in the sense that an exception can only be raised as a direct consequence of executing the program itself. Examples include: divide by zero,
pattern-match failure, and explicitly raising a user exception. Synchronous exceptions are relatively tractable:
• The denotation, or meaning, of an expression says
whether evaluating the expression will raise a synchronous exception and, if so, specifies the set of exceptions that may be raised. In other words, the synchronous exceptions that an expression may raise is
properly part of the semantics of that expression.

• It follows that a compiler can reasonably infer (an approximation to) the set of synchronous exceptions that
any given expression could possibly raise [18].

Concurrent Haskell. The problem is that polling a global
flag is not a functional operation, yet in a Concurrent Haskell
program, most of the time is spent in purely-functional code.
On the other hand, since there is absolutely no problem with
abandoning a purely-functional computation at any point,
asynchronous exceptions are safe in a functional setting. In
short, in a functional setting, fully-asynchronous exceptions
are both necessary and safe — whereas in an imperative context fully-asynchronous exceptions are not the only solution
and are unsafe. For these reasons, the semi-asynchronous
approach is almost universal in imperative languages.
All of the above motivations concern the premature abortion of a computation. We do not deal with resumption, in
which the interrupted computation can be resumed. We also
do not deal with killing rogue threads, since such threads can
exploit our mechanisms to ignore asynchronous exceptions.

Since exceptions already provide a control-flow mechanism for signalling and handling exceptional conditions,
it is natural to consider extending the exception handling
mechanism to include asynchronous exceptions.1 Such asynchronous exceptions are raised as the result of an “external
event,” such as a signal from another thread, and can occur at any point during execution. Since the evaluation of
any expression could yield an asynchronous exception, we
cannot sensibly consider asynchronous exceptions as part of
the semantics of the expression. This property makes asynchronous exceptions much less tractable, both semantically
and from a programmer’s standpoint, than synchronous exceptions.
Nevertheless, there are several compelling reasons to support asynchronous exceptions:

3

Input/output in Haskell

Haskell is a purely functional language with lazy semantics.
Input/output in Haskell is done using a monad; in Haskell
a value of type IO a is an “action” that, when performed,
may do some input/output before delivering a value of type
a. For example, here are two basic I/O functions2 :

Speculative computation. A parent thread might start a
child thread to compute some value speculatively; later
the parent thread might decide that it does not need
the value so it may want to kill the child thread.
Timeouts. If some computation does not complete within
a specified time budget, it should be aborted.

getChar :: IO Char
putChar :: Char -> IO ()

User interrupt. Interactive systems often need to cancel a
computation that has already been started, for example
when the user clicks on the “stop” button in a web
browser.

getChar is an I/O action that, when performed, reads a
character from the standard input, and returns it to the
program as the result of the action. putChar is a function
that takes a character and returns an action that, when
performed, prints the character on the standard output, and
returns the trivial value ().
I/O actions can be combined using the >>= operator:

Resource exhaustion. Most Haskell implementations use
a stack and heap, both of which are essentially finite
resources, so it seems reasonable to inform the program
when memory is running out, in order that it can take
remedial action. Since such exceptions can occur at
almost any program point, it is natural to treat them
as asynchronous.

(>>=) :: IO a -> (a -> IO b) -> IO b
So, for example, we can make a compound I/O action that
reads a character from standard input and writes it to standard output (\x -> e is Haskell’s notation for λx.e):

A naı̈ve approach to these problems is to provide a mechanism for one thread to kill another thread. While such a
mechanism gets the job done, it creates serious problems. If
a thread is killed while it holds a lock, how does the lock get
released? If the thread is in the process of mutating a shared
data structure, how do we reestablish the data structure’s
invariants? For these reasons, a simple kill mechanism is
unacceptable.
In practice, few concurrent languages provide any mechanism for one thread to asynchronously signal another thread.
More common are semi-asynchronous mechanisms based on
polling, where the target occasionally checks for signals; or
safe points, where the target accepts signals at certain designated points. For example,to terminate a thread we might
set a global flag, and rely on the thread to periodically check
the flag, as is done in POSIX threads, Modula-3, and Java
(Section 10 elaborates).
While the semi-asynchronous approach avoids breaking
synchronization abstractions, it is non-modular in that the
target code must be written to use the signalling mechanism.
Worse still (for us), the semi-asynchronous approach is simply incompatible with a purely-functional language, such as

getChar >>= \c -> putChar c
The action as a whole has type IO (). Haskell also provides
syntactic sugar, the do-notation, for expressing monadic
combinations. The above expression could also be written
do { c <- getChar; putChar c }
Most of the code examples in this paper will use this donotation.
For a thorough introduction to I/O in Haskell, see [?].
4

Concurrent Haskell

Concurrent Haskell [11] extends standard Haskell with a
small set of primitives for creating new threads and performing simple inter-thread communication:
forkIO
:: IO a -> IO ThreadId
myThreadId :: IO ThreadId
sleep
:: Int -> IO ()
data MVar a
-- abstract
newEmptyMVar :: IO (MVar a)

1

There are reasons why one might keep these notions distinct, but
they are orthogonal to the main points of the paper. See Section 9
for more discussion.

2

2

The notation “f :: t” means “f has type t”

putMVar
takeMVar

5.1

:: MVar a -> a -> IO ()
:: MVar a -> IO a

We now consider the issues raised by writing code in the
presence of asynchronous exceptions. An example which
illustrates a number of these issues is the use of locking to
provide concurrency control for shared mutable state. It is
important that asynchronous exceptions be handled without
leaving the shared mutable state in an internally inconsistent
state.
In Concurrent Haskell, shared mutable state is normally
represented by an MVar, which holds the value of the current
state. Any thread wishing to access the state must first take
the value from the MVar, leaving it temporarily empty, and
put the new state back in the MVar afterwards. Hence only
a single thread has access to the state at any one time.
The problem with this approach is that if an exception
is raised while the thread holds the MVar, it will be left in
an empty state, and deadlock may ensue.
To make this process safe in the presence of synchronous
exceptions is straightforward: we simply arrange that should
an exception be raised while we are building the new value
of the state, the old value is replaced in the MVar and the exception propagated to the caller. If m is the MVar in question,
and compute is an IO operation that takes the old state and
returns the new state, then the code would look like this:

throw :: Exception -> IO ()
catch :: IO a -> (Exception -> IO a) -> IO a
A new thread can be “forked” using forkIO, with the informal understanding that the IO computation passed to
forkIO may be arbitrarily interleaved with the current computation. Both cooperative and preemptive implementations of Concurrent Haskell exist. The forkIO function returns the ThreadId of the forked thread. A thread can also
obtain its own ThreadId by calling myThreadId. ThreadIds
support equality. Threads can sleep for a specified period of
time (in microseconds) by calling sleep.
MVars are a generic synchronization mechanism, similar
to the M-structures of Id [3]. A value of type MVar t can
be thought of as a box that can be in two possible states:
empty or containing a value of type t. The takeMVar operation waits if it finds the box empty, or removes and returns
its contents otherwise. The putMVar operation puts a new
value in the box, waking up any threads that were waiting
for the MVar to become full, or waits if the MVar is already
full3 . Using only MVars, many complex datatypes for concurrent communication can be built, including typed channels,
semaphores and so on [11].
A synchronous exception can be raised by throw, and
caught by catch. The computation catch M H runs M .
If M succeeds, then its result is the result of the catch. If
instead it raises an exception, the handler H is run, passing the exception raised by M . The types of throw and
catch are identical to the ioError and catch operations in
the Haskell 98 standard [?], except that we have enlarged
the IOError type to Exception, to take account of non-IO
exceptions.
5

Safe Locking

do { a <- takeMVar m;
b <- catch (compute a)
(\e -> do { putMVar m a; throw e });
putMVar m b }
This is fine for synchronous exceptions, but in the presence of asynchronous exceptions there is a race condition:
an exception can occur just after the takeMVar but before
catch, when there is no exception handler in place to restore
the state.
We could try to fix the hole by moving the catch around
the takeMVar, but this opens another race window: the
exception could occur before the takeMVar, causing the
putMVar which replaces the old state to block forever on the
still-full MVar (this is in addition to the fact that expanding
the scope of the catch around the takeMVar makes it difficult to propagate the value of the old state to the exception
handler).

Asynchronous Exceptions in Haskell

We are now ready to work on asynchronous exceptions. We
start by adding a new primitive to Concurrent Haskell to
enable one thread to asynchronously raise an exception in
another, throwTo:
throwTo :: ThreadId -> Exception -> IO ()

5.2
Informally, the meaning of throwTo t e is that the exception e is raised in thread t as soon as possible, and the call
returns immediately. In practice, the exception may not be
delivered to the target thread until some time later, perhaps
because it is running on another processor, or even another
machine. If the thread t has already died or completed, then
throwTo trivially succeeds.
Note that implementing throwTo is not as simple as it
might seem: the target thread may be blocked, perhaps on
an MVar, and will therefore have to be woken up before the
exception can be raised. The implementation of throwTo is
covered in more detail in Section 8.
Note that throwTo is the only source of asynchronous
exceptions in the system, but asynchronous interrupts from
the environment may also be converted into asynchronous
exceptions by the programmer.

Blocking exceptions

Clearly, some way to postpone the delivery of asynchronous
exceptions during critical sections is needed. The standard
method is to disable interrupts, using two operations placed
around the critical section:
block
:: IO ()
unblock :: IO ()
The idea is that executing block puts the thread into a state
in which asynchronous exceptions are blocked, and unblock
does the reverse. These combinators are still somewhat
clumsy for our purposes though, as we can see if we try
to use them to fix up the locking example:
do { block;
a <- takeMVar m;
b <- catch (do { unblock; compute a; block })
(\e -> do { putMVar m a; throw e });
putMVar m b;
unblock;
}

3
This semantics for putMVar is slightly different from that given in
[11], where putMVar on a full MVar was an error.

3

Notice that we try to unblock asynchronous exceptions for
the duration of the call to compute only. However, if an
exception is raised during compute, whether synchronous or
asynchronous, then control is passed to the exception handler with asynchronous exceptions unblocked, which opens
up another race window as there is the possibility that we
can receive another exception before replacing the contents
of the MVar. Also somewhat unsatisfactory is the fragility
of the programming model: it is all too easy to forget to
re-enable exceptions after a critical section, especially if the
control flow is complicated.
A much better approach is to use scoped combinators:

Wait a minute! Have we not just shot ourselves in the
foot? Previously block was sure protection from asynchronous interrupts, now it is not. Nevertheless, there are
several good reasons for adopting this approach:
• Having made this modification to the semantics,
takeMVar behaves atomically when enclosed in a block.
The takeMVar may receive asynchronous exceptions
right up until the point when it acquires the MVar, but
not after. Without this change, takeMVar is unsafe to
use inside block at all.
• Although it seems strange that operations inside a
block may raise asynchronous exceptions, the exceptions are synchronous in nature since we specify exactly
which operations are interruptible.

block
:: IO a -> IO a
unblock :: IO a -> IO a

The code to acquire the MVar as given above works fine
with this addition to the semantics, with the difference that
now the takeMVar operation is interruptible.
Also note the careful wording of the definition above: by
implication it states that an interruptible operation cannot
be interrupted if the resource it is attempting to acquire
is always available. Looking back at our locking example
from the previous section, even though we used putMVar,
an interruptible operation, in the exception handler, in this
case the putMVar is non-interruptible because we can be sure
the MVar is always empty.

block (do {
a <- takeMVar m;
b <- catch (unblock (compute a))
(\e -> do { putMVar m a; throw e });
putMVar m b
})
where the meaning of (block a) is “execute a in a state
where asynchronous exception delivery is blocked,” while
unblock does the reverse. The block and unblock combinators may be arbitrarily nested. There is no counting of
scopes, i.e., two nested blocks behave the same as a single
block. This is an important property from a modularity
perspective: it means that unblock always unblocks asynchronous exceptions, regardless of the context.
Notice how the scoping of block closes the race condition
in the exception handler: if an exception is received during
compute a, then we exit the scope of unblock and enter the
exception handler which is inside the blocked scope.
In practical terms, the implementation of exception handling must respect scopes. That is, it must save the current
state of the thread (blocked or unblocked) when entering
the scope of a block or unblock combinator, and restore it
again when leaving that scope, whether normally or by a
synchronous or asynchronous exception being raised.
This appears to solve our original problem: there are now
no windows of vulnerability during which the thread could
terminate with the lock still in hand. But there is a new
problem, namely that if the thread has to wait for the lock,
it now waits in a blocked state. This is in violation of one of
the cardinal rules of concurrent programming: “do not block
while holding a lock,” the reason being that it increases the
potential for deadlock. More practically, it means we cannot
time-out the thread waiting for the lock until it acquires the
lock.
5.3

6

Operational Semantics

In this section we give an operational semantics for Concurrent Haskell with exceptions,4 and then proceed to add
in our new features for asynchronous exceptions. We have
so far introduced the new constructs using informal definitions; the semantics in this section precisely specifies the
intended meanings. Our semantics is stratified in two levels: an inner denotational semantics describes the behaviour
of pure terms, while an outer monadic transition semantics
describes the behaviour of IO computations.
M and N range over terms in our language, and V ranges
over values (Figure 1). A value is a term that is considered
by the inner, purely-functional semantics to be evaluated.
The values in Figure 1 include constants and lambda abstractions, as usual, but are unusual in two ways:
• We treat the primitive monadic IO operations as values.
For example, putChar ’c’ is a value. No further work
can be done on this term in the purely-functional world;
it is time to hand it over to the outer, behavioural
semantics. In the same way, M >>= N , sleep 3, and
return M are all values.
• Many of these monadic IO values have arguments that
are not arbitrary terms (M, N , etc.), but are themselves
values (m, c, d, etc.). For example, putChar (chr 65)
is not a value, but putChar ’A’ is. It is as if putChar
is a strict data constructor. The reason for this choice
is that evaluating putChar’s argument is indeed something that can be done in the purely-functional world;
indeed, it must be done before the output operation
can take place.

Interruptible Operations

How do we take the MVar, and atomically install an exception
handler as soon as we have the MVar? Our solution is a
subtle change to the semantics of blocking operations:
Any operation which may need to wait indefinitely for a resource (e.g., takeMVar) may receive
asynchronous exceptions even within an enclosing
block, but only while the resource is unavailable.
Such operations are termed interruptible operations.

4
There exists a published operational semantics for Concurrent
Haskell [11], a denotational semantics for exceptions in Haskell [12],
and an operational semantics for exceptions in Haskell [10], but so far
no published semantics links these concepts or describes exceptions
in the IO monad.

4

Values

Terms

x, y
k
c
ch
d
e
m
t, u

∈
∈
∈
∈
∈
∈
∈
∈

Variable
Constant
Constructor
Char
Integer
Exception
MVar
ThreadId

V

::=

x | \x -> M | k | c M1 · · · Mn |
ch | d | e | m | t |
return M | M >>= N |
putChar ch | getChar |
putMVar m N | takeMVar m |
newEmptyMVar | sleep d |
throw e | catch M H |

M, N, H

::=

P |Q
P | (Q | R)
νx.νy.P
(νx.P ) | Q
νx.P

≡
≡
≡
≡
≡

Q|P
(P | Q) | R
νy.νx.P
νx.(P | Q),
νy.P [y/x],

α

α

P −
→ Q
α

(Par )

P ≡ P′

P′ −
→ Q′

P |R −
→ Q|R

(Comm)
(Assoc)
(Swap)
x∈
/ fn (Q) (Extrude )
y∈
/ fn (P )
(Alpha)

α

α

P −
→ Q

P −
→ Q
α

νx.P −
→ νx.Q
Q′ ≡ Q

(Nu)

(Equiv )

Figure 3: Structural congruence and structural transitions.

V | M N | if M then N1 else N2 | · · ·

Figure 1: The syntax of values and terms.

P, Q, R ::=
|

LM Mt

0t

In the standard way [11], we define a structural equivalence over processes, formalizing the idea of a “solution”
of processes a la the chemical abstract machine [8]. Let ≡
be the least congruence (i.e., equivalence relation preserved
by all process contexts) that also satisfies the (standard)
rules in Figure 3 and contains alpha equivalence. Rules
(Par ) and (Nu) allow transitions within parallel compositions and inside restrictions respectively. The equivalence
rules, (Comm), (Assoc) etc., say that | is associative and
commutative and that the scope of ν can be restricted or
expanded as long as it does not interfere with any existing scopes, while (Equiv ) says that we are free to use these
equivalence rules to bring parts of the program state together.

thread of computation named t
finished thread named t

|

him

empty MVar named m

|
|

hM im
νx.P

full MVar named m, holding M
restriction

|

P |Q

parallel composition

Figure 2: The syntax of program states.

6.2

Transition rules for the standard IO and concurrency operations are given in Figure 4. Transitions take place within
evaluation contexts, where an evaluation context is defined
as
E ::= [·] | E >>= M | catch E M

In the following sections, we confuse m :: MVar with the
name of that MVar, and t :: ThreadId with the name of
the thread. We also treat MVar and thread names as normal
variables (i.e., they may be bound and α-converted).
6.1

Transition Rules

That is, to find the evaluation site, repeatedly look inside
the first argument of >>= and catch. The rules in Figure 4
are standard in form, so we describe them only briefly:

Program Transitions

We give the semantics by describing how one program state
evolves into a new program state by making a transition. A
program state consists of a collection of threads and MVars
in parallel, see Figure 2.
The transition from one program state to the next may
or may not be labelled by an event, α. We write a transition
like this:
α
P −
→ Q

Sequencing of IO operations is handled by >>=. When its
left operand becomes a return, rule (Bind) passes the
returned value on to >>=’s right operand.
Input/output. The canonical IO operations are putChar
and getChar, described in (PutChar ) and (GetChar ).
Other basic I/O operations, like openFile, have analogous semantics. Rule (Sleep) deliberately underspecifies sleep. Here, the $d label represents an external
clock interrupt, indicating that d microseconds have
passed since sleep d first became blocked. A correct implementation must guarantee that at least d
microseconds have passed before a thread executing
sleep d is woken; further delay is acceptable.

The events α represent communication with the external
environment; that is, input and output. We will use just
three events:
!ch
• P −−→ Q means “program state P can move to Q,
by writing the character ch to the standard output”.
?ch
• P −−→ Q means “program state P can move to Q,
by reading the character ch from the standard input”.

MVar operations are described by rules (PutMVar ),
(TakeMVar ) and (NewMVar ). (Recall from Figure 2
that him represents an empty MVar, while hM im represents a full MVar containing M .) Note that if takeMVar

$t

• P −→ Q means “program state P can move to Q,
when an amount of time t has elapsed”.
5

LE[return N >>= M ]Mt →
− LE[M N ]Mt

(Bind)

!ch
LE[putChar ch]Mt −−→ LE[return ()]Mt

(PutChar )

?ch
LE[getChar]Mt −−→ LE[return ch]Mt

(GetChar )

$d

LE[sleep d]Mt −
−
→ LE[return ()]Mt

(Sleep)

him |LE[putMVar m M ]Mt →
− hM im |LE[return ()]Mt

hM im |LE[takeMVar m]Mt →
− him |LE[return M ]Mt
− νm.(him |LE[return m]Mt ),
LE[newEmptyMVar]Mt →
LE[forkIO M ]Mt →
− νu.(LE[return u]Mt |LM Mu ),
− LE[return t]Mt
LE[myThreadId]Mt →

(PutMVar )
m∈
/ fn (E)
u∈
/ fn (E, M )

LE[throw e >>= M ]Mt →
− LE[throw e]Mt
− LE[return M ]Mt
LE[catch (return M ) H]Mt →

(TakeMVar )
(NewMVar )
(Fork )
(ThreadId )
(Propagate )
(Catch)

LE[catch (throw e) H]Mt →
− LE[H e]Mt

(Handle)

Lreturn M Mt →
− 0t
Lthrow eMt →
− 0t

(Return GC )
(Throw GC )

− 0main
0main | P →

(Proc GC )
M :: IO a M ↑ e
(Raise)
LE[M ]Mt →
− LE[throw e]Mt

M :: IO a M 6≡ V M ⇓ V
(Eval )
LE[M ]Mt →
− LE[V ]Mt

Figure 4: Transition Rules for Concurrent Haskell (without asynchronous exceptions).

• Exceptional convergence, written M ↑ e, means that
closed term M may raise exception e.

finds an empty MVar, no transition can take place; this
is how a stuck thread is modeled in the semantics. Similarly for putMVar: when the MVar is full, the thread
cannot make any further transitions.

Apart from describing call-by-name evaluation of our language, the inner semantics also allows one to raise (but
not catch) an exception in purely-functional code, using the
function

Forking a new thread is described by rule (Fork ), while
(ThreadId ) allows a thread access to its own ThreadId.
Synchronous exceptions raised by throw are propagated
by >>= (Propagate ), and caught by catch (Catch).
Rule (Handle) explains how catch behaves when the
computation it protects succeeds.

raise :: Exception -> a
A crucial characteristic of the inner semantics is that convergence and exceptional convergence are mutually exclusive:
no term both evaluates to some value and raises an exception. Moreover, while convergence is deterministic, the exceptional convergence is not. In other words, a term may
raise many different exceptions; which it does raise when
evaluated is decided upon at run-time. This is the essence
of imprecise exceptions [12].
Given this inner semantics, rule (Eval ) “lifts” evaluation
in the inner semantics to a transition in the outer system.
(We stipulate that M 6≡ V to prevent infinite sequences
of the form V →
− V →
− V →
− · · · .) Similarly, if
the evaluation yields an exception, rule (Raise) replaces the
failing evaluation by a throw of the exception.

Termination. Rules (Return GC ) and (Throw GC ) state
that final return values and uncaught exceptions are
lost, while (Proc GC ) says that once the main thread
is finished, all other threads will eventually die.
These rules are enough if there is a value at the evaluation
site. But sometimes there is not — for example, after a use
of rule (Bind ) the evaluation site is an application, which
will not match any of the rules described so far. Of course,
we must evaluate the application M N , using the “inner”
semantics, and that is what rules (Eval ) and (Raise) are
about.
The inner operational semantics, which we do not present
here, is described in [10]. It defines two relations over terms:

6.3

• Convergence of terms is written M ⇓ V , meaning that
closed term M evaluates to value V .

Operational Semantics for Asynchronous Exceptions

We now extend the semantics to support the asynchronous
exceptions we introduced in Section 5. Firstly, we need to
6

!ch
LE[putChar ch]Mbt −−→ LE[return ()]M◦t

(PutChar )

?ch
LE[getChar]Mbt −−→ LE[return ch]M◦t

(GetChar )

$d

LE[sleep d]Mbt −
−
→ LE[return ()]M◦t

(Sleep)

LE[forkIO M ]Mt →
− νu.(LE[return u]Mt |Lunblock M Mu ),

u∈
/ fn (E, M )

− LE[return M ]Mt
LE[block (return M )]Mt →

(Fork )
(Block Return)

LE[unblock (return M )]Mt →
− LE[return M ]Mt
− LE[throw e]Mt
LE[block (throw e)]Mt →

(Unblock Return)
(Block Throw )

LE[unblock (throw e)]Mt →
− LE[throw e]Mt

(Unblock Throw )

LE[throwTo t e]Mu →
− LE[return ()]Mu | Jt eK
− LE[unblock F[throw e]]Mt ,
LE[unblock F[M ]]Mt | Jt eK →

(ThrowTo)
(Receive)

M 6≡ block N

LE[M ]M•t | Jt eK →
− LE[throw e]M◦t

(Interrupt )

LE[putChar ch]M◦t →
− LE[putChar ch]M•t

(Stuck PutChar )

− LE[getChar]M•t
LE[getChar]M◦t →
◦
− LE[sleep d]M•t
LE[sleep d]Mt →

(Stuck GetChar )
(Stuck Sleep)

him | LE[takeMVar m]M◦t →
− him | LE[takeMVar m]M•t

(Stuck TakeMVar)

− hM im | LE[putMVar m N ]M•t
hM im | LE[putMVar m N ]M◦t →

(Stuck PutMVar )

Figure 5: Transition Rules for Asynchronous Exceptions.

add new values for throwTo, block, and unblock:
V

::=

of the rules from Section 6.1 are still valid with this new
definition of E-contexts, and apply only to runnable threads.
The rules that change are discussed below.
Our new transition rules are given in Figure 5. The first
four rules are revised versions of rules from Figure 4. The
next four rules are concerned with propagating return values
and exceptions through block and unblock, and are unsurprising.
Rule (ThrowTo) describes how invoking throwTo causes
the exception to be spawned as a separate entity, with the
caller of throwTo continuing immediately.
Rule (Receive) says that any runnable thread may be interrupted by an exception targeted at its ThreadId, provided
the thread is executing in an unblocked context. Any thread
that is stuck may be interrupted, (Interrupt ), except that
the interruption is allowed in any context. As a side-effect,
the interrupted thread becomes runnable.
To express the fact that they each wait for some impetus
from the outside world, putChar, getChar, and sleep may
all immediately become stuck. (We say may since we allow a
signal from the environment will take precedence.) putMVar
will become stuck when putting to a full MVar, and takeMVar
will become stuck when trying to take from an empty MVar.

. . . | throwTo t e | block M | unblock M.

Secondly, we need to add a new form of process that represents an “exception in flight”:
P

::=

. . . | Jt eK.

Here, Jt eK represents an exception e which has been thrown
to thread t, but not yet received.
Thirdly, we need to extend our notion of evaluation context to distinguish blocked and unblocked contexts:

F
E

::=
::=

[·] | F >>= M | catch F H

F | F[block E] | F[unblock E]

The split-level evaluation context allows us to specify
whether the innermost context in a thread is block or
unblock. Thus an unblocked context is of the form

E[unblock F].
We will follow the convention that when parsing a term with
a view to matching evaluation context rules, contexts must
be maximal.
We also need to distinguish between threads that are
runnable, and those that are stuck (e.g., trying to do a
putMVar to a full MVar, or trying to take an empty MVar). We
denote runnable threads by a superscript ◦, thus: LM M◦t , and
stuck threads by a superscript •: LM M•t . We will also write
LM Mbt to mean that a thread is either runnable or stuck, but
we do not know (or care) which.
Since most of the rules concern runnable threads, we
normally elide the ◦ in the interests of reducing clutter. Most

7

Building more powerful combinators

The features introduced in Section 5.1 are expressive but
rather low-level. We do not advocate programming with
them directly; instead, we hope to build a library of robust
abstractions, layered on top of the primitives, that express
common programming patterns.

7

7.1

Bracketing abstractions

(either a b)? Does it get propagated to the child threads?
What happens if one of the child threads raises an exception?
Here is a more precise specification of the desired behaviour of (either a b):

A useful combinator is finally, which embodies the concept
of “do A, then whatever happens do B”:
finally :: IO a -> IO b -> IO a

• a and b run concurrently

A possible implementation of finally is:

• Result is (Left r) if a finishes first and returns r,
(Right r) if b finishes first and returns r, or (throw e)
if either a or b raises an exception e before one of them
returns a result.

finally a b =
block (do {
r <- catch (unblock a)
(\e -> do { b; throw e });
b;
return r; })

• If the thread executing either receives an asynchronous exception, it is propagated to both children.

Notice that the second argument to finally is executed
inside a block. This is necessary in order to guarantee that
the second argument is always executed, and using block
in this case ensures that. The behaviour is similar to that
of interrupts or Unix signals: in a signal handler, signals of
the same type are normally disabled, so that the application
has a chance to deal with the signal it has already received.
Reversing the arguments to finally yields later, which
is sometimes useful:

• The behaviour is undefined if either computation
throws an exception to the main thread.
One possible implementation uses two child threads, and
an MVar to hold the result:
data EitherRet a b = A a | B b | X Exception
either a b = do {
m <- newEmptyMVar;
block (do {
a_id <- forkIO (catch (do { r <- unblock a;
putMVar m (A r) })
(\e -> putMVar m (X e)));
b_id <- forkIO (catch (do { r <- unblock b;
putMVar m (B r) })
(\e -> putMVar m (X e)));
let loop = catch (takeMVar m)
(\e -> do { throwTo a_id e;
throwTo b_id e;
loop });
r <- loop;
throwTo a_id KillThread; throwTo b_id KillThread;
case r of {
A r -> return (Left r);
B r -> return (Right r);
X e -> throw e
} }) }

later b a = finally a b
In fact, finally is an instance of a more general combinator,
bracket:
bracket :: IO a -> (a -> IO b) -> (a -> IO c) -> IO b

bracket is useful for the class of tasks of the form “acquire
a resource, operate on it, free the resource.” We want the
resource to be freed if either the operation succeeds or raises
an exception. For example, consider opening a file:
bracket (openFile "file.tmp")
(\h -> workOnFile h)
(\h -> hClose h)
Using bracket here makes sure that the file will always be
closed, regardless of what exceptions are flying around. Furthermore, it makes sure that the openFile operation behaves atomically: it either succeeds, in which case we have
acquired the resource, or raises an exception, in which case
we have not. The implementation of bracket is a straightforward generalization of finally, above.
7.2

Note how we propagate all received exceptions to the
children until one of them has returned a result or raised an
exception.
It is important here that the throwTo calls in the main
thread are non-interruptible: we have to be sure that all
exceptions are properly propagated to the children, and also
that both children are sent the KillThread exception before
we return. If throwTo was interruptible, these properties
would be hard to guarantee (see Section 9 for a discussion
of an alternative design in which throwTo is interruptible).

Symmetric process abstractions

The forkIO primitive is asymmetric: it forks a child while
the parent continues in parallel. Here are two more symmetrical forms of forking:

7.3

either :: IO a -> IO b -> IO (Either a b)
both
:: IO a -> IO b -> IO (a,b)

Time-outs

Having either allows us to define a composable timeout
combinator:

either executes both of its arguments concurrently, and returns the result from the first one to finish; the other thread
is sent a KillThread exception. both also evaluates its arguments concurrently, but waits for them both to terminate
before returning the results in a pair.
These informal descriptions seem simple, but in the presence of asynchronous exceptions we have to be more precise
about the behaviour. For instance, what happens when
an asynchronous exception is sent to a thread executing

timeout :: Int -> IO a -> IO (Maybe a)
timeout t a = do r <- either (sleep t) a
case r of
Left _ -> Nothing
Right a -> Just a
timeouts may be arbitrarily nested, and the semantics of
either ensure that they cannot interfere with each other.
8

7.4

• Extend the per-thread data block to include the current state of asynchronous exceptions, which is either
blocked or unblocked, and a queue of pending asynchronous exceptions waiting to be delivered to the
thread.

Safe points

Sometimes we cannot use an immutable value to represent
the data structure we are interested in; perhaps it has been
passed to us across a foreign language interface, or the structure we are dealing with is large enough that creating a new
one for each operation would be too expensive (standard
Haskell does not have mutable structures, but many compilers support them as extensions). In Concurrent Haskell,
MVars are commonly used to hold an immutable value, but
they can equally well be used in a more conventional way,
as a semaphore to protect a directly mutable structure.
If an MVar is being used to protect a shared mutable data
structure, such as a mutable array, then the chances are that
we do not want to be disturbed at all while we operate on
it, because an exception received during the operation may
leave the mutable data structure in an inconsistent state.
In this case, it makes sense to omit the call to unblock
in the locking example in the previous section. But what
if compute is going to take a long time? Then we have
to explicitly program checkpoints into the code such that
compute will receive any pending asynchronous exceptions
at designated safe points during execution. The easi

[...omitted: remainder of paper (approx. last 19 KB: later sections, related work, references)...]
