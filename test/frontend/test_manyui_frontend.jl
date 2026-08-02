@testitem "frontend: names resolve to explicit selector frontends" begin
    using TryIt

    @test TryIt.selector_frontend("tachikoma") isa TryIt.TachikomaFrontend
    @test TryIt.selector_frontend("tui") isa TryIt.ManyUITUIFrontend

    native = TryIt.selector_frontend("webnative"; port=8123)
    @test native isa TryIt.WebNativeFrontend
    @test native.port == 8123

    webtui = TryIt.selector_frontend("webtui"; port=8124)
    @test webtui isa TryIt.WebTUIFrontend
    @test webtui.port == 8124

    @test TryIt.frontend_name(native) == "webnative"
    @test TryIt.frontend_name(webtui) == "webtui"
    @test TryIt.requires_terminal(TryIt.ManyUITUIFrontend())
    @test !TryIt.requires_terminal(native)
    @test_throws ArgumentError TryIt.selector_frontend("unknown")
    @test_throws ArgumentError TryIt.selector_frontend("webnative"; port=0)
end

@testitem "frontend: environment selects frontend and web port" begin
    using TryIt

    env = Dict("TRY_FRONTEND" => "webtui", "TRY_WEB_PORT" => "9123")
    frontend = TryIt.configured_selector_frontend(env)
    @test frontend isa TryIt.WebTUIFrontend
    @test frontend.port == 9123
    @test TryIt.configured_background_preset(
        Dict("TRY_BACKGROUND_PRESET" => "3")) == 3

    @test TryIt.configured_selector_frontend(Dict{String, String}()) isa
          TryIt.ManyUITUIFrontend
    @test_throws ArgumentError TryIt.configured_selector_frontend(
        Dict("TRY_FRONTEND" => "webnative", "TRY_WEB_PORT" => "not-a-port"))
end

@testitem "frontend: every TryIt background projects through ManyUI" begin
    using TryIt
    const ManyUI = TryIt.ManyUI
    const ManyUITUI = TryIt.ManyUITUI
    const ManyUIWeb = TryIt.ManyUIWeb

    names = ["fog", "aurora", "plasma", "rain", "pulse", "mesh",
        "dotwave", "phylo", "clado", "off"]
    for name in names
        effect = TryIt.selector_background_effect(name; intensity=0.4, preset=2)
        canvas = TryIt.SelectorBackgroundWidget(
            ManyUI.Container(ManyUI.Label("content")); effect=effect)

        @test TryIt.background_name(effect) == name
        html = ManyUIWeb.to_html(canvas)
        @test occursin("tryit-background--$name", html)

        if name != "off"
            @test occursin("animation:", html)
            buffer = ManyUITUI.Buffer(ManyUI.Size(24, 10))
            ManyUITUI.render!(canvas, buffer)
            @test any(c -> c.content != " " || !ManyUI.is_unset(c.style.bg), buffer)
        end
    end
end

@testitem "frontend: legacy glyph backgrounds tolerate shared intensity" begin
    using TryIt
    using Tachikoma

    backgrounds = (DotWaveBackground(), PhyloTreeBackground(),
        CladogramBackground())
    for background in backgrounds
        @test TryIt.with_intensity(background, 0.4) === background
    end
end

@testitem "frontend: one ManyUI tree drives selector state" begin
    using TryIt
    const ManyUI = TryIt.ManyUI

    function widget_by_id(w, id)
        ManyUI.node(w).id === id && return w
        for child in ManyUI.children(w)
            found = widget_by_id(child, id)
            found === nothing || return found
        end
        return nothing
    end

    mktempdir() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        TryIt.create_try(root, TryIt.slug("beta"))
        session = TryIt.open_session(root; tachikoma=false)
        @test session.background === nothing
        ui = TryIt.manyui_selector(session)

        @test ui isa ManyUI.Widget
        filter_box = widget_by_id(ui, :filter)
        folders = widget_by_id(ui, :folders)
        status = widget_by_id(ui, :status)
        open_button = widget_by_id(ui, :open)

        @test filter_box isa ManyUI.TextInput
        @test folders isa ManyUI.List
        @test length(folders.items) == 2

        filter_box.text[] = "alp"
        filter_box.on_change(filter_box)
        @test session.filter == "alp"
        @test length(session.visible) == 1
        @test length(folders.items) == 1
        @test folders.items[1].slug.value == "alpha"
        @test occursin("1 try", status.text[])

        open_button.on_click(open_button)
        @test session.done
        @test session.exit_action === :cd
        @test session.exit_path == folders.items[1].path
    end
end
