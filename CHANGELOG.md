<!--
SPDX-License-Identifier: MPL-2.0
SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
-->

# Changelog

All notable changes to `volumod` will be documented in this file.

This file is generated from conventional commits by the
[`changelog-reusable.yml`](https://github.com/hyperpolymath/standards/blob/main/.github/workflows/changelog-reusable.yml)
workflow (`hyperpolymath/standards#206`). Adopt the workflow in this repo's CI to keep this file in sync automatically — see
[`templates/cliff.toml`](https://github.com/hyperpolymath/standards/blob/main/templates/cliff.toml)
for the canonical config.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- feat(ci): enable Hypatia scanning

### Fixed

- fix(codeql): switch language matrix to 'actions' (no JS/TS in repo) (#37)
- fix(codeql): switch language matrix to 'actions' (no JS/TS in repo) (#35)
- fix(licence): clear scaffold-placeholder leak (PLMP sentinel + doubled suffix) (#32)
- fix(ci): sync hypatia-scan.yml to canonical (kill cd-scanner build drift) (#27)
- fix(ci): build Hypatia escript from repo root (estate dogfood drift)
- fix(codeql): switch language matrix to 'actions' (no JS/TS in repo) (#25)
- fix(ci): Phase-2 fleet submission must not fail the security gate (#24)
- fix(ci): hypatia-scan workdir (${{ env.HOME }} resolves empty) (#23)
- fix(ci): rsr-antipattern.yml duplicate heredoc (#21)
- fix(codeql): switch language matrix to 'actions' (no JS/TS in repo) (#22)

### Documentation

- docs: record tech-debt audit findings (2026-05-26) (#43)
- docs: integrate research findings and design decisions into project documentation
- docs: update SCM files with project information
- docs: add SCM checkpoint files
- docs: add checkpoint files for state tracking

### CI

- build(deps): bump github/codeql-action from 4.35.5 to 4.36.0 (#38)
- build(deps): bump actions/upload-artifact from 4.6.2 to 7.0.1 (#30)
- build(deps): bump actions/github-script from 8.0.0 to 9.0.0 (#29)
- build(deps): bump github/codeql-action from 4.32.6 to 4.35.5 (#28)
- build(deps): bump actions/upload-artifact from 4.6.2 to 7.0.1 (#20)

## Pre-history

Prior commits to this file's introduction are recorded in git history but not formally classified into Keep-a-Changelog sections. To backfill, run `git cliff -o CHANGELOG.md` locally using the canonical [`cliff.toml`](https://github.com/hyperpolymath/standards/blob/main/templates/cliff.toml) — this is one-shot mechanical work.

---

<!-- This file was seeded by the 2026-05-26 estate tech-debt audit follow-up (Row-2 Phase 3); see [`hyperpolymath/standards/docs/audits/2026-05-26-estate-documentation-debt.md`](https://github.com/hyperpolymath/standards/blob/main/docs/audits/2026-05-26-estate-documentation-debt.md). -->
