# lake check fails: bwrap blocked by Ubuntu AppArmor user-namespace restriction (own diagnosis)

> Source: own experiments on this machine (Ubuntu, kernel 6.8.0-149), plus `lake check --help` and `lake help comparator` of Lean v4.35.0
> Collected: 2026-11-10
> Published: 2026-11-10

## Observed

```
$ lake check
Resolving dependencies
bwrap: setting up uid map: Permission denied
error: Child exited with 1

$ cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns
1
$ unshare -Ur id
unshare: write failed /proc/self/uid_map: Operation not permitted
$ bwrap --unshare-user --ro-bind / / true
bwrap: setting up uid map: Permission denied
$ ls -l /usr/bin/bwrap        # package bubblewrap, NOT setuid
-rwxr-xr-x 1 root root 72160 ... /usr/bin/bwrap
$ ls /etc/apparmor.d | grep -i bwrap
(nothing: no AppArmor profile grants bwrap the `userns` permission)
```

`lake check --inadvisably-no-sandbox` succeeds ("Lean default kernel accepts the solution. Uses axioms: Classical.choice, propext, Quot.sound").

## lake's own documentation (v4.35.0)

`lake check --help`: the project is "built and exported, inside a `bwrap` sandbox, and none of its `.olean` files is ever loaded into Lake's own address space. `bubblewrap` is required, and needs either unprivileged user namespaces or to be installed setuid root." `--inadvisably-no-sandbox`: "disable the built-in sandbox. This can compromise the result fully and is only advised for expert users." `COMPARATOR_BWRAP` env var selects the sandbox executable.

`lake help comparator` HARDENING: `/` is bound read-only and home directories are covered, so the code being judged reads none of the invoking user's files. Only `.lake` is writable. Only dependency resolution has network; build, export and external kernels run in an empty network namespace.

## Cause

Ubuntu 23.10+ sets `kernel.apparmor_restrict_unprivileged_userns=1`. An unconfined program may create a user namespace, but it gets no capabilities inside it unless an AppArmor profile grants `userns`. So writing `/proc/self/uid_map` fails. bwrap is not setuid, and no profile exists for it, so bwrap cannot build its sandbox.

## Why the sandbox matters for this project

Lean code runs arbitrary code at build time (macros, elaborators, `initialize`, `#eval`, IO in tactics). An agent-written file could, at build time, rewrite exported artefacts, tamper with the checker, read secrets in `$HOME`, or use the network. The sandbox stops that, so `lake check` can be trusted as an anti-cheating gate. Without it, the check is only as trustworthy as the code it builds.

## Fix options (none applied; need sudo)

1. AppArmor profile for bwrap (narrowest): `/etc/apparmor.d/bwrap` with `abi <abi/4.0>, include <tunables/global>, profile bwrap /usr/bin/bwrap flags=(unconfined) { userns, include if exists <local/bwrap> }`, then `sudo apparmor_parser -r /etc/apparmor.d/bwrap`. Side effect: any local user program can use bwrap to get user namespaces (the protection Ubuntu added is bypassable through bwrap).
2. `sudo chmod u+s /usr/bin/bwrap` (the other mode lake supports). Wider attack surface; package upgrades reset it.
3. `sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0` (global; turns off the Ubuntu hardening for every program). Least preferred.
4. Run `lake check` in CI or a container/VM where user namespaces work. GitHub `ubuntu-24.04` runners: unverified.
