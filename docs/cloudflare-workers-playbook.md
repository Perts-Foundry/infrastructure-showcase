# The Definitive Hugo Playbook for Cloudflare Workers

**Hugo paired with Cloudflare Workers (with Static Assets) and GitHub Actions is a near-ideal stack for a DevOps consulting website** — blazing build speeds, zero server-side attack surface, a Git-native workflow that fits engineering culture, and a future-proof platform that Cloudflare is actively investing in. This guide distills community wisdom from r/gohugo, Hugo Discourse, Stack Overflow, GitHub issues, and developer blogs into practical, battle-tested advice across every dimension of building and maintaining a professional Hugo site.

**Why Workers instead of Pages?** As of early 2026, Cloudflare has shifted all new investment and feature development to Workers, with Pages entering maintenance mode. Workers now supports serving static assets natively (free and unlimited), `_headers` and `_redirects` file conventions, custom domains, and preview URLs — achieving near-feature-parity with Pages for static site hosting. Starting on Workers avoids a future migration and provides access to the broader Workers platform (Durable Objects, Cron Triggers, Secrets Store, advanced observability) if dynamic features are ever needed.

The biggest pitfalls — silent content disappearance from `_index.md` misuse, forgetting to pin Hugo version in CI, and Go template context confusion — are all avoidable with the right knowledge upfront.

---

## 1. Project structure and the assets-vs-static decision

Hugo's directory layout is its skeleton. Every directory has a specific role, and confusing them — especially `assets/` versus `static/` — is one of the most common beginner mistakes on Hugo Discourse.

```
my-site/
├── archetypes/     # Templates for `hugo new` content
├── assets/         # Files processed by Hugo Pipes (SCSS, JS, images for optimization)
├── config/         # Multi-file configuration (recommended over single hugo.toml)
│   ├── _default/   # Base config for all environments
│   ├── development/
│   └── production/
├── content/        # Markdown content organized into sections
├── data/           # Supplemental JSON/YAML/TOML data (accessible via .Site.Data)
├── i18n/           # Translation tables for multilingual sites
├── layouts/        # HTML templates (override theme templates here)
├── static/         # Files copied verbatim to output (favicon, robots.txt, _headers, verification files)
├── themes/         # Theme directories
├── resources/      # [Generated] Hugo Pipes cache — commit this for CI speed
├── public/         # [Generated] Build output — never commit this
└── wrangler.toml   # Cloudflare Workers configuration
```

**The critical distinction is `assets/` vs `static/`**. Put files in `assets/` when they need processing — SCSS compilation, CSS/JS minification, fingerprinting, image resizing, or WebP conversion. Put files in `static/` only when they should be copied verbatim: `favicon.ico`, Google site verification files, downloadable PDFs, pre-built vendor files, and the `_headers` file for Cloudflare. Files in `assets/` are accessed via `resources.Get` in templates and only published when explicitly referenced. Files in `static/` are always published at their relative path.

The standard Hugo Pipes pattern chains processing steps:

```go
{{ $css := resources.Get "css/main.css" | minify | fingerprint "sha512" }}
<link rel="stylesheet" href="{{ $css.RelPermalink }}"
      integrity="{{ $css.Data.Integrity }}" crossorigin="anonymous">
```

### Leaf bundles vs branch bundles — Hugo's most critical distinction

This trips up nearly every Hugo newcomer. **`index.md` (no underscore) creates a leaf bundle** — a single page with no children. All other files in the directory become page resources (images, data), not separate pages. **`_index.md` (with underscore) creates a branch bundle** — a section/list page that can have child pages beneath it.

```
content/
├── services/              # Branch bundle
│   ├── _index.md          # Section list page → /services/
│   ├── cloud-consulting/  # Leaf bundle
│   │   ├── index.md       # Single page → /services/cloud-consulting/
│   │   └── hero.jpg       # Page resource (not a separate page)
│   └── devsecops/
│       └── index.md       # Single page → /services/devsecops/
```

Using `index.md` when you need `_index.md` will **silently hide all child pages** with zero warning. This is documented in Hugo GitHub issue #7108 as one of the most confusing behaviors.

### Config directory approach for multi-environment builds

For anything beyond a toy project, split configuration into the `config/` directory. Hugo's `hugo server` defaults to the **development** environment; `hugo build` defaults to **production**. Split files by root key — `params.toml` should not contain a `[params]` wrapper.

```
config/
├── _default/
│   ├── hugo.toml       # Core: baseURL, title, theme
│   ├── params.toml     # Custom site parameters
│   ├── menus.toml      # Navigation menus
│   └── markup.toml     # Goldmark, syntax highlighting
├── development/
│   └── params.toml     # No analytics, debug flags
└── production/
    ├── hugo.toml       # Production baseURL
    └── params.toml     # Analytics IDs, minification
```

Override the environment with `hugo build --environment staging` or `HUGO_ENVIRONMENT=staging`. Verify the right config loads with `hugo config -e production | grep baseurl`.

---

## 2. Theme selection and the module-vs-submodule debate

### Hugo Modules vs git submodules

The community increasingly favors **Hugo Modules** (powered by Go Modules) over git submodules, though both work. Hugo Modules offer version locking via `go.sum`, one-command updates (`hugo mod get -u`), and composable imports from multiple sources. Git submodules are simpler (no Go installation needed) and support GitHub Dependabot auto-updates.

The biggest git submodule pain points: everyone must remember `git clone --recurse-submodules` (forgetting causes a blank site), removal requires editing three files (`.gitmodules`, `.git/config`, and deleting `.git/modules/`), and merge conflicts on submodule pointers are common. Hugo Modules require Go installed locally and in CI, and private repos need extra auth configuration.

**For a new project in 2026, use Hugo Modules if Go is already in your toolchain; otherwise git submodules are perfectly fine.** Pin versions either way.

### Best themes for a consulting business

For a DevOps/DevSecOps consulting site needing services pages, case studies, and a blog, the community recommends:

- **Blowfish** (~2k stars, Tailwind CSS 3, actively maintained) — flexible landing page layouts, dark mode, image galleries, 30+ language translations. Sits between PaperMod's simplicity and Hugo Blox's complexity. Best general-purpose choice for business sites.
- **Zerostatic themes** (Serif, Winston) — specifically designed for agencies/freelancers with CTAs, service sections, and perfect Lighthouse scores. No npm/Node dependency.
- **Hugoplate** (~1.1k stars, Tailwind) — starter template for business sites with pre-built page types.
- **PaperMod** (~10k stars) — the most popular Hugo theme overall, but primarily blog-focused. Lacks dropdown menus and flexible page layouts needed for service/consulting sites.

**Start with an existing theme and customize via overrides.** Hugo's union file system means your project's `layouts/` directory always takes precedence over the theme's. Override the smallest partial possible rather than entire templates. Well-designed themes provide empty "hook" partials (`custom-head.html`, `extend-footer.html`) specifically for user injection. If you find yourself overriding more than 50% of a theme's templates, build a custom one.

---

## 3. Configuration settings people miss and baseURL gotchas

### Essential settings commonly overlooked

```toml
# hugo.toml — Settings people frequently miss

enableRobotsTXT = true          # Default is FALSE — no robots.txt without this
enableGitInfo = true            # Auto-populate .Lastmod from git commits

[markup.goldmark.renderer]
  unsafe = true                 # Required for ANY inline HTML in Markdown

[markup.goldmark.parser.attribute]
  block = true                  # Enable {.class} attributes on Markdown blocks

[build]
  writeStats = true             # Essential for Tailwind CSS purging

[sitemap]
  changefreq = ''               # Google ignores this — leave empty
  priority = -1                 # Google ignores this — omit
```

The **`enableRobotsTXT`** default of `false` means many Hugo sites ship without a `robots.txt`. The **`unsafe = true`** Goldmark setting is misleadingly named — it simply allows inline HTML that CommonMark permits. Without it, raw HTML in Markdown is silently stripped.

### baseURL — the #1 configuration footgun

The `baseURL` must include the protocol, must end with a trailing slash, and must be a valid URL. `https://example.com/` is correct; `example.com`, `https://example.com`, and `"/"` are all wrong for production.

**Never concatenate `.Site.BaseURL` with paths in templates.** Use `.RelPermalink`, `.Permalink`, or the `relURL`/`absURL` template functions. Hardcoded baseURL concatenation breaks when the site moves domains, runs behind a reverse proxy, or serves from a subdirectory. This advice comes directly from Hugo core developer bep.

### Permalink structure for SEO

Flat, descriptive URLs outperform date-based hierarchies. Configure in `hugo.toml`:

```toml
[permalinks]
  [permalinks.page]
    blog = '/:slug/'                    # /my-great-article/
    services = '/services/:slug/'       # /services/cloud-consulting/
  [permalinks.section]
    blog = '/blog/'
```

Use `slug` in front matter to override URL-unfriendly titles. The `url` front matter field overrides all permalink patterns for that specific page.

---

## 4. Content management for a consulting business

### Recommended content organization

```
content/
├── _index.md                          # Homepage
├── services/
│   ├── _index.md                      # Services overview listing
│   ├── cloud-consulting/index.md      # Leaf bundle per service
│   └── devsecops/index.md
├── case-studies/
│   ├── _index.md                      # Portfolio listing
│   └── acme-migration/
│       ├── index.md                   # Co-located images
│       └── architecture-diagram.png
├── blog/
│   ├── _index.md
│   └── k8s-security-guide/
│       ├── index.md
│       └── cover.jpg
├── about/index.md
└── contact/index.md
```

Use **sections** (directories) for primary, permanent content grouping that mirrors URL structure. Use **taxonomies** for cross-cutting, many-to-many relationships. A case study lives in `/case-studies/acme-migration/` (section) but is tagged with `industries: ["Healthcare"]` and `services: ["Cloud Migration"]` (taxonomies) so it appears in multiple listing contexts.

### Archetypes for standardized content creation

Archetypes are templates for `hugo new`. Create section-specific archetypes matching your content directories:

```yaml
# archetypes/case-studies.md
---
title: "{{ replace .File.ContentBaseName `-` ` ` | title }}"
date: {{ .Date }}
draft: true
params:
  client: ""
  industry: ""
  challenge: ""
  result: ""
  featured_image: "cover.jpg"
tags: []
---

## The Challenge

## Our Approach

## Results
```

Set `draft: true` by default — content must be explicitly published. Pre-populate all custom fields so authors never forget them. Include a skeleton content structure in the body.

### Shortcodes for business content

Build reusable components as shortcodes. For a consulting site, useful custom shortcodes include:

```html
<!-- layouts/shortcodes/cta-button.html -->
<div class="cta-container">
  <a href="{{ .Get "url" }}" class="cta-button">
    {{ .Get "text" | default "Schedule a Consultation" }}
  </a>
</div>

<!-- layouts/shortcodes/testimonial.html -->
<blockquote class="testimonial">
  <p>{{ .Inner | markdownify }}</p>
  {{ with .Get "author" }}<cite>— {{ . }}{{ with $.Get "role" }}, {{ . }}{{ end }}</cite>{{ end }}
</blockquote>
```

Hugo's built-in `ref` and `relref` shortcodes validate internal links at build time — use them for all cross-references. Hugo also provides built-in `figure`, `highlight`, `youtube`, and (since v0.140) `details` shortcodes.

---

## 5. Go template gotchas and the infamous dot context

### The dot (`.`) rebinding problem

**This is the #1 source of Hugo template confusion.** At the top level, `.` is the Page object. But `range` and `with` rebind the dot to a new value:

```go
{{ .Title }}              {{/* Page title — works */}}

{{ range .Pages }}
  {{ .Title }}            {{/* NOW this is the iterated page's title */}}
  {{ $.Title }}           {{/* $ escapes to root context — parent page title */}}
{{ end }}

{{ with .Params.author }}
  {{ . }}                 {{/* NOW this is the author string */}}
  {{ $.Title }}           {{/* $ still reaches the page */}}
{{ end }}
```

Always use `$` to escape back to the template's root context from inside `range` or `with` blocks. When passing multiple values to partials, use `dict`:

```go
{{ partial "hero.html" (dict "title" .Title "image" .Params.hero "page" .) }}
```

### .Scratch is dead — use .Store

`.Scratch` was essential before Hugo v0.48.0 (when variables couldn't be reassigned). It had a notorious bug: values were reset on `hugo server` live reloads. **`.Store`** (Hugo v0.93.0+) fixes this and is now the recommended replacement. As of v0.139.0+, `Page.Scratch` is aliased to `Page.Store` — they're identical at the page level. But `SHORTCODE.Scratch` is soft-deprecated and should be replaced with `SHORTCODE.Store`.

### Template debugging techniques

```go
{{ printf "%#v" .Params }}             {{/* Dump any variable */}}
<pre>{{ debug.Dump .Page }}</pre>       {{/* Pretty-printed dump */}}

{{ if site.IsServer }}
  <pre>{{ debug.Dump . }}</pre>         {{/* Only in dev server */}}
{{ end }}
```

Run Hugo with `--templateMetrics` to identify slow templates and `--logLevel debug` for verbose output. Use `--printPathWarnings` and `--printUnusedTemplates` to catch issues early.

---

## 6. Performance optimization and Core Web Vitals

### Image processing — the highest-impact optimization

Hugo's built-in image processing eliminates the need for external tools. Create a Markdown render hook for automatic optimization of every image:

```go
{{/* layouts/_default/_markup/render-image.html */}}
{{ $image := .Page.Resources.GetMatch .Destination }}
{{ if $image }}
  {{ $small := $image.Resize "500x webp" }}
  {{ $medium := $image.Resize "800x webp" }}
  {{ $large := $image.Resize "1200x webp" }}
  <picture>
    <source srcset="{{ $small.RelPermalink }} 500w, {{ $medium.RelPermalink }} 800w, {{ $large.RelPermalink }} 1200w"
            sizes="(max-width: 600px) 500px, (max-width: 900px) 800px, 1200px" type="image/webp">
    <img src="{{ $medium.RelPermalink }}" alt="{{ .Text }}"
         width="{{ $image.Width }}" height="{{ $image.Height }}"
         loading="lazy" decoding="async">
  </picture>
{{ else }}
  <img src="{{ .Destination | safeURL }}" alt="{{ .Text }}" loading="lazy">
{{ end }}
```

**Always set `width` and `height`** on images — Hugo provides `.Width` and `.Height` — to eliminate Cumulative Layout Shift (CLS). Use `loading="lazy"` on all below-the-fold images, but **never lazy-load the LCP element** (hero image). For the hero, use `loading="eager"` and `fetchpriority="high"`, plus a preload hint in `<head>`:

```go
{{ with .Params.featured_image }}
  {{ $img := $.Resources.GetMatch . }}
  {{ if $img }}
    {{ $hero := $img.Resize "1200x webp" }}
    <link rel="preload" as="image" href="{{ $hero.RelPermalink }}" type="image/webp">
  {{ end }}
{{ end }}
```

### Critical CSS and asset optimization

Inline critical above-the-fold CSS and async-load the rest:

```go
{{ $critical := resources.Get "css/critical.css" | minify }}
<style>{{ $critical.Content | safeCSS }}</style>

{{ $styles := resources.Get "css/main.css" | minify | fingerprint }}
<link rel="preload" href="{{ $styles.RelPermalink }}" as="style"
      onload="this.onload=null;this.rel='stylesheet'">
<noscript><link rel="stylesheet" href="{{ $styles.RelPermalink }}"></noscript>
```

Use `partialCached` for expensive, reusable template fragments — community benchmarks show **up to 40% reduction** in template rendering time.

### Cloudflare Workers caching strategy

Place a `_headers` file in `static/` for aggressive caching of fingerprinted (content-hashed) assets. **Cloudflare Workers with Static Assets natively respects the `_headers` file convention**, just as Pages did — no code changes needed:

```
# Fingerprinted assets — immutable forever
/css/*
  Cache-Control: public, max-age=31556952, immutable
/js/*
  Cache-Control: public, max-age=31556952, immutable

# HTML — always revalidate
/*.html
  Cache-Control: public, max-age=0, must-revalidate
```

Hugo's `fingerprint` function generates content-hash filenames, making `immutable` caching safe — when the content changes, the filename changes, busting the cache automatically.

Workers static asset requests are **free and unlimited with no storage cost** on Cloudflare's free tier, so there is no cost concern around caching strategy or request volume.

---

## 7. SEO implementation with code examples

### Meta tags, Open Graph, and Twitter Cards

Hugo provides built-in embedded templates, but custom partials give more control:

```go
{{/* layouts/partials/seo/meta.html */}}
<meta name="description" content="{{ with .Description }}{{ . }}{{ else }}{{ .Site.Params.description }}{{ end }}">

<meta property="og:title" content="{{ .Title }}">
<meta property="og:description" content="{{ with .Description }}{{ . }}{{ else }}{{ .Summary }}{{ end }}">
<meta property="og:type" content="{{ if .IsPage }}article{{ else }}website{{ end }}">
<meta property="og:url" content="{{ .Permalink }}">
{{ with .Params.images }}{{ range first 1 . }}
<meta property="og:image" content="{{ . | absURL }}">
{{ end }}{{ end }}

<meta name="twitter:card" content="{{ if .Params.images }}summary_large_image{{ else }}summary{{ end }}">
<meta name="twitter:title" content="{{ .Title }}">
```

**Gotcha**: Hugo's built-in OG templates expect `images` (plural, YAML array) in front matter — not `image` (singular). Page bundle images named `*feature*`, `*cover*`, or `*thumbnail*` are auto-detected as fallbacks.

### Structured data via JSON-LD

Use Hugo's `dict` + `jsonify` + `safeJS` pattern to avoid escaping issues:

```go
{{/* layouts/partials/schema-org.html */}}
{{ if .IsHome }}
<script type="application/ld+json">
{{- dict
  "@context" "https://schema.org"
  "@type" "ProfessionalService"
  "name" .Site.Title
  "url" .Site.BaseURL
  "description" .Site.Params.description
  "email" .Site.Params.email
| jsonify | safeJS -}}
</script>
{{ end }}

{{ if and .IsPage (eq .Section "blog") }}
<script type="application/ld+json">
{{- dict
  "@context" "https://schema.org"
  "@type" "BlogPosting"
  "headline" .Title
  "url" .Permalink
  "datePublished" (.PublishDate.Format "2006-01-02T15:04:05Z07:00")
  "dateModified" (.Lastmod.Format "2006-01-02T15:04:05Z07:00")
  "wordCount" .WordCount
  "author" (dict "@type" "Person" "name" (default "Your Name" .Params.author))
| jsonify | safeJS -}}
</script>
{{ end }}
```

Never use string interpolation inside JSON-LD — Go's template engine aggressively escapes content inside `<script>` tags and will produce broken JSON.

### Custom robots.txt with AI crawler blocking

```
{{/* layouts/robots.txt — enable with enableRobotsTXT: true */}}
User-agent: *
Disallow: /tags/
Disallow: /categories/

User-agent: GPTBot
Disallow: /

User-agent: ChatGPT-User
Disallow: /

Sitemap: {{ "sitemap.xml" | absLangURL }}
```

For staging environments, add a `noindex` meta tag conditionally:

```go
{{ if ne hugo.Environment "production" }}
  <meta name="robots" content="noindex,nofollow">
{{ end }}
```

---

## 8. Security headers and SRI for Cloudflare Workers

### Complete production _headers file

Place as `static/_headers`. Cloudflare Workers with Static Assets natively respects this file convention — the behavior is identical to the Pages approach:

```
/*
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  X-XSS-Protection: 0
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=(), interest-cohort=()
  Content-Security-Policy: default-src 'self'; script-src 'self' https://static.cloudflareinsights.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'; upgrade-insecure-requests
  Strict-Transport-Security: max-age=31536000; includeSubDomains; preload

# Fingerprinted assets — immutable cache
/css/*
  Cache-Control: public, max-age=31556952, immutable
/js/*
  Cache-Control: public, max-age=31556952, immutable

# Prevent workers.dev from being indexed
https://*.workers.dev/*
  X-Robots-Tag: noindex
```

**Key difference from Pages:** The noindex rule targets `*.workers.dev` instead of `*.pages.dev`. Alternatively, set `workers_dev = false` in `wrangler.toml` once the custom domain is confirmed working to disable the workers.dev subdomain entirely.

If using Cloudflare Web Analytics, the CSP must allow `https://static.cloudflareinsights.com` in `script-src`. Start HSTS with a shorter `max-age` (300 seconds) to test before committing to 12 months.

### Subresource Integrity with Hugo Pipes

Hugo Pipes generates SRI hashes automatically via `fingerprint`. The recommended algorithm is **sha384** for the best balance of security and performance:

```go
{{ $css := resources.Get "css/main.css" | minify | fingerprint "sha384" }}
<link rel="stylesheet" href="{{ $css.RelPermalink }}"
      integrity="{{ $css.Data.Integrity }}" crossorigin="anonymous">

{{ $js := resources.Get "js/main.js" | js.Build | minify | fingerprint "sha384" }}
<script src="{{ $js.RelPermalink }}"
        integrity="{{ $js.Data.Integrity }}" crossorigin="anonymous"></script>
```

Skip fingerprinting and SRI in development for faster rebuilds:

```go
{{ $css := resources.Get "css/main.css" }}
{{ if hugo.IsProduction }}
  {{ $css = $css | minify | fingerprint "sha384" }}
{{ end }}
<link rel="stylesheet" href="{{ $css.RelPermalink }}"
  {{ if hugo.IsProduction }}integrity="{{ $css.Data.Integrity }}" crossorigin="anonymous"{{ end }}>
```

### Safe HTML handling

Keep Goldmark's `unsafe = false` default if your content comes from untrusted sources. Use **shortcodes** instead of raw HTML in Markdown — they're Hugo's secure alternative to inline HTML. Create a render hook for external links to automatically add security attributes:

```go
{{/* layouts/_default/_markup/render-link.html */}}
<a href="{{ .Destination | safeURL }}"
  {{ if strings.HasPrefix .Destination "http" }}
    target="_blank" rel="noopener noreferrer"
  {{ end }}>{{ .Text | safeHTML }}</a>
```

---

## 9. Wrangler configuration and Workers setup

### The wrangler.toml configuration

Place `wrangler.toml` at the project root. This tells Workers how to serve the Hugo output:

```toml
name = "example-website"
compatibility_date = "2026-03-07"

[assets]
directory = "./public"
not_found_handling = "404-page"
html_handling = "auto-trailing-slash"
```

**Key settings:**

- **`directory`** — points to Hugo's build output (`./public`)
- **`not_found_handling = "404-page"`** — serves a custom `404.html` from the Hugo build for missing routes. Hugo generates this automatically if you create a `layouts/404.html` template.
- **`html_handling = "auto-trailing-slash"`** — matches Hugo's default URL style where `/services/` serves `services/index.html`

### Adding dynamic functionality later

If a contact form Worker function is needed later, add a `main` entry point and use `run_worker_first` to route API requests to the Worker while serving everything else as static assets:

```toml
name = "example-website"
compatibility_date = "2026-03-07"
main = "functions/worker.js"

[assets]
directory = "./public"
not_found_handling = "404-page"
html_handling = "auto-trailing-slash"
run_worker_first = true
```

Then in `functions/worker.js`:

```javascript
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Route API requests to Worker logic
    if (url.pathname.startsWith("/api/")) {
      // Handle dynamic requests (contact form, etc.)
      return handleApiRequest(request, env);
    }

    // Everything else falls through to static assets
    return env.ASSETS.fetch(request);
  }
};
```

This pattern keeps the site purely static by default while leaving a clean upgrade path for dynamic features — no architecture changes required.

### Workers custom domain requirements

**Workers custom domains require that the domain's nameservers are managed by Cloudflare.** Unlike the old Pages approach, this is a hard requirement with no workaround. If your domain is already on Cloudflare (as it should be for this stack), no action is needed. But document this constraint — it means you cannot use Workers custom domains with domains parked at external registrars that only delegate DNS via NS records for a subdomain.

---

## 10. GitHub Actions workflow for Cloudflare Workers deployment

### The complete, production-ready workflow

```yaml
name: Deploy Hugo to Cloudflare Workers

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      deployments: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # Full git history for .GitInfo/.Lastmod
          submodules: true        # If using git submodules for theme

      - name: Cache Hugo resources
        uses: actions/cache@v3
        with:
          path: resources/_gen
          key: ${{ runner.os }}-hugo-${{ github.ref_name }}-${{ github.sha }}
          restore-keys: |
            ${{ runner.os }}-hugo-${{ github.ref_name }}-
            ${{ runner.os }}-hugo-main-

      - name: Setup Hugo
        uses: peaceiris/actions-hugo@v3
        with:
          hugo-version: "0.148.2"    # Always pin exact version
          extended: true              # Required for SCSS and WebP

      - name: Build
        run: hugo --gc --minify --cleanDestinationDir
        env:
          HUGO_ENVIRONMENT: production

      - name: Deploy to production
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          command: deploy

      - name: Deploy preview
        if: github.event_name == 'pull_request'
        id: preview
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          command: versions upload

      - name: Comment preview URL on PR
        uses: thollander/actions-comment-pull-request@v3
        if: github.event_name == 'pull_request'
        with:
          message: |
            🚀 **Preview deployed.** Check the Cloudflare dashboard for the preview URL.
          comment-tag: cf-preview
```

### Why this approach beats Cloudflare's built-in Git integration

Building in GitHub Actions gives you **full control over Hugo version, build flags, and caching**. Cloudflare's built-in build system has no native Hugo support for Workers — Hugo is not a first-class Workers framework in Cloudflare's dashboard or auto-detection. With GitHub Actions, build logs are visible in GitHub, caching drops build times from minutes to seconds, and your workflow definition lives in version control.

**The API token for the website repo needs only Workers Scripts Edit permission** — the minimal scope needed for Wrangler to deploy the Worker.

### Preview deployments on Workers

Workers preview deployments are evolving. The Pages-era branch-based preview URLs (`<branch>.<project>.pages.dev`) were mature and ergonomic. Workers uses a version-based approach instead:

- **`wrangler versions upload`** uploads a new version without promoting it to production, generating a preview URL
- **`wrangler deploy`** promotes a version to production on the custom domain

Alternatively, enable `workers_dev = true` in `wrangler.toml` to get a `*.workers.dev` URL for non-production deployments. The Workers preview workflow is newer than Pages and may evolve — check the Cloudflare Workers docs for the latest preview deployment guidance at implementation time.

### Key build flags

- `--gc`: Garbage collects unused cache files
- `--minify`: Minifies HTML, CSS, JS, JSON, SVG, XML
- `--cleanDestinationDir`: Removes stale files from previous builds (Hugo does NOT do this by default — a notorious gotcha)

**Always use the extended Hugo edition.** Most themes require it for SCSS compilation, and the overhead is negligible. Without it, SCSS-dependent themes fail with a cryptic `TOCSS` error (or in some historical versions, silently produce broken CSS with no error at all).

---

## 11. The top gotchas that silently break Hugo sites

### Content that vanishes without warning

The most dangerous Hugo behaviors are the silent ones:

**`_index.md` with `draft: true` makes an entire section disappear.** No warning, no error. A site can go from 67 pages to 2 pages because a single section's `_index.md` was marked as a draft. This is documented in GitHub issue #7108 and catches experienced users.

**Future-dated `_index.md` silently suppresses all descendant content.** If a section's `_index.md` has a date newer than its children's dates, Hugo skips the entire section without any diagnostic message.

**Hugo does not clean `public/` before building.** Content you deleted or marked as draft in a previous build persists in the output directory. Always use `--cleanDestinationDir` or `rm -rf public` before production builds.

### Template lookup order — Hugo's most misunderstood concept

Hugo selects templates based on an inverted cascade considering page kind, content type, layout, and output format. The key rules:

- Project `layouts/` **always overrides** theme `layouts/` at the same path
- `layouts/_default/single.html` is the fallback for all single pages
- `layouts/_default/list.html` is the fallback for all list/section pages
- Content type defaults to the **section name** (the directory under `content/`)
- Content in `content/` root has type `page`, not a section name
- Front matter `layout: contact` targets `layouts/page/contact.html`

### URL handling — leave the legacy options alone

**`relativeURLs` and `canonifyURLs` are both legacy options** that cause more problems than they solve. `relativeURLs` rewrites all URLs as relative paths (breaking content in unexpected ways), and `canonifyURLs` is marked for removal in a future Hugo release. Leave both at their defaults (`false`). Use `.RelPermalink` for internal links and `.Permalink` for contexts requiring absolute URLs (RSS, Open Graph, sitemaps, canonical tags).

### .RelPermalink vs .Permalink — when to use which

`.RelPermalink` returns the path-only URL (`/services/cloud-consulting/`). `.Permalink` returns the full absolute URL (`https://example.com/services/cloud-consulting/`). **Use `.RelPermalink` for all internal navigation links and asset references.** Use `.Permalink` for RSS feeds, canonical tags, Open Graph/Twitter Card meta tags, sitemaps, and structured data. Never use the deprecated `.URL`.

### Breaking changes to watch for

Hugo releases frequently include breaking changes. Notable versions: **v0.123.0** (significant content/template changes), **v0.145.1–v0.147.x** (rapid breaking changes in succession), **v0.146.0** (new templating system, April 2025), and **v0.153.0** (LibSass deprecated, WebP via WASM). Always read release notes before upgrading, test locally first, and pin your Hugo version in CI.

---

## 12. Building a consulting business site on Hugo

### Contact forms without a server

Since Cloudflare Workers can run server-side JavaScript, you have two clean paths for contact forms:

**Option A: Inline Worker function (recommended for Workers).** Add a `main` entry point in `wrangler.toml` with `run_worker_first = true` and handle `/api/contact` in the Worker script. This keeps everything in one deployment — no external services needed:

```javascript
// functions/worker.js
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/contact" && request.method === "POST") {
      const { name, email, message, honeypot } = await request.json();

      // Honeypot spam check
      if (honeypot) return new Response(JSON.stringify({ success: true }));

      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${env.RESEND_API_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          from: "website@yourdomain.com",
          to: "contact@yourdomain.com",
          subject: `Contact: ${name}`,
          html: `<p><strong>${name}</strong> (${email})</p><p>${message}</p>`
        })
      });

      return new Response(JSON.stringify({ success: res.ok }), {
        status: res.ok ? 200 : 500,
        headers: { "Content-Type": "application/json" }
      });
    }

    // Everything else served as static assets
    return env.ASSETS.fetch(request);
  }
};
```

Store the `RESEND_API_KEY` as a Worker secret via `wrangler secret put RESEND_API_KEY` or manage it in Terraform. Add Cloudflare Turnstile (free CAPTCHA alternative) for spam protection.

**Option B: External form services.** For simpler setups without any Worker code, **Formspree** (50 free submissions/month) or **Web3Forms** (more generous free tier) work without any backend code — just a form `action` URL.

### Analytics — privacy-first with Cloudflare Web Analytics

Enable Cloudflare Web Analytics with one click in the Cloudflare dashboard (Workers & Pages → project → Metrics → Enable). It's **free, cookie-free, and requires no code changes** — Cloudflare auto-injects the JS beacon. No personal data collection, no fingerprinting. For more accurate bot filtering, community members recommend **Umami** (self-hosted, open source) as a complement.

### CMS options for when non-technical editors arrive

**Start without a CMS** — you're technical, and Markdown + Git is the ideal workflow. When non-technical collaborators need access, add a CMS layer:

- **Sitepins** — Native Hugo shortcode support, no GitHub account needed for editors, generous free tier
- **Sveltia CMS** — Modern drop-in replacement for the now-unmaintained Decap CMS (formerly Netlify CMS)
- **CloudCannon** ($55+/month) — Best visual editing for Hugo, but overkill for a solo consultant
- **Front Matter** (VS Code extension) — Free, developer-focused, no web UI

---

## 13. Maintenance strategy and Hugo's future

### Update cadence and theme management

**Update Hugo quarterly, not immediately after releases.** Wait 2–4 weeks for community feedback on new versions. Always read the "Breaking Changes" section in release notes. Test locally with `hugo server --disableFastRender` (forces full rebuild) before pushing. Keep local and CI Hugo versions synchronized.

For themes managed via Hugo Modules:

```bash
hugo mod get -u github.com/author/theme@v2.0.0   # Pin to specific version
hugo mod get -u ./...                              # Update all modules
hugo mod tidy                                      # Clean unused deps
```

After every theme update, verify your layout overrides still work — theme changes can silently conflict with files in your project's `layouts/` directory.

### Platform portability

Hugo's static output is host-agnostic. The same `public/` directory deploys to Cloudflare Workers, Netlify, Vercel, GitHub Pages, AWS S3+CloudFront, or any static host by changing only the deploy step in the GitHub Actions workflow. The `wrangler.toml` is the only Cloudflare-specific file; everything else is standard Hugo. Hugo's official docs now include a Workers hosting guide and `wrangler.toml` configuration.

If Cloudflare's direction changes again, migration is a matter of swapping the deploy step. No content, templates, or build process changes are required.

### Workers-specific maintenance considerations

- **Pin the `compatibility_date` in `wrangler.toml`** — this locks the Workers runtime behavior to a specific date, preventing surprise breaking changes from Cloudflare runtime updates. Update it deliberately after testing.
- **Monitor Workers preview deployment tooling** — the preview URL workflow is actively evolving. Check Cloudflare's changelog periodically for improvements.
- **Worker script invocations** — pure static asset serving does not consume the free tier's 100,000 daily Worker invocations. Only dynamic Worker logic (contact form handler, API routes) counts against this quota. Monitor usage in the Cloudflare dashboard if you add dynamic features.

### When Hugo isn't the right tool

Hugo has real limitations to consider. There's **no plugin system** — all logic must be expressed in Go templates, shortcodes, or partials. Complex build-time transformations that would be trivial in JavaScript SSGs may be impossible. There's **no dynamic content** without external services or Workers functions — no user auth, no database, no server-side personalization (though Workers opens the door to some of these if needed). The **Go template learning curve** is steep for teams coming from Jinja2, Liquid, or JSX. And Hugo **cannot generate pages from data files alone** — every page needs a Markdown content file.

For a DevOps/DevSecOps consulting site, however, none of these are deal-breakers. The site is fundamentally static content — services, case studies, blog posts, team info. Dynamic needs (contact forms, analytics) are cleanly handled by Workers functions and Cloudflare Web Analytics. Hugo's **86,900+ GitHub stars**, sub-second build times, and zero server-side attack surface make it the right tool for this job. Keep customizations minimal, pin your versions, and commit your `resources/_gen` cache — your site will be fast, secure, and maintainable for years.

---

## Summary of changes from the Cloudflare Pages approach

For reference, here are the key differences between the Pages-based playbook and this Workers-based playbook:

| Concern | Pages approach | Workers approach |
|---|---|---|
| **Deployment command** | `wrangler pages deploy public` | `wrangler deploy` (reads `wrangler.toml`) |
| **Configuration file** | None (CLI flags) | `wrangler.toml` with `[assets]` block |
| **Preview deployments** | Branch-based `<branch>.<project>.pages.dev` | Version-based via `wrangler versions upload` |
| **Noindex subdomain** | `*.pages.dev` | `*.workers.dev` |
| **Custom domain requirement** | Works with external nameservers | Requires Cloudflare-managed nameservers |
| **Dynamic functionality** | Pages Functions (`functions/` directory) | Worker script with `run_worker_first` and `env.ASSETS.fetch()` |
| **`_headers` / `_redirects`** | Supported natively | Supported natively (same convention) |
| **Contact form endpoint** | `functions/api/contact.js` (Pages Functions) | Inline in Worker script or separate `functions/worker.js` |
| **Platform investment** | Maintenance mode | Active development |
| **GitHub Action** | `cloudflare/wrangler-action@v3` with `pages deploy` | `cloudflare/wrangler-action@v3` with `deploy` |
| **Free tier static requests** | Unlimited | Unlimited (static assets don't count as invocations) |
