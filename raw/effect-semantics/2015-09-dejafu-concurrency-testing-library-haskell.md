# Deja Fu: A Concurrency Testing Library for Haskell (Walker and Runciman, Haskell Symposium 2015) - text extracted from PDF

> Source: https://www.barrucadu.co.uk/publications/dejafu-hs15.pdf
> Collected: 2026-11-10
> Published: 2015-09

_Text extracted with pdftotext -layout (two columns interleaved). Kept first ~40 KB verbatim._

                Déjà Fu: A Concurrency Testing Library for Haskell
                                    Michael Walker                                                                         Colin Runciman
                                  University of York, UK                                                                University of York, UK
                                   msw504@york.ac.uk                                                                  colin.runciman@york.ac.uk




Abstract                                                                                           not wait for child threads before terminating[10], so the output may
Systematic concurrency testing (SCT) is an approach to testing po-                                 also be “0”, although this behaviour can only be exhibited in GHC
tentially nondeterministic concurrent programs. SCT avoids poten-                                  with multiple OS threads. As we shall see in §4, we can test this
tially unrepeatable results that may arise from unit testing con-                                  program to produce the following trace:
current programs. It seems to have received little attention from                                  [pass] Never Deadlocks (checked: 23)
Haskell programmers. This paper introduces a generalisation of                                     [pass] No Exceptions (checked: 23)
Haskell’s concurrency abstraction in the form of typeclasses, and                                  [fail] Consistent Result (checked: 1)
a library for testing concurrent programs. A number of examples                                      0 S0-------
are provided, some of which come from pre-existing packages.                                         2 S0----P2---S0---
Categories and Subject Descriptors D.2.5 [Software Engineer-                                         1 S0----P1---S0---
ing]: Testing and Debugging—Testing tools
                                                                                                      Here each of the last three lines represents a possible execution
Keywords Concurrency, functional programming, Haskell, non-                                        of the program: “S” indicates the start of execution of a thread,
determinism, systematic concurrency testing                                                        “P” indicates the pre-emption of the running thread by another, and
                                                                                                   each dash represents one execution step.
1.     Introduction
                                                                                                   1.1     Contributions
Haskell has been extended in different ways to express parallelism1
and concurrency2 . Deterministic parallelism implementations, such                                 The contributions of this paper are:
as the Par monad[12] and Strategies[11] are very suitable for data-                                 • a generalisation of the standard concurrency abstraction, allow-
parallel tasks where the difficulty is efficiently performing some
                                                                                                         ing different concrete implementations to be used;
pure computation. However, they achieve their determinism by
constraining the functionality of shared state, and so lose some                                    • a library called Déjà Fu3 for systematically testing concurrent
convenience and utility.                                                                                 Haskell programs for possible deadlocks, race-conditions, or
    In this paper, the interest is more general: computations with                                       uncaught exceptions, with the testing functionality based on
constrained nondeterminism, or interaction with the real world, as                                       monadic concurrency[14] and schedule bounding[13].
a key part of their functioning. Though very general, such compu-
tations can give rise to race conditions and deadlocks.                                            1.2     Roadmap
                                                                                                   The rest of the paper is organised as follows.
Example
                                                                                                    • §2 reviews the solutions for deterministic parallelism in Haskell,
main :: IO ()
                                                                                                         and highlights their limitations.
main = do
  shared <- newMVar 0                                                                               • §3 presents the typeclass concurrency-abstraction, emphasising
  forkIO . void $ swapMVar shared 1                                                                      the few points where it departs from the usual concurrency
  forkIO . void $ swapMVar shared 2                                                                      model.
  readMVar shared >>= print                                                                         • §4 introduces writing tests with Déjà Fu.
   This program may look like it will output either “1” or “2”                                      • §5 explains how the library implements systematic concurrency
depending on the ordering of swaps. Actually, a parent thread does                                       testing.
1 Doing multiple things at once.                                                                    • §6 presents a small selection of case studies.
2 Programming as if doing multiple things at once.                                                  • §7 gives pointers to existing concurrency testing work in both
                                                                                                         Haskell and other programming languages.
                                                                                                    • §8 draws conclusions and suggests further work.




This is the author’s version of the work. It is posted here for your personal use. Not for
redistribution. The definitive version was published in the following publication:                 3 [Déjà Fu is] A martial art in which the user’s limbs move in time as well
Haskell’15, September 3-4, 2015, Vancouver, BC, Canada                                             as space, [. . . ] It is best described as “the feeling that you have been kicked
ACM. 978-1-4503-3808-0/15/09...                                                                    in the head this way before”.                     (Terry Pratchett, Thief of Time)
http://dx.doi.org/10.1145/2804302.2804306



                                                                                             141
2.    Deterministic Parallelism and Concurrency in                            3.    Déjà Fu: Concurrency and Haskell Revisited
      Haskell                                                                 Readers already familiar with Haskell’s concurrency primitives
2.1   The Eval Monad                                                          may find it enough to skim this section noting the syntactic dif-
                                                                              ferences in the Déjà Fu variant.
The Eval monad, and the Strategies[11] package built on top of it,
is a way of evaluating data structures in parallel. The programmer
                                                                              Departure Departures from the semantics of the traditional con-
is provided with primitives to evaluate something sequentially, in
                                                                              currency abstraction are highlighted like this.
parallel (without blocking), and to run an Eval computation.
    The following example[10] applies a function to both elements                 If we remove the limitations, allowing non-blocking reads and
of a tuple in parallel, waits until the evaluation is complete, and           multiple writes, we get to Haskell’s traditional concurrency abstrac-
returns the result:                                                           tion in the IO monad. Déjà Fu1 generalises a very large subset of
                                                                              that abstraction to work in arbitrary members of a typeclass, named
tupleMap :: (a -> b) -> (a, a) -> (b, b)                                      MonadConc. There is an instance of MonadConc for IO, and so ex-
tupleMap f (x, y) = runEval $ do                                              isting code using only the functions generalised over can be made
  x’ <- rpar $ f x                                                            suitable for testing quite simply. Existing code which makes use of
  y’ <- rpar $ f y                                                            more functionality may require a light dusting of liftIOs.
  rseq x’                                                                         To make use of the Déjà Fu library, we must first import the
  rseq y’                                                                     class:
  return (x’, y’)
                                                                              import Control.Monad.Conc.Class
   There is no notion of threading, or of shared mutable state. The
Eval monad is for the use-case of having a large data structure               3.1   Threads
which is expensive to compute.                                                Threads let a program do multiple things at once. Every program
                                                                              has at least one thread, which starts where main does and runs until
2.2   The Par Monad                                                           the program terminates. A thread is the basic unit of concurrency. It
                                                                              lets us pretend (with parallelism, it might even be true!) that we’re
The Par monad[12] is a library providing a traditional-looking con-           computing multiple things at once.
currency abstraction, providing the programmer with threads and                   We can start a new thread with the fork2 function:
mutable state, however it maintains determinism by restricting its
shared variables to one write, and operations to read block until a           fork :: ... => m () -> m (ThreadId m)
value has been written. Thus, Par’s IVars are futures, not mutable
state. Par uses a work-stealing scheduler running on multiple oper-               This starts evaluating its argument in a separate thread. It also
ating system threads, fully evaluating values on their own threads            gives us back a (monad-specific) ThreadId value, which we can
before inserting them into an IVar. Despite its limitations, the Par          use to kill the thread later on, if we want.
monad can be very effective in speeding up pure code.                             In a real machine, there are of course a number of processors
    The following example maps a function in parallel over a list,            and cores. It may be that a particular application of concurrency is
fully evaluating it. Of course, laziness is generally what is desired         only a net gain if every thread is operating on a separate core, so
in Haskell programs, but often it is known that an entire result will         that threads are not interrupting each other. The GHC runtime refers
definitely be needed:                                                         to the number of Haskell threads that can run truly simultaneously
                                                                              as the number of capabilities. We can query this value, and fork
parMap :: NFData b => (a -> b) -> [a] -> [b]                                  threads which are bound to a particular capability:
parMap f as = runPar $ do
  bs <- mapM (spawnP . f) as                                                  getNumCapabilities :: ... => m Int
  mapM get bs                                                                 forkOn :: ... => Int -> m () -> m (ThreadId m)

                                                                                 The forkOn function interprets the capability number modulo
   However, with a lack of multi-write shared variables and non-              the value returned by getNumCapabilities.
blocking reads, Par is unsuitable for long-lived concurrent pro-
grams with a central shared state. It could not be used to implement          Departure getNumCapabilities is not required to return a true
a multi-threaded work-stealing scheduler, such as the one under-              result. The testing instances return “2” despite executing everything
pinning Par itself.                                                           in the same capability, to encourage more concurrency. The IO
                                                                              instance does return a true result.
2.3   LVish
                                                                                  Sometimes we just want the special case of evaluating some-
A recent development is the LVish[9] library, which overcomes                 thing in a separate thread, for which we can use spawn (imple-
some of the limitations of the Par monad by allowing multiple                 mented in terms of fork):
writes, as long as they only ever add information to the shared
structure. To maintain determinism, reads of the same kind return             spawn :: ... => m a -> m (CVar m a)
the same value that they always did. LVish allows shared state
which forms a lattice, and reads correspond to seeing a small part               This returns a CVar (Concurrent Variable), to which we can
of that lattice.                                                              apply readCVar, blocking until the computation is done and the
    Necessarily, reads block until there is enough information in             value is stored.
the structure to determine the result. This approach means that the
                                                                              1 https://github.com/barrucadu/dejafu
entire data structure must be kept around for as long as there is a
single reference, even if that reference is only ever used to read a          2 To save on horizontal space, a MonadConc   m => has been omitted from
small part of the data.                                                       type signatures.



                                                                        142
3.2   Mutable State                                                              If we read a CTVar and don’t like the value it has, the transaction
Threading by itself is not really enough. We need to be able to               can be aborted, and the thread will block until any of the referenced
communicate between threads: we’ve already seen an instance of                CTVars have been mutated:
this with the spawn function.
                                                                              retry :: MonadSTM s => s a
    The simplest type of mutable shared state provided is the CRef
                                                                              check :: MonadSTM s => Bool -> s ()
(Concurrent Reference). CRefs are shared variables which can be
written to and read from:                                                          We can also try executing a transaction, and do something else
newCRef    :: ... => a -> m (CRef m a)                                        if it fails:
readCRef   :: ... => CRef m a -> m a
modifyCRef :: ... => CRef m a -> (a -> (a, b)) -> m b                         orElse :: MonadSTM s => s a -> s a -> s a
writeCRef :: ... => CRef m a -> a -> m ()
                                                                                 The nice thing about STM transactions is that they compose.
                                                                              We can take small transactions and build bigger transactions from
Departure IORef actions can be re-ordered[7], but this is not                 them, and the whole is still executed atomically. This means we
the case for CRef actions. The modifyCRef function corre-                     can do complex state operations involving multiple shared variables
sponds to atomicModifyIORef, and writeCRef corresponds to                     without worrying!
atomicWriteIORef.                                                                We have emphasised that STM transactions are atomic. The
   As any thread can write at any time, we risk threads overwrit-             function which atomically executes a transaction:
ing each other’s work! At least modifyCRef is atomic: no thread
can update it between the value being read and the new value being            atomically :: ... => STMLike m a -> m a
stored, as could happen if readCRef and writeCRef were com-
posed. Even so, CRefs quickly fall down if we want to do anything             Departure Every MonadConc has an associated MonadSTM,
complicated. We need something more robust.                                   whereas there is just one STM normally. This is so that STM trans-
                                                                              actions can be tested without needing to bring IO into the test run-
3.3   Mutual Exclusion                                                        ner. The IO MonadConc instance uses STM as its MonadSTM.
A CVar is a shared variable under mutual exclusion. It has two
possible states: full or empty. Writing to a full CVar blocks until
it is empty, and reading or taking from an empty CVar blocks until                For example, suppose we have a collection of worker threads
it is full. There are also non-blocking functions which return an             each of which can either produce a result or fail. We might want
indication of success:                                                        to block until either one completes successfully and kill the other
                                                                              threads, or until all fail. We can implement this using CTMVars, an
putCVar     :: ... => CVar m a -> a -> m ()                                   analogue of CVars built from CTVars:
tryPutCVar :: ... => CVar m a -> a -> m Bool
readCVar    :: ... => CVar m a -> m a                                         awaitResult :: MonadConc m
takeCVar    :: ... => CVar m a -> m a                                             => [(ThreadId m, CTMVar (STMLike m) (Maybe a))]
tryTakeCVar :: ... => CVar m a -> m (Maybe a)                                     -> m (Maybe a)
                                                                              awaitResult workers = do
    Unfortunately, the mutual exclusion behaviour of CVars means                out <- atomically $ do
that computations can become deadlocked. For example, deadlock                    progress <- mapM (tryReadCTMVar . snd) workers
occurs if every thread tries to take from the same CVar. The GHC                  let finished = catMaybes progress
runtime can detect this (and will complain if it does), and so can                case catMaybes finished of
Déjà Fu in a more informative way, as we shall see in §4.                         (x:_) -> return $ Just x
                                                                                    [] -> check (length finished < length workers)
3.4   Software Transactional Memory                                                       >> return Nothing
CVars are nice, until we need more than one, and find they need to              mapM_ (killThread . fst) workers
be kept synchronised. As we can only claim one CVar atomically,                 return out
it seems we need to introduce a CVar to control access to CVars!
This is unwieldy and prone to bugs.                                              Here tryReadCTMVar attempts to read from a CTMVar and, if
    Software transactional memory (STM) is the solution. STM                  there is no value present, calls retry.
uses CTVars, or Concurrent Transactional Variables, and is based
upon the idea of atomic transactions. An STM transaction consists             3.5   Exceptions
of one or more operations over a collection of CTVars, where a                Exceptions are a way to bail out of a computation early. Whether
transaction may be aborted part-way through depending on their                they’re a good solution to that problem is a question of style, but
values. If the transaction fails, none of its effects take place, and         they can be used to jump quickly to error handling code when
the thread blocks until the transaction can succeed. This means we            necessary. The basic functions for dealing with exceptions are:
need to limit the possible actions in an STM transaction, so we have
another typeclass:                                                            catch :: ... => m a -> (e -> m a) -> m a
                                                                              throw :: ... => e -> m a
import Control.Monad.STM.Class
   CTVars always contain a value, as shown in the types of the                    Where throw causes the computation to jump back to the near-
functions:                                                                    est enclosing catch capable of handling the particular exception.
                                                                              As exceptions belong to a typeclass, rather than being a concrete
newCTVar   :: MonadSTM s => a -> s (CTVar s a)                                type, different catch functions can be nested, to handle different
readCTVar :: MonadSTM s => CTVar s a -> s a                                   types of exceptions.
writeCTVar :: MonadSTM s => CTVar s a -> a -> s ()


                                                                        143
Departure The IO catch function can catch exceptions from                       alwaysTrue
pure code. This is not true in general for MonadConc instances.                     :: (Either Failure a -> Bool) -> Predicate a
So some things which work normally may not work in testing, and                 somewhereTrue
we risk false negatives. This is a small cost, however, as exceptions               :: (Either Failure a -> Bool) -> Predicate a
from pure code are things like pattern match failures and evaluating
undefined, which are arguably bugs.                                                There are also variants which take binary predicates for check-
                                                                                ing properties over the entire collection as a whole, for example:
     Exceptions can be used to kill a thread:
                                                                                alwaysSame :: Eq a => Predicate a
throwTo    :: ... => ThreadId m -> e -> m ()                                    alwaysSame = alwaysTrue2 (==)
killThread :: ... => ThreadId m -> m ()
                                                                                alwaysTrue2
     These functions block until the target thread is in an appropriate
                                                                                    :: (Either Failure a -> Either Failure a -> Bool)
state to receive the exception.
                                                                                    -> Predicate a
     What if we don’t want our threads to be subject to destruction
                                                                                somewhereTrue2
in this way? A thread also has a masking state, which can be used
                                                                                    :: (Either Failure a -> Either Failure a -> Bool)
to block exceptions from other threads. There are three masking
                                                                                    -> Predicate a
states: unmasked, in which a thread can have exceptions thrown to
it; interruptible, in which a thread can only have exceptions thrown                The functions alwaysTrue2 and somewhereTrue2 only check
to it if it is blocked; and uninterruptible, in which a thread cannot           the predicate between values adjacent in the result list. The order
have exceptions thrown to it. When a thread is started, it inherits             of this list depends on the scheduling algorithm used, and so these
the masking state of its parent, and the forkWithUnmask function                functions should only be used for properties which are symmetric
forks a thread and passes it a function which can be used to execute            and transitive. There is also a collection of standard predicates, for
a subcomputation in the unmasked state. We can also execute a                   doing things like checking for the existence of deadlock.
subcomputation with a new masking state:                                            For the common case of checking for determinism, deadlock
                                                                                freedom, and proper exception handling, there is an autocheck
mask :: ... => ((forall a. m a -> m a) -> m b) -> m b
                                                                                function:
uninterruptibleMask
     :: ... => ((forall a. m a -> m a) -> m b) -> m b                           autocheck :: (Eq a, Show a)
forkWithUnmask                                                                      => (forall t. Conc t a) -> IO Bool
     :: ... => ((forall a. m a -> m a) -> m ())
     -> m (ThreadId m)                                                              Let’s see what we get from testing the example from the start of
                                                                                this paper. We’ll have it return the value, rather than print it, though:
    STM can also use exceptions, with its throwSTM and catchSTM
functions. If an exception propagates uncaught to the top of a                  bad :: MonadConc m => m Int
transaction, that transaction is aborted.                                       bad = do
                                                                                  shared <- newCVar 0
4.     Testing using Déjà Fu                                                    fork . void $ swapCVar shared 1
                                                                                  fork . void $ swapCVar shared 2
Testing with Déjà Fu consists in writing a small concurrent compu-              readCVar shared
tation to test, and some predicates over the return value and traces
produced. Predicates may be lazy: they need not examine the entire                 Firstly let’s put it through autocheck:
output before determining whether the test has passed or failed.
                                                                                > autocheck bad
import Test.DejaFu                                                              [pass] Never Deadlocks (checked: 23)
                                                                                [pass] No Exceptions (checked: 23)
runTest :: Eq a                                                                 [fail] Consistent Result (checked: 1)
    => Predicate a -> (forall t. Conc t a)                                        0 S0-------
    -> Result a                                                                   2 S0----P2---S0---
                                                                                  1 S0----P1---S0---
   The abstract Conc t type is one of the instances of Monad-
                                                                                False
Conc for testing purposes (there’s also ConcIO t for computations
which do IO). The locally quantified type t prevents mutable state                  Déjà Fu reports three distinct failures! Two failures are distinct
from leaking out of the computation, similarly to the ST monad.                 if they have different results, or the same result but one trace is not
                                                                                a simplification of another. For each failure, the result is shown,
type Predicate a
                                                                                along with the trace that led to it. “Sx” means that thread “x” started
    = [(Either Failure a, Trace)] -> Result a
                                                                                execution; “Px” means that thread “x” pre-empted the running
data Result a = Result                                                          thread; and the number of dashes indicates how many steps each
  { _pass         :: Bool                                                       thread ran for. So this output means that we get a “0” if there is no
  , _casesChecked :: Int                                                        pre-emption, a “1” if thread 1 pre-empts the initial thread before
  , _casesTotal   :: Int                                                        the read, and a “2” if thread 2 pre-empts the initial thread before
  , _failures     :: [(Either Failure a, Trace)]                                the read.
  } deriving (Show, Eq)                                                             This output is nice for automated test suites, but perhaps not so
                                                                                friendly for interactive debugging. There are functions to run tests
   A Result consists of a Boolean flag indicating whether the test              and return a more detailed result:
passed, the number of results checked to arrive at that conclusion,
the total number of results, and a list of all failing cases.                   > runTest alwaysSame bad
   Helper functions lift predicates over a single result to predicates          Result {_pass = False, _casesChecked = 1
over the collection:                                                                   , _casesTotal = 23, _failures = [...]}


                                                                          144
   The Result value tells us testing failed after looking at 1 case,             bad :: MonadConc m Int
there are 23 cases in total, and there is a simplified list of failures.         bad = do
These are quite long, so here is the second only:                                  _concAllKnown
                                                                                   a <- newEmptyCVar
( Right 2                                                                          b <- newEmptyCVar
, [ (Start 0,[],New 1)                                                             fork $ do
  , (Continue,[],Put 1 [])                                                           _concKnowsAbout (Left a)
  , (Continue,[],Fork 1)                                                             _concAllKnown
  , (Continue,[SwitchTo 1],Fork 2)                                                   let loop = takeCVar a >> loop in loop
  , (SwitchTo 2,[Continue,SwitchTo 1],Take 1 [])                                   fork $ do
  , (Continue,[SwitchTo 0,SwitchTo 1],Put 1 [])                                      _concKnowsAbout (Left a)
  , (Continue,[SwitchTo 0,SwitchTo 1],Stop)                                          _concAllKnown
  , (Start 0,[Start 1],Read 1)                                                       let loop = putCVar a 1 >> loop in loop
  , (Continue,[SwitchTo 1],Lift)                                                   takeCVar b
  , (Continue,[SwitchTo 1],Stop)])
                                                                                     The main thread is blocked on “b”, to which neither of the other
    We have the result returned, and a log of what decision the                  two threads has a reference. By adding annotations, this can be de-
scheduler made at each step, what alternative decisions it could                 tected and reported. There are three annotations: concKnowsAbout
have made, and what the thread did. Each thread and CVar (and                    records that the current thread has a reference to a CVar or CTVar;
CRef/CTVar) has its own unique identifier. In particular, we can                  concForgets records that the current thread will never touch the
see that when thread 2 pre-empted thread 0, it modified CVar 1,                  referenced CVar or CTVar again; and concAllKnown indicates
and there is evidence to suggest that the final result was determined            that all CVars or CTVars which were passed in to the thread have
by CVar 1 (as it was read just before the main thread terminated),               been recorded. If every thread is in a known state, then detection
this should suggest to us that maybe CVar 1 is the culprit, and lead             of non-global deadlock is enabled. Otherwise the example above
us to look more closely at that area of the program.                             never terminates, as the two forked threads run forever, even though
    It may seem difficult to keep track of which thread is which.                the main thread can never progress.
Studies have found[16] that many errors are exposed with as few                      Misuse of these aids can lead to invalid test results. In particular,
as two threads. This finding encourages us to write small test cases.             concNoTest should only be used for actions which involve no
However, there could be an optional mechanism to assign names to                 shared variables from a larger scope. If two threads with a reference
threads.                                                                         to the same shared variable are executed under concNoTest, then
    We can of course test STM transactions individually. The result              the test runner will not consider possible interleavings of those
may be a success (along with the value returned), a failure due to a             threads.
retry, or a failure due to an uncaught exception:
                                                                                 4.2   IO
import Test.DejaFu.STM
runTransaction :: (forall t. STMST t a) -> Result a                              By itself, MonadConc cannot do IO. However, by adding in a
                                                                                 MonadIO context and applying liftIO as appropriate, concur-
  The abstract STMST t type is the testing implementation of                     rency can be separated from other IO, allowing testing.
MonadSTM.                                                                            However, once IO is involved, the test runner loses control
                                                                                 of what’s going on. If a thread, during some IO, blocks on the
4.1   Testing Aids                                                               action of another thread, this cannot be detected, and deadlock may
Some other functions generically defined for the typeclass only                  arise. Furthermore, it is assumed for testing that the only source
alter the running of the code during testing. They are provided to               of nondeterminism is the scheduler (see §5). Any IO that is done
make it easier to write good tests.                                              should be deterministic given the same set of scheduling decisions,
    Firstly, there is concNoTest, used to indicate that a subcom-                to not invalidate test results, although this is good practice in any
putation already has its own tests, and so it should not be tested               sort of testing. Finally, the test runner cannot pre-empt within
again here. Specifically, the test runner executes the argument of               liftIO blocks, they should be as small as possible to avoid the
 concNoTest atomically. This allows tests to compose without re-                 risk of obscuring bugs.
peating work:
                                                                                 5.    Implementation
big :: MonadConc m => m Int
big = do                                                                         Readers who just want to use the Déjà Fu library can skip over this
  a <- _concNoTest little1                                                       section and go straight to the example applications in §6.
  b <- _concNoTest little2
                                                                                 5.1   Systematic Concurrency Testing
  combine a b
                                                                                 Systematic concurrency testing[16] (SCT) is a method for testing
    If little1 and little2 already have their own tests, and have                concurrent programs which works by forcing a particular set of
been verified to work, there is no need to test them again when                  scheduling decisions to be made. Different schedules can then be
testing big.                                                                     explored in order to try to find bugs. It is systematic because the
    Secondly, there are cases where the main thread may be blocked               order of exploration is generally not random, but follows some
on some CVar or CTVar, to which no other thread has a reference.                 deterministic search pattern.
This should cause immediate failure with deadlock as the reason.                     SCT can be implemented by overriding the concurrency prim-
By default Déjà Fu cannot detect deadlocks of this kind. However,              itives of the programming language, forcing all threads to run on
the user has the option to provide extra information, indicating                 one controlling thread, and making scheduling decisions between
which shared variables a thread knows about:                                     effectively-atomic blocks. An effectively-atomic block consists of
                                                                                 a number of thread-local actions followed by a single access to a
                                                                                 shared resource. This is preferable to exploring all possible points


                                                                           145
for making scheduling decisions, as the order of interleaving of                     data Action ... =
thread-local operations cannot affect the final result.                                  AFork     thread_action action
    There is some terminology associated with scheduling:                              | AMyTId    (thread_id -> action)
                                                                                       | APut      cvar new_value action
Blocked A thread awaiting access to a shared resource which is                         | ATryPut   cvar new_value (Bool -> action)
   currently unavailable.                                                              | AGet      cvar (value -> action)
Blocking An operation which may result in its thread becoming                          | ATake     cvar (value -> action)
   blocked.         
[...omitted: remainder (case studies continued, evaluation, related work, references)...]
