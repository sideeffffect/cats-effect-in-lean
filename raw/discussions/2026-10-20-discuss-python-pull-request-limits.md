# Pull request limits for CPython repo (discuss.python.org)

> Source: https://discuss.python.org/t/pull-request-limits-for-cpython-repo/109564
> Collected: 2026-11-10
> Published: 2026-10-20

Context for maintainer burden: CPython capped open PRs per non-core user at 3 after bursts of LLM-generated PRs/issues. Full thread (11 posts).

---
### #1 hugovk (Hugo van Kemenade) — 2026-10-20

We've set a [limit for the maximum number of PRs](https://github.blog/changelog/2026-06-17-limit-open-pull-requests-for-users-without-write-access/) you can open at [python/cpython](https://github.com/python/cpython) to 3, [including drafts](https://github.blog/changelog/2026-10-08-draft-pull-requests-count-toward-pull-request-limits/).

* This *does not* affect members of the core or triage teams.

* If you have more than 3 PRs already open, they stay open, but you won't be able to open another before dropping below the limit.

We have done this following several recent incidents of bulk PR creation in a short amount of time, and we're struggling to handle them. For example:

* Today: 21 CPython [PRs](https://github.com/python/cpython/pulls/limadog9) opened in a single two-hour burst across about 19 unrelated stdlib areas, as part of 177 template-written [PRs](https://github.com/pulls?q=is%3Apr+author%3Alimadog9) sent to 13 repos in three weeks. Account [banned](https://github.com/atuinsh/atuin/pull/4470) by one project.

*  October: 19 CPython [PRs](https://github.com/python/cpython/pulls/esadomer) opened plus 13 companion [issues](https://github.com/python/cpython/issues/esadomer) in a 20-minute burst across about 22 unrelated stdlib modules.

* October: 7 CPython [issues](https://github.com/python/cpython/issues/sricursion) opened, then then 7 matching [PRs](https://github.com/python/cpython/pulls/sricursion) within a single minute across unrelated modules, all 14 still untouched by a reviewer, from an account with 60 [PRs](https://github.com/pulls?q=is%3Apr+author%3Asricursion) spread over 18 repos.

* September: 17 CPython [PRs](https://github.com/python/cpython/pulls/v0ropaev) opened over three days across unrelated modules, as part of 225 [PRs](https://github.com/pulls?q=is%3Apr+author%3Av0ropaev) across ~50 repos.

* September: A user whose profile boasts a "117 PRs merged upstream" badge, opened 6 CPython [PRs](https://github.com/python/cpython/pulls/sankalpsthakur) in two hours against unrelated modules, as part of 487 [PRs](https://github.com/pulls?q=is%3Apr+author%3Asankalpsthakur) across ~40 repos, about half of those closed unmerged since August.

Yes, these do look LLM generated, and no, we don't want to be the first humans to read that code.

(We also get mass issue reports, but unfortunately GitHub has no configurable limit for this.)

A reminder from our [AI policy](https://devguide.python.org/getting-started/ai-tools/): 

> Authors must review the work done by AI tooling in detail to ensure it actually makes sense before proposing it as a PR or filing it as an issue.
> 
> We expect PR authors and those filing issues to be able to explain their proposed changes in their own words.

And:

> Maintainers may close issues and PRs that are not useful or productive, without explanation, regardless of whether AI tools were used or not.
> 
> If a contributor repeatedly opens unproductive issues or PRs, they may be blocked from contributing to the project because it is disruptive and disrespectful of the maintainers time.

---
### #2 pekkaklarck (Pekka Klärck) — 2026-10-20

This is certainly a good decision. That said, at least in this latest case all PRs don't seem to be slop. I noticed that [one of them](https://github.com/python/cpython/pull/159855) fixes an issue [I had submitted](https://github.com/python/cpython/issues/131064), and based on a quick look on a mobile screen the fix looks good.

---
### #3 hugovk (Hugo van Kemenade) — 2026-10-20 reply to #2

Yeah, some PRs by these particular contributors have already been merged. But the main thing is we can't deal with this volume.

And thanks for reviewing that PR, it helps.

(Let's avoid the term slop as there's no settled definition: for some it means all LLM-generated content, for others only low-quality content.)

---
### #4 deadlovelll (Deadlovelll) — 2026-10-20

What about regular contributors (outside the triage / core team)? With a cap of 3 they can't send new fixes, or even backports

---
### #5 cjames23 (Cary Hawkins) — 2026-10-20

Is there a mechanism to short term override when doing backports that require conflict resolution? I have 3 open right now just with having to have done manual backports to handle conflicts which was done so that the Core team didn’t have to do it. 

I do agree with the general direction though as I also get waves of PRs from LLMs that are hard to keep up with.

---
### #6 zware (Zachary Ware) — 2026-10-20

Things are still new, so nothing is set in stone.  I get the feeling that we're going to be pretty free with the exclusion list for known contributors, so I wouldn't worry about it too much.  Do mention to your reviewer if you're having issues with the limit.

There are also further tweaks to the system apparently [in development](https://github.blog/open-source/maintainers/how-pull-request-limits-are-cutting-down-the-noise/) at GitHub that should hopefully improve things as well.

---
### #7 lpyu001 (stevens) — 2026-10-24

Is the community considering granting exemptions to certain contributors, such as regular contributors who have had a certain number of PRs merged over the past six months or year?

Many PRs require manual backporting to maintenance branches, while others cannot move forward quickly for various reasons. The current PR limit has made it difficult for me to continue contributing.

---
### #8 hugovk (Hugo van Kemenade) — 2026-10-24 reply to #7

Yes, see Zach's message just before yours.

---
### #9 hugovk (Hugo van Kemenade) — 2026-10-29

[quote="Zachary Ware, post:6, topic:109564, username:zware"]
There are also further tweaks to the system apparently [in development](https://github.blog/open-source/maintainers/how-pull-request-limits-are-cutting-down-the-noise/) at GitHub that should hopefully improve things as well.
[/quote]

GitHub has now added some [exemption categories](https://github.blog/changelog/2026-10-28-pull-request-limits-exempt-contributors-by-age-or-history/), and we've enabled one: if you've already had 5 PRs merged, the limit of 3 open PRs doesn't apply.

---
### #10 guido (Guido van Rossum) — 2026-10-29 reply to #9

Can you set limits on new Issues now?

---
### #11 hugovk (Hugo van Kemenade) — 2026-10-29 reply to #10

Not yet, but it's [planned](https://github.com/orgs/community/discussions/197319).
