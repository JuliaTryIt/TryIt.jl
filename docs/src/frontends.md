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
the portable selection data and the resolved reference effect. It contains no
terminal cell or HTML node. `SelectorBackgroundWidget` projects that same
value below the selector content:

- ManyUITUI and WebTUI call the Tachikoma reference renderer and translate its
  cells into ManyUI cells;
- WebNative paints color effects into a full-viewport canvas on the same
  logical cell grid, using the current Tachikoma palette and effect parameters;
- glyph effects use a lightweight CSS projection until the generic ManyUI
  effects engine can expose vector primitives to WebNative;
- a future Dear ImGui target can translate it to a draw list.

Every configured TryIt effect is accepted by all current projections:
`fog`, `aurora`, `plasma`, `rain`, `pulse`, `mesh`, `dotwave`, `phylo`,
`clado`, and `off`.

The selector root always accepts the complete backend viewport. TUI and
WebTUI therefore resize beyond their former 80x24 intrinsic area, and the
animation starts only after the application is actually open.

The project-language legend is also backend-neutral. Its badge symbols retain
the reference palette in terminal cells and are projected as coloured DOM
spans by WebNative, while labels follow the active theme's dim text colour.

## Themes and modal windows

The terminal stylesheet is rebuilt from the active Tachikoma palette. Text,
dimmed shortcuts, titles, and borders therefore keep the same contrast as the
reference selector. Modal surfaces are transparent in TUI, WebTUI, and
WebNative, allowing the animated background to remain visible through them.

`Ctrl+T` opens the theme picker and `Ctrl+B` opens the animation picker.
Moving with `↑`/`↓` previews the highlighted choice, `Enter` keeps it, and
`Esc` restores the value active before the picker opened. `Ctrl+A` About and
`?` Help are also centered modal windows. TUI and WebTUI use ManyUI's centered
popup layer; WebNative projects the same application state as a fixed centered
DOM overlay.

## Migration scope

The ManyUI selector covers filter, select, open, create, preview, refresh,
delete, rename, graduate, theme/animation selection, help, about, and quit.
The legacy Tachikoma frontend remains available as the visual and behavioural
reference while the shared effects protocol is extracted into ManyUI. It is
not the default application path.
