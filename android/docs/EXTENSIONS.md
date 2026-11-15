# Kalao Extensions: Framework and Authoring Guide

> This document is public. Kalao ships no content scrapers. Every lyrics, metadata or audio source is an extension the user installs. Extensions made by the Kalao maintainer are distributed privately and are not part of this repository.

The design follows Mornye's extension system: a zip package with a root `manifest.json` and `index.js`, run inside an embedded QuickJS sandbox, with network access granted per extension.

## 1. What an extension can do

An extension declares one or more **capabilities** and implements the matching functions:

| Capability | Function(s) | Returns |
| --- | --- | --- |
| `lyrics` | `searchLyrics(query)`, optional `getLyrics(id)` | Lyrics candidates: plain, LRC, or enhanced LRC (word-timed) |
| `metadata` | `searchTracks(query)`, `getTrack(id)` | Title, artist(s), album, duration, ISRC, language, artwork URL |
| `audio` | `resolveAudio(trackRef)` | One or more streamable URLs (+ headers), or a file to download |
| `artwork` | `getArtwork(trackRef)` | Image URLs by size |

`query` is `{ title, artist, album?, durationMs?, isrc?, language? }`. Extensions **never** see the user's library, other extensions' data, Kalao's own keys, or local files.

## 2. Package format

A `.kalaoext` file is a zip archive:

```
my-extension.kalaoext
├── manifest.json      # required, at the root, ≤ 1 MiB
├── index.js           # required, at the root (entry point)
├── icon.png           # optional, 256×256
└── lib/…              # optional additional JS modules (imported relatively)
```

Limits (enforced by the loader): ≤ 2048 entries, ≤ 64 MiB extracted, no absolute paths or `..` segments, no symlinks.

## 3. `manifest.json`

```json
{
  "schema": 1,
  "id": "dev.example.lrcfinder",
  "name": "LRC Finder",
  "version": "1.2.0",
  "minKalao": "1.0.0",
  "author": "Example Dev",
  "description": "Synced lyrics from example.org",
  "homepage": "https://example.org",
  "capabilities": ["lyrics"],
  "languages": ["zh", "ja", "en"],
  "network": {
    "hosts": ["api.example.org", "*.cdn.example.org"]
  },
  "settings": [
    { "key": "token", "type": "secret", "label": "API token", "grantsNetwork": "api.example.org" },
    { "key": "preferSynced", "type": "toggle", "label": "Prefer synced", "default": true },
    { "key": "region", "type": "select", "label": "Region", "options": ["jp", "tw", "cn"] },
    { "key": "login", "type": "button", "label": "Log in to example.org", "action": "startLogin" }
  ],
  "auth": { "callbackPath": "callback" },
  "health": [ { "id": "api", "url": "https://api.example.org/ping", "method": "HEAD" } ]
}
```

- `id` is reverse-DNS, unique and immutable. `version` is semver; the runtime refuses downgrades unless the user confirms.
- `network.hosts` is the **complete** list of hosts `fetch` may reach. A `secret` setting with `grantsNetwork` only enables its host once the user has filled it in.
- Setting types: `text`, `secret` (stored encrypted, redacted in logs), `toggle`, `select`, `number`, `button` (calls the named JS function).
- `auth.callbackPath` registers `kalao://ext/<id>/callback` for OAuth or login redirects.
- `health` entries are probed (GET/HEAD) to show status in Settings → Extensions.

## 4. JavaScript API

Extensions are ES modules. Export the functions for your declared capabilities:

```js
// index.js
export async function searchLyrics(query) {
  const res = await kalao.fetch(`https://api.example.org/search?` +
    kalao.url.params({ q: `${query.artist} ${query.title}` }), {
      headers: { Authorization: `Bearer ${kalao.settings.get("token")}` },
      timeoutMs: 8000,
    });
  if (res.status !== 200) return [];
  const items = res.json();
  return items.map(it => ({
    id: String(it.id),
    title: it.title,
    artist: it.artist,
    durationMs: it.duration * 1000,
    format: it.synced ? "lrc" : "plain",   // "plain" | "lrc" | "elrc"
    body: it.lyrics,
    language: it.lang,                       // optional BCP-47
  }));
}

export async function startLogin() {
  await kalao.auth.openBrowser("https://example.org/oauth?redirect=" +
    encodeURIComponent(kalao.auth.callbackUrl()));
  const { query } = await kalao.auth.waitForCallback({ timeoutMs: 120000 });
  kalao.settings.set("token", query.code);
}
```

Host object `kalao`:

| API | Purpose |
| --- | --- |
| `kalao.fetch(url, {method, headers, body, timeoutMs})` | HTTP(S) only, to hosts in the allowlist; returns `{status, headers, text(), json(), bytes()}`. Cookies are kept per extension |
| `kalao.settings.get/set(key)` | Manifest-declared settings only |
| `kalao.storage.get/set/remove(key)` | Private key-value store (≤ 5 MiB per extension) |
| `kalao.auth.callbackUrl() / openBrowser(url) / waitForCallback()` | Login flows |
| `kalao.html.parse(text)` | HTML parsing with CSS selectors (`select`, `text`, `attr`), running in Rust |
| `kalao.crypto.*` | `sha1`, `sha256`, `md5`, `hmac`, `aes`, `base64` helpers |
| `kalao.log.debug/info/warn` | Shown in the extension's debug log (secrets redacted) |
| `kalao.url.params(obj)` · `kalao.time.now()` | Utilities |

There is **no** filesystem access, child process, `eval` of fetched code, or access to other extensions.

## 5. Sandbox and limits

- Each extension runs in its own QuickJS runtime on a Rust worker thread.
- Limits: 64 MiB heap, 10 s per call (configurable down), 4 concurrent fetches, 16 MiB per response.
- Every fetch is checked against the allowlist after redirects; HTTPS is required (HTTP only for `localhost` in developer mode).
- Return values are validated against the capability schema. Invalid results are dropped and logged, and do not crash the app.
- Repeated failures or health-check failures mark the extension *degraded*, and it is skipped in fallback chains until it recovers.

## 6. How Kalao uses results

- **Lyrics:** all enabled `lyrics` extensions are queried in parallel. Candidates are scored on match quality (title, artist, duration within ±3 s) and format (`elrc` > `lrc` > `plain`), with the user's priority order as the tie-break. The best candidate is normalised (section markers, brackets, whitespace) and annotated by Kalao, not by the extension.
- **Metadata and artwork** are merged across extensions; the user can pin a preferred source.
- **Audio:** `resolveAudio` URLs are streamed or downloaded by Kalao; the extension never handles audio bytes.

## 7. Distribution

- **File:** open a `.kalaoext` to install it. Kalao shows the name, author, capabilities, hosts and a SHA-256 fingerprint, and asks for confirmation.
- **Repository:** add a repository URL that serves `index.json`:

```json
{
  "name": "Example Repo",
  "publicKey": "ed25519:BASE64...",
  "extensions": [
    { "id": "dev.example.lrcfinder", "version": "1.2.0",
      "url": "https://example.org/ext/lrcfinder-1.2.0.kalaoext",
      "sha256": "…", "signature": "ed25519:…", "minKalao": "1.0.0" }
  ]
}
```

  Each package's SHA-256 must match and its signature must verify against the repository key the user trusted when adding the repo. A key change requires re-trust. Updates are checked daily and installed with consent (auto-update per repository is optional).

## 8. Developing an extension

1. Copy the public sample `examples/extensions/local-lrc/`.
2. Enable **Settings → Extensions → Developer mode**, which allows unsigned installs, `localhost` HTTP and a live reload from a folder on the device.
3. Run `kalao-ext` (a CLI crate in the top-level `rust_backend/`, built at M5) to `validate` the manifest, `test` against recorded fixtures, `pack` the package and `sign` with your ed25519 key.
4. Respect the terms of the sites you access. Extensions are the author's responsibility.
