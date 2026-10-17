# Site checks on the Mac

Studio #469 reserves hosted Actions for the Echappee Windows Steam executable.
Site review uses the shared Studio workflow and filters changes to site sources.
Pages deployment is manual and requires an isolated Mac executor.

The workflow is prepared, not active. Studio currently denies cross-repository
workflow access. No isolated Mac runner is provisioned by this PR. Both the
`studio-isolated` runner label and `STUDIO_ISOLATED_MAC_ENABLED=true` are
required before executing any job. The shared Mac host must not be registered.
No repository settings are changed by this PR.

Run `bin/studio-site-review /path/to/this/checkout` from a checkout of Studio
on the Mac to execute the same read-only generation and SEO checks locally.
No page content, availability claim, app code, or store metadata changes here.
This PR does not deploy the site.
