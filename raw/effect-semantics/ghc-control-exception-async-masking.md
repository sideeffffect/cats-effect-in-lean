# GHC base Control.Exception: asynchronous exceptions, throwTo, mask, interruptible operations (excerpts)

> Source: https://hackage.haskell.org/package/base/docs/Control-Exception.html
> Collected: 2026-11-10
> Published: Unknown (base-4.22.0.0)

_HTML stripped to text by collector; excerpts verbatim._

### Excerpt starting at "Asynchronous Exceptions"

Asynchronous ExceptionsApplying mask to an exception handlerUtilitiesPrintingDescriptionThis module provides support for raising and catching both built-in
 and user-defined exceptions.In addition to exceptions thrown by IO operations, exceptions may
 be thrown by pure code (imprecise exceptions) or by external events
 (asynchronous exceptions), but may only be caught in the IO monad.
 For more details, see:A semantics for imprecise exceptions, by Simon Peyton Jones,
    Alastair Reid, Tony Hoare, Simon Marlow, Fergus Henderson,
    in PLDI'99.Asynchronous exceptions in Haskell, by Simon Marlow, Simon Peyton
    Jones, Andy Moran and John Reppy, in PLDI'01.An Extensible Dynamically-Typed Hierarchy of Exceptions,
    by Simon Marlow, in Haskell '06.Synopsisdata SomeException = (Exception e, HasExceptionContext) =>  SomeException eclass (Typeable e, Show e) => Exception e wheretoException :: e -> SomeExceptionfromException :: SomeException -> Maybe edisplayException :: e -> StringbacktraceDesired :: e -> BooladdExceptionContext :: ExceptionAnnotation a => a -> SomeException -> SomeExceptionsomeExceptionContext :: SomeException -> ExceptionContextannotateIO :: ExceptionAnnotation e => e -> IO a -> IO anewtype NoBacktrace e = NoBacktrace edata ExceptionWithContext a = ExceptionWithContext ExceptionContext adata WhileHandling = WhileHandling SomeExceptiondata IOExceptiondata ArithException= Overflow| Underflow| LossOfPrecision| DivideByZero| Denormal| RatioZeroDenominatordata ArrayException= IndexOutOfBounds String| UndefinedElement Stringnewtype AssertionFailed = AssertionFailed Stringnewtype NoMethodError = NoMethodError Stringnewtype PatternMatchFail = PatternMatchFail Stringnewtype RecConError = RecConError Stringnewtype RecSelError = RecSelError Stringnewtype RecUpdError = RecUpdError Stringdata ErrorCall whereErrorCall Stringpattern ErrorCallWithLocation :: String -> String -> ErrorCallnewtype TypeError = TypeError Stringdata SomeAsyncException = Exception e =>  SomeAsyncException edata AsyncException= StackOverflow| HeapOverflow| ThreadKilled| UserInterruptasyncExceptionToException :: Exception e => e -> SomeExceptionasyncExceptionFromException :: Exception e => SomeException -> Maybe edata NonTermination = NonTerminationdata NestedAtomically = NestedAtomicallydata BlockedIndefinitelyOnMVar = BlockedIndefinitelyOnMVardata BlockedIndefinitelyOnSTM = BlockedIndefinitelyOnSTMdata AllocationLimitExceeded = AllocationLimitExceedednewtype CompactionFailed = CompactionFailed Stringdata Deadlock = Deadlockthrow :: forall a e. (HasCallStack, Exception e) => e -> athrowIO :: (HasCallStack, Exception e) => e -> IO arethrowIO :: Exception e => ExceptionWithContext e -> IO aioError :: HasCallStack => IOError -> IO athrowTo :: Exception e => ThreadId -> e -> IO ()catch :: Exception e => IO a -> (e -> IO a) -> IO acatchNoPropagate :: Exception e => IO a -> (ExceptionWithContext e -> IO a) -> IO acatches :: IO a -> [Handler a] -> IO adata Handler a = Exception e =>  Handler (e -> IO a)catchJust :: Exception e => (e -> Maybe b) -> IO a -> (b -> IO a) -> IO ahandle :: Exception e => (e -> IO a) -> IO a -> IO ahandleJust :: Exception e => (e -> Maybe b) -> (b -> IO a) -> IO a -> IO atry :: Exception e => IO a -> IO (Either e a)tryWithContext :: Exception e => IO a -> IO (Either (ExceptionWithContext e) a)tryJust :: Exception e => (e -> Maybe b) -> IO a -> IO (Either b a)evaluate :: a -> IO amapException :: (Exception e1, Exception e2) => (e1 -> e2) -> a -> amask :: ((forall a. IO a -> IO a) -> IO b) -> IO bmask_ :: IO a -> IO auninterruptibleMask :: ((forall a. IO a -> IO a) -> IO b) -> IO buninterruptibleMask_ :: IO a -> IO adata MaskingState= Unmasked| MaskedInterruptible| MaskedUninterruptiblegetMaskingState :: IO MaskingStateinterruptible :: IO a -> IO aallowInterrupt :: IO ()assert :: Bool -> a -> abracket :: IO a -> (a -> IO b) -> (a -> IO c) -> IO cbracket_ :: IO a -> IO b -> IO c -> IO cbracketOnError :: IO a -> (a -> IO b) -> (a -> IO c) -> IO cfinally :: IO a -> IO b -> IO aonException :: IO a -> IO b -> IO adisplayExceptionWithInfo :: SomeException -> StringThe SomeException typedata SomeException Source #The SomeException type is the root of the exception type hierarchy.
When an exception of type e is thrown, behind the scenes it is
encapsulated in a SomeException.Constructors(Exception e, HasExceptionContext) =>  SomeException e InstancesInstances details Exception SomeException Source #This drops any attached ExceptionContext.Since: base-3.0Instance detailsDefined in GHC.Internal.Exception.Type MethodstoException :: SomeException -> SomeException Source #fromException :: SomeException -> Maybe SomeException Source #displayException :: SomeException -> String Source #backtraceDesired :: SomeException -> Bool Source # Show SomeException Source #Since: ghc-internal-3.0Instance detailsDefined in GHC.Internal.Exception.Type MethodsshowsPrec :: Int -> SomeException -> ShowS Source #show :: SomeException -> String Source #showList :: [SomeException] -> ShowS Source #The Exception classclass (Typeable e, Show e) => Exception e where Source #Any type that you wish to throw or catch as an exception must be an
instance of the Exception class. The simplest case is a new exception
type directly below the root:data MyException = ThisException | ThatException
    deriving Show

instance Exception MyExceptionThe default method definitions in the Exception class do what we need
in this case. You can now throw and catch ThisException and
ThatException as exceptions:*Main> throw ThisException `catch` \e -> putStrLn ("Caught " ++ show (e :: MyException))
Caught ThisException
In more complicated examples, you may wish to define a whole hierarchy
of exceptions:---------------------------------------------------------------------
-- Make the root exception type for all the exceptions in a compiler

data SomeCompilerException = forall e . Exception e => SomeCompilerException e

instance Show SomeCompilerException 

### Excerpt starting at "throwTo :: "

throwTo :: Exception e => ThreadId -> e -> IO ()catch :: Exception e => IO a -> (e -> IO a) -> IO acatchNoPropagate :: Exception e => IO a -> (ExceptionWithContext e -> IO a) -> IO acatches :: IO a -> [Handler a] -> IO adata Handler a = Exception e =>  Handler (e -> IO a)catchJust :: Exception e => (e -> Maybe b) -> IO a -> (b -> IO a) -> IO ahandle :: Exception e => (e -> IO a) -> IO a -> IO ahandleJust :: Exception e => (e -> Maybe b) -> (b -> IO a) -> IO a -> IO atry :: Exception e => IO a -> IO (Either e a)tryWithContext :: Exception e => IO a -> IO (Either (ExceptionWithContext e) a)tryJust :: Exception e => (e -> Maybe b) -> IO a -> IO (Either b a)evaluate :: a -> IO amapException :: (Exception e1, Exception e2) => (e1 -> e2) -> a -> amask :: ((forall a. IO a -> IO a) -> IO b) -> IO bmask_ :: IO a -> IO auninterruptibleMask :: ((forall a. IO a -> IO a) -> IO b) -> IO buninterruptibleMask_ :: IO a -> IO adata MaskingState= Unmasked| MaskedInterruptible| MaskedUninterruptiblegetMaskingState :: IO MaskingStateinterruptible :: IO a -> IO aallowInterrupt :: IO ()assert :: Bool -> a -> abracket :: IO a -> (a -> IO b) -> (a -> IO c) -> IO cbracket_ :: IO a -> IO b -> IO c -> IO cbracketOnError :: IO a -> (a -> IO b) -> (a -> IO c) -> IO cfinally :: IO a -> IO b -> IO aonException :: IO a -> IO b -> IO adisplayExceptionWithInfo :: SomeException -> StringThe SomeException typedata SomeException Source #The SomeException type is the root of the exception type hierarchy.
When an exception of type e is thrown, behind the scenes it is
encapsulated in a SomeException.Constructors(Exception e, HasExceptionContext) =>  SomeException e InstancesInstances details Exception SomeException Source #This drops any attached ExceptionContext.Since: base-3.0Instance detailsDefined in GHC.Internal.Exception.Type MethodstoException :: SomeException -> SomeException Source #fromException :: SomeException -> Maybe SomeException Source #displayException :: SomeException -> String Source #backtraceDesired :: SomeException -> Bool Source # Show SomeException Source #Since: ghc-internal-3.0Instance detailsDefined in GHC.Internal.Exception.Type MethodsshowsPrec :: Int -> SomeException -> ShowS Source #show :: SomeException -> String Source #showList :: [SomeException] -> ShowS Source #The Exception classclass (Typeable e, Show e) => Exception e where Source #Any type that you wish to throw or catch as an exception must be an
instance of the Exception class. The simplest case is a new exception
type directly below the root:data MyException = ThisException | ThatException
    deriving Show

instance Exception MyExceptionThe default method definitions in the Exception class do what we need
in this case. You can now throw and catch ThisException and
ThatException as exceptions:*Main> throw ThisException `catch` \e -> putStrLn ("Caught " ++ show (e :: MyException))
Caught ThisException
In more complicated examples, you may wish to define a whole hierarchy
of exceptions:---------------------------------------------------------------------
-- Make the root exception type for all the exceptions in a compiler

data SomeCompilerException = forall e . Exception e => SomeCompilerException e

instance Show SomeCompilerException where
    show (SomeCompilerException e) = show e

instance Exception SomeCompilerException

compilerExceptionToException :: Exception e => e -> SomeException
compilerExceptionToException = toException . SomeCompilerException

compilerExceptionFromExcept

### Excerpt starting at "mask :: ("

mask :: ((forall a. IO a -> IO a) -> IO b) -> IO b Source #Executes an IO computation with asynchronous
 exceptions masked.  That is, any thread which attempts to raise
 an exception in the current thread with throwTo
 will be blocked until asynchronous exceptions are unmasked again.The argument passed to mask is a function that takes as its
 argument another function, which can be used to restore the
 prevailing masking state within the context of the masked
 computation.  For example, a common way to use mask is to protect
 the acquisition of a resource:mask $ \restore -> do
    x <- acquire
    restore (do_something_with x) `onException` release
    releaseThis code guarantees that acquire is paired with release, by masking
 asynchronous exceptions for the critical parts. (Rather than write
 this code yourself, it would be better to use
 bracket which abstracts the general pattern).Note that the restore action passed to the argument to mask
 does not necessarily unmask asynchronous exceptions, it just
 restores the masking state to that of the enclosing context.  Thus
 if asynchronous exceptions are already masked, mask cannot be used
 to unmask exceptions again.  This is so that if you call a library function
 with exceptions masked, you can be sure that the library call will not be
 able to unmask exceptions again.  If you are writing library code and need
 to use asynchronous exceptions, the only way is to create a new thread;
 see forkIOWithUnmask.Asynchronous exceptions may still be received while in the masked
 state if the masked thread blocks in certain ways; see
 Control.Exception.Threads created by forkIO inherit the
 MaskingState from the parent; that is, to start a thread in the
 MaskedInterruptible state,
 use mask_ $ forkIO ....  This is particularly useful if you need
 to establish an exception handler in the forked thread before any
 asynchronous exceptions are received.  To create a new thread in
 an unmasked state use forkIOWithUnmask.mask_ :: IO a -> IO a Source #Like mask, but does not pass a restore action to the argument.uninterruptibleMask :: ((forall a. IO a -> IO a) -> IO b) -> IO b Source #Like mask, but the masked computation is not interruptible (see
 Control.Exception).  THIS SHOULD BE USED WITH
 GREAT CARE, because if a thread executing in uninterruptibleMask
 blocks for any reason, then the thread (and possibly the program,
 if this is the main thread) will be unresponsive and unkillable.
 This function should only be necessary if you need to mask
 exceptions around an interruptible operation, and you can guarantee
 that the interruptible operation will only block for a short period
 of time.uninterruptibleMask_ :: IO a -> IO a Source #Like uninterruptibleMask, but does not pass a restore action
 to the argument.data MaskingState Source #Describes the behaviour of a thread when an asynchronous
 exception is received.ConstructorsUnmaskedasynchronous exceptions are unmasked (the normal state)MaskedInterruptiblethe state during mask: asynchronous exceptions are masked, but blocking operations may still be interruptedMaskedUninterruptiblethe state during uninterruptibleMask: asynchronous exceptions are masked, and blocking operations may not be interruptedInstancesInstances details Eq MaskingState Source #Since: base-4.3.0.0Instance detailsDefined in GHC.Internal.IO Methods(==) :: MaskingState -> MaskingState -> Bool Source #(/=) :: MaskingState -> MaskingState -> Bool Source # Show MaskingState Source #Since: base-4.3.0.0Instance detailsDefined in GHC.Internal.IO MethodsshowsPrec :: Int -> MaskingState -> ShowS Source #show :: MaskingState -> String Source #showList :: [MaskingState] -> ShowS Source #getMaskingState :: IO MaskingState Source #Returns the MaskingState for the current thread.interruptible :: IO a -> IO a Source #Allow asynchronous exceptions to be raised even inside mask, making
 the operation interruptible (see the discussion of "Interruptible operations"
 in Exception).When calle

### Excerpt starting at "Interruptible operations"

Interruptible operations"
 in Exception).When called outside mask, or inside uninterruptibleMask, this
 function has no effect.Since: base-4.9.0.0allowInterrupt :: IO () Source #When invoked inside mask, this function allows a masked
 asynchronous exception to be raised, if one exists.  It is
 equivalent to performing an interruptible operation (see
 #interruptible), but does not involve any actual blocking.When called outside mask, or inside uninterruptibleMask, this
 function has no effect.Since: base-4.4.0.0Applying mask to an exception handlerThere's an implied mask around every exception handler in a call
to one of the catch family of functions.  This is because that is
what you want most of the time - it eliminates a common race condition
in starting an exception handler, because there may be no exception
handler on the stack to handle another exception if one arrives
immediately.  If asynchronous exceptions are masked on entering the
handler, though, we have time to install a new exception handler
before being interrupted.  If this weren't the default, one would have
to write something like     mask $ \restore ->
          catch (restore (...))
                (\e -> handler)If you need to unmask asynchronous exceptions again in the exception
handler, restore can be used there too.Note that try and friends do not have a similar default, because
there is no exception handler in this case.  Don't use try for
recovering from an asynchronous exception.
Some operations are interruptible, which means that they can receive
asynchronous exceptions even in the scope of a mask.  Any function
which may itself block is defined as interruptible; this includes
takeMVar
(but not tryTakeMVar),
and most operations which perform
some I/O with the outside world.  The reason for having
interruptible operations is so that we can write things like     mask $ \restore -> do
        a <- takeMVar m
        catch (restore (...))
              (\e -> ...)if the takeMVar was not interruptible,
then this particular
combination could lead to deadlock, because the thread itself would be
blocked in a state where it can't receive any asynchronous exceptions.
With takeMVar interruptible, however, we can be
safe in the knowledge that the thread can receive exceptions right up
until the point when the takeMVar succeeds.
Similar arguments apply for other interruptible operations like
openFile.It is useful to think of mask not as a way to completely prevent
asynchronous exceptions, but as a way to switch from asynchronous mode
to polling mode.  The main difficulty with asynchronous
exceptions is that they normally can occur anywhere, but within a
mask an asynchronous exception is only raised by operations that are
interruptible (or call other interruptible operations).  In many cases
these operations may themselves raise exceptions, such as I/O errors,
so the caller will usually be prepared to handle exceptions arising from the
operation anyway.  To perform an explicit poll for asynchronous exceptions
inside mask, use allowInterrupt.Sometimes it is too onerous to handle exceptions in the middle of a
critical piece of stateful code.  There are three ways to handle this
kind of situation:Use STM.  Since a transaction is always either completely executed
   or not at all, transactions are a good way to maintain invariants
   over state in the presence of asynchronous (and indeed synchronous)
   exceptions.Use mask, and avoid interruptible operations.  In order to do
   this, we have to know which operations are interruptible.  It is
   impossible to know for any given library function whether it might
   invoke an interruptible operation internally; so instead we give a
   list of guaranteed-not-to-be-interruptible operations below.Use uninterruptibleMask.  This is generally not recommended,
   unless you can guarantee that any interruptible operations invoked
   during the scope of uninterruptibleMask can only ever block for
   a short time.  Otherwise, uninterruptibleMask is a good way to
   make your program deadlock and be unresponsive to user interrupts.The following operations are guaranteed not to be interruptible:operations on IORef from Data.IORefSTM transactions that do not use retryeverything from the Foreign moduleseverything from Control.Exception except for throwTotryTakeMVar, tryPutMVar,
   isEmptyMVartakeMVar if the MVar is
   definitely full, and conversely putMVar if the
   MVar is definitely emptynewEmptyMVar, newMVarforkIO, myThr

