# Inventory generator: first run notes (Phase 1 step 2)

> Source: own work in this repository (`scripts/gen_inventory.py`, `scripts/check_inventory.py`), run on `~/Projects/cats-effect` at v3.7.1 (`eb0cc258`)
> Collected: 2026-11-10
> Published: 2026-11-10

## Result

`python3 scripts/gen_inventory.py` wrote 3,255 rows to `inventory/inventory.csv`. Two runs gave byte-identical output.

| area | kind | todo | excluded |
|------|------|-----:|---------:|
| core | constructor | 37 | 0 |
| core | runloop-branch | 58 | 0 |
| core | method | 394 | 334 |
| kernel | constructor | 10 | 0 |
| kernel | method | 358 | 496 |
| std | method | 481 | 182 |
| laws | law | 58 | 2 |
| laws | method | 0 | 16 |
| runtime | method | 0 | 829 |
| **total** | | **1,396** | **1,859** |

Excluded rows by reason prefix: `deferred:` 968 (571 runtime, 306 monad-transformer instances, 91 core app/tracing support), `platform:` 483, `internal:` 287, `trivial:` 116, `no-behaviour:` 5.

Constructors: 26 `IO` tags (0..24 and `EndFiber` -1), 11 `SyncIO` tags (0..10), 3 `Outcome`, 4 `Resource`, 3 `Resource.ExitCase`.
Run-loop branches: `IOFiber.runLoop` has 25 top-level tag cases plus the `EndFiber` early return, plus 21 fast-path sub-cases (`Map`, `FlatMap`, `Attempt` over `Pure`/`Error`/`Delay`/`RealTime`/`Monotonic`/`ReadEC`/default). `SyncIO.runLoop` has 11 tag cases.
Laws: 58 law defs. 2 are `@deprecated` (`GenSpawnLaws.raceCanceledIdentityLeft/Right`) and are excluded as `trivial:`.

## Validation

- Every row was checked by a script: the cited line holds `def <name>` / `val <name>` (method, law), `class|object <name>` (constructor), or `case N =>` (run-loop branch). 0 mismatches out of 3,255.
- 22 random rows were also read by eye against the source. All were correct.
- `scripts/check_inventory.py` passes. It also passes with the file check skipped (no checkout, as in CI).

## Scope decisions

- JVM is the target platform. `jvm/` and `jvm-native/` sources count as in scope. `js/`, `native/`, `js-native/` sources are `excluded` with `platform:`. Their ids get a platform segment (`core.js.IOApp...`) so that JVM rows keep the plain ids.
- Core files in scope: `IO`, `IOFiber`, `SyncIO`, `IODeferred`, `IOLocal`, `ContState`, `LiftIO`, the `ByteStack`/`ArrayStack`/`CallbackStack` data structures, and the JVM `IO*Platform` files. Other core files (`IOApp`, `ResourceApp`, tracing, metrics, CPU starvation check, fiber snapshots, signals, selectors) are `deferred: phase 9`. `syntax/`, `instances/`, `implicits`, `package.scala` are `trivial:`.
- `unsafe/**` is area `runtime`, all `deferred: phase 9`.
- `private` / `protected` members are `excluded` with `internal:`. Exceptions: all `IOFiber` members stay `todo` (they are the run loop we mirror), and two private interpreters stay `todo`: `Resource.fold` and `SyncStep.interpret` (the `IO.syncStep` interpreter, a twin of the run loop).
- Members of named private implementation classes (for example `Queue.BoundedQueue`, `Semaphore.impl`, `IO.IOAsync`) stay `todo`. They hold the real behavior and some are twins (the two `Queue` implementations, the `IO` overrides of derived combinators in `IOAsync`).
- Monad-transformer instances (`OptionT`, `EitherT`, `IorT`, `Kleisli`, `WriterT`, `StateT`, `ReaderWriterStateT`) are `deferred:`. They lift behavior that we model first on `IO` and on the generic derived combinators.
- `@deprecated` members are `trivial:` (binary-compatibility shims; the current API has its own row). `toString` is `no-behaviour:`. Auxiliary constructors (`def this`) are `trivial:`.
- Kernel and std `syntax/` files are `trivial:` (forwarders).
- Members of the `IO`/`SyncIO` constructor case classes (`def tag`) get no rows; the constructor row covers them.
- Law traits: only `def`s of the `*Laws` trait itself are `law` rows. The instance parameter `F`, the `app` helper, and the companion `apply` factory are `method` rows, `excluded` as `trivial:`.

## Parser limits

- Line/brace scanner, not a Scala parser. It blanks comments (nested `/* */`), string literals (including `"""`), and char literals first.
- Members of anonymous classes (`new Foo { def ... }`) and local defs inside a def body are not rows. About 430 such defs exist in kernel, std and `IO*.scala` (for example the `mapK` wrappers and the anonymous `Semaphore` implementation). The abstract trait member row covers each of them.
- Modifiers (`private`, `protected`) are read only from the line of the `def`. A modifier on an earlier line would be missed. None was seen.
- `@deprecated` is found on the `def` line or on up to three annotation lines above it.
- An `s"... ${ "x" } ..."` string with a nested quote would confuse the string blanking. None affects the result (the line check passed for all rows).
- Overloads and a trait plus its companion with the same member name share a base id. The second and later get `#2`, `#3` in source order.
- Run-loop branches are found by the pattern `(cur0.tag: @switch) match {` and sub-switches on `ioe.tag` / `ioa.tag`. Other dispatches (the `resumeTag` switch, the continuation switches in `succeeded`/`failed`) are not branch rows; their methods have method rows.
