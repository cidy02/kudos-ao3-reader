# Team scorecard (LOOP-v3)

| Agent | Model | Jobs | Findings accepted | Rejected | Hallucinations | Notes |
|---|---|---|---|---|---|---|
| Codex | gpt-5.6-sol high | 7 | 4 | 2 | 0 | Landed T-310, T-311, T-324 (clean, built first time); tasks 2/3 cut off by quota, Claude finished. Solid SwiftUI; copies artboard rgba literally (dark-only) and over-caps AX text — review both. Sandbox cannot build or commit. |
| Grok | grok-4.7 xhigh | 3 | 11 | 3 | 0 | B2 (queues): 16 findings, 2 real P1s, precise file:line + spec values, all verified; 3 rejected on owner decisions/semantics. Excellent. Don't use --read (it cancels). |
| Gemini 3.1 Pro (High) | gemini-3.1-pro-high | 1 | 0 | 1 | 5 | trial inventory: tabs mapped to wrong views (Home→HomeSectionListView, Library→LibrarySectionListView), WorkDetailView in wrong file, "challenges lack Swift views" (false). Not usable. |
| Gemini 3.8 Flash (High) | gemini-3.8-flash-high | 2 | 2 | 0 | 0 | trial run 2: accurate, specific (5 tabs at ContentView:386; 1ce is a plain confirm by design, CollectionModerationView:105). WINNER. Use without --digest (digest dropped the table). B4 spec digest (non-digest mode) hung past its 30m timeout — killed at 50m. Keep Gemini jobs small. |

Role changes: (none yet)

Inventory built by Claude instead (INVENTORY.md).

Role changes: Gemini = gemini-3.8-flash-high (trial winner, 2026-09-29 13:25).

2026-09-29 15:17: Grok OUT — B7 run hit HTTP 402 "Grok Build usage balance exhausted" after 89 turns ($2.36), no findings. Codex out until 17:27. Claude carries B7 (and B6/B8) until Codex returns.

2026-09-29 20:05: owner reminder — agy also serves Claude Sonnet 4.6, Claude Opus 4.6 (Thinking) and GPT-OSS 120B
(`agy-delegate -m <name>`; `agy models`). Roster while Codex is out (until 22:29): agy claude-opus-4-6-thinking
takes implementation tasks in accept-edits mode (edit-only; Claude builds, screenshots, commits);
GPT-OSS only for tiny, fully specified edits. Task 5 (fixtures + B6/B8 form/failure fixes) → agy Opus, 20:05.
| agy claude-opus-4-6 | accept-edits | 1 | fixtures good (10 parseable pages); partial | 0 | 0 | Quota exhausted ~20 min into task 5 (resets ~01:10). Output built first time. Skipped the header-padding and failure-page parts of the brief. |
