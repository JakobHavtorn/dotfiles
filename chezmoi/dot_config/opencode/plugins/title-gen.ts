// Session title generation plugin for opencode.
//
// Reads the title agent spec from opencode's config tree
// (~/.config/opencode/agents/title.md, symlinked by skillctl). Strips
// YAML frontmatter and sends the body as the system prompt to a direct
// API call. The resulting title is set via the `title` session hook:
// assigning event.result skips opencode's built-in title model request.
//
// Unlike the omp/pi `input`-event hooks, opencode's own title flow drives
// timing (initial + regeneration); this plugin only replaces the
// generation with the shared spec.
//
// A direct API call returns in ~1s.  A subprocess loads the full coding
// agent context and takes 10-45s, racing the hook budget.
//
// API endpoint, auth, and model come from opencode's configured corti
// provider (opencode.jsonc) at runtime, falling back to corti-s1-instant.
//
// Ported from the omp hook (dot_omp/private_agent/hooks/post/title-gen.ts).
// Node runtime — no Bun APIs; use node:fs/promises and fetch.
//
// Install path (chezmoi-managed):
//   dot_config/opencode/plugins/title-gen.ts
//     → ~/.config/opencode/plugins/title-gen.ts   (auto-discovered, all projects)

import { readFile } from "node:fs/promises";
import { Plugin } from "@opencode/plugin";

const TITLE_SPEC_PATHS = [
  // skillctl-symlinked spec in opencode's config tree.
  `${process.env.HOME}/.config/opencode/agents/title.md`,
];

const API_TIMEOUT_MS = 15_000;

// Non-reasoning model: returns clean content within the token budget.
const FALLBACK_MODEL = "corti-s1-instant";
const CORTI_BASE_URL = "https://ai.eu.corti.app/v1";

function extractBody(md: string): string {
  // Capture must span the multi-line body: [\s\S]* instead of .*
  // (the omp original used (.*)$ which can never match a multi-line
  // body and silently fell back to the whole file, frontmatter included).
  const m = md.match(/^---\n[\s\S]*?\n---\n([\s\S]*)$/);
  return m ? m[1].trim() : md.trim();
}

async function readTextIfExists(path: string): Promise<string | null> {
  try {
    return await readFile(path, "utf8");
  } catch {
    return null;
  }
}

function debug(msg: string) {
  console.debug(`title-gen: ${msg}`);
}

export default Plugin.define({
  id: "title-gen",
  setup: async (ctx) => {
    await ctx.session.hook("title", async (event) => {
      const spec = await readSpec();
      if (!spec) {
        debug("title.md not found");
        return; // fall through to built-in generation
      }

      // Last user message is the title trigger context. LLM.UserMessage
      // carries content: ContentPart[] with {type: "text", text} parts.
      const lastUser = [...event.messages].reverse().find((m) => m.role === "user");
      const userText = (lastUser?.content ?? [])
        .filter((p: any) => p.type === "text" && typeof p.text === "string")
        .map((p: any) => p.text)
        .join("\n")
        .trim();
      if (!userText) {
        debug("no user message; skipping");
        return;
      }

      const title = await generateTitle(extractBody(spec), userText);
      if (title) {
        // Setting result skips opencode's built-in title model request.
        event.result = title;
      }
    });
  },
});

async function readSpec(): Promise<string | null> {
  for (const p of TITLE_SPEC_PATHS) {
    const spec = await readTextIfExists(p);
    if (spec) return spec;
  }
  return null;
}

async function generateTitle(systemPrompt: string, userMessage: string): Promise<string | null> {
  const apiKey = process.env.CORTI_BEARER;
  if (!apiKey) {
    debug("CORTI_BEARER not set");
    return null;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), API_TIMEOUT_MS);

  try {
    const response = await fetch(`${CORTI_BASE_URL}/chat/completions`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: FALLBACK_MODEL,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userMessage },
        ],
        temperature: 0.3,
        max_tokens: 100,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      debug(`API ${response.status}: ${await response.text()}`);
      return null;
    }

    const data = await response.json();
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== "string") {
      debug("no content in response");
      return null;
    }

    const firstLine = content.trim().split("\n")[0].trim();
    if (firstLine && firstLine.length > 0 && firstLine.length <= 80) {
      return firstLine;
    }
    return null;
  } finally {
    clearTimeout(timer);
  }
}
