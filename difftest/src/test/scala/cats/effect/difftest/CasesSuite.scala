package cats.effect.difftest

import java.nio.file.{Files, Path, Paths}
import scala.jdk.CollectionConverters.*

/** Golden test: each `cases/NAME.jsonl` line must give the line in `cases/NAME.expected.jsonl`.
  * Regenerate the expected files with `sbt -Ddifftest.update=true test`, then review the diff.
  */
class CasesSuite extends munit.FunSuite:
  private val dir = Paths.get("cases")
  private val update = sys.props.get("difftest.update").contains("true")

  private def inputs: List[Path] =
    Files.list(dir).iterator.asScala.filter(p => p.toString.endsWith(".jsonl") && !p.toString.endsWith(".expected.jsonl")).toList.sorted

  private def lines(p: Path): List[String] = Files.readAllLines(p).asScala.toList.filter(_.trim.nonEmpty)

  for in <- inputs do
    val expectedPath = Paths.get(in.toString.stripSuffix(".jsonl") + ".expected.jsonl")
    val ins = lines(in)
    val got = ins.map(Main.runLine)
    if update then Files.write(expectedPath, got.asJava)
    val expected = if Files.exists(expectedPath) then lines(expectedPath) else Nil
    test(s"${in.getFileName}: same number of results") {
      assertEquals(got.size, expected.size)
    }
    for ((g, e), i) <- got.zip(expected).zipWithIndex do
      val id = scala.util.Try(ujson.read(ins(i))("id").str).getOrElse(i.toString)
      test(s"${in.getFileName}: $id") {
        assertEquals(ujson.read(g), ujson.read(e))
        // replay and testcontrol runs are deterministic: a second run gives the same line
        assertEquals(Main.runLine(ins(i)), g)
      }

  // Hand-checked facts, so the golden files are not only "what the runner printed".
  private def run(id: String): ujson.Value =
    val line = lines(dir.resolve("basic.jsonl")).find(l => ujson.read(l)("id").str == id).get
    ujson.read(Main.runLine(line))

  private def nat(n: Int) = ujson.Obj("t" -> "nat", "v" -> n)

  test("facts: uncancelable body runs to the end after IO.canceled, then the fiber still succeeds") {
    // IO.canceled inside uncancelable only marks the fiber; with no poll the outcome is the body
    assertEquals(run("uncancelable-canceled-continues")("outcome"), ujson.Obj("t" -> "succeeded", "v" -> nat(1)))
  }
  test("facts: external cancel of the root runs the onCancel finalizer") {
    val r = run("external-cancel-root")
    assertEquals(r("outcome")("t").str, "canceled")
    assertEquals(r("trace")(0)("ev").str, "fin")
  }
  test("facts: second Deferred.complete returns false") {
    assertEquals(run("deferred-handoff")("trace")(1)("ok").bool, false)
  }
  test("facts: the chosen schedule changes the interleaving") {
    def args(id: String) = run(id)("trace").arr.map(_("arg")("v").num.toInt).toList
    assertEquals(args("two-fibers-fifo"), List(1, 3, 2, 4))
    assertEquals(args("two-fibers-chosen"), List(3, 1, 2, 4))
  }
  test("facts: a second async callback call is ignored") {
    assertEquals(run("async-later-twice")("outcome"), ujson.Obj("t" -> "succeeded", "v" -> nat(1)))
  }
  test("facts: sleep advances virtual time") {
    assertEquals(run("sleep-time")("time").num, 100.0)
  }
  test("decoder rejects unbound variables, unknown keys and handle literals") {
    for bad <- List(
        """{"v":0,"id":"a","mode":"replay","prog":{"op":"pure","v":{"t":"var","x":"y"}}}""",
        """{"v":0,"id":"b","mode":"replay","prog":{"op":"pure","v":{"t":"unit"},"extra":1}}""",
        """{"v":0,"id":"c","mode":"replay","prog":{"op":"pure","v":{"t":"fiber","id":0}}}""",
        """{"v":0,"id":"d","mode":"replay","prog":{"op":"poll","poll":"p","e":{"op":"cede"}}}""",
        """{"v":3,"id":"e","mode":"replay","prog":{"op":"cede"}}""",
        """{"v":0,"id":"f","mode":"replay","prog":{"op":"queueNew"}}""",
        """{"v":1,"id":"g","mode":"replay","prog":{"op":"seq","ps":[{"op":"syncStep","limit":1,"e":{"op":"cede"}}]}}""",
        """{"v":1,"id":"h","mode":"replay","prog":{"op":"rPure","v":{"t":"unit"}}}""",
        """{"v":1,"id":"i","mode":"replay","prog":{"op":"pure","v":{"t":"queue","id":0}}}""",
        """{"v":1,"id":"j","mode":"replay","prog":{"op":"guarantee","e":{"op":"cede"},"fin":{"op":"cede"}}}""",
        """{"v":2,"id":"k","mode":"replay","prog":{"op":"bracket","acq":{"op":"pure","v":{"t":"var","x":"a"}},"x":"a","use":{"op":"cede"},"rel":{"op":"cede"}}}""",
        """{"v":2,"id":"l","mode":"replay","prog":{"op":"bracketFull","poll":"p","acq":{"op":"cede"},"x":"a","use":{"op":"poll","poll":"p","e":{"op":"cede"}},"y":"o","rel":{"op":"cede"}}}"""
      )
    do assert(ujson.read(Main.runLine(bad)).obj.contains("error"), bad)
  }
