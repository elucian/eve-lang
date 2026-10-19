# eveux: the design folder

The design of eveux (the Eve native workbench) is [../README.md](../README.md). This folder holds what belongs to the design and is not code:

| Path | What |
|---|---|
| `gen_svg.py` | writes the 16 SVG drawings; run `python eveux/design/gen_svg.py` from the repository root after a change (or edit an SVG by hand) |
| `design*.svg` | the drawings, 1400 × 860: main window, debug, Markdown, HTML, image, media, database, SQL, structure dialog, source control, deploy, new file, menus, dialogs, architecture; the list with what each shows is section 3 of the README |
| `notes/design-ideas.md` | the notes of the author (two tiers, deploy flow, eve as the server, the backends); not edited by the model |
| `notes/elaboration.md` | the notes checked against the plan: source control, deploy with manifest and versions, the machine messages, the backends, ten questions (written for the browser design; the server side stands) |
| `notes/dvui.md` | dvui in detail, the comparison with the browser design, the spike; corrected on 2026-10-18 after reading the source of v0.5.0 |

The drawings use the colors of the evetx drawings (`evetx/design/`), so the two tools show one theme. A drawing is a plan for review, not a screenshot: nothing is built yet.
