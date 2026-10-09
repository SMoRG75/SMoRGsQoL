# Releasing SMoRG's QoL

Pushing a tag that starts with `v` (for example `v1.2.0`) runs
`.github/workflows/release.yml`. It builds `SMoRGsQoL-v1.2.0.zip` with the
[BigWigs packager](https://github.com/BigWigsMods/packager) and uploads it to
CurseForge, Wago Addons, WoWInterface and GitHub Releases. WowUp and other
addon managers install from those sites.

`.pkgmeta` controls what goes in the zip: everything except `tests/`, `output/`,
`TODO.md`, this file and dotfiles (`.github`, `.claude`, `.luarc.json`, ...).

## One-time setup

The tokens below are added as repository secrets on GitHub:
**Settings → Secrets and variables → Actions → New repository secret**.
A site without its secret (or without its ID in the TOC) is simply skipped, so
you can set the sites up one at a time.

| Secret | Where to get it |
| --- | --- |
| `CF_API_KEY` | CurseForge [API tokens](https://authors.curseforge.com/#/settings/api-tokens) |
| `WAGO_API_TOKEN` | Wago Addons [API keys](https://addons.wago.io/account/apikeys) |
| `WOWI_API_TOKEN` | WoWInterface [API tokens](https://www.wowinterface.com/downloads/filecpl.php?action=apitokens) |

GitHub Releases needs no secret; the workflow uses the built-in `GITHUB_TOKEN`.

### CurseForge

Nothing more to do: the project ID is already in the TOC
(`## X-Curse-Project-ID: 1418599`).

### Wago Addons

1. Sign in at [addons.wago.io](https://addons.wago.io) and create a new project
   for SMoRG's QoL from the developer dashboard.
2. Copy the project ID from the dashboard (a short code such as `he54k6bL`) into
   the TOC: `## X-Wago-ID: he54k6bL`.

### WoWInterface

1. Create an account at [wowinterface.com](https://www.wowinterface.com) and
   upload the current release zip by hand once. This creates the addon page;
   WoWInterface may need to approve it first.
2. The addon ID is the number in the page URL, e.g. `12345` in
   `wowinterface.com/downloads/info12345-SMoRGsQoL.html`. Put it in the TOC:
   `## X-WoWI-ID: 12345`.

WoWInterface has no WoW Forever category, so it only gets the Retail version.

## Cutting a release

1. Bump `## Version:` in `SMoRGsQoL.toc` and date the new section in
   `CHANGELOG.md`. Commit.
2. Tag and push the tag:

   ```bash
   git tag v1.2.0
   git push origin v1.2.0
   ```

3. Follow the run on the repository's **Actions** tab.

Tags containing `alpha` or `beta` (e.g. `v1.2.0-beta1`) are uploaded as alpha or
beta files instead of releases.

The game versions come from `## Interface: 120100, 16001`: `120100` is Retail
12.1.0 and `16001` is WoW Forever. The whole `CHANGELOG.md` is uploaded as the
release notes.

## Testing the package locally

Git Bash can run the packager without uploading anything (`-d`); it needs a
`zip` command on the PATH. The package is written to `.release/` (git-ignored as
a dotfolder):

```bash
curl -sSLO https://raw.githubusercontent.com/BigWigsMods/packager/v2/release.sh
bash release.sh -d
```
