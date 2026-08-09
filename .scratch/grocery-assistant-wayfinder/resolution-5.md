## Resolution

Do not build a throwaway prototype for this question.

Apple already documents the behavior this ticket was meant to prove: a Dynamic Profile can switch models through model-directed tool calls; baton-pass profiles share one session history; and phone-a-friend creates a short-lived child session with independent history. Reimplementing those mechanics as throwaway code would duplicate the central work of the Reference App.

The Reference App itself will implement and demonstrate both orchestration patterns. Its Model Trace will expose profile transitions and the effective Remote Context View, including that baton-pass shares history and therefore raises a privacy concern when App-Owned Context is visible remotely. The purpose is to research and show the behavior, not to choose an orchestration winner based on privacy.

The governing vocabulary and goal have been updated in `CONTEXT.md`.

Primary sources:

- [What's new in the Foundation Models framework — WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- [Build agentic app experiences with the Foundation Models framework — WWDC26 session 242](https://developer.apple.com/videos/play/wwdc2026/242/)

