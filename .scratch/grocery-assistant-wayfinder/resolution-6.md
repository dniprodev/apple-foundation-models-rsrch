## Resolution

Do not spend a separate prototype cycle specifying the Thin Reference Shell in depth. The Reference App is itself the meaningful prototype: its detailed UX and layout should be decided while implementing the real Foundation Models SDK, provider integration, tools, and observable outputs.

The short exploration established this provisional interaction contract:

- The surface feels like a grocery assistant first; architecture is available on demand.
- One active request and its result occupy the primary surface. Earlier runs live elsewhere.
- Demo Household and Model Strategy remain compact, visible request context. Changing either preserves the current result but marks it as belonging to the previous context.
- A Model Run is presented chronologically: request interpretation, model and tool outputs, synthesis, then final answer.
- Concise intermediate output excerpts are visible by default and shown verbatim, with complete observable outputs expandable. The app does not invent reasoning summaries or expose hidden chain-of-thought.
- The final answer is visually dominant, with its evidence attached.
- The narrative timeline explored as variant A is the provisional layout direction.
- Applying proposed cart changes is not required to validate this readability contract. A cart proposal may be displayed as model output; detailed action and approval UX can be decided only if it proves necessary in the Reference App.

The discarded sketch was useful only for reaching these constraints and is not a product deliverable. Visual polish, exact component placement, sheets versus disclosures, Claude setup flow, product-detail navigation, and action mechanics remain implementation-time UX choices informed by the real app.

The domain glossary now names **Model Run** and sharpens **Thin Reference Shell** around readable observable outputs.
