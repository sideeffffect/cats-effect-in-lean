# Lean 4 reference: Tasks and Threads (v4.34.0)

> Source: https://lean-lang.org/doc/reference/4.34.0/IO/Tasks-and-Threads/
> Collected: 2026-11-10
> Published: Unknown

Tasks and Threads

              21.11. Tasks and Threads

              Tasks are the fundamental primitive for writing multi-threaded code.
A Task α represents a computation that, at some point, will resolve to a value of type α; it may be computed on a separate thread.
When a task has resolved, its value can be read; attempting to get the value of a task before it resolves causes the current thread to block until the task has resolved.
Tasks are similar to promises in JavaScript, JoinHandle in Rust, and Future in Scala.

              Tasks may either carry out pure computations or IO actions.
The API of pure tasks resembles that of thunks: Task.spawn creates a Task α from a function in Unit → α, and Task.get waits until the function's value has been computed and then returns it.
The value is cached, so subsequent requests do not need to recompute it.
The key difference lies in when the computation occurs: while the values of thunks are not computed until they are forced, tasks execute opportunistically in a separate thread.

              Tasks in IO are created using IO.asTask.
Similarly, BaseIO.asTask and EIO.asTask create tasks in other IO monads.
These tasks may have side effects, and can communicate with other tasks.

              When the last reference to a task is dropped it is canceled.
Pure tasks created with Task.spawn are terminated upon cancellation.
Tasks spawned with IO.asTask, EIO.asTask, or BaseIO.asTask continue executing and must explicitly check for cancellation using IO.checkCanceled.
Tasks may be explicitly canceled using IO.cancel.

              The Lean runtime maintains a thread pool for running tasks.
The size of the thread pool is determined by the environment variable LEAN_NUM_THREADS if it is set, or by the number of logical processors on the current machine otherwise.
The size of the thread pool is not a hard limit; in certain situations it may be exceeded to avoid deadlocks.
By default, these threads are used to run tasks; each task has a priority (Task.Priority), and higher-priority tasks take precedence over lower-priority tasks.
Tasks may also be assigned to dedicated threads by spawning them with a sufficiently high priority.

              type

Task.{u} (α : Type u) : Type u
Task.{u} (α : Type u) : Type u

                  Task α is a primitive for asynchronous computation.
It represents a computation that will resolve to a value of type α,
possibly being computed on another thread. This is similar to Future in Scala,
Promise in Javascript, and JoinHandle in Rust.

                  The tasks have an overridden representation in the runtime.

                21.11.1. Creating Tasks

                Pure tasks should typically be created with Task.spawn, as Task.pure is a task that's already been resolved with the provided value.
Impure tasks are created by one of the asTask actions.

                  21.11.1.1. Pure Tasks

                  Pure tasks may be created outside the IO family of monads.
They are terminated when the last reference to them is dropped.

                  def

Task.spawn.{u} {α : Type u} (fn : Unit → α)
  (prio : Task.Priority := Task.Priority.default) : Task α
Task.spawn.{u} {α : Type u}
  (fn : Unit → α)
  (prio : Task.Priority :=
    Task.Priority.default) :
  Task α

                      spawn fn : Task α constructs and immediately launches a new task for
evaluating the function fn () : α asynchronously.

                      prio, if provided, is the priority of the task.

                  constructor of Task

Task.pure.{u} {α : Type u} (get : α) : Task α
Task.pure.{u} {α : Type u} (get : α) :
  Task α

                      Task.pure (a : α) constructs a task that is already resolved with value a.

                  21.11.1.2. Impure Tasks

                  When spawning a task with side effects using one of the asTask functions, it's important to actually execute the resulting IO action.
A task is spawned each time the resulting action is executed, not when asTask is called.
Impure tasks continue running even when there are no references to them, though this does result in cancellation being requested.
Cancellation may also be explicitly requested using IO.cancel.
The impure task must check for cancellation using IO.checkCanceled.

                  opaque

BaseIO.asTask {α : Type} (act : BaseIO α)
  (prio : Task.Priority := Task.Priority.default) : BaseIO (Task α)
BaseIO.asTask {α : Type} (act : BaseIO α)
  (prio : Task.Priority :=
    Task.Priority.default) :
  BaseIO (Task α)

                      Runs act in a separate Task, with priority prio.

                      Running the resulting BaseIO action causes the task to be started eagerly. Pure accesses to the
Task do not influence the impure act.

                      Unlike pure tasks created by Task.spawn, tasks created by this function will run even if the last
reference to the task is dropped. The act should explicitly check for cancellation via
IO.checkCanceled if it should be terminated or otherwise react to the last reference being
dropped.

                  def

EIO.asTask {ε α : Type} (act : EIO ε α)
  (prio : Task.Priority := Task.Priority.default) :
  BaseIO (Task (Except ε α))
EIO.asTask {ε α : Type} (act : EIO ε α)
  (prio : Task.Priority :=
    Task.Priority.default) :
  BaseIO (Task (Except ε α))

                      Runs act in a separate Task, with priority prio. Because EIO ε actions may throw an exception
of type ε, the result of the task is an Except ε α.

                      Running the resulting IO action causes the task to be started eagerly. Pure accesses to the Task
do not influence the impure act.

                      Unlike pure tasks created by Task.spawn, tasks created by this function will run even if the last
reference to the task is dropped. The act should explicitly check for cancellation via
IO.checkCanceled if it should be terminated or otherwise react to the last reference being
dropped.

                  def

IO.asTask {α : Type} (act : IO α)
  (prio : Task.Priority := Task.Priority.default) :
  BaseIO (Task (Except IO.Error α))
IO.asTask {α : Type} (act : IO α)
  (prio : Task.Priority :=
    Task.Priority.default) :
  BaseIO (Task (Except IO.Error α))

                      Runs act in a separate Task, with priority prio. Because IO actions may throw an exception
of type IO.Error, the result of the task is an Except IO.Error α.

                      Running the resulting BaseIO action causes the task to be started eagerly. Pure accesses to the
Task do not influence the impure act. Because IO actions may throw an exception of type
IO.Error, the result of the task is an Except IO.Error α.

                      Unlike pure tasks created by Task.spawn, tasks created by this function will run even if the last
reference to the task is dropped. The act should explicitly check for cancellation via
IO.checkCanceled if it should be terminated or otherwise react to the last reference being
dropped.

                  21.11.1.3. Priorities

                  Task priorities are used by the thread scheduler to assign tasks to threads.
Within the priority range default–max, higher-priority tasks always take precedence over lower-priority tasks.
Tasks spawned with priority dedicated are assigned their own dedicated threads and do not contend with other tasks for the threads in the thread pool.

                  def

Task.Priority : Type
Task.Priority : Type

                      Task priority.

                      Tasks with higher priority will always be scheduled before tasks with lower priority. Tasks with a
priority greater than Task.Priority.max are scheduled on dedicated threads.

                  def

Task.Priority.default : Task.Priority
Task.Priority.default : Task.Priority

                      The default priority for spawned tasks, also the lowest priority: 0.

                  def

Task.Priority.max : Task.Priority
Task.Priority.max : Task.Priority

                      The highest regular priority for spawned tasks: 8.

                      Spawning a task with a priority higher than Task.Priority.max is not an error but will spawn a
dedicated worker for the task. This is indicated using Task.Priority.dedicated. Regular priority
tasks are placed in a thread pool and worked on according to their priority order.

                  def

Task.Priority.dedicated : Task.Priority
Task.Priority.dedicated : Task.Priority

                      Indicates that a task should be scheduled on a dedicated thread.

                      Any priority higher than Task.Priority.max will result in the task being scheduled
immediately on a dedicated thread. This is particularly useful for long-running and/or
I/O-bound tasks since Lean will, by default, allocate no more non-dedicated workers
than the number of cores to reduce context switches.

                21.11.2. Task Results

                def

Task.get.{u} {α : Type u} (self : Task α) : α
Task.get.{u} {α : Type u}
  (self : Task α) : α

                    Blocks the current thread until the given task has finished execution, and then returns the result
of the task. If the current thread is itself executing a (non-dedicated) task, the maximum
threadpool size is temporarily increased by one while waiting so as to ensure the process cannot
be deadlocked by threadpool starvation. Note that when the current thread is unblocked, more tasks
than the configured threadpool size may temporarily be running at the same time until sufficiently
many tasks have finished.

                    Task.map and Task.bind should be preferred over Task.get for setting up task dependencies
where possible as they do not require temporarily growing the threadpool in this way. In
particular, calling Task.get in a task continuation with (sync := true) will panic as the
continuation is decidedly not "cheap" in this case and deadlocks may otherwise occur. The
waited-upon task should instead be returned and unwrapped using Task.bind/IO.bindTask.

                opaque

IO.wait {α : Type} (t : Task α) : BaseIO α
IO.wait {α : Type} (t : Task α) : BaseIO α

                    Waits for the task to finish, then returns its result.

                opaque

IO.waitAny {α : Type} (tasks : List (Task α))
  (h : tasks.length > 0 := by exact Nat.zero_lt_succ _) : BaseIO α
IO.waitAny {α : Type}
  (tasks : List (Task α))
  (h : tasks.length > 0 := by
    exact Nat.zero_lt_succ _) :
  BaseIO α

                    Waits until any of the tasks in the list has finished, then returns its result.

                21.11.3. Sequencing Tasks

                These operators create new tasks from old ones.
When possible, it's good to use Task.map or Task.bind instead of manually calling Task.get in a new task because they don't temporarily increase the size of the thread pool.

                def

Task.map.{u_1, u_2} {α : Type u_1} {β : Type u_2} (f : α → β)
  (x : Task α) (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : Task β
Task.map.{u_1, u_2} {α : Type u_1}
  {β : Type u_2} (f : α → β) (x : Task α)
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) : Task β

                    map f x maps function f over the task x: that is, it constructs
(and immediately launches) a new task which will wait for the value of x to
be available and then calls f on the result.

                    prio, if provided, is the priority of the task.
If sync is set to true, f is executed on the current thread if x has already finished and
otherwise on the thread that x finished on. prio is ignored in this case. This should only be
done when executing f is cheap and non-blocking.

                def

Task.bind.{u_1, u_2} {α : Type u_1} {β : Type u_2} (x : Task α)
  (f : α → Task β) (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : Task β
Task.bind.{u_1, u_2} {α : Type u_1}
  {β : Type u_2} (x : Task α)
  (f : α → Task β)
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) : Task β

                    bind x f does a monad "bind" operation on the task x with function f:
that is, it constructs (and immediately launches) a new task which will wait
for the value of x to be available and then calls f on the result,
resulting in a new task which is then run for a result.

                    prio, if provided, is the priority of the task.
If sync is set to true, f is executed on the current thread if x has already finished and
otherwise on the thread that x finished on. prio is ignored in this case. This should only be
done when executing f is cheap and non-blocking.

                def

Task.mapList.{u_1, u_2} {α : Type u_1} {β : Type u_2} (f : List α → β)
  (tasks : List (Task α))
  (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : Task β
Task.mapList.{u_1, u_2} {α : Type u_1}
  {β : Type u_2} (f : List α → β)
  (tasks : List (Task α))
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) : Task β

                    Creates a task that, when all tasks have finished, computes the result of f applied to their
results.

                opaque

BaseIO.mapTask.{u_1} {α : Type u_1} {β : Type} (f : α → BaseIO β)
  (t : Task α) (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task β)
BaseIO.mapTask.{u_1} {α : Type u_1}
  {β : Type} (f : α → BaseIO β)
  (t : Task α)
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task β)

                    Creates a new task that waits for t to complete and then runs the BaseIO action f on its
result. This new task has priority prio.

                    Running the resulting BaseIO action causes the task to be started eagerly. Unlike pure tasks
created by Task.spawn, tasks created by this function will run even if the last reference to the
task is dropped. The act should explicitly check for cancellation via IO.checkCanceled if it
should be terminated or otherwise react to the last reference being dropped.

                def

EIO.mapTask.{u_1} {α : Type u_1} {ε β : Type} (f : α → EIO ε β)
  (t : Task α) (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task (Except ε β))
EIO.mapTask.{u_1} {α : Type u_1}
  {ε β : Type} (f : α → EIO ε β)
  (t : Task α)
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) :
  BaseIO (Task (Except ε β))

                    Creates a new task that waits for t to complete and then runs the IO action f on its result.
This new task has priority prio.

                    Running the resulting BaseIO action causes the task to be started eagerly. Unlike pure tasks
created by Task.spawn, tasks created by this function will run even if the last reference to the
task is dropped. The act should explicitly check for cancellation via IO.checkCanceled if it
should be terminated or otherwise react to the last reference being dropped. Because EIO ε actions
may throw an exception of type ε, the result of the task is an Except ε α.

                def

IO.mapTask.{u_1} {α : Type u_1} {β : Type} (f : α → IO β) (t : Task α)
  (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task (Except IO.Error β))
IO.mapTask.{u_1} {α : Type u_1} {β : Type}
  (f : α → IO β) (t : Task α)
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) :
  BaseIO (Task (Except IO.Error β))

                    Creates a new task that waits for t to complete and then runs the IO action f on its result.
This new task has priority prio.

                    Running the resulting BaseIO action causes the task to be started eagerly. Unlike pure tasks
created by Task.spawn, tasks created by this function will run even if the last reference to the
task is dropped. The act should explicitly check for cancellation via IO.checkCanceled if it
should be terminated or otherwise react to the last reference being dropped. Because IO actions
may throw an exception of type IO.Error, the result of the task is an Except IO.Error α.

                def

BaseIO.mapTasks.{u_1} {α : Type u_1} {β : Type} (f : List α → BaseIO β)
  (tasks : List (Task α))
  (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task β)
BaseIO.mapTasks.{u_1} {α : Type u_1}
  {β : Type} (f : List α → BaseIO β)
  (tasks : List (Task α))
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task β)

                    Creates a new task that waits for all the tasks in the list tasks to complete, and then runs the
IO action f on their results. This new task has priority prio.

                    Running the resulting BaseIO action causes the task to be started eagerly. Unlike pure tasks
created by Task.spawn, tasks created by this function will run even if the last reference to the
task is dropped. The act should explicitly check for cancellation via IO.checkCanceled if it
should be terminated or otherwise react to the last reference being dropped.

                def

EIO.mapTasks.{u_1} {α : Type u_1} {ε β : Type} (f : List α → EIO ε β)
  (tasks : List (Task α))
  (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task (Except ε β))
EIO.mapTasks.{u_1} {α : Type u_1}
  {ε β : Type} (f : List α → EIO ε β)
  (tasks : List (Task α))
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) :
  BaseIO (Task (Except ε β))

                    Creates a new task that waits for all the tasks in the list tasks to complete, and then runs the
EIO ε action f on their results. This new task has priority prio.

                    Running the resulting BaseIO action causes the task to be started eagerly. Unlike pure tasks
created by Task.spawn, tasks created by this function will run even if the last reference to the
task is dropped. The act should explicitly check for cancellation via IO.checkCanceled if it
should be terminated or otherwise react to the last reference being dropped.

                def

IO.mapTasks.{u_1} {α : Type u_1} {β : Type} (f : List α → IO β)
  (tasks : List (Task α))
  (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task (Except IO.Error β))
IO.mapTasks.{u_1} {α : Type u_1}
  {β : Type} (f : List α → IO β)
  (tasks : List (Task α))
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) :
  BaseIO (Task (Except IO.Error β))

                    IO specialization of EIO.mapTasks.

                opaque

BaseIO.bindTask.{u_1} {α : Type u_1} {β : Type} (t : Task α)
  (f : α → BaseIO (Task β))
  (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task β)
BaseIO.bindTask.{u_1} {α : Type u_1}
  {β : Type} (t : Task α)
  (f : α → BaseIO (Task β))
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task β)

                    Creates a new task that waits for t to complete, runs the IO action f on its result, and then
continues as the resulting task. This new task has priority prio.

                    Running the resulting BaseIO action causes this new task to be started eagerly. Unlike pure tasks
created by Task.spawn, tasks created by this function will run even if the last reference to the
task is dropped. The act should explicitly check for cancellation via IO.checkCanceled if it
should be terminated or otherwise react to the last reference being dropped.

                def

EIO.bindTask.{u_1} {α : Type u_1} {ε β : Type} (t : Task α)
  (f : α → EIO ε (Task (Except ε β)))
  (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task (Except ε β))
EIO.bindTask.{u_1} {α : Type u_1}
  {ε β : Type} (t : Task α)
  (f : α → EIO ε (Task (Except ε β)))
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) :
  BaseIO (Task (Except ε β))

                    Creates a new task that waits for t to complete, runs the EIO ε action f on its result, and
then continues as the resulting task. This new task has priority prio.

                    Running the resulting BaseIO action causes this new task to be started eagerly. Unlike pure tasks
created by Task.spawn, tasks created by this function will run even if the last reference to the
task is dropped. The act should explicitly check for cancellation via IO.checkCanceled if it
should be terminated or otherwise react to the last reference being dropped. Because EIO ε actions
may throw an exception of type ε, the result of the task is an Except ε α.

                def

IO.bindTask.{u_1} {α : Type u_1} {β : Type} (t : Task α)
  (f : α → IO (Task (Except IO.Error β)))
  (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : BaseIO (Task (Except IO.Error β))
IO.bindTask.{u_1} {α : Type u_1}
  {β : Type} (t : Task α)
  (f : α → IO (Task (Except IO.Error β)))
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) :
  BaseIO (Task (Except IO.Error β))

                    Creates a new task that waits for t to complete, runs the IO action f on its result, and then
continues as the resulting task. This new task has priority prio.

                    Running the resulting BaseIO action causes this new task to be started eagerly. Unlike pure tasks
created by Task.spawn, tasks created by this function will run even if the last reference to the
task is dropped. The act should explicitly check for cancellation via IO.checkCanceled if it
should be terminated or otherwise react to the last reference being dropped. Because IO actions
may throw an exception of type IO.Error, the result of the task is an Except IO.Error α.

                def

BaseIO.chainTask.{u_1} {α : Type u_1} (t : Task α) (f : α → BaseIO Unit)
  (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : BaseIO Unit
BaseIO.chainTask.{u_1} {α : Type u_1}
  (t : Task α) (f : α → BaseIO Unit)
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) : BaseIO Unit

                    Creates a new task that waits for t to complete and then runs the IO action f on its result.
This new task has priority prio.

                    This is a version of BaseIO.mapTask that ignores the result value.

                    Running the resulting BaseIO action causes the task to be started eagerly. Unlike pure tasks
created by Task.spawn, tasks created by this function will run even if the last reference to the
task is dropped. The act should explicitly check for cancellation via IO.checkCanceled if it
should be terminated or otherwise react to the last reference being dropped.

                def

EIO.chainTask.{u_1} {α : Type u_1} {ε : Type} (t : Task α)
  (f : α → EIO ε Unit) (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : EIO ε Unit
EIO.chainTask.{u_1} {α : Type u_1}
  {ε : Type} (t : Task α)
  (f : α → EIO ε Unit)
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) : EIO ε Unit

                    Creates a new task that waits for t to complete and then runs the EIO ε action f on its result.
This new task has priority prio.

                    This is a version of EIO.mapTask that ignores the result value.

                    Running the resulting EIO ε action causes the task to be started eagerly. Unlike pure tasks
created by Task.spawn, tasks created by this function will run even if the last reference to the
task is dropped. The act should explicitly check for cancellation via IO.checkCanceled if it
should be terminated or otherwise react to the last reference being dropped.

                def

IO.chainTask.{u_1} {α : Type u_1} (t : Task α) (f : α → IO Unit)
  (prio : Task.Priority := Task.Priority.default)
  (sync : Bool := false) : IO Unit
IO.chainTask.{u_1} {α : Type u_1}
  (t : Task α) (f : α → IO Unit)
  (prio : Task.Priority :=
    Task.Priority.default)
  (sync : Bool := false) : IO Unit

                    Creates a new task that waits for t to complete and then runs the IO action f on its result.
This new task has priority prio.

                    This is a version of IO.mapTask that ignores the result value.

                    Running the resulting IO action causes the task to be started eagerly. Unlike pure tasks created
by Task.spawn, tasks created by this function will run even if the last reference to the task is
dropped. The act should explicitly check for cancellation via IO.checkCanceled if it should be
terminated or otherwise react to the last reference being dropped.

                21.11.4. Cancellation and Status

                Impure tasks should use IO.checkCanceled to react to cancellation, which occurs either as a result of IO.cancel or when the last reference to the task is dropped.
Pure tasks are terminated automatically upon cancellation.

                opaque

IO.cancel.{u_1} {α : Type u_1} : Task α → BaseIO Unit
IO.cancel.{u_1} {α : Type u_1} :
  Task α → BaseIO Unit

                    Requests cooperative cancellation of the task. The task must explicitly call IO.checkCanceled to
react to the cancellation.

                opaque

IO.checkCanceled : BaseIO Bool
IO.checkCanceled : BaseIO Bool

                    Checks whether the current task's cancellation flag has been set by calling IO.cancel or by
dropping the last reference to the task.

                def

IO.hasFinished.{u_1} {α : Type u_1} (task : Task α) : BaseIO Bool
IO.hasFinished.{u_1} {α : Type u_1}
  (task : Task α) : BaseIO Bool

                    Checks whether the task has finished execution, at which point calling Task.get will return
immediately.

                opaque

IO.getTaskState.{u_1} {α : Type u_1} : Task α → BaseIO IO.TaskState
IO.getTaskState.{u_1} {α : Type u_1} :
  Task α → BaseIO IO.TaskState

                    Returns the current state of a task in the Lean runtime's task manager.

                    For tasks derived from Promises, the states waiting and running should be considered
equivalent.

                inductive type

IO.TaskState : Type
IO.TaskState : Type

                    The current state of a Task in the Lean runtime's task manager.

                      Constructors

IO.TaskState.waiting : IO.TaskState

                          The Task is waiting to be run.

                          It can be waiting for dependencies to complete or sitting in the task manager queue waiting for a
thread to run on.

IO.TaskState.running : IO.TaskState

                          The Task is actively running on a thread or, in the case of a Promise, waiting for a call to
IO.Promise.resolve.

IO.TaskState.finished : IO.TaskState

                          The Task has finished running and its result is available. Calling Task.get or IO.wait on
the task will not block.

                opaque

IO.getTID : BaseIO UInt64
IO.getTID : BaseIO UInt64

                    Returns the thread ID of the calling thread.

                21.11.5. Promises

                Promises represent a value that will be supplied in the future.
Supplying the value is called resolving the promise.
Once created, a promise can be stored in a data structure or passed around like any other value, and attempts to read from it will block until it is resolved.

                structure

IO.Promise (α : Type) : Type
IO.Promise (α : Type) : Type

                    Promise α allows you to create a Task α whose value is provided later by calling resolve.

                    Typical usage is as follows:

                        let promise ← Promise.new creates a promise

                        promise.result? : Task (Option α) can now be passed around

                        promise.result?.get blocks until the promise is resolved

                        promise.resolve a resolves the promise

                        promise.result?.get now returns some a

                    If the promise is dropped without ever being resolved, promise.result?.get will return none.
See Promise.result!/resultD for other ways to handle this case.

                opaque

IO.Promise.new {α : Type} [Nonempty α] : BaseIO (IO.Promise α)
IO.Promise.new {α : Type} [Nonempty α] :
  BaseIO (IO.Promise α)

                    Creates a new Promise.

                def

IO.Promise.isResolved {α : Type} (promise : IO.Promise α) : BaseIO Bool
IO.Promise.isResolved {α : Type}
  (promise : IO.Promise α) : BaseIO Bool

                    Checks whether the promise has already been resolved, i.e. whether access to result* will return
immediately.

                opaque

IO.Promise.result? {α : Type} (promise : IO.Promise α) : Task (Option α)
IO.Promise.result? {α : Type}
  (promise : IO.Promise α) :
  Task (Option α)

                    Like Promise.result, but resolves to none if the promise is dropped without ever being resolved.

                def

IO.Promise.result! {α : Type} (promise : IO.Promise α) : Task α
IO.Promise.result! {α : Type}
  (promise : IO.Promise α) : Task α

                    The result task of a Promise.

                    The task blocks until Promise.resolve is called. If the promise is dropped without ever being
resolved, evaluating the task will panic and, when not using fatal panics, block forever. As
Promise.result! is a pure value and thus the point of evaluation may not be known precisely, this
means that any promise on which Promise.result! may be evaluated must be resolved eventually.
When in doubt, always prefer Promise.result? to handle dropped promises explicitly.

                def

IO.Promise.resultD {α : Type} (promise : IO.Promise α) (dflt : α) :
  Task α
IO.Promise.resultD {α : Type}
  (promise : IO.Promise α) (dflt : α) :
  Task α

                    Like Promise.result, but resolves to dflt if the promise is dropped without ever being resolved.

                opaque

IO.Promise.resolve {α : Type} (value : α) (promise : IO.Promise α) :
  BaseIO Unit
IO.Promise.resolve {α : Type} (value : α)
  (promise : IO.Promise α) : BaseIO Unit

                    Resolves a Promise.

                    Only the first call to this function has an effect.

                21.11.6. Communication Between Tasks

                In addition to the types and operations described in this section, IO.Ref can be used as a lock.
Taking the reference (using take) causes other threads to block when reading until the reference is set again.
This pattern is described in the section on reference cells.

                  21.11.6.1. Channels

                  The types and functions in this section are available after importing Std.Sync.Channel.

                  structure

Std.Channel (α : Type) : Type
Std.Channel (α : Type) : Type

                      A multi-producer multi-consumer FIFO channel that offers both bounded and unbounded buffering
and an asynchronous API. To switch into synchronous mode use Channel.sync.

                      If a channel needs to be closed to indicate some sort of completion event use Std.CloseableChannel
instead. Note that Std.CloseableChannel introduces a need for error handling in some cases, thus
Std.Channel is usually easier to use if applicable.

                  def

Std.Channel.new {α : Type} (capacity : Option Nat := none) :
  BaseIO (Std.Channel α)
Std.Channel.new {α : Type}
  (capacity : Option Nat := none) :
  BaseIO (Std.Channel α)

                      Create a new channel. If:

                          capacity is none it will be unbounded (the default)

                          capacity is some 0 it will always force a rendezvous between sender and receiver

                          capacity is some n with n > 0 it will use a buffer of size n and begin blocking once it
is filled

                  def

Std.Channel.send {α : Type} (ch : Std.Channel α) (v : α) :
  BaseIO (Task Unit)
Std.Channel.send {α : Type}
  (ch : Std.Channel α) (v : α) :
  BaseIO (Task Unit)

                      Send a value through the channel, returning a task that will resolve once the transmission could be
completed.

                  def

Std.Channel.recv {α : Type} [Inhabited α] (ch : Std.Channel α) :
  BaseIO (Task α)
Std.Channel.recv {α : Type} [Inhabited α]
  (ch : Std.Channel α) : BaseIO (Task α)

                      Receive a value from the channel, returning a task that will resolve once the transmission could be
completed. Note that the task may resolve to none if the channel was closed before it could be
completed.

                  opaque

Std.Channel.forAsync {α : Type} [Inhabited α] (f : α → BaseIO Unit)
  (ch : Std.Channel α) (prio : Task.Priority := Task.Priority.default) :
  BaseIO (Task Unit)
Std.Channel.forAsync {α : Type}
  [Inhabited α] (f : α → BaseIO Unit)
  (ch : Std.Channel α)
  (prio : Task.Priority :=
    Task.Priority.default) :
  BaseIO (Task Unit)

                      ch.forAsync f calls f for every message received on ch.

                      Note that if this function is called twice, each message will only arrive at exactly one invocation.

                  def

Std.Channel.sync {α : Type} (ch : Std.Channel α) : Std.Channel.Sync α
Std.Channel.sync {α : Type}
  (ch : Std.Channel α) :
  Std.Channel.Sync α

                      This function is a no-op and just a convenient way to expose the synchronous API of the channel.

                  def

Std.Channel.Sync (α : Type) : Type
Std.Channel.Sync (α : Type) : Type

                      A multi-producer multi-consumer FIFO channel that offers both bounded and unbounded buffering
and a synchronous API. This type acts as a convenient layer to use a channel in a blocking fashion
and is not actually different from the original channel.

                      If a channel needs to be closed to indicate some sort of completion event use
Std.CloseableChannel.Sync instead. Note that Std.CloseableChannel.Sync introduces a need for error
handling in some cases, thus Std.Channel.Sync is usually easier to use if applicable.

                  def

Std.CloseableChannel (α : Type) : Type
Std.CloseableChannel (α : Type) : Type

                      A multi-producer multi-consumer FIFO channel that offers both bounded and unbounded buffering
and an asynchronous API, to switch into synchronous mode use CloseableChannel.sync.

                      Additionally Std.CloseableChannel can be closed if necessary, unlike Std.Channel.
This introduces a need for error handling in some cases, thus it is usually easier to use
Std.Channel if applicable.

                  def

Std.CloseableChannel.new {α : Type} (capacity : Option Nat := none) :
  BaseIO (Std.CloseableChannel α)
Std.CloseableChannel.new {α : Type}
  (capacity : Option Nat := none) :
  BaseIO (Std.CloseableChannel α)

                      Create a new channel. If:

                          capacity is none it will be unbounded (the default)

                          capacity is some 0 it will always force a rendezvous between sender and receiver

                          capacity is some n with n > 0 it will use a buffer of size n and begin blocking once it
is filled

                  Synchronous channels can also be read using Lean.Parser.Term.doFor : doElem`for x in e do s` iterates over `e` assuming `e`'s type has an instance of the `ForIn` typeclass.
`break` and `continue` are supported inside `for` loops.
`for x in e, x2 in e2, ... do s` iterates over the given collections in parallel,
until at least one of them is exhausted.
The types of `e2` etc. must implement the `Std.ToStream` typeclass.
for loops.
In particular, there is an instance of type ForIn m (Std.Channel.Sync α) α for every monad m with a MonadLiftT BaseIO m instance and α with an Inhabited α instance.

                  21.11.6.2. Mutexes

                  The types and functions in this section are available after importing Std.Sync.Mutex.

                  type

Std.Mutex (α : Type) : Type
Std.Mutex (α : Type) : Type

                      Mutual exclusion primitive (lock) guarding shared state of type α.

                      The type Mutex α is similar to IO.Ref α, except that concurrent accesses are guarded by a mutex
instead of atomic pointer operations and busy-waiting.

                  def

Std.Mutex.new {α : Type} (a : α) : BaseIO (Std.Mutex α)
Std.Mutex.new {α : Type} (a : α) :
  BaseIO (Std.Mutex α)

                      Creates a new mutex.

                  def

Std.Mutex.atomically {m : Type → Type} {α β : Type} [Monad m]
  [MonadLiftT BaseIO m] [MonadFinally m] (mutex : Std.Mutex α)
  (k : Std.AtomicT α m β) : m β
Std.Mutex.atomically {m : Type → Type}
  {α β : Type} [Monad m]
  [MonadLiftT BaseIO m] [MonadFinally m]
  (mutex : Std.Mutex α)
  (k : Std.AtomicT α m β) : m β

                      mutex.atomically k runs k with access to the mutex's state while locking the mutex.

                      Calling mutex.atomically while already holding the underlying BaseMutex in the same thread
is undefined behavior. If this is unavoidable in your code, consider using RecursiveMutex.

                  def

Std.Mutex.atomicallyOnce {m : Type → Type} {α β : Type} [Monad m]
  [MonadLiftT BaseIO m] [MonadFinally m] (mutex : Std.Mutex α)
  (condvar : Std.Condvar) (pred : Std.AtomicT α m Bool)
  (k : Std.AtomicT α m β) : m β
Std.Mutex.atomicallyOnce {m : Type → Type}
  {α β : Type} [Monad m]
  [MonadLiftT BaseIO m] [MonadFinally m]
  (mutex : Std.Mutex α)
  (condvar : Std.Condvar)
  (pred : Std.AtomicT α m Bool)
  (k : Std.AtomicT α m β) : m β

                      mutex.atomicallyOnce condvar pred k runs k, waiting on condvar until pred returns true.
Both k and pred have access to the mutex's state.

                      Calling mutex.atomicallyOnce while already holding the underlying BaseMutex in the same thread
is undefined behavior. If this is unavoidable in your code, consider using RecursiveMutex.

                  def

Std.AtomicT (σ : Type) (m : Type → Type) (α : Type) : Type
Std.AtomicT (σ : Type) (m : Type → Type)
  (α : Type) : Type

                      AtomicT α m is the monad that can be atomically executed inside mutual exclusion primitives like
Mutex α with outside monad m.
The action has access to the state α of the mutex (via get and set).

                  21.11.6.3. Condition Variables

                  The types and functions in this section are available after importing Std.Sync.Mutex.

                  def

Std.Condvar : Type
Std.Condvar : Type

                      Condition variable, a synchronization primitive to be used with a BaseMutex or Mutex.

                      The thread that wants to modify the shared variable must:

                          Lock the BaseMutex or Mutex

                          Work on the shared variable

                          Call Condvar.notifyOne or Condvar.notifyAll after it is done. Note that this may be done
before or after the mutex is unlocked.

                      If working with a Mutex the thread that waits on the Condvar can use Mutex.atomicallyOnce
to wait until a condition is true. If working with a BaseMutex it must:

                          Lock the BaseMutex.

                          Do one of the following:

                          Use Condvar.waitUntil to (potentially repeatedly wait) on the condition variable until
the condition is true.

                      
[...omitted: tail of API listing...]
