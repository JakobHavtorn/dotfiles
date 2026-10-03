// Session title generation hook for omp.
//
// Reuses the cross-harness title agent spec from agent-skills/agents/title.md
// so opencode and omp share one title-generation prompt.  Reads the spec at
// runtime, strips YAML frontmatter, and uses the body as the system prompt for
// a one-shot model call via `omp -p`.  The resulting title is set via
// pi.setSessionName(title, "user"), which sets source:"user" so omp's built-in
// auto-title never overwrites it.
//
// Install path (chezmoi-managed):
//   dot_omp/private_agent/hooks/post/title-gen.ts
//     → ~/.omp/agent/hooks/post/title-gen.ts   (user scope, all projects)
//
// The title.md spec lives in a separate repo and is NOT copied here.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

// Candidate paths for the title agent spec, checked in order.
const TITLE_SPEC_PATHS = [
  // standard install.sh location
  `${process.env.HOME}/.agent-skills/agents/title.md`,
  // env override
  ...(process.env.AGENT_SKILLS_DIR
    ? [`${process.env.AGENT_SKILLS_DIR}/agents/title.md`]
    : []),
];

// Subprocess timeout — the hook event has a 30s budget; keep margin.
const MODEL_TIMEOUT_MS = 20_000;

// ─── frontmatter helpers ─────────────────────────────────────────────

function extractBody(md: string): string {
  const m = md.match(/^---\n[\s\S]*?\n---\n(.*)$/);
  return m ? m[1].trim() : md.trim();
}

function extractModel(md: string): string | undefined {
  const m = md.match(/^model:\s*(.+)$/m);
  return m?.[1]?.trim();
}

// ─── hook ──────────────────────────────────────────────────────────────

export default function titleGenHook(pi: ExtensionAPI) {
  let firstUserMessage: string | null = null;
  let renamed = false;

  // Capture the first user message for the title input.
  pi.on("input", (event) => {
    if (firstUserMessage === null && event.text) {
      firstUserMessage = event.text;
    }
  });

  pi.on("turn_end", async (_event, ctx) => {
    if (renamed || firstUserMessage === null) return;
    if (ctx.mode !== "tui") return;

    // Locate the title agent spec.
    let spec: string | null = null;
    for (const p of TITLE_SPEC_PATHS) {
      try {
        const file = Bun.file(p);
        if (await file.exists()) {
          spec = await file.text();
          break;
        }
      } catch {}
    }
    if (!spec) {
      pi.logger?.debug?.("title-gen: title.md not found in any candidate path");
      return;
    }

    const systemPrompt = extractBody(spec);
    // Fallback model verified working with omp -p --model.
    // @tiny is a role alias that doesn't resolve via --model.
    const model = extractModel(spec) ?? "corti/corti-s1-mini";

    try {
      const proc = Bun.spawn(
        [
          "omp", "-p",
          "--no-session",
          "--no-tools",
          "--model", model,
          "--system-prompt", systemPrompt,
          firstUserMessage,
        ],
        {
          cwd: ctx.cwd,
          stdout: "pipe",
          stderr: "pipe",
        },
      );

      // Enforce a timeout so we don't burn the full 30s hook budget.
      const timer = setTimeout(() => proc.kill(), MODEL_TIMEOUT_MS);
      try {
        const title = (await new Response(proc.stdout).text()).trim();
        if (title && title.length > 0 && title.length <= 80) {
          await pi.setSessionName(title, "user");
          renamed = true;
        }
      } finally {
        clearTimeout(timer);
      }
    } catch (e) {
      pi.logger?.debug?.(`title-gen: model call failed: ${e}`);
    }
  });
}
