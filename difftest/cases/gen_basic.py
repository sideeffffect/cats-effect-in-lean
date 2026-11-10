import json
def N(n): return {"t":"nat","v":n}
U={"t":"unit"}
def V(x): return {"t":"var","x":x}
def op(o, **k): d={"op":o}; d.update(k); return d
def seq(*ps): return op("seq", ps=list(ps))
def delay(fn,arg=None): return op("delay",fn=fn,**({"arg":arg} if arg is not None else {}))
def bind(x,e,k): return op("bind",x=x,e=e,k=k)
cases=[]
def case(id, prog, mode="replay", **k):
    c={"v":0,"id":id,"mode":mode}; c.update(k); c["prog"]=prog; cases.append(c)
two = bind("a", op("start", e=seq(delay(0,N(1)), op("cede"), delay(0,N(2)))),
       bind("b", op("start", e=seq(delay(0,N(3)), op("cede"), delay(0,N(4)))),
         seq(op("join",f=V("a")), op("join",f=V("b")))))
case("pure", op("pure", v=N(1)))
case("raise-handle", op("handleErrorWith", e=op("raise",code=7), x="e", k=op("pure",v=V("e"))))
case("attempt-user-raise", op("attempt", e=delay(3,N(5))))
case("map-inc", op("map", e=delay(2,N(1)), fn=2))
case("map-raise", op("attempt", e=op("map", e=op("pure",v=N(4)), fn=3)))
case("oncancel-canceled", op("onCancel", e=op("canceled"), fin=delay(1,N(0)), tag=1))
case("uncancelable-canceled-continues", op("uncancelable", poll="p", body=seq(op("canceled"), delay(0,N(1)))))
case("poll-canceled", op("uncancelable", poll="p", body=seq(op("poll",poll="p",e=op("canceled")), delay(0,N(1)))))
case("two-fibers-fifo", two)
case("two-fibers-chosen", two, choices=[0,1,0,1,0,1,0,1])
case("two-fibers-tc-seed1", two, mode="testcontrol", seed=1)
case("two-fibers-tc-seed2", two, mode="testcontrol", seed=2)
case("external-cancel-root", op("onCancel", e=op("never"), fin=delay(1,N(9)), tag=2), choices=[0,{"cancel":0}])
case("external-cancel-unknown-handle", op("pure",v=N(1)), choices=[{"cancel":5}])
case("cancel-child-guaranteecase",
  bind("f", op("start", e=op("guaranteeCase", e=op("never"), x="oc", fin=delay(0,V("oc")), tag=3)),
    seq(op("cede"), op("cancel",f=V("f")), op("join",f=V("f")))))
case("racepair-sleep-loser", op("racePair", a=seq(op("sleep",ms=10), op("pure",v=N(1))), b=op("pure",v=N(2))))
case("ref-modify-set-get", bind("r", op("refNew",v=N(0)), seq(op("refModify",r=V("r"),fn=5), op("refSet",r=V("r"),v=N(10)), op("refGet",r=V("r")))))
case("deferred-handoff", bind("d", op("deferredNew"), bind("f", op("start", e=op("deferredGet",d=V("d"))),
   seq(op("deferredComplete",d=V("d"),v=N(5)), op("deferredComplete",d=V("d"),v=N(6)), op("join",f=V("f"))))))
case("async-sync-once", op("async", cbs=[{"when":"sync","ok":N(1)}]))
case("async-later-twice", op("async", cbs=[{"when":"later","ok":N(1)},{"when":"later","err":4}]))
case("async-later-error-first", op("attempt", e=op("async", cbs=[{"when":"later","err":4},{"when":"sync","ok":N(1)}])))
case("async-no-cb-external-cancel", op("async", cbs=[], fin=delay(1,N(0)), tag=4), choices=[0,{"cancel":0}])
case("sleep-time", seq(op("sleep",ms=100), op("pure",v=N(1))))
case("never-blocked", op("never"))
case("fuel", seq(op("cede"),op("cede"),op("cede"),op("cede"),op("cede")), maxSteps=3)
case("attempt-case", bind("x", op("attempt", e=op("raise",code=2)), op("case", on=V("x"), l="c", lk=op("pure",v=V("c")), r="v", rk=op("pure",v=N(0)))))
case("split-pair", op("split", on={"t":"pair","a":N(1),"b":{"t":"bool","v":True}}, a="x", b="y", k=op("pure",v=V("y"))))
for c in cases: print(json.dumps(c, separators=(",",":")))
