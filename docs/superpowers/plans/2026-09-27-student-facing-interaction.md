# Student-facing interaction implementation plan

> Execution: isolated domains delegated under dispatching-parallel-agents; root integrates and verifies. No commit, deployment or version bump.

**Goal:** Make the whole app operate as a student-facing schedule product, with consistent navigation, a direct voice entry and concise contextual actions.

**Architecture:** Reuse existing account/source/confirmation guards; change presentation and interaction state where required. Shared segmented controls distinguish navigation from multi-selection; single fields open touch-friendly sheets. Media recorder handles gesture/lifecycle cancellation independently from recognition and confirmation.

**Tech Stack:** Flutter, Material primitives with custom interaction components, existing API and recorder/OCR adapters.

- [x] Inventory all routes and page families; record default controls, duplicate prompts and internal concepts.
- [x] Navigation domain: animated mode/range controls; calendar/category/tag filter sheets; preserve list and chart semantics.
- [x] Detail domain: contextual appbar actions, one main task action, concise risk and direct progress/reminder access; simplify item/event/exam/course forms.
- [x] Voice domain: keyboard/hold-to-talk switch, release finish, slide cancel, permission/lifecycle race protection; compact editable recognition result and one send action.
- [x] Root: shared value picker, assistant composer integration, registration and remaining planning/import/operation/settings copy and layout.
- [x] Verify meaningful control/gesture/data-preservation behavior; render actual widgets at normal/large/small/keyboard sizes and inspect images.
- [x] Run full Flutter suite with configured Chinese/Material fonts, analyze, build and verify QA APK. Mark native and effective-speech evidence separately.

Acceptance: no checkmarks for navigation; no automatic microphone access on opening a page; no repeated source/transcript/assistant stages in ordinary voice flow; no grid of equal-weight detail actions; absent facts do not become placeholder rows; safeguards shown only where they affect the pending action. Empty/loading/offline/error and advanced capabilities remain accessible.

Implementation/component verification complete; APK build record in docs/32-面向学生的交互重构.md. Native device/voice validation remains explicitly pending.
