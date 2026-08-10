# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## Notes for this repo

`wontfix` already existed as a GitHub default label; the other four were created for these
skills. The one that carries weight here is **`ready-for-human`** — Kvitta has a standing list
of things no agent can verify: anything needing a physical iPhone (Swish payload, Sign in with
Apple), anything needing a paid Apple Developer account (APNs, TestFlight), and any judgement
call on how the app should *feel*. Label those `ready-for-human` rather than letting an agent
produce plumbing it can never run.
