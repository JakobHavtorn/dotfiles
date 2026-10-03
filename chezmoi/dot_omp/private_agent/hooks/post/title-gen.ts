// Session title generation extension for omp.
//
// Reuses the cross-harness title agent spec from agent-skills/agents/title.md
// so opencode and omp share one title-generation prompt.  Reads the spec at
// runtime, strips YAML frontmatter, and pipes the body + user message as stdin
// to `omp -p --no-extensions`.  The resulting title is set via
// pi.setSessionName(title, "user") from the `input` event, which fires before
// omp's built-in auto-title check and prevents it from running (per
// extensions.md: "Extensions that call await pi.setSessionName(...) from input
// can set the persisted session name and prevent the default auto-generated
// title from running for that session").
//
// The title instructions are piped via stdin (not --system-prompt, which omp
// ignores, and not as a CLI argument, which fails for long prompts).
// --no-extensions prevents the subprocess from re-loading this hook.
// The subprocess is fired without awaiting so it doesn't block the turn;
// setSessionName(title, "user") overrides any auto title already set.
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

// Subprocess timeout — keep margin under the hook event budget.
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

// ─── extension ───────────────────────────────────────────────────────

export default function titleGenHook(pi: ExtensionAPI) {
  let titled = false;

  pi.on("input", (event, ctx) => {
    if (titled) return;
    if (!event.text) return;

    // Skip slash commands — they're not conversational messages worth titling.
    if (event.text.startsWith("/")) return;

    titled = true;

    // Fire title generation in the background — don't block the turn.
    // The built-in auto-title may set an "auto" title immediately; our
    // setSessionName(title, "user") will override it when the subprocess
    // completes (user-source overrides auto-source).
    generateTitle(pi, event.text, ctx.cwd).catch((e) => {
      pi.logger?.debug?.(`title-gen: model call failed: ${e}`);
    });
  });
}

async function generateTitle(
  pi: ExtensionAPI,
  userMessage: string,
  cwd: string,
): Promise<void> {
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

  const instructions = extractBody(spec);
  const model = extractModel(spec) ?? "corti/corti-s1-mini";

  // Embed title instructions in the user message since omp -p's
  // --system-prompt does not replace the built-in coding assistant prompt.
  // Pipe via stdin to avoid shell argument length limits.
  const prompt = `${instructions}\n\n---\n\nGenerate a title for this user message:\n\n${userMessage}`;

  const proc = Bun.spawn(
    [
      "omp", "-p",
      "--no-extensions",
      "--no-session",
      "--no-tools",
      "--model", model,
    ],
    {
      cwd,
      stdout: "pipe",
      stderr: "pipe",
      stdin: "pipe",
    },
  );

  const timer = setTimeout(() => proc.kill(), MODEL_TIMEOUT_MS);
  try {
    // Write prompt to stdin then close it.
    proc.stdin.write(prompt);
    proc.stdin.end();
    const title = (await new Response(proc.stdout).text()).trim();
    // Take only the first line — the model may add explanatory text after.
    const firstLine = title.split("\n")[0].trim();
    if (firstLine && firstLine.length > 0 && firstLine.length <= 80) {
      await pi.setSessionName(firstLine, "user");
    }
  } finally {
    clearTimeout(timer);
  }
}
