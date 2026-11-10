package cats.effect.difftest

import ujson.Value

/** JSON codec for format v1 (v0 is the subset without the v1 ops). The decoder is strict:
  * unknown keys, unknown ops, handle literals in the input, unbound variables, poll misuse, a v1
  * op in a v0 case, a resource op outside a resource position, and `syncStep` below the root are
  * all decode errors.
  */
object Json:
  val FormatVersion = 2
  val Versions = Set(0L, 1L, 2L)
  /** `Int.MaxValue`: the largest `syncStep` limit. */
  val MaxLimit = 2147483647L
  val DefaultMaxSteps = 10000

  private def fail(msg: String): Nothing = throw DecodeError(msg)

  private def obj(j: Value, ctx: String): collection.Map[String, Value] = j match
    case o: ujson.Obj => o.value
    case _ => fail(s"$ctx: expected an object, got $j")

  private def keys(o: collection.Map[String, Value], allowed: Set[String], ctx: String): Unit =
    val extra = o.keySet.diff(allowed)
    if extra.nonEmpty then fail(s"$ctx: unknown keys ${extra.mkString(",")}")

  private def field(o: collection.Map[String, Value], k: String, ctx: String): Value =
    o.getOrElse(k, fail(s"$ctx: missing key '$k'"))

  private def nat(j: Value, ctx: String): Long = j match
    case ujson.Num(d) if d >= 0 && d == d.floor && d <= 9.0e15 => d.toLong
    case _ => fail(s"$ctx: expected a natural number, got $j")

  private def str(j: Value, ctx: String): String = j match
    case ujson.Str(s) if s.nonEmpty => s
    case _ => fail(s"$ctx: expected a non-empty string, got $j")

  // ------------------------------------------------------------------ values

  def decodeVal(j: Value): Val =
    val o = obj(j, "value")
    val t = str(field(o, "t", "value"), "value.t")
    def only(ks: String*) = keys(o, Set("t") ++ ks, s"value '$t'")
    t match
      case "unit" => only(); Val.VUnit
      case "bool" =>
        only("v")
        field(o, "v", t) match
          case ujson.Bool(b) => Val.VBool(b)
          case x => fail(s"bool: expected true/false, got $x")
      case "nat" => only("v"); Val.VNat(nat(field(o, "v", t), "nat.v"))
      case "pair" => only("a", "b"); Val.VPair(decodeVal(field(o, "a", t)), decodeVal(field(o, "b", t)))
      case "left" => only("v"); Val.VLeft(decodeVal(field(o, "v", t)))
      case "right" => only("v"); Val.VRight(decodeVal(field(o, "v", t)))
      case "succeeded" => only("v"); Val.VSucceeded(decodeVal(field(o, "v", t)))
      case "errored" => only("code"); Val.VErrored(Err.User(nat(field(o, "code", t), "errored.code")))
      case "canceled" => only(); Val.VCanceled
      case "fiber" | "ref" | "deferred" | "queue" | "memo" => fail(s"value '$t': handles cannot be literals")
      case _ => fail(s"unknown value tag '$t'")

  def encodeErr(e: Err): ujson.Obj = e match
    case Err.User(c) => ujson.Obj("t" -> "errored", "code" -> c.toDouble)
    case Err.Foreign(d) => ujson.Obj("t" -> "errored", "exn" -> d)

  def encodeVal(v: Val): Value = v match
    case Val.VUnit => ujson.Obj("t" -> "unit")
    case Val.VBool(b) => ujson.Obj("t" -> "bool", "v" -> b)
    case Val.VNat(n) => ujson.Obj("t" -> "nat", "v" -> n.toDouble)
    case Val.VPair(a, b) => ujson.Obj("t" -> "pair", "a" -> encodeVal(a), "b" -> encodeVal(b))
    case Val.VLeft(x) => ujson.Obj("t" -> "left", "v" -> encodeVal(x))
    case Val.VRight(x) => ujson.Obj("t" -> "right", "v" -> encodeVal(x))
    case Val.VSucceeded(x) => ujson.Obj("t" -> "succeeded", "v" -> encodeVal(x))
    case Val.VErrored(e) => encodeErr(e)
    case Val.VCanceled => ujson.Obj("t" -> "canceled")
    case Val.VFiber(i) => ujson.Obj("t" -> "fiber", "id" -> i)
    case Val.VRef(i) => ujson.Obj("t" -> "ref", "id" -> i)
    case Val.VDeferred(i) => ujson.Obj("t" -> "deferred", "id" -> i)
    case Val.VQueue(i) => ujson.Obj("t" -> "queue", "id" -> i)
    case Val.VMemo(i) => ujson.Obj("t" -> "memo", "id" -> i)

  // --------------------------------------------------------------- programs

  private enum Kind:
    case V, P

  private type Scope = Map[String, Kind]

  private def atom(j: Value, scope: Scope, ctx: String): Atom = j match
    case o: ujson.Obj if o.value.get("t").contains(ujson.Str("var")) =>
      keys(o.value, Set("t", "x"), ctx)
      val x = str(field(o.value, "x", ctx), s"$ctx.x")
      scope.get(x) match
        case Some(Kind.V) => Atom.Var(x)
        case Some(Kind.P) => fail(s"$ctx: '$x' is a poll, not a value")
        case None => fail(s"$ctx: unbound variable '$x'")
    case _ => Atom.Lit(decodeVal(j))

  /** Ops of format v1 (a decode error in a v0 case). */
  val V1Ops: Set[String] =
    Set("syncStep", "timeout", "timeoutTo", "queueNew", "queueOffer", "queueTake", "queueTryTake",
      "allocatedCase", "rPure", "rEval", "rMake", "rFlatMap")
  private val ResOps = Set("rPure", "rEval", "rMake", "rFlatMap")

  /** Ops of format v2 (a decode error in a v0 or v1 case). */
  val V2Ops: Set[String] = Set("race", "raceOutcome", "both", "bothOutcome", "guarantee", "bracket", "bracketCase",
    "bracketFull", "memoize", "memoGet")

  /** Reject a v2 op anywhere in `j` (a case of format v0 or v1). */
  private def checkNoV2(j: Value): Unit = j match
    case o: ujson.Obj =>
      o.value.get("op") match
        case Some(ujson.Str(op)) if V2Ops.contains(op) => fail(s"op '$op': not in format v0/v1 (use \"v\":2)")
        case _ => ()
      o.value.valuesIterator.foreach(checkNoV2)
    case ujson.Arr(xs) => xs.foreach(checkNoV2)
    case _ => ()

  /** Decode a closed program. `syncStep` is allowed only here, at the root. */
  def decodeProg(j: Value, version: Long = FormatVersion): Prog =
    val v1 = version >= 1
    if version < 2 then checkNoV2(j)
    val ver = version
    obj(j, "prog").get("op") match
      case Some(ujson.Str("syncStep")) if v1 =>
        val o = obj(j, "prog")
        keys(o, Set("op", "e", "limit"), "op 'syncStep'")
        val limit = nat(field(o, "limit", "op 'syncStep'"), "op 'syncStep'.limit")
        if limit > MaxLimit then fail(s"op 'syncStep'.limit: more than Int.MaxValue: $limit")
        Prog.SyncStep(prog(field(o, "e", "op 'syncStep'"), Map.empty, ver), limit.toInt)
      case _ => prog(j, Map.empty, ver)

  private def opOf(j: Value, ver: Long): (collection.Map[String, Value], String) =
    val o = obj(j, "prog")
    val op = str(field(o, "op", "prog"), "prog.op")
    if ver < 1 && V1Ops.contains(op) then fail(s"op '$op': not in format v0 (use \"v\":1)")
    if ver < 2 && V2Ops.contains(op) then fail(s"op '$op': not in format v$ver (use \"v\":2)")
    (o, op)

  /** A resource position (format v1). */
  private def res(j: Value, scope: Scope, v1: Long): Res =
    val (o, op) = opOf(j, v1)
    val ctx = s"op '$op'"
    def only(ks: String*) = keys(o, Set("op") ++ ks, ctx)
    def s(k: String) = str(field(o, k, ctx), s"$ctx.$k")
    op match
      case "rPure" => only("v"); Res.RPure(atom(field(o, "v", ctx), scope, s"$ctx.v"))
      case "rEval" => only("e"); Res.REval(prog(field(o, "e", ctx), scope, v1))
      case "rMake" =>
        only("acq", "x", "rel"); val x = s("x")
        Res.RMake(prog(field(o, "acq", ctx), scope, v1), x, prog(field(o, "rel", ctx), scope + (x -> Kind.V), v1))
      case "rFlatMap" =>
        only("res", "x", "k"); val x = s("x")
        Res.RFlatMap(res(field(o, "res", ctx), scope, v1), x, res(field(o, "k", ctx), scope + (x -> Kind.V), v1))
      case _ => fail(s"$ctx: not a resource op (expected rPure, rEval, rMake or rFlatMap)")

  private def prog(j: Value, scope: Scope, v1: Long): Prog =
    val (o, op) = opOf(j, v1)
    val ctx = s"op '$op'"
    def only(ks: String*) = keys(o, Set("op") ++ ks, ctx)
    def p(k: String, s: Scope = scope) = prog(field(o, k, ctx), s, v1)
    def a(k: String) = atom(field(o, k, ctx), scope, s"$ctx.$k")
    def n(k: String) = nat(field(o, k, ctx), s"$ctx.$k")
    def s(k: String) = str(field(o, k, ctx), s"$ctx.$k")
    def tag = o.get("tag").map(nat(_, s"$ctx.tag")).getOrElse(0L)
    def fn(k: String) =
      val i = n(k)
      if i >= UserFns.size then fail(s"$ctx.$k: unknown user function $i")
      i.toInt
    op match
      case "pure" => only("v"); Prog.Pure(a("v"))
      case "raise" => only("code"); Prog.Raise(n("code"))
      case "delay" =>
        only("fn", "arg")
        Prog.Delay(fn("fn"), o.get("arg").fold(Atom.Lit(Val.VUnit))(atom(_, scope, s"$ctx.arg")))
      case "bind" =>
        only("x", "e", "k"); val x = s("x")
        Prog.Bind(x, p("e"), p("k", scope + (x -> Kind.V)))
      case "seq" =>
        only("ps")
        field(o, "ps", ctx) match
          case ujson.Arr(ps) if ps.nonEmpty => Prog.Seq(ps.toList.map(prog(_, scope, v1)))
          case x => fail(s"$ctx.ps: expected a non-empty array, got $x")
      case "map" => only("e", "fn"); Prog.Map(p("e"), fn("fn"))
      case "handleErrorWith" =>
        only("e", "x", "k"); val x = s("x")
        Prog.HandleErrorWith(p("e"), x, p("k", scope + (x -> Kind.V)))
      case "attempt" => only("e"); Prog.Attempt(p("e"))
      case "uncancelable" =>
        only("poll", "body"); val q = s("poll")
        Prog.Uncancelable(q, p("body", scope + (q -> Kind.P)))
      case "poll" =>
        only("poll", "e"); val q = s("poll")
        if !scope.get(q).contains(Kind.P) then fail(s"$ctx: '$q' is not a bound poll")
        Prog.Poll(q, p("e"))
      case "onCancel" => only("e", "fin", "tag"); Prog.OnCancel(p("e"), p("fin"), tag)
      case "guaranteeCase" =>
        only("e", "x", "fin", "tag"); val x = s("x")
        Prog.GuaranteeCase(p("e"), x, p("fin", scope + (x -> Kind.V)), tag)
      case "canceled" => only(); Prog.Canceled
      case "cede" => only(); Prog.Cede
      case "never" => only(); Prog.Never
      case "start" => only("e"); Prog.Start(p("e"))
      case "join" => only("f"); Prog.Join(a("f"))
      case "cancel" => only("f"); Prog.Cancel(a("f"))
      case "racePair" => only("a", "b"); Prog.RacePair(p("a"), p("b"))
      case "sleep" => only("ms"); Prog.Sleep(n("ms"))
      case "refNew" => only("v"); Prog.RefNew(a("v"))
      case "refGet" => only("r"); Prog.RefGet(a("r"))
      case "refSet" => only("r", "v"); Prog.RefSet(a("r"), a("v"))
      case "refModify" => only("r", "fn"); Prog.RefModify(a("r"), fn("fn"))
      case "deferredNew" => only(); Prog.DeferredNew
      case "deferredGet" => only("d"); Prog.DeferredGet(a("d"))
      case "deferredComplete" => only("d", "v"); Prog.DeferredComplete(a("d"), a("v"))
      case "async" =>
        only("cbs", "fin", "tag")
        val cbs = field(o, "cbs", ctx) match
          case ujson.Arr(cs) => cs.toList.map(cb)
          case x => fail(s"$ctx.cbs: expected an array, got $x")
        Prog.Async(cbs, o.get("fin").map(prog(_, scope, v1)), tag)
      case "case" =>
        only("on", "l", "lk", "r", "rk"); val l = s("l"); val r = s("r")
        Prog.Case(a("on"), l, p("lk", scope + (l -> Kind.V)), r, p("rk", scope + (r -> Kind.V)))
      case "split" =>
        only("on", "a", "b", "k"); val x = s("a"); val y = s("b")
        Prog.Split(a("on"), x, y, p("k", scope + (x -> Kind.V) + (y -> Kind.V)))
      case "timeout" => only("e", "ms"); Prog.Timeout(p("e"), n("ms"))
      case "timeoutTo" => only("e", "ms", "fb"); Prog.TimeoutTo(p("e"), n("ms"), p("fb"))
      case "queueNew" => only(); Prog.QueueNew
      case "queueOffer" => only("q", "v"); Prog.QueueOffer(a("q"), a("v"))
      case "queueTake" => only("q"); Prog.QueueTake(a("q"))
      case "queueTryTake" => only("q"); Prog.QueueTryTake(a("q"))
      case "allocatedCase" => only("res"); Prog.AllocatedCase(res(field(o, "res", ctx), scope, v1))
      case "race" => only("a", "b"); Prog.Race(p("a"), p("b"))
      case "raceOutcome" => only("a", "b"); Prog.RaceOutcome(p("a"), p("b"))
      case "both" => only("a", "b"); Prog.Both(p("a"), p("b"))
      case "bothOutcome" => only("a", "b"); Prog.BothOutcome(p("a"), p("b"))
      // ---- format v2
      case "guarantee" => only("e", "fin", "tag"); Prog.Guarantee(p("e"), p("fin"), tag)
      case "bracket" =>
        only("acq", "x", "use", "rel", "tag"); val x = s("x")
        Prog.Bracket(p("acq"), x, p("use", scope + (x -> Kind.V)), p("rel", scope + (x -> Kind.V)), tag)
      case "bracketCase" =>
        only("acq", "x", "use", "y", "rel", "tag"); val x = s("x"); val y = s("y")
        Prog.BracketCase(p("acq"), x, p("use", scope + (x -> Kind.V)), y,
          p("rel", scope + (x -> Kind.V) + (y -> Kind.V)), tag)
      case "bracketFull" =>
        only("poll", "acq", "x", "use", "y", "rel", "tag"); val q = s("poll"); val x = s("x"); val y = s("y")
        Prog.BracketFull(q, p("acq", scope + (q -> Kind.P)), x, p("use", scope + (x -> Kind.V)), y,
          p("rel", scope + (x -> Kind.V) + (y -> Kind.V)), tag)
      // ---- format v2 (track M)
      case "memoize" => only("e"); Prog.Memoize(p("e"))
      case "memoGet" => only("m"); Prog.MemoGet(a("m"))
      case "syncStep" => fail(s"$ctx: only at the root of a program")
      case r if ResOps.contains(r) => fail(s"$ctx: a resource op outside a resource position")
      case _ => fail(s"unknown op '$op'")

  private def cb(j: Value): CbCall =
    val o = obj(j, "callback")
    keys(o, Set("when", "ok", "err"), "callback")
    val when = str(field(o, "when", "callback"), "callback.when") match
      case "sync" => When.Sync
      case "later" => When.Later
      case w => fail(s"callback.when: expected sync or later, got '$w'")
    (o.get("ok"), o.get("err")) match
      case (Some(v), None) => CbCall(when, Right(decodeVal(v)))
      case (None, Some(c)) => CbCall(when, Left(nat(c, "callback.err")))
      case _ => fail("callback: give exactly one of 'ok' or 'err'")

  // ------------------------------------------------------------------ cases

  def decodeCase(j: Value): TestCase =
    val o = obj(j, "case")
    keys(o, Set("v", "id", "mode", "choices", "seed", "maxSteps", "runtime", "prog"), "case")
    val v = nat(field(o, "v", "case"), "case.v")
    if !Versions.contains(v) then fail(s"case.v: unsupported format version $v")
    val id = str(field(o, "id", "case"), "case.id")
    val mode = str(field(o, "mode", "case"), "case.mode") match
      case "replay" =>
        if o.contains("seed") then fail("case: 'seed' is only for mode testcontrol")
        val cs = o.get("choices") match
          case None => Nil
          case Some(ujson.Arr(cs)) => cs.toList.map(choice)
          case Some(x) => fail(s"case.choices: expected an array, got $x")
        Mode.Replay(cs)
      case "testcontrol" =>
        if o.contains("choices") then fail("case: 'choices' is only for mode replay")
        Mode.TestControlSeed(nat(field(o, "seed", "case"), "case.seed"))
      case m => fail(s"case.mode: unknown mode '$m'")
    val max = o.get("maxSteps").map(nat(_, "case.maxSteps").toInt).getOrElse(DefaultMaxSteps)
    // `runtime`: IORuntimeConfig thresholds, with the checks of IORuntimeConfig.scala:33-40.
    val runtime = o.get("runtime").map { r =>
      if o.contains("seed") then fail("case: 'runtime' is only for mode replay")
      val ro = obj(r, "case.runtime")
      keys(ro, Set("cancelationCheckThreshold", "autoYieldThreshold"), "case.runtime")
      val c = nat(field(ro, "cancelationCheckThreshold", "case.runtime"), "case.runtime.cancelationCheckThreshold")
      val a = nat(field(ro, "autoYieldThreshold", "case.runtime"), "case.runtime.autoYieldThreshold")
      if c == 0 || a <= 1 || a % c != 0 || a > MaxLimit then
        fail(s"case.runtime: invalid thresholds $c, $a")
      (c.toInt, a.toInt)
    }
    TestCase(id, mode, decodeProg(field(o, "prog", "case"), v), max, v.toInt, runtime)

  private def choice(j: Value): Choice = j match
    case ujson.Num(_) => Choice.Pick(nat(j, "choice").toInt)
    case o: ujson.Obj =>
      keys(o.value, Set("cancel"), "choice")
      Choice.CancelFiber(nat(field(o.value, "cancel", "choice"), "choice.cancel").toInt)
    case _ => fail(s"choice: expected a number or {\"cancel\":n}, got $j")
