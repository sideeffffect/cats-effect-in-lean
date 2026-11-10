# Lean 4 reference: IO Logical Model (v4.34.0)

> Source: https://lean-lang.org/doc/reference/4.34.0/IO/Logical-Model/
> Collected: 2026-11-10
> Published: Unknown

Logical Model

              21.1. Logical Model

              Conceptually, Lean distinguishes evaluation or reduction of terms from execution of side effects.
Term reduction is specified by rules such as β and δ, which may occur anywhere at any time.
Side effects, which must be executed in the correct order, are abstractly described in Lean's logic.
When programs are run, the Lean runtime system is responsible for actually carrying out the described effects.

              The type IO α is a description of a process that, by performing side effects, should either return a value of type α or throw an error.
It can be thought of as a state monad in which the state is the entire world.
Just as a value of type StateM Nat Bool computes a Bool while having the ability to mutate a natural number, a value of type IO Bool computes a Bool while potentially changing the world.
Error handling is accomplished by layering an appropriate exception monad transformer on top of this.

              Because the entire world can't be represented in memory, the actual implementation uses an abstract token that stands for its state.
The Lean runtime system is responsible for providing the initial token when the program is run, and each primitive action accepts a token that represents the world and returns another when finished.
This ensures that effects occur in the proper order, and it clearly separates the execution of side effects from the reduction semantics of Lean terms.

              Non-termination via general recursion is treated separately from the effects described by IO.
Programs that may not terminate due to infinite loops must be defined as partial functions.
From the logical perspective, they are treated as arbitrary constants; IO is not needed.

              A very important property of IO is that there is no way for values to “escape”.
Without using one of a few clearly-marked unsafe operators, programs have no way to extract a pure Nat from an IO Nat.
This ensures that the correct ordering of side effects is preserved, and it ensures that programs that have side effects are clearly marked as such.

                21.1.1. The IO, EIO and BaseIO Monads

                There are two monads that are typically used for programs that interact with the real world:

                    Actions in IO may throw exceptions of type IO.Error or modify the world.

                    Actions in BaseIO can't throw exceptions, but they can modify the world.

                The distinction makes it possible to tell whether exceptions are possible by looking at an action's type signature.
BaseIO actions are automatically promoted to IO as necessary.

                def

BaseIO (α : Type) : Type
BaseIO (α : Type) : Type

                    An IO monad that cannot throw exceptions.

                def

IO : Type → Type
IO : Type → Type

                    A monad that supports arbitrary side effects and throwing exceptions of type IO.Error.

                IO is an instance of EIO, in which the type of errors is a parameter.
In particular, IO is defined as EIO IO.Error.
In some circumstances, such as bindings to non-Lean libraries, it can be convenient to use EIO with a custom error type, which ensures that errors are handled at the boundaries between these and other IO actions.

                def

EIO (ε α : Type) : Type
EIO (ε α : Type) : Type

                    A monad that can have side effects on the external world or throw exceptions of type ε.

                    BaseIO is a version of this monad that cannot throw exceptions. IO sets the exception type to
IO.Error.

                def

IO.lazyPure {α : Type} (fn : Unit → α) : IO α
IO.lazyPure {α : Type} (fn : Unit → α) :
  IO α

                    Creates an IO action that will invoke fn if and when it is executed, returning the result.

                def

BaseIO.toIO {α : Type} (act : BaseIO α) : IO α
BaseIO.toIO {α : Type} (act : BaseIO α) :
  IO α

                    Runs a BaseIO action, which cannot throw an exception, as an IO action.

                    This function is usually used implicitly via automatic monadic
lifting rather than being called explicitly.

                def

BaseIO.toEIO {α ε : Type} (act : BaseIO α) : EIO ε α
BaseIO.toEIO {α ε : Type}
  (act : BaseIO α) : EIO ε α

                    Runs a BaseIO action, which cannot throw an exception, in any other EIO monad.

                    This function is usually used implicitly via automatic monadic
lifting rather being than called explicitly.

                def

EIO.toBaseIO {ε α : Type} (act : EIO ε α) : BaseIO (Except ε α)
EIO.toBaseIO {ε α : Type}
  (act : EIO ε α) : BaseIO (Except ε α)

                    Converts an EIO ε action that might throw an exception of type ε into an exception-free BaseIO
action that returns an Except value.

                def

EIO.toIO {ε α : Type} (f : ε → IO.Error) (act : EIO ε α) : IO α
EIO.toIO {ε α : Type} (f : ε → IO.Error)
  (act : EIO ε α) : IO α

                    Converts an EIO ε action into an IO action by translating any exceptions that it throws into
IO.Errors using f.

                def

EIO.toIO' {ε α : Type} (act : EIO ε α) : IO (Except ε α)
EIO.toIO' {ε α : Type} (act : EIO ε α) :
  IO (Except ε α)

                    Converts an EIO ε action that might throw an exception of type ε into an exception-free IO
action that returns an Except value.

                def

IO.toEIO {ε α : Type} (f : IO.Error → ε) (act : IO α) : EIO ε α
IO.toEIO {ε α : Type} (f : IO.Error → ε)
  (act : IO α) : EIO ε α

                    Runs an IO action in some other EIO monad, using f to translate IO exceptions.

                21.1.2. Errors and Error Handling in IO

                Error handling in the IO monad uses the same facilities as any other exception monad.
In particular, throwing and catching exceptions uses the methods of the MonadExceptOf type class.
The exceptions thrown in IO have the type IO.Error.
The constructors of this type represent the low-level errors that occur on most operating systems, such as files not existing.
The most-used constructor is userError, which covers all other cases and includes a string that describes the problem.

                inductive type

IO.Error : Type
IO.Error : Type

                    Exceptions that may be thrown in the IO monad.

                    Many of the constructors of IO.Error correspond to POSIX error numbers. In these cases, the
documentation string lists POSIX standard error macros that correspond to the error. This list is
not necessarily exhaustive, and these constructor includes a field for the underlying error number.

                      Constructors

IO.Error.alreadyExists (filename : Option String)
  (osCode : UInt32) (details : String) : IO.Error

                          The operation failed because a file already exists.

                          This corresponds to POSIX errors EEXIST, EINPROGRESS, and EISCONN.

IO.Error.otherError (osCode : UInt32) (details : String) :
  IO.Error

                          Some error not covered by the other constructors of IO.Error occurred.

                          This also includes POSIX error EFAULT.

IO.Error.resourceBusy (osCode : UInt32) (details : String) :
  IO.Error

                          A necessary resource was busy.

                          This corresponds to POSIX errors EADDRINUSE, EBUSY, EDEADLK, and ETXTBSY.

IO.Error.resourceVanished (osCode : UInt32)
  (details : String) : IO.Error

                          A necessary resource is no longer available.

                          This corresponds to POSIX errors ECONNRESET, EIDRM, ENETDOWN, ENETRESET, ENOLINK, and
EPIPE.

IO.Error.unsupportedOperation (osCode : UInt32)
  (details : String) : IO.Error

                          An operation was not supported.

                          This corresponds to POSIX errors EADDRNOTAVAIL, EAFNOSUPPORT, ENODEV, ENOPROTOOPT
ENOSYS, EOPNOTSUPP, ERANGE, ESPIPE, and EXDEV.

IO.Error.hardwareFault (osCode : UInt32)
  (details : String) : IO.Error

                          The operation failed due to a hardware problem, such as an I/O error.

                          This corresponds to the POSIX error EIO.

IO.Error.unsatisfiedConstraints (osCode : UInt32)
  (details : String) : IO.Error

                          A constraint required by an operation was not satisfied (e.g. a directory was not empty).

                          This corresponds to the POSIX error ENOTEMPTY.

IO.Error.illegalOperation (osCode : UInt32)
  (details : String) : IO.Error

                          An inappropriate I/O control operation was attempted.

                          This corresponds to the POSIX error ENOTTY.

IO.Error.protocolError (osCode : UInt32)
  (details : String) : IO.Error

                          A protocol error occurred.

                          This corresponds to the POSIX errors EPROTO, EPROTONOSUPPORT, and EPROTOTYPE.

IO.Error.timeExpired (osCode : UInt32) (details : String) :
  IO.Error

                          An operation timed out.

                          This corresponds to the POSIX errors ETIME, and ETIMEDOUT.

IO.Error.interrupted (filename : String) (osCode : UInt32)
  (details : String) : IO.Error

                          The operation was interrupted.

                          This corresponds to the POSIX error EINTR.

IO.Error.noFileOrDirectory (filename : String)
  (osCode : UInt32) (details : String) : IO.Error

                          No such file or directory.

                          This corresponds to the POSIX error ENOENT.

IO.Error.invalidArgument (filename : Option String)
  (osCode : UInt32) (details : String) : IO.Error

                          An argument to an I/O operation was invalid.

                          This corresponds to the POSIX errors ELOOP, ENAMETOOLONG, EDESTADDRREQ, EILSEQ, EINVAL, EDOM, EBADF
ENOEXEC, ENOSTR, ENOTCONN, and ENOTSOCK.

IO.Error.permissionDenied (filename : Option String)
  (osCode : UInt32) (details : String) : IO.Error

                          An operation failed due to insufficient permissions.

                          This corresponds to the POSIX errors EACCES, EROFS, ECONNABORTED, EFBIG, and EPERM.

IO.Error.resourceExhausted (filename : Option String)
  (osCode : UInt32) (details : String) : IO.Error

                          A resource was exhausted.

                          This corresponds to the POSIX errors  EMFILE, ENFILE, ENOSPC, E2BIG, EAGAIN, EMLINK,
EMSGSIZE, ENOBUFS, ENOLCK, ENOMEM, and ENOSR.

IO.Error.inappropriateType (filename : Option String)
  (osCode : UInt32) (details : String) : IO.Error

                          An argument was the wrong type (e.g. a directory when a file was required).

                          This corresponds to the POSIX errors EISDIR, EBADMSG, and ENOTDIR.

IO.Error.noSuchThing (filename : Option String)
  (osCode : UInt32) (details : String) : IO.Error

                          A required resource does not exist.

                          This corresponds to the POSIX errors ENXIO, EHOSTUNREACH, ENETUNREACH, ECHILD,
ECONNREFUSED, ENODATA, ENOMSG, and ESRCH.

IO.Error.unexpectedEof : IO.Error

                          An unexpected end-of-file marker was encountered.

IO.Error.userError (msg : String) : IO.Error

                          Some other error occurred.

                def

IO.Error.toString : IO.Error → String
IO.Error.toString : IO.Error → String

                    Converts an IO.Error to a descriptive string.

                    IO.Error.userError is converted to its embedded message. The other constructors are converted in a
way that preserves structured information, such as error codes and filenames, that can help
diagnose the issue.

                def

IO.ofExcept.{u_1} {ε : Type u_1} {α : Type} [ToString ε]
  (e : Except ε α) : IO α
IO.ofExcept.{u_1} {ε : Type u_1}
  {α : Type} [ToString ε]
  (e : Except ε α) : IO α

                    Converts an Except ε action into an IO action.

                    If the Except ε action throws an exception, then the exception type's ToString instance is used
to convert it into an IO.Error, which is thrown. Otherwise, the value is returned.

                def

EIO.catchExceptions {ε α : Type} (act : EIO ε α) (h : ε → BaseIO α) :
  BaseIO α
EIO.catchExceptions {ε α : Type}
  (act : EIO ε α) (h : ε → BaseIO α) :
  BaseIO α

                    Handles any exception that might be thrown by an EIO ε action, transforming it into an
exception-free BaseIO action.

                def

IO.userError (s : String) : IO.Error
IO.userError (s : String) : IO.Error

                    Constructs an IO.Error from a string.

                    IO.Error is the type of exceptions thrown by the IO monad.

              Throwing and Catching Errors

                    This program repeatedly demands a password, using exceptions for control flow.
The syntax used for exceptions is available in all exception monads, not just IO.
When an incorrect password is provided, an exception is thrown, which is caught by the loop that repeats the password check.
A correct password allows control to proceed past the check, terminating the loop, and any other exceptions are re-thrown.
                  def accessControl : IO Unit := do
  IO.println "What is the password?"
  let password ← (← IO.getStdin).getLine
  if password.trimAscii.copy != "secret" then
    throw (.userError "Incorrect password")
  else return

def repeatAccessControl : IO Unit := do
  repeat
    try
      accessControl
      break
    catch
      | .userError "Incorrect password" =>
        continue
      | other =>
        throw other

def main : IO Unit := do
  repeatAccessControl
  IO.println "Access granted!"

                    When run with this input:

                    stdinpublicinfosecondtrysecret

                    the program emits:

                    stdoutWhat is the password?What is the password?What is the password?Access granted!
