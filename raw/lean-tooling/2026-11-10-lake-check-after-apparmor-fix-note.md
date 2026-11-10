# lake check works after the bwrap AppArmor profile (own result)

> Source: own run on this machine after `sudo scripts/setup-bwrap-apparmor.sh`
> Collected: 2026-11-10
> Published: 2026-11-10

Script output (run by the user): "Installed and loaded /etc/apparmor.d/bwrap." and "OK: bwrap creates a sandbox as user 'ondra'."

`lake check` (sandboxed, no --inadvisably-no-sandbox), exit 0:
```
Resolving dependencies
Building and exporting
Running Lean default kernel on solution
Lean default kernel accepts the solution
Uses axioms: Classical.choice, propext, Quot.sound
```

`lake check --paranoid`, exit 0, took more than 2 minutes on the empty scaffold. Each kernel checks 57,920 declarations (the scaffold plus everything it imports from core):
```
con-leche: accepted 57920 declarations (--verified)
con-leche kernel accepts the solution
con-ron: accepted 57920 declarations (--verified)
con-ron kernel accepts the solution
Lean default kernel accepts the solution
Uses axioms: Classical.choice, propext, Quot.sound
```
