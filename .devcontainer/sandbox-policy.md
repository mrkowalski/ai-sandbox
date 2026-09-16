# Sandbox policy: commands that must be run outside the sandbox

You are running inside a locked-down container. Some commands cannot work in
here, for either of two reasons:

- **No credentials, no route.** Egress is default-deny and the host user's home
  directory is not mounted, so a command that authenticates against, or acts
  on, an account living on the host cannot succeed. Authenticating on the host
  does not help either: those credentials are written on the host and stay
  there. `git push` is one of these — there is no SSH key and no credential
  helper in here at all.
- **The repository is read-only.** The project's `.git` directory is mounted
  read-only. The working tree is writable — you can edit, create, and delete
  files freely — but nothing can write the repository itself. Committing,
  merging, rebasing, tagging, staging, and stashing all fail in the kernel, not
  by anyone's choice at the time.

`/usr/local/etc/host-only-commands.txt` is the list of such commands, with the
reason for each. Consult it before shell work that might touch a hosted service
or the repository.

When a task needs one of them:

- **Do not run it** — and do not run a variant, a wrapper, or a script that
  calls it. A script does not get further than you do; the mount and the
  firewall do not care who invoked the command.
- **Do not offer to run it, and do not ask to be allowed to.** Where you would
  ordinarily propose the step, or ask whether to take it, recommend the
  operation instead and state plainly that it is not possible inside the
  sandbox. "Want me to commit this?" is the wrong move; "this is ready to
  commit, which has to happen on the host — here is the command" is the right
  one. A general instruction to act when the user asks does not reinstate these
  commands: being asked to commit does not make committing possible in here.
- **Say so at the point you would have run it.** State that this step has to be
  run in a terminal outside the sandbox, give the reason from the list, and
  quote the exact command, verbatim, on its own line so the user can copy it.
- **Do not present it as a failure**, a bug, or something to retry, and do not
  substitute another route to the same effect without saying that is what you
  are doing. A refused git command is not a broken repository and not a
  permissions problem in the project.
- **Finish the rest.** Do everything the sandbox can do, then state plainly
  which steps you left for the user to run on the host.

Working with git in here, concretely: read freely — `git status`, `git diff`,
`git log`, `git show`, `git branch`, `git tag` all work normally. Make your
changes in the working tree and show them with `git diff`, which needs no
write. Do not stage them; the user stages and commits on the host, and an
unstaged working tree is exactly what they need to do that. To move or delete
files use plain `mv` and `rm` rather than `git mv` and `git rm`.

If you attempt one of these anyway, a guard blocks it before it runs and hands
you the same explanation. Relay that to the user; do not retry it, reword it to
get past the guard, or work around it.

That message names a single-invocation bypass (`HOST_ONLY_GUARD_BYPASS=1`). It
exists so the *user* can override a mistaken or over-broad entry. It is not
yours to reach for, and on a git command it buys nothing: it gets you past the
guard and into the same read-only mount, so the command fails anyway — just
without the explanation. Do not use it to retry a blocked command, and do not
suggest it as the way to complete a step the list declines. Mention it only if
you believe an entry matches something it was never meant to, and then as
something for the user to decide.

A blocked command here is the sandbox working as designed, not a defect to
route around.
