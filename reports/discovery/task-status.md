# Discovery task status

Format: `ID | status | owner | branch/PR | evidence | blocker | next action | last checked`. See SS-DISCOVERY-001 and `baseline-2026-11-16.md`.

| ID | Status | Owner | Branch/PR | Evidence | Blocker | Next action | Last checked |
|---|---|---|---|---|---|---|---|
| DISC-00 | DONE | agent | disc/canonical-domain | baseline-2026-11-16.md | none | none | 2026-11-16 |
| DISC-01 | REVIEW | agent, owner | disc/canonical-domain | Every site URL moved to samirmaikap.dev/spawnsweep/; repo Website field updated | Merge to main deploys it | Merge, then verify live canonical. Enforce HTTPS turned on 2026-11-16; http now 301s to https | 2026-11-16 |
| DISC-02 | BLOCKED_OWNER | owner | user site repo | Crawlers allowed; root sitemap and home page don't list /spawnsweep/ | Fix lives in samirmaikap/samirmaikap.github.io; console access | Add /spawnsweep/ to root sitemap and link it from samirmaikap.dev. Verify the property in Google Search Console and Bing, submit the sitemap | 2026-11-16 |
| DISC-03 | REVIEW | agent | disc/canonical-domain | JSON-LD parses, one entity @id, title names Claude Code | Rich Results Test needs the live page | Run Rich Results Test and a social card check after deploy | 2026-11-16 |
| DISC-04 | REVIEW | agent | disc/canonical-domain | All links 200; page now states the build isn't notarized and mentions the Pro license check | none | Manual viewport, keyboard and dark mode pass | 2026-11-16 |
| TRUST-01 | BLOCKED_OWNER | owner | none | release.sh supports Developer ID signing and notarytool; v0.2.3 release notes say it isn't notarized | Apple Developer ID certificate and notary credentials | Run scripts/release.sh without --unsigned, then remove the Gatekeeper workaround copy | 2026-11-16 |
| TRUST-02 | BACKLOG | agent | none | install.sh has no checksum check; no SHA-256 published | TRUST-01 | Publish SHA256SUMS with each release and verify it in install.sh | 2026-11-16 |
| CONTENT-01 | BACKLOG | agent, owner | none | none | Owner approval to publish | Draft the port-3000 and leftover-dev-server guides | 2026-11-16 |
| CONTENT-02 | BACKLOG | agent, owner | none | none | CONTENT-01 | none | 2026-11-16 |
| DEMO-01 | BACKLOG | owner | none | marketing/launch-video and docs/images/launch.mp4 exist | Approval | Reuse the existing video | 2026-11-16 |
| DIST-01 | BACKLOG | agent | none | none | TRUST-01 | Check Homebrew cask rules after a notarized release | 2026-11-16 |
| DIST-02 | BACKLOG | owner | none | Competing CLIs are listed on awesome.ecosyste.ms and similar lists | Owner approval for every submission | Research relevant curated lists | 2026-11-16 |
| MEASURE-01 | IN_PROGRESS | agent | none | Baseline 0/10 queries | Search Console access | Re-run the same 10 queries weekly | 2026-11-16 |
