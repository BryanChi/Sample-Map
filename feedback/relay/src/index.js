// CRS Feedback relay: receives reports from the in-script feedback window
// (feedback/CRS_Feedback.lua) and files them as GitHub issues.
//
// POST /report   multipart/form-data: payload (JSON) + image1..image5
// GET  /f/<id>   serves an uploaded picture or full log (linked from the issue)
// GET  /         health check
//
// Bindings (wrangler.toml): FEEDBACK (KV namespace), GITHUB_TOKEN (secret),
// optional SCRIPTS (JSON var overriding DEFAULT_SCRIPTS), optional LIMITER
// (rate limiting binding).

export const DEFAULT_SCRIPTS = {
  "sample-map": { repo: "BryanChi/Sample-Map", label: "Sample Map" },
  "sample-map-quick-swap": { repo: "BryanChi/Sample-Map", label: "Quick Swap" },
  "sample-map-extract-pattern": { repo: "BryanChi/Sample-Map", label: "Extract Drum Pattern" },
  "fx-devices": { repo: "BryanChi/BryanChi-FX-Devices", label: "FX Devices" },
  "vertical-fx-list": { repo: "BryanChi/Vertical-FX-List", label: "Vertical FX List" },
};

export const LIMITS = {
  maxBodyBytes: 30 * 1024 * 1024,
  maxImages: 5,
  maxImageBytes: 5 * 1024 * 1024,
  maxTitle: 120,
  maxNote: 8000,
  maxContact: 200,
  maxLogInline: 30000,
  maxLogStored: 512 * 1024,
  perIpPer10Min: 5,
  perIpPerDay: 20,
  globalPerDay: 300,
};

const KINDS = {
  bug: { label: "bug", prefix: "Bug" },
  idea: { label: "enhancement", prefix: "Idea" },
  question: { label: "question", prefix: "Question" },
  other: { label: "feedback", prefix: "Feedback" },
};

const LABEL_COLORS = {
  "user-report": "5319e7",
  bug: "d73a4a",
  enhancement: "a2eeef",
  question: "d876e3",
  feedback: "c5def5",
};

const IMAGE_TYPES = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/gif": "gif",
  "image/webp": "webp",
};

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function json(status, obj, extraHeaders = {}) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...extraHeaders },
  });
}

function scripts(env) {
  if (env.SCRIPTS) {
    try {
      return typeof env.SCRIPTS === "string" ? JSON.parse(env.SCRIPTS) : env.SCRIPTS;
    } catch {
      // fall through to the defaults
    }
  }
  return DEFAULT_SCRIPTS;
}

function clip(s, n) {
  s = String(s ?? "");
  return s.length > n ? s.slice(0, n) : s;
}

// Keep reporter text from pinging people or closing issues.
export function neutralize(s) {
  return String(s ?? "")
    .replace(/@(?=[A-Za-z0-9-])/g, "@​")
    .replace(/\b(close[sd]?|fix(e[sd])?|resolve[sd]?)(\s+)#(\d)/gi, "$1$3#​$4");
}

// Text inside a code fence can't end the fence early.
function fenceSafe(s) {
  return String(s ?? "").replace(/```/g, "``​`");
}

function oneLine(s) {
  return String(s ?? "").replace(/[\r\n|]+/g, " ").trim();
}

export function sniffImage(bytes) {
  const b = bytes;
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b.length >= 6 && b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38) return "image/gif";
  if (b.length >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46
    && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) return "image/webp";
  return null;
}

function randomId(bytes = 16) {
  const a = new Uint8Array(bytes);
  crypto.getRandomValues(a);
  return [...a].map((x) => x.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(text) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

// --- Rate limiting -----------------------------------------------------------
// KV counters (eventually consistent, so approximate) plus the optional
// rate limiting binding for bursts.

async function bump(kv, key, ttl) {
  const n = parseInt((await kv.get(key)) || "0", 10) + 1;
  await kv.put(key, String(n), { expirationTtl: ttl });
  return n;
}

async function checkRate(env, ipHash) {
  if (env.LIMITER) {
    const { success } = await env.LIMITER.limit({ key: ipHash });
    if (!success) throw new HttpError(429, "Too many reports in a short time. Please wait a minute and try again.");
  }
  const now = Math.floor(Date.now() / 1000);
  const tenMin = Math.floor(now / 600);
  const day = Math.floor(now / 86400);
  const kv = env.FEEDBACK;
  const [a, b, g] = await Promise.all([
    kv.get(`rl:10m:${ipHash}:${tenMin}`),
    kv.get(`rl:day:${ipHash}:${day}`),
    kv.get(`rl:global:${day}`),
  ]);
  if (parseInt(a || "0", 10) >= LIMITS.perIpPer10Min) {
    throw new HttpError(429, "Too many reports in a short time. Please try again in a few minutes.");
  }
  if (parseInt(b || "0", 10) >= LIMITS.perIpPerDay) {
    throw new HttpError(429, "Daily report limit reached for this computer. Please try again tomorrow.");
  }
  if (parseInt(g || "0", 10) >= LIMITS.globalPerDay) {
    throw new HttpError(429, "The report inbox is full for today. Please try again tomorrow.");
  }
  return async () => {
    await Promise.all([
      bump(kv, `rl:10m:${ipHash}:${tenMin}`, 1200),
      bump(kv, `rl:day:${ipHash}:${day}`, 172800),
      bump(kv, `rl:global:${day}`, 172800),
    ]);
  };
}

// --- GitHub ------------------------------------------------------------------

async function gh(env, method, path, body) {
  const res = await fetch(`${env.GITHUB_API || "https://api.github.com"}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      accept: "application/vnd.github+json",
      "x-github-api-version": "2022-11-28",
      "user-agent": "crs-feedback-relay",
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
  return { status: res.status, data };
}

// Create any missing labels once per repo (remembered in KV).
async function ensureLabels(env, repo, labels) {
  const kv = env.FEEDBACK;
  const key = `labels:${repo}`;
  const known = new Set(JSON.parse((await kv.get(key)) || "[]"));
  const missing = labels.filter((l) => !known.has(l));
  if (missing.length === 0) return;
  for (const name of missing) {
    const color = LABEL_COLORS[name] || (name.startsWith("os:") ? "bfd4f2" : "ededed");
    const res = await gh(env, "POST", `/repos/${repo}/labels`, { name, color });
    if (res.status === 201 || res.status === 422) known.add(name); // 422 = already exists
  }
  await kv.put(key, JSON.stringify([...known]));
}

function osLabel(osName) {
  const o = String(osName || "");
  if (/^Win/i.test(o)) return "os:windows";
  if (/^(OSX|macOS)/i.test(o)) return "os:mac";
  if (/linux/i.test(o)) return "os:linux";
  return null;
}

// --- Report → issue --------------------------------------------------------

export function buildIssue({ payload, script, imageLinks, logLink, origin }) {
  const kind = KINDS[payload.kind] || KINDS.other;
  const env = payload.env || {};
  const title = `[${kind.prefix}] ${oneLine(clip(payload.title, LIMITS.maxTitle))}`;
  const lines = [];
  lines.push(neutralize(clip(payload.note, LIMITS.maxNote)).trim());
  lines.push("");
  if (imageLinks.length) {
    lines.push("### Pictures");
    lines.push("");
    for (const img of imageLinks) lines.push(`![${img.alt}](${img.url})`);
    lines.push("");
  }
  lines.push("### Environment");
  lines.push("");
  lines.push("| | |");
  lines.push("|---|---|");
  lines.push(`| Script | ${oneLine(clip(payload.script_name || script.label, 80))} ${oneLine(clip(payload.script_version, 40))} |`);
  lines.push(`| REAPER | ${oneLine(clip(env.reaper, 40))} |`);
  lines.push(`| OS | ${oneLine(clip(env.os, 40))} |`);
  lines.push(`| ReaImGui | ${oneLine(clip(env.reaimgui, 40))} |`);
  lines.push(`| JS API / SWS | ${env.js_api ? "yes" : "no"} / ${env.sws ? "yes" : "no"} |`);
  lines.push(`| Reporter | \`${oneLine(clip(env.install_id, 16)).replace(/`/g, "")}\` |`);
  const contact = oneLine(clip(payload.contact, LIMITS.maxContact));
  if (contact) lines.push(`| Contact | ${neutralize(contact)} |`);
  lines.push("");
  const log = String(payload.log || "");
  if (log) {
    let shown = log;
    let note = "";
    if (log.length > LIMITS.maxLogInline) {
      shown = log.slice(log.length - LIMITS.maxLogInline);
      note = logLink ? `\n\nShowing the end of the log. [Full log](${logLink})` : "\n\nShowing the end of the log.";
    }
    lines.push("<details><summary>Usage log</summary>");
    lines.push("");
    lines.push("```");
    lines.push(fenceSafe(shown));
    lines.push("```" + note);
    lines.push("");
    lines.push("</details>");
    lines.push("");
  }
  lines.push(`<sub>Sent from the ${oneLine(script.label)} feedback window via ${origin}.</sub>`);
  lines.push("<!-- crs-feedback v1 -->");
  const labels = ["user-report", kind.label];
  const os = osLabel(env.os);
  if (os) labels.push(os);
  return { title, body: lines.join("\n"), labels };
}

async function readForm(request) {
  const len = parseInt(request.headers.get("content-length") || "0", 10);
  if (len > LIMITS.maxBodyBytes) throw new HttpError(413, "The report is too large.");
  const type = request.headers.get("content-type") || "";
  if (!type.toLowerCase().startsWith("multipart/form-data")) {
    throw new HttpError(415, "Expected multipart/form-data.");
  }
  let form;
  try {
    form = await request.formData();
  } catch {
    throw new HttpError(400, "Couldn't read the report.");
  }
  const raw = form.get("payload");
  const text = typeof raw === "string" ? raw : raw ? await raw.text() : "";
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    throw new HttpError(400, "The report data is not valid JSON.");
  }
  return { form, payload };
}

function validate(payload, scriptMap) {
  if (!payload || typeof payload !== "object") throw new HttpError(400, "Missing report.");
  const script = scriptMap[payload.script_id];
  if (!script) throw new HttpError(400, "Unknown script.");
  const title = String(payload.title || "").trim();
  const note = String(payload.note || "").trim();
  if (title.length < 3) throw new HttpError(400, "Add a short title.");
  if (note.length < 5) throw new HttpError(400, "Add a few words about what happened.");
  if (note.length > LIMITS.maxNote) throw new HttpError(400, "The note is too long.");
  return script;
}

async function handleReport(request, env, ctx) {
  if (!env.GITHUB_TOKEN) throw new HttpError(503, "The report server isn't configured yet.");
  if (!env.FEEDBACK) throw new HttpError(503, "The report server has no storage configured.");
  const { form, payload } = await readForm(request);
  const script = validate(payload, scripts(env));

  const ip = request.headers.get("cf-connecting-ip") || "unknown";
  const ipHash = (await sha256Hex(`${env.IP_SALT || "crs"}:${ip}`)).slice(0, 24);
  const commitRate = await checkRate(env, ipHash);

  // Same report twice in a row (double click, retry after a timeout): return the first issue.
  const dedupeKey = `dup:${await sha256Hex(`${ipHash}|${payload.script_id}|${payload.title}|${payload.note}`)}`;
  const previous = await env.FEEDBACK.get(dedupeKey);
  if (previous) return json(200, { ...JSON.parse(previous), duplicate: true });

  const origin = new URL(request.url).origin;
  const imageLinks = [];
  let count = 0;
  for (let i = 1; i <= LIMITS.maxImages + 5; i++) {
    const file = form.get(`image${i}`);
    if (!file || typeof file === "string") continue;
    count++;
    if (count > LIMITS.maxImages) throw new HttpError(400, `Up to ${LIMITS.maxImages} pictures per report.`);
    if (file.size > LIMITS.maxImageBytes) throw new HttpError(413, `Picture ${count} is larger than 5 MB.`);
    const bytes = new Uint8Array(await file.arrayBuffer());
    const type = sniffImage(bytes);
    if (!type) throw new HttpError(400, `Picture ${count} isn't a PNG, JPG, GIF or WebP image.`);
    const id = `${randomId()}.${IMAGE_TYPES[type]}`;
    await env.FEEDBACK.put(`f:${id}`, bytes, { metadata: { type } });
    imageLinks.push({ url: `${origin}/f/${id}`, alt: `Picture ${count}` });
  }

  let logLink = null;
  const log = String(payload.log || "");
  if (log.length > LIMITS.maxLogInline) {
    const id = `${randomId()}.txt`;
    await env.FEEDBACK.put(`f:${id}`, log.slice(-LIMITS.maxLogStored), {
      metadata: { type: "text/plain; charset=utf-8" },
    });
    logLink = `${origin}/f/${id}`;
  }

  const issue = buildIssue({ payload, script, imageLinks, logLink, origin: new URL(origin).host });
  try {
    await ensureLabels(env, script.repo, issue.labels);
  } catch {
    // Labels are nice to have; the issue matters more.
  }
  let res = await gh(env, "POST", `/repos/${script.repo}/issues`, issue);
  if (res.status === 422 || res.status === 403) {
    // Retry without labels in case the token can't set them.
    res = await gh(env, "POST", `/repos/${script.repo}/issues`, { title: issue.title, body: issue.body });
  }
  if (res.status !== 201 || !res.data) {
    console.log("GitHub error", res.status, JSON.stringify(res.data));
    throw new HttpError(502, "GitHub didn't accept the report. Please try again later.");
  }
  const result = { ok: true, url: res.data.html_url, number: res.data.number };
  const finish = Promise.all([
    commitRate(),
    env.FEEDBACK.put(dedupeKey, JSON.stringify(result), { expirationTtl: 900 }),
  ]);
  if (ctx && ctx.waitUntil) ctx.waitUntil(finish);
  else await finish;
  return json(201, result);
}

async function handleFile(env, id) {
  if (!/^[0-9a-f]{32}\.(png|jpg|gif|webp|txt)$/.test(id)) return new Response("Not found", { status: 404 });
  const { value, metadata } = await env.FEEDBACK.getWithMetadata(`f:${id}`, { type: "arrayBuffer" });
  if (!value) return new Response("Not found", { status: 404 });
  return new Response(value, {
    headers: {
      "content-type": (metadata && metadata.type) || "application/octet-stream",
      "cache-control": "public, max-age=31536000, immutable",
      "x-content-type-options": "nosniff",
      "content-security-policy": "default-src 'none'",
    },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/") {
        return json(200, { ok: true, service: "crs-feedback" });
      }
      if (request.method === "GET" && url.pathname.startsWith("/f/")) {
        return await handleFile(env, url.pathname.slice(3));
      }
      if (url.pathname === "/report") {
        if (request.method !== "POST") throw new HttpError(405, "Use POST.");
        return await handleReport(request, env, ctx);
      }
      return json(404, { error: "Not found." });
    } catch (e) {
      if (e instanceof HttpError) return json(e.status, { error: e.message });
      console.log("Unexpected error", e && e.stack);
      return json(500, { error: "Something went wrong on the report server." });
    }
  },
};
