# Let's discuss the cancelation model (cats-effect discussion #1979, A. Nedelcu)

> Source: https://github.com/typelevel/cats-effect/discussions/1979
> Collected: 2026-11-10
> Published: 2021-05-18

I may revive an old topic that was already discussed. Sorry about that, better late than never 🙂

Take this snippet of code, that continuously writes lines of text into a file (a resource), and we attempt killing it via a `timeout` ...

```scala
import cats.effect._
import java.io._
import scala.concurrent.duration._

object Hello extends IOApp {

  override def run(args: List[String]): IO[ExitCode] = {
    val task = IO.bracketFull { _ => 
      IO(
        new BufferedWriter(
          new OutputStreamWriter(
            new FileOutputStream(new File("/tmp/hello")),
            "utf-8"
          )))
    } { reader => 
      IO {
        var line = 0
        while (true) {
          println(s"Writing line $line ...")
          reader.write("Hello, world!\n")
          reader.flush()
          line += 1
          Thread.sleep(1000)
        }
        ExitCode.Success
      }
    } { (reader, outcome) =>
      IO {
        println(s"Ending with: $outcome")
        reader.close()
        ()
      }
    }
    
    // Race condition here...
    task.timeout(10.seconds)
  }
}
```

In Cats Effect 2.x this program behaves as expected (to me anyway) — it triggers a `TimeoutException` after 10 seconds and exits. It may also log an `IOException` via the thread's default error handler (because that Writer ends up forcefully closed).

In Cats Effect 3.x this program is stuck forever. It can't be killed by `SIGHUP` / `SIGTERM` either, so `IOApp` too is problematic — it definitely defies common sense, being very unlike normal app behavior (because you can interrupt a `Main` with a `while (true)`, by default, in most programming environments I've seen).

And I fear this is by design, a design (possibly imported from ZIO) with which I deeply disagree with. If this behavior is by design, it completely misses the main purpose of cancellation.

Cancellation is NOT user input. We have other ways for modeling user input. If we want to detect the *client's intent* to exit, we could share a `Defer` (aka fancy `Future`), or some sort of stream. Cancellation is forceful shutdown in case of a race condition. Cancellation is not a SHOULD, but a MUST. It doesn't matter if we now have an `IO.blocking` that's well-behaved. Being able to do a forceful shutdown of resources should not rely on good client behavior.

In the old Cats Effect 2.x the problem was that the resource could have been closed while in use, concurrently, leading to an `IOException` and possibly corrupted data. But that was better than this — one does expect corrupted data in case of cancellation, being normal. Whereas this behavior here can create a zombie process that can't be killed without a `SIGKILL`, which is not normal, defeating common sense.

---

In terms of network protocols, getting confirmation from the client that a "connection" is no longer used or closed is a pretty bad idea, because the client might misbehave. In case of a race condition (such as a `timeout`) a `cancel()` is not an operation that you want to back-pressure, before or after invoking it.

The perennial example is the TCP protocol. Google is filled with articles on detecting "closed TCP connections" or "broken TCP connections". Detecting liveness is its own can of worms, but even closing a connection is pretty challenging, as it goes via a complex handshake, like this:

![image](https://user-images.githubusercontent.com/11753/118631862-937a0b00-b7d8-11eb-9a29-f59720f40786.png)

Note how the protocol has states like `FIN_WAIT_1`, `TIMED_WAIT`, `FIN_WAIT_2`, `CLOSE_WAIT`. These states are reflected at the kernel level. They are timed-out by the kernel at some point, because either the client or the server can completely stop responding.

Even with that timeout, because it's a generous one, with huge traffic you can still end up with so many opened file handles that you can exhaust the available file handles, with the kernel refusing to allocate more, temporarily, until the timeouts are triggered. You can then, of course, modify the OS's settings, e.g you can increase the file handles available (since they are cheap), you can decrease the timeouts, etc.

The question is ... if a client is misbehaving, should the app freeze because of it? If it's a long-running server we're talking about, the answer is almost always no — the right answer is for the client's connection to get killed. And it is true that sometimes we can't stop a client easily. For example inside a JVM process this can't be easily killed:

```scala
IO { while (true) {} }
```

And that's fine. `IO.race` and `IO.timeout` should still work on it though. Yes, this too creates a leak, which may end up crashing the process, but that's a better outcome than a frozen process that can't be restarted by a supervisor 😉 

---

Also, `IOApp` should forcefully kill the app when repeatedly getting `SIGHUP` / `SIGTERM` signals. That you can't specify such a behavior via normal mechanisms (other than giving up and manually triggering a `System.exit` at some point) indicates we have a problem.

---

Speaking of, it always seemed wrong that `bracket`'s `release` triggers an `IO[Unit]`, which can be asynchronous in case of cancellation. A release in case of cancellation should always be synchronous. If you have to block on anything to do a release in case of cancellation, that's just wrong.

I always disliked `bracket`, feels like an improvement over the status quo, but it invalidates the reasoning we have with `Monad` and I'm getting the feeling that it is a bad gift that keeps on giving 🤷‍♂️

---

Sorry for my strong opinions, I just had an emotional reaction 😅

[...omitted: replies (not collected)...]
