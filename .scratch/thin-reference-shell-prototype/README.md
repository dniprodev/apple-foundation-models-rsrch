# Thin Reference Shell — throwaway prototype

This prototype compares three ways to make one model run readable on an iPhone-sized surface:

- `A` — narrative timeline
- `B` — compact execution ledger
- `C` — focused step reader

All variants use the same chronological, verbatim run data. The final answer is visually dominant and complete observable outputs are expandable.

Run from the repository root:

```sh
python3 -m http.server 8080 --directory .scratch/thin-reference-shell-prototype
```

Then open <http://localhost:8080/?variant=A>. Use the floating switcher or left/right arrow keys to compare variants.

This is deliberately throwaway UI. It does not call models, persist state, or apply cart changes.
