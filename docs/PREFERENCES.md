# PREFERENCES.md

How I like to work with Claude on a new app project. Paste this into the new project's CLAUDE.md
(or drop it in the repo root and tell the session to read it) alongside `DESIGN.md` — this one is
about *process*, that one is about *visuals*. Fill in the `[ ]` placeholders once the new project's
concrete details (language, build command, branch names) are known; everything else applies as-is.

## How to propose features

- When I say "more ideas" or similar, don't just list ideas in prose — use a grouped
  multiple-choice question (3–4 groups by theme, multi-select) so I can pick a batch in one go.
  Keep offering more rounds afterward; I like to keep going for a while in one sitting ("put
  everything in, this is fun" energy is normal, not a one-off).
- Once I've picked, implement the whole batch before checking back in — don't stop after one
  feature to ask if you should continue. Batch big, ship generously.
- If something I said earlier reframes the kind of features worth suggesting (a constraint, a use
  case, who the app is really for), carry that forward into every later round of ideas without me
  having to repeat it.
- Rejected ideas stay rejected — don't resuggest something I explicitly said no to unless I bring
  it up again myself.

## How to implement

- Keep new business logic in pure/static functions, separate from UI code, so it's unit-testable
  without spinning up the UI layer. Write the matching unit tests in the same batch of work, not
  as a follow-up.
- Reuse existing infrastructure aggressively before writing new code — check whether a similar
  feature already has 80% of what's needed before building a parallel system.
- Never fabricate real-world facts (prices, business hours, current names/status of real
  places, specific published numbers). If the app's own data could be stale or wrong, verify with
  a web search and cite what you found before writing it into code, rather than guessing.
- Never delete a user's historical/personal data as a side effect of a "fix" — if something in
  the real world changes (a business closes, a record needs correcting), add a flag or a new
  entry; don't overwrite or drop rows that might carry a rating, note, or photo.
- Watch for footguns in your target language (e.g. Swift: unlabeled tuple closures, tuple
  destructuring in `if let`, `.init` inside `.map`, cross-type unqualified static calls) and
  double check them before considering a change done, since I generally can't compile/build from
  inside the session — a final read-through of the diff for these patterns is part of "done," not
  optional polish.
- [ ] Project-specific build/registration step, if any (e.g. an Xcode project needs new files
  registered in `project.pbxproj` in 4 places; a different platform may have no equivalent).

## Git / shipping workflow

- [ ] Feature branch name: `___` → base branch: `___` (or: just work on `main` / trunk-based,
  whichever the new project actually uses — confirm once, then follow it every time without
  asking again).
- Always merge when a batch of work is done: open a PR, then merge it — don't leave finished work
  sitting unmerged waiting for me to ask.
- [ ] Default CI behavior: does every merge trigger a build/deploy, and if so should it be skipped
  by default (e.g. `[ci skip]` in the merge commit) unless I've explicitly asked to test on a real
  build? State the rule once it's known; keep a running "what's new / what to test" note
  (cumulative since the last real build) if the project has anything like a beta/TestFlight/staging
  channel.
- Create a new commit rather than amending, unless I explicitly ask for an amend. Never
  force-push over shared history without asking first.
- Commit messages and PR bodies: explain *why*, not just what changed. No AI model name/version
  anywhere in a commit message, PR title/body, or code comment — keep that out of anything that
  ships in the repo.
- Update the project's own CLAUDE.md (architecture doc) as part of every feature that adds a new
  concept, not as separate cleanup work later.

## Communication style

- Short status updates while working, not a wall of narration. Tell me what you found, when you
  change direction, and when you hit something blocking — skip narrating routine steps.
- When you do stop to ask me something, use a real decision point (multiple concrete options),
  not an open-ended "what do you think?" — I'd rather pick from a short list than write an essay.
- End-of-task summary: a few lines on what shipped and what's next, not a re-explanation of the
  whole conversation.

## Design

- See `DESIGN.md` (companion file) for the actual visual language — colors, components, spacing,
  interaction rules. Use it from the first screen, not retrofitted later.

---

*Fill in the `[ ]` items once during the new project's setup conversation, then this file (plus
DESIGN.md) should need no further updates — treat both as living documents you extend, not
replace, as new conventions come up.*
