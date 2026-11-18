// host-only-guard.js - opencode v2 adapter over the base host-only-check matcher.
//
// Loaded from the read-only OPENCODE_CONFIG_DIR, so nothing in the workspace
// can switch it off. It hands every shell command to /usr/local/bin/host-only-check
// and blocks it by throwing that command's message. Like the Claude hook, this
// is ergonomics, not containment.
//
// v2 dropped v1's `tool.execute.before` plugin hook; a plugin is now
// `{ id, setup(context) }` and registers hooks through the context. Two hooks:
//   - tool `execute.before` on the shell tool: the thrown message becomes the
//     tool call's error, which is what the model reads.
//   - shell `create.before`: every command the Shell service starts, so a
//     command run some other way (the `execute` code-mode tool's nested calls,
//     a `!` command) is caught too, if less tidily worded.
//
// No imports from @opencode/plugin (`define` is the identity function): the
// baked config dir is read-only and has no node_modules.

import { spawnSync } from "node:child_process"

const CHECK = "/usr/local/bin/host-only-check"

// v2's shell tool is `shell`; it maps a model's `bash` call onto it.
const SHELL_TOOLS = new Set(["shell", "bash"])

function check(command) {
  if (typeof command !== "string" || command.trim() === "") return
  const r = spawnSync(CHECK, [command], { encoding: "utf8" })
  if (r.status === 0) return
  // Anything else, a failed spawn included, refuses the command: a guard
  // that cannot run must not degrade into "nothing is host-only".
  throw new Error(r.stderr || `${CHECK} could not run (${r.error ?? `exit ${r.status}`})`)
}

export default {
  id: "sbx.host-only-guard",
  setup: async (ctx) => {
    await ctx.tool.hook("execute.before", (input) => {
      if (SHELL_TOOLS.has(input?.tool)) check(input?.input?.command)
    })
    await ctx.shell.hook("create.before", (input) => check(input?.command))
  },
}
