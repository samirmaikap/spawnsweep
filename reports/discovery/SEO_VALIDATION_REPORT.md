# SpawnSweep SEO validation

Validated November 17, 2026 in the SpawnSweep worktree. The [baseline](SEO_BASELINE.md), [progress checklist](SEO_PROGRESS.md), and [tracker](DISCOVERABILITY_TRACKER.csv) contain the live starting point, deployment handoff, and search observations.

## Implemented and verified

| Check | Result |
|---|---|
| Pages build | GitHub Pages-compatible Jekyll 3.10.0 and Kramdown 2.4.0 built 13 public HTML pages with strict front matter. The homepage and all 12 guides returned 200 under the `/spawnsweep/` prefix. The 12 include every requested landing page plus the port 3000 and Xcode simulator tutorials. |
| Sitemap and navigation | XML parsed successfully and listed exactly the 13 indexable HTML pages. Every guide is linked from the homepage, README and `llms.txt`. The latter two are companion indexes for readers and tools. |
| Canonical and social metadata | All pages have one H1, one self-referencing HTTPS canonical, unique titles and descriptions, and matching Open Graph and X card metadata. No local route sent an indexing restriction. The smallest visual logo is a 14,282-byte derivative of the 52,352-byte original, which remains the application and touch icon asset. |
| Structured data | Every JSON-LD document parsed. The homepage associates one SoftwareApplication entity with its page and maintainer. Each guide has a TechArticle and a matching breadcrumb. Pricing, operating system, author and titles were checked against the visible site and release. |
| Links and media | Browser crawl verified 28 distinct local link, fragment and asset targets. External site links returned 200 or 206 except AlternativeTo, which issued a CLI challenge and returned the correct listing through web browsing. Separate documentation checks verified local Markdown targets. Product Hunt exports were inspected and measured at 240×240 and 1270×760. |
| Accessibility and design | Automated axe WCAG 2.0 and 2.1 A/AA checks passed in Chrome across all 13 pages at 375 px and 1280 px in light and dark modes. The install command and comparison table are now keyboard focusable. Visual checks covered both homepage sizes and representative guides. An independent browser review also checked 320, 390, 768 and 1280 px layouts for overflow. |
| Homepage functionality | The install copy button copied the original command to the clipboard. The sample cleanup demo ran and reset. The existing homepage component styles matched the baseline, with a mobile Guides link added. Core text, media fallback and guide navigation were available without JavaScript. |
| Product claims and commands | Reviewed agent detection, weak matches, process signals, worktree eligibility and backup limit, simulator removal, Docker context and auto-remove, pricing and licensing against public source, tool docs and release evidence. Verified command syntax through read-only checks or disposable fixtures. |
| Native app | `swift build` and `.build/debug/SpawnSweep --selftest` passed. The app, plugin and installer source match the original base. A fresh fixture build emitted the existing UserNotifications Sendable warning. Three repeat fixture runs each identified one eligible worktree, stopped one loopback process, released one port and reclaimed 16 MiB. [Benchmark method and results](CLEANUP_BENCHMARK.md) |
| Download and security | v0.2.3 ZIP resolved and matched the GitHub release asset’s SHA-256 digest. Its arm64 app targets macOS 14+. Signature verification found a valid ad hoc signature, and Gatekeeper rejected the build. Stapler found no ticket. [Release audit](PRODUCT_TRUST.md) · [Security reporting](../../SECURITY.md) |
| Independent review | A separate agent rebuilt and crawled the site, checked the layouts and sources, and flagged Docker context and data caveats, worktree recovery limits, process signalling and stale guide links. All findings were addressed and independently rechecked. |

Local Lighthouse 13.6.0 mobile lab sample on the same host and server:

| Page | Performance / accessibility / SEO | LCP | CLS | TBT | Transferred |
|---|---|---:|---:|---:|---:|
| Baseline homepage | 100 / 100 / 100 | 790 ms | 0 | 0 ms | 305,420 B |
| Updated homepage | 100 / 100 / 100 | 901 ms | 0 | 0 ms | 268,864 B |
| AI coding agent cleanup guide | 100 / 100 / 100 | 751 ms | 0 | 0 ms | 93,538 B |

The homepage transferred about 12% fewer bytes in the local run. LCP varied between local runs. The published site's field LCP, INP and CLS require field measurement after deployment.

## Implemented but awaiting external verification

- The branch contains the website, sitemap, guide, README and security updates. Verify the production Pages rebuild and all deployed URLs, response headers, redirects and rendered structured data after merge. Compare live snippet and social previews after crawlers retrieve the updated site.
- The baseline found the official repository in GitHub Search and an independent listing in one unbranded retrieval sample. The tracker records one Bing sample, a partial Gemini answer, and service challenges for the direct Google, ChatGPT Search and Perplexity checks. Post-deployment positions, mentions, recommendations and citations remain to be measured.
- The optional `llms.txt` mirrors guide URLs as a readable reference. Google’s documented AI feature eligibility relies on ordinary indexability and snippet eligibility. [Google AI features](https://developers.google.com/search/docs/appearance/ai-features) · [OpenAI crawler options](https://developers.openai.com/api/docs/bots) · [Perplexity crawler options](https://docs.perplexity.ai/docs/resources/perplexity-crawlers)

## Pending human action

1. Approve and deploy the branch to GitHub Pages. Verify the property and submit the project sitemap to Google Search Console and Bing Webmaster Tools.
2. Apply the proposed public GitHub About copy and topics, and update the portfolio-homepage link if approved. [Proposed repository metadata](KEYWORD_STRATEGY.md)
3. Review and approve any directory edits, Product Hunt launch and private outreach. The kit records existing listings and drafts by channel. [Distribution kit](DISTRIBUTION_KIT.md)
4. Consider enabling GitHub private vulnerability reports. The published maintainer contact is the fallback route in the security policy.

## Blocked

- Developer ID signing, Apple notarization and a standalone release checksum require owner release access and signing credentials. Official Homebrew Cask eligibility also depends on Gatekeeper acceptance and upstream notability. [Release handoff](PRODUCT_TRUST.md) · [Homebrew requirements](https://docs.brew.sh/Acceptable-Casks)
- Native AI and Google result checks that returned a protection page require a supported interactive session. Console index and performance data require property access.

## Not applicable

- Host-root crawler policy already permits public crawling, and the host sitemap already points to the product homepage. A project-path robots file would not govern GitHub Pages crawling.
- Ratings and reviews markup, distribution submissions and real-project performance claims require verified evidence and separate publication scope. The benchmark reports only its reproducible fixture results.
