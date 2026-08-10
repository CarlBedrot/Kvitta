# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

**Layout: single-context.** One `CONTEXT.md` at the repo root, ADRs in `docs/adr/`. The repo
holds two deployables (`ios/` in Swift, `backend/` in C#) but one domain — an expense, its
shares and the balance they produce mean the same thing on both sides of the wire, and the
event names are literally shared. Splitting the glossary per language would let the two drift,
which is the exact bug class this project cares most about.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

Note that `docs/expense-app-sync-design.md` is the existing long-form design document and
`docs/how-slice-works.md` the existing narrative overview. They predate `CONTEXT.md` and remain
the authority on the sync protocol; `CONTEXT.md`, once it exists, is the glossary, not a
replacement for them.

## File structure

Single-context repo (most repos):

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

Multi-context repo (presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

The app's user-facing copy is Swedish (`Gör upp`, `Vem är skyldig vem`, `Jag`) while the code is
English. When a term has both, `CONTEXT.md` should carry the pair, so nobody has to guess which
screen `settle-up` refers to.

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
