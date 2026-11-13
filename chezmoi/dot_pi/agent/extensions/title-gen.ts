// Session title generation extension for pi.
//
// Reads the title agent spec from Pi's config tree
// (~/.pi/agent/agents/title.md, symlinked by skillctl).  Strips YAML
// frontmatter and sends the body as the system prompt to a direct API
// call.  The resulting title is set via pi.setSessionName(title)
// from the `input` event, which fires before Pi's built-in auto-title.
//
// A direct API call returns in ~1s.  A `pi -p` subprocess loads the full
// coding agent context and takes 10-45s, racing the hook budget.
//
// API endpoint, auth, and model come from pi's models.json at runtime
// (written by `corti models init`).  The hook selects the first
// non-reasoning model from the corti provider, falling back to
// corti-s1-instant.
//
// Ported from the omp hook (dot_omp/private_agent/hooks/post/title-gen.ts).
// Node runtime — no Bun APIs; use node:fs/promises and fetch.
//
// Install path (chezmoi-managed):
//   dot_pi/agent/extensions/title-gen.ts
//     → ~/.pi/agent/extensions/title-gen.ts   (auto-discovered, all projects)

import { readFile } from "node:fs/promises";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const TITLE_SPEC_PATHS = [
  // skillctl-symlinked spec in Pi's config tree.
  `${process.env.HOME}/.pi/agent/agents/title.md`,
];

const MODELS_JSON_PATHS = [
  `${process.env.HOME}/.pi/agent/models.json`,
  ...(process.env.PI_MODELS_JSON ? [process.env.PI_MODELS_JSON] : []),
];

const API_TIMEOUT_MS = 15_000;

// Non-reasoning model: returns clean content within the token budget.
const FALLBACK_MODEL = "corti-s1-instant";

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

interface ProviderConfig {
  baseUrl: string;
  apiKeyEnv: string;
  modelId: string;
}

// Read the corti provider from models.json (written by `corti models
// init`).  Picks the first non-reasoning model — reasoning models spend
// the token budget on chain-of-thought, leaving none for the title.
async function readProviderConfig(): Promise<ProviderConfig | null> {
  let raw: string | null = null;
  for (const p of MODELS_JSON_PATHS) {
    raw = await readTextIfExists(p);
    if (raw) break;
  }
  if (!raw) return null;

  let data: any;
  try {
    data = JSON.parse(raw);
  } catch {
    return null;
  }

  const provider = data?.providers?.corti;
  if (!provider?.baseUrl || !provider?.apiKey) return null;

  const models: any[] = Array.isArray(provider.models) ? provider.models : [];
  const firstNonReasoning = models.find((m) => m && m.reasoning === false && m.id);
  return {
    baseUrl: String(provider.baseUrl).replace(/\/+$/, ""),
    apiKeyEnv: provider.apiKey.replace(/^\$/, ""), // "$CORTI_BEARER" → "CORTI_BEARER"
    modelId: firstNonReasoning?.id ?? FALLBACK_MODEL,
  };
}

export default function titleGenExtension(pi: ExtensionAPI) {
  let titled = false;

  pi.on("input", (event, ctx) => {
    if (titled || !event.text || event.text.startsWith("/")) return;
    titled = true;

    // Fire-and-forget: setSessionName overrides the auto title when
    // the API call completes.
    generateTitle(pi, event.text, ctx.cwd).catch((e) => {
      console.error(`title-gen: API call failed: ${e}`);
    });
  });
}

async function generateTitle(
  pi: ExtensionAPI,
  userMessage: string,
  _cwd: string,
): Promise<void> {
  let spec: string | null = null;
  for (const p of TITLE_SPEC_PATHS) {
    spec = await readTextIfExists(p);
    if (spec) break;
  }
  if (!spec) {
    console.error("title-gen: title.md not found");
    return;
  }

  const systemPrompt = extractBody(spec);
  const config = await readProviderConfig();
  const baseUrl = config?.baseUrl ?? "https://ai.eu.corti.app/v1";
  const apiKeyEnv = config?.apiKeyEnv ?? "CORTI_BEARER";
  const model = config?.modelId ?? FALLBACK_MODEL;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), API_TIMEOUT_MS);

  try {
    const apiKey = process.env[apiKeyEnv];
    if (!apiKey) {
      console.error(`title-gen: ${apiKeyEnv} not set`);
      return;
    }

    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
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
      console.error(
        `title-gen: API ${response.status}: ${await response.text()}`,
      );
      return;
    }

    const data = await response.json();
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== "string") {
      console.error("title-gen: no content in response");
      return;
    }

    const firstLine = content.trim().split("\n")[0].trim();
    if (firstLine && firstLine.length > 0 && firstLine.length <= 80) {
      await pi.setSessionName(firstLine);
    }
  } finally {
    clearTimeout(timer);
  }
}
