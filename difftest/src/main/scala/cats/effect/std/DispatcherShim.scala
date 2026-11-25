package cats.effect.std

/** Difftest access (format v2, Phase 7 track P7D) to `Dispatcher`'s worker count. `Cpus`
  * (`Dispatcher.scala:108`, `Runtime.getRuntime().availableProcessors()`) is a `static final int`
  * of `Dispatcher$`; `parallel` makes `Cpus` workers and picks one with
  * `ThreadLocalRandom.current().nextInt(Cpus)` (`:277`, `:327`). The difftest sets it to 1 once,
  * right after the class is initialized and before any `Dispatcher` code runs, so the worker choice
  * is fixed (the model takes it as an input). A JVM flag (`-XX:ActiveProcessorCount=1`) would also
  * do it, but it changes the JVM for every other op too (it moved the identity-hash order of a
  * track V `Supervisor` case in the self-test).
  */
object DispatcherShim:
  private val field = "cats$effect$std$Dispatcher$$$Cpus"

  /** The current value of `Cpus`. */
  def cpus: Int =
    val f = Class.forName("cats.effect.std.Dispatcher$").getDeclaredField(field)
    f.setAccessible(true)
    f.getInt(null)

  /** Set `Cpus` to 1 (once). */
  lazy val oneCpu: Unit =
    val _ = Dispatcher // class initialization (`Cpus` is assigned in `<clinit>`)
    val cls = Class.forName("cats.effect.std.Dispatcher$")
    val f = cls.getDeclaredField(field)
    val uf = classOf[sun.misc.Unsafe].getDeclaredField("theUnsafe")
    uf.setAccessible(true)
    val u = uf.get(null).asInstanceOf[sun.misc.Unsafe]
    u.putInt(u.staticFieldBase(f), u.staticFieldOffset(f), 1)
