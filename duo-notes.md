# iPhone Duo redesign notes
Journey: document launcher (system) -> diagram editor (Code / Preview)
Stack: SwiftUI + UITextView via UIViewRepresentable; iOS 17 target; iOS 27.1 SDK, Xcode 27.1
Stage: 5  Next: try Split View beside another app by hand (each side), then the App Resizability skill in Xcode

Scope note: a focused pass done inside milestone 2, not the full workflow. Only
the Duo HIG page and the checklist were loaded. Stage 3 did not stop for
choices; the agent built its recommendations and the user confirmed them after.

## Findings
- Editor layout: Change — 640pt width breakpoint decided tabs vs split; now size class [HIG, T461]
- Editor two-pane: Change — custom HStack split had no fold handling; now ArrangementView split [HIG, T463]
- Toolbar: Ready — system `toolbar` in DocumentGroup's stack; Templates and Export are Labels with title + symbol, grouped, no fixed spacing [HIG, T462]
- Zoom controls: Ready — stay with the preview pane they affect, inside the safe area [HIG]
- Code/Preview segmented control: Ready — too wide for a side bar, kept in content [T466]
- No UIScreen.main, idiom or orientation checks, no locked orientations [T461]
- Ready: 4; N/A: camera, multiwindow, scene accessories, hinge effects, tab bars, games

## Decisions
- Inner display: recommended split arrangement (code primary, preview secondary); chosen same (agent, confirmed by user, 2026-11-24) — the layout was already a two-pane split
- Outer display: recommended inset, one pane with Code/Preview switch; chosen same (agent, confirmed by user, 2026-11-24) — two panes do not fit compact width
- Split ratio: recommended system default; chosen same (agent, confirmed by user, 2026-11-24) — equal panes when folded come for free
- Table-pose layout: recommended none; chosen none (agent, confirmed by user, 2026-11-24) — optional, and the split already stacks when taller than wide
- Visibility priority for Templates vs Export: pending — only two items, no overflow seen

## Done / verified
- Size-class layout — run on Duo simulator: closed shows one pane, open and half open show two
- ArrangementView split — run: half open gives equal panes with a gap at the fold; keyboard splits around it
- Vertical toolbar on the outer display with Back, Templates, Export — run
- Continuity: text and diagnostics survive fold and unfold — run. Caret, scroll position and undo do not: the code view is rebuilt when the size class changes
- Outer landscape — run: bar moves to the camera side, Back, Templates and Export all stay visible with the keyboard up; only about five lines of code show above the keyboard
- Inner portrait — run: horizontal bars, code stacked above preview; zoom level and text kept through rotation
- Right-to-left — run: found code pushed to the far edge of its pane; fixed with an explicit left-to-right paragraph style and rerun. Panes mirror, the side bar stays put
- Reduce Transparency — run: side bar and zoom controls get a solid background and stay legible
- Split View beside another app — not run: could not start it through simulator automation
- Picture in Picture, App Resizability skill, physical device — not run
