# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This repo is **single-context**: one `CONTEXT.md` and one `docs/adr/` at the root.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — the glossary and domain overview.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If either doesn't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved. As of this file's writing, neither exists yet.

## File structure

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-....md
│   └── 0002-....md
└── lib/
```

## Relationship to `doc/`

`doc/` is this repo's canonical **prose** documentation tree (architecture, integration, operations, reference) — see the root `CLAUDE.md`. `CONTEXT.md` and `docs/adr/` are the machine-read domain layer the skills consult, and are additive to `doc/`, not a replacement. The deep architectural narrative already lives in `doc/architecture/HYBRID_ARCHITECTURE.en.md` and `doc/architecture/MAINTAINER_ARCHITECTURE.en.md`; read those too when the topic is the hybrid binary-replacement / platform-path split.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
