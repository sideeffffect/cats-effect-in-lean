package cats.effect.difftest

import scala.io.Source
import scala.util.control.NonFatal

/** Reads test cases as JSON lines on stdin and writes one result line per case on stdout.
  * Empty lines are skipped. A bad line gives {"v":0,"id":...,"error":"..."}.
  */
object Main:
  def runLine(line: String): String =
    val parsed =
      try Right(ujson.read(line))
      catch case NonFatal(e) => Left(s"json: ${e.getMessage}")
    val out = parsed.flatMap { j =>
      try Right(Runner.run(Json.decodeCase(j)))
      catch
        case e: DecodeError => Left(s"decode: ${e.getMessage}")
        case NonFatal(e) => Left(s"harness: ${e.getClass.getSimpleName}: ${e.getMessage}")
    }
    out match
      case Right(v) => ujson.write(v)
      case Left(msg) =>
        val id = scala.util.Try(ujson.read(line)("id").str).getOrElse("")
        ujson.write(ujson.Obj("v" -> Json.FormatVersion, "id" -> id, "error" -> msg))

  /** Arguments: input files (JSON lines). No arguments: read stdin. */
  def main(args: Array[String]): Unit =
    val out = new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.out), false, "UTF-8")
    val sources = if args.isEmpty then List(Source.stdin) else args.toList.map(Source.fromFile(_, "UTF-8"))
    for src <- sources do
      for line <- src.getLines() if line.trim.nonEmpty do out.println(runLine(line))
      src.close()
    out.flush()
