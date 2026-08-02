# Upstream bugs

## ManyUIWeb 0.1 WebNative handle has no `isopen`

`ManyUITUI.launch(...; wait=false)` documents a common handle contract of
`isopen`, `close`, and `wait`. `ManyUIWeb.WebNativeServer` currently implements
`close` and `wait`, but calling `isopen(server)` raises a `MethodError`.

TryIt keeps a private `_selector_handle_isopen` adapter at its frontend
boundary. Once ManyUIWeb implements `Base.isopen(::WebNativeServer)`, this shim
can be removed.
