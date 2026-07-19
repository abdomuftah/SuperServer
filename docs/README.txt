SuperServer GitHub Pages website
================================

Repository-ready folder: docs/
Publishing source: main branch /docs folder
Default URL: https://abdomuftah.github.io/SuperServer/

Local preview on macOS
----------------------
From the repository root:

    python3 -m http.server 8080 --directory docs

Then open:

    http://localhost:8080/

Optional custom domain
----------------------
1. Rename docs/CNAME.example to docs/CNAME.
2. Keep superserver.snyt.xyz inside it.
3. Add a DNS CNAME from superserver to abdomuftah.github.io.
4. Configure the same custom domain in GitHub repository Settings > Pages.
5. Enable Enforce HTTPS after GitHub verifies the domain.

The site uses no build tools or external front-end libraries.
The release buttons query the GitHub Releases API and fall back to v3.5.2.
