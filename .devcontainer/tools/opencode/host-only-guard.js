// host-only-guard.js - opencode adapter over the base host-only-check matcher.
//
// Loaded from the read-only OPENCODE_CONFIG_DIR, so nothing in the workspace
// can switch it off. It hands every bash command to /usr/local/bin/host-only-check
// and blocks the call by throwing that command's message, which opencode feeds
// back to the model. Like the Claude hook, this is ergonomics, not containment.
//
// No imports from @opencode-ai/plugin: opencode installs that package in the
// background, and the baked config dir is read-only, so the plugin must not
// depend on it.

import { spawnSync } from "node:child_process"

const CHECK = "/usr/local/bin/host-only-check"

export const HostOnlyGuard = async () => ({
  "tool.execute.before": async (input, output) => {
    if (input?.tool !== "bash") return
    const command = output?.args?.command
    if (typeof command !== "string" || command.trim() === "") return

    const r = spawnSync(CHECK, [command], { encoding: "utf8" })
    if (r.status === 0) return
    // Anything else, a failed spawn included, refuses the command: a guard
    // that cannot run must not degrade into "nothing is host-only".
    throw new Error(r.stderr || `${CHECK} could not run (${r.error ?? `exit ${r.status}`})`)
  },
})
