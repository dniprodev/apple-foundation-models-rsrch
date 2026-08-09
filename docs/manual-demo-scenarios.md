# Manual Demo Scenarios

The Reference App exposes these scenarios in the **Manual Demo Scenarios** section. Each button selects the fictional household, request, Model Strategy, and Orchestration Pattern needed for the run. After running one, expand **Model Run** and **Model Trace** to inspect observable output, tools, transitions, timing, errors, and any Remote Context View.

These scenarios are acceptance evidence, not model-quality benchmarks. Do not judge them by exact generated wording or a numeric score.

## Prerequisites

- Build and launch the Reference App in an eligible Foundation Models environment for local-only runs.
- Use the bundled fictional households; no personal data is needed.
- For the opt-in live Claude smoke path, use Xcode 27 and an iOS 27 simulator or device, enter a developer Anthropic API key in the Model Strategy section, and choose **Save credential**. The app reads it from Keychain only when constructing `ClaudeLanguageModel`; it is never shown in a Model Run or Model Trace.
- Select Hybrid and run **Hybrid healthier substitutions** for the shared dynamic-profile path or **Pantry-aware planning** for the isolated child-session path. Remove the credential after the smoke run.
- Without a credential, use **Missing Claude setup** to verify the visible setup path. With an invalid credential saved, **Provider failure** verifies the generic safe provider-failure path.

## Scenarios

| Scenario | Run and inspect |
| --- | --- |
| Private purchase analysis | Run **Private purchase analysis**. Confirm the selected household is `Budget Family`, the strategy is local-only, and the trace has no Remote Context View. Inspect the household purchase history and catalog evidence. |
| Hybrid healthier substitutions | Run **Hybrid healthier substitutions** with a credential. Confirm the hybrid strategy and inspect the disclosed remote context, tools, privacy concerns, and provider events. |
| Pantry-aware planning | Run **Pantry-aware planning** with a credential. Confirm the phone-a-friend pattern, isolated child session, bounded Remote Task, and local parent final-answer ownership. |
| Cart review and approval | Run **Cart review and approval**. Inspect the proposed cart and verify the household cart is unchanged. Choose **Decline** or **Approve cart changes** explicitly, then inspect the resulting local state. |
| Cross-household personalization | Run **Cross-household personalization**, then switch households and run it again. Compare the household IDs, restrictions, priorities, and evidence shown in each Model Trace; exact answer wording is intentionally not compared. |
| Baton-pass disclosure | Run **Baton-pass disclosure** with a credential. Inspect shared history, the remote session, profile transition, and Claude final-answer ownership. |
| Phone-a-friend disclosure | Run **Phone-a-friend disclosure** with a credential. Inspect the isolated child session, narrower Remote Context View, and local parent final-answer ownership. |
| Missing Claude setup | Remove the credential, run **Missing Claude setup**, and confirm a generic setup message with a safe `claude-not-configured` trace error. |
| Provider failure | Save a credential, run **Provider failure**, and confirm a generic unavailable-provider message with safe trace facts and no credential material. |

Every hybrid scenario should expose the exact semantic Remote Context View for the invocation. Local-only runs should show that no remote transport or remote context was created.
