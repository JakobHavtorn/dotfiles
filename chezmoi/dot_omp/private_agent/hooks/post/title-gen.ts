// Session title generation extension for omp.
//
// Reads the title agent spec from OMP's config tree
// (~/.omp/agent/agents/title.md, symlinked by skillctl).  Strips YAML
// frontmatter and sends the body as the system prompt to a direct API
// call.  The resulting title is set via pi.setSessionName(title, "user")
// from the `input` event, which fires before omp's built-in auto-title.
//
// A direct API call returns in ~1s.  An `omp -p` subprocess loads the full
// coding agent context and takes 10-45s, racing the hook budget.
//
// API endpoint, auth, and model come from omp's models.yml at runtime.
// The hook selects the first non-reasoning model from the first provider,
// falling back to corti-s1-instant.
//
// Install path (chezmoi-managed):
//   dot_omp/private_agent/hooks/post/title-gen.ts
//     → ~/.omp/agent/hooks/post/title-gen.ts   (user scope, all projects)

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const TITLE_SPEC_PATHS = [
  // skillctl-symlinked spec in OMP's config tree.
  `${process.env.HOME}/.omp/agent/agents/title.md`,
];

const MODELS_YML_PATHS = [
  `${process.env.HOME}/.omp/agent/models.yml`,
  ...(process.env.OMP_MODELS_YML ? [process.env.OMP_MODELS_YML] : []),
];

const API_TIMEOUT_MS = 15_000;

// Non-reasoning model: returns clean content within the token budget.
const FALLBACK_MODEL = "corti-s1-instant";

function extractBody(md: string): string {
  const m = md.match(/^---\n[\s\S]*?\n---\n(.*)$/);
  return m ? m[1].trim() : md.trim();
}

interface ProviderConfig {
  baseUrl: string;
  apiKeyEnv: string;
  modelId: string;
}

// Parse the first provider from models.yml.  Simple regex on a known
// hand-maintained format.
async function readProviderConfig(): Promise<ProviderConfig | null> {
  let yml: string | null = null;
  for (const p of MODELS_YML_PATHS) {
    try {
      const file = Bun.file(p);
      if (await file.exists()) {
        yml = await file.text();
        break;
      }
    } catch {}
  }
  if (!yml) return null;

  const baseUrlMatch = yml.match(/baseUrl:\s*(\S+)/);
  const apiKeyMatch = yml.match(/apiKey:\s*(\S+)/);
  if (!baseUrlMatch || !apiKeyMatch) return null;

  const baseUrl = baseUrlMatch[1].replace(/\/+$/, "");
  const apiKeyEnv = apiKeyMatch[1];

  // First non-reasoning model — reasoning models spend the token budget on
  // chain-of-thought, leaving none for the title.
  const modelBlocks = yml.split(/^\s*-\s*id:/m);
  for (const block of modelBlocks.slice(1)) {
    const idMatch = block.match(/^\s*["']([^"'\n]+)["']/);
    const reasoningMatch = block.match(/reasoning:\s*(\w+)/);
    if (idMatch && reasoningMatch?.[1] === "false") {
      return { baseUrl, apiKeyEnv, modelId: idMatch[1].trim() };
    }
  }

  const firstId = yml.match(/id:\s*["']([^"']+)["']/);
  return firstId ? { baseUrl, apiKeyEnv, modelId: firstId[1] } : null;
}

export default function titleGenHook(pi: ExtensionAPI) {
  let titled = false;

  pi.on("input", (event, ctx) => {
    if (titled || !event.text || event.text.startsWith("/")) return;
    titled = true;

    // Fire-and-forget: setSessionName("user") overrides the auto title when
    // the API call completes.
    generateTitle(pi, event.text, ctx.cwd).catch((e) => {
      pi.logger?.debug?.(`title-gen: API call failed: ${e}`);
    });
  });
}

async function generateTitle(
  pi: ExtensionAPI,
  userMessage: string,
  cwd: string,
): Promise<void> {
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
    pi.logger?.debug?.("title-gen: title.md not found");
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
      pi.logger?.debug?.(`title-gen: ${apiKeyEnv} not set`);
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
      pi.logger?.debug?.(
        `title-gen: API ${response.status}: ${await response.text()}`,
      );
      return;
    }

    const data = await response.json();
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== "string") {
      pi.logger?.debug?.("title-gen: no content in response");
      return;
    }

    const firstLine = content.trim().split("\n")[0].trim();
    if (firstLine && firstLine.length > 0 && firstLine.length <= 80) {
      await pi.setSessionName(firstLine, "user");
    }
  } finally {
    clearTimeout(timer);
  }
}
