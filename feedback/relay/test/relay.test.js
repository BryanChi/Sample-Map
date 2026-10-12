import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import worker, { buildIssue, neutralize, sniffImage, DEFAULT_SCRIPTS } from "../src/index.js";

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);

function makeKV() {
  const m = new Map();
  return {
    m,
    async get(k) {
      return m.has(k) ? m.get(k).value : null;
    },
    async put(k, value, opts = {}) {
      m.set(k, { value, metadata: opts.metadata });
    },
    async getWithMetadata(k) {
      const e = m.get(k);
      return e ? { value: e.value, metadata: e.metadata } : { value: null, metadata: null };
    },
  };
}

let calls;
let issueStatus;
beforeEach(() => {
  calls = [];
  issueStatus = 201;
  globalThis.fetch = async (url, init) => {
    const body = init.body ? JSON.parse(init.body) : null;
    calls.push({ url, method: init.method, body, auth: init.headers.authorization });
    if (url.endsWith("/labels")) return new Response("{}", { status: 201 });
    if (url.endsWith("/issues")) {
      if (issueStatus !== 201) return new Response("{}", { status: issueStatus });
      return new Response(JSON.stringify({ html_url: "https://github.com/BryanChi/Sample-Map/issues/7", number: 7 }), { status: 201 });
    }
    return new Response("{}", { status: 404 });
  };
});

function payload(over = {}) {
  return {
    v: 1,
    script_id: "sample-map",
    script_name: "Sample Map",
    script_version: "0.1.0",
    kind: "bug",
    title: "Crash when dragging a sample",
    note: "I dragged a sample onto the sequencer and the script stopped.",
    contact: "",
    log: "Sample Map 0.1.0\n12:00:01 Scanned 10 files",
    env: { reaper: "7.22", os: "macOS-arm64", reaimgui: "0.9.3", js_api: true, sws: false, install_id: "abc123" },
    images: [],
    ...over,
  };
}

function request(p, images = [], ip = "1.2.3.4") {
  const fd = new FormData();
  fd.append("payload", JSON.stringify(p));
  images.forEach((bytes, i) => fd.append(`image${i + 1}`, new Blob([bytes], { type: "image/png" }), `img${i + 1}.png`));
  return new Request("https://crs-feedback.example.workers.dev/report", {
    method: "POST",
    body: fd,
    headers: { "cf-connecting-ip": ip },
  });
}

const env = () => ({ GITHUB_TOKEN: "t0ken", FEEDBACK: makeKV() });

test("files an issue on the script's repo with labels and pictures", async () => {
  const e = env();
  const res = await worker.fetch(request(payload(), [PNG]), e, null);
  assert.equal(res.status, 201);
  const out = await res.json();
  assert.equal(out.number, 7);
  const issue = calls.find((c) => c.url.endsWith("/issues"));
  assert.equal(issue.url, "https://api.github.com/repos/BryanChi/Sample-Map/issues");
  assert.equal(issue.auth, "Bearer t0ken");
  assert.equal(issue.body.title, "[Bug] Crash when dragging a sample");
  assert.deepEqual(issue.body.labels, ["user-report", "bug", "os:mac"]);
  assert.match(issue.body.body, /!\[Picture 1\]\(https:\/\/crs-feedback\.example\.workers\.dev\/f\/[0-9a-f]{32}\.png\)/);
  assert.match(issue.body.body, /<summary>Usage log<\/summary>/);

  // The picture is served back from KV.
  const url = issue.body.body.match(/\((https:[^)]+\.png)\)/)[1];
  const img = await worker.fetch(new Request(url), e, null);
  assert.equal(img.status, 200);
  assert.equal(img.headers.get("content-type"), "image/png");
  assert.deepEqual(new Uint8Array(await img.arrayBuffer()), PNG);
});

test("routes each script to its repo and rejects unknown scripts", async () => {
  await worker.fetch(request(payload({ script_id: "vertical-fx-list" })), env(), null);
  assert.ok(calls.some((c) => c.url.endsWith("/repos/BryanChi/Vertical-FX-List/issues")));
  const res = await worker.fetch(request(payload({ script_id: "someone-else/repo" })), env(), null);
  assert.equal(res.status, 400);
  assert.ok(DEFAULT_SCRIPTS["fx-devices"].repo === "BryanChi/BryanChi-FX-Devices");
});

test("rejects non-images and too many pictures", async () => {
  let res = await worker.fetch(request(payload(), [new Uint8Array([1, 2, 3, 4])]), env(), null);
  assert.equal(res.status, 400);
  res = await worker.fetch(request(payload(), [PNG, PNG, PNG, PNG, PNG, PNG]), env(), null);
  assert.equal(res.status, 400);
});

test("rate limits per IP", async () => {
  const e = env();
  for (let i = 0; i < 5; i++) {
    const res = await worker.fetch(request(payload({ title: `Report number ${i}` })), e, null);
    assert.equal(res.status, 201);
  }
  const res = await worker.fetch(request(payload({ title: "One too many" })), e, null);
  assert.equal(res.status, 429);
  const other = await worker.fetch(request(payload({ title: "Different computer" }), [], "5.6.7.8"), e, null);
  assert.equal(other.status, 201);
});

test("a repeated report returns the first issue instead of a new one", async () => {
  const e = env();
  await worker.fetch(request(payload()), e, null);
  const res = await worker.fetch(request(payload()), e, null);
  const out = await res.json();
  assert.equal(out.duplicate, true);
  assert.equal(calls.filter((c) => c.url.endsWith("/issues")).length, 1);
});

test("missing title or note is refused; GitHub errors become 502", async () => {
  let res = await worker.fetch(request(payload({ title: "" })), env(), null);
  assert.equal(res.status, 400);
  issueStatus = 500;
  res = await worker.fetch(request(payload()), env(), null);
  assert.equal(res.status, 502);
});

test("unconfigured server says so", async () => {
  const res = await worker.fetch(request(payload()), { FEEDBACK: makeKV() }, null);
  assert.equal(res.status, 503);
});

test("issue text can't ping people, close issues or break the log fence", () => {
  assert.equal(neutralize("cc @bryan fixes #3"), "cc @​bryan fixes #​3");
  const { body } = buildIssue({
    payload: payload({ log: "x```y" }),
    script: DEFAULT_SCRIPTS["sample-map"],
    imageLinks: [],
    logLink: null,
    origin: "example",
  });
  assert.ok(!body.includes("x```y"));
});

test("long logs are trimmed in the issue and stored in full", async () => {
  const e = env();
  const log = "line\n".repeat(10000);
  await worker.fetch(request(payload({ log })), e, null);
  const issue = calls.find((c) => c.url.endsWith("/issues"));
  assert.match(issue.body.body, /\[Full log\]\(https:[^)]+\.txt\)/);
  assert.ok(issue.body.body.length < 65000);
});

test("image sniffing", () => {
  assert.equal(sniffImage(PNG), "image/png");
  assert.equal(sniffImage(new Uint8Array([0xff, 0xd8, 0xff, 0xe0])), "image/jpeg");
  assert.equal(sniffImage(new Uint8Array([0x3c, 0x73, 0x76, 0x67])), null);
});

test("health check and unknown routes", async () => {
  assert.equal((await worker.fetch(new Request("https://x.dev/"), env(), null)).status, 200);
  assert.equal((await worker.fetch(new Request("https://x.dev/nope"), env(), null)).status, 404);
  assert.equal((await worker.fetch(new Request("https://x.dev/f/../../etc"), env(), null)).status, 404);
});
