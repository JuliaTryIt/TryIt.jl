# ManyUI frontends

TryIt's selector is a single high-level ManyUI application. The widget tree
owns filtering, selection, creation, refresh, and quit actions; choosing a
target changes only how that tree is projected.

| `TRY_FRONTEND` | Projection | Description |
|:---------------|:-----------|:------------|
| `tui` | ManyUITUI | Local terminal; the default. |
| `webnative` | ManyUI WebNative | Native browser inputs, buttons, and lists. |
| `webtui` | ManyUI WebTUI | Terminal cells transported to a browser. |
| `tachikoma` | Legacy selector | Temporary compatibility path during migration. |

Web targets listen on port `8000` by default. Override it with
`TRY_WEB_PORT`:

```sh
TRY_FRONTEND=webnative TRY_WEB_PORT=8080 tryit
TRY_FRONTEND=webtui    TRY_WEB_PORT=8081 tryit
```

Unlike the terminal projections, both web projections can start without a TTY
on stdin. Selecting or creating a try stops the server before TryIt emits its
shell `cd` command.

## Programmatic launch

Embedding code can select a frontend without mutating the process environment:

```julia
using TryIt

session = launch_selector(frontend=:webnative, port=8080)
session.exit_action
session.exit_path
```

`launch_selector` also accepts a concrete `SelectorFrontend`. This small seam
is the intended extension point for another ManyUI target such as Dear ImGui.
The application model must stay unchanged when a target is added.

## Background effects

Backgrounds are represented by `SelectorBackgroundEffect`, which contains
only a name, intensity, and preset. It contains no terminal cell, HTML node,
or renderer-specific color type. `SelectorBackgroundWidget` projects that
same value below the selector content:

- ManyUITUI and WebTUI paint terminal cells;
- WebNative emits animated CSS backgrounds;
- a future Dear ImGui target can translate it to a draw list.

Every configured TryIt effect is accepted by all current projections:
`fog`, `aurora`, `plasma`, `rain`, `pulse`, `mesh`, `dotwave`, `phylo`,
`clado`, and `off`. The projections preserve the effect's visual identity,
although a cell animation and a CSS animation are not pixel-identical.

## Migration scope

The ManyUI selector currently covers the primary workflow: filter, select,
open, create, refresh, and quit. The legacy Tachikoma frontend remains
available while advanced overlays and maintenance actions are moved to
backend-neutral ManyUI widgets. It is not the default application path.
