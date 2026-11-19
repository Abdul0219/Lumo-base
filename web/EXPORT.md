# Lumo Base — Export Manifest

**Deliverable:** `web/dist/lumo-base-console.html` — "Lumo Base — Project Console".
**Format:** Standalone HTML (single HTML5 file), the default export format.
**Size:** 42,322 bytes. Byte-for-byte identical to `web/index.html`; SHA-256 `34a2d80370ed4712165770dde1986e304f215e7f3fbd6ead235e9c126463ba9c` on both.

**Standalone / offline guarantee:** All CSS is in one inline `<style>` block. Graphics are inline SVG or CSS; system font stacks replace web fonts. Zero external `href`/`src`, zero `http(s)` URLs, no `@import`, `url(http`, `<link>`, `<script src>`, or scripts. No CDN, no build step, no server, no network requests. Confirmed by `cmp` and SHA-256.

**How to open:**
- Double-click the file, or open `file:///D:/projects/lumo%20base/web/dist/lumo-base-console.html`.
- Or serve `web/` with Caddy (`caddy file-server --root "D:/projects/lumo base/web"`) and visit `/dist/lumo-base-console.html`. Renders fully offline either way.

**Verification:** PASS — doctype, charset, viewport meta, single inline style, zero external refs, zero `@import`, zero `url(http`, zero `<script src>`.

**Scope:** PDF, PPTX, and ZIP exports were not requested and were not produced. The console contains no billing, pricing, or plans section.

**Source integrity:** `web/index.html` was not modified; this export is a copy only, with no external assets added.
