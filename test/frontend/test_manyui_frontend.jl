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
            buffer = ManyUITUI.Buffer(ManyUI.Size(24, 10))
            ManyUITUI.render!(canvas, buffer)
            @test any(c -> c.content != " " || !ManyUI.is_unset(c.style.bg), buffer)
        end
        if name in ("fog", "aurora", "plasma", "rain", "pulse", "mesh")
            @test occursin("tryit_background_canvas", html)
            @test occursin("data-name=\"$name\"", html)
            @test occursin("requestAnimationFrame", html)
        elseif name != "off"
            @test occursin("animation:", html)
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

@testitem "frontend: ManyUI preserves the Tachikoma information architecture" begin
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
        selected = TryIt.create_try(root, TryIt.slug("reference"))
        mkpath(joinpath(selected.path, "src"))
        write(joinpath(selected.path, "Project.toml"), "name = \"Reference\"\n")

        session = TryIt.open_session(root; tachikoma=false)
        ui = TryIt.manyui_selector(session)

        for id in (:main, :left, :search_panel, :folders_panel, :side,
            :disk_panel, :preview_panel, :legend_panel, :footer)
            @test widget_by_id(ui, id) !== nothing
        end

        @test widget_by_id(ui, :preview) isa ManyUI.List
        @test widget_by_id(ui, :legend) isa TryIt.SelectorLegendWidget
        for id in (:delete, :rename, :graduate, :theme, :about, :help)
            @test widget_by_id(ui, id) isa ManyUI.Button
        end

        row = TryIt._manyui_try_label(selected)
        @test occursin(string(selected.date), row)
        @test occursin(selected.name, row)
        @test occursin("(", row)

        preview = widget_by_id(ui, :preview)
        @test any(contains("src"), preview.items)
        @test any(contains("Project.toml"), preview.items)
    end
end

@testitem "frontend: language legends keep their colours in every projection" begin
    using TryIt
    const ManyUI = TryIt.ManyUI
    const ManyUITUI = TryIt.ManyUITUI
    const ManyUIWeb = TryIt.ManyUIWeb

    legend = TryIt.SelectorLegendWidget()
    buffer = ManyUITUI.Buffer(ManyUI.Size(34, 6))
    ManyUITUI.render!(legend, buffer)

    rust = TryIt._manyui_style(TryIt.BADGE_STYLES[:rust])
    julia = TryIt._manyui_style(TryIt.BADGE_STYLES[:julia])
    @test buffer[1, 1].content == string(TryIt.BADGE_GLYPH)
    @test buffer[1, 1].style.fg == rust.fg
    @test buffer[18, 1].content == string(TryIt.BADGE_GLYPH)
    @test buffer[18, 1].style.fg == julia.fg

    html = ManyUIWeb.to_html(legend)
    @test occursin("class=\"tryit-legend-glyph\"", html)
    @test occursin("color: rgb(222,89,63)", html)
    @test occursin("color: rgb(149,88,178)", html)
end

@testitem "frontend: terminal backgrounds use the Tachikoma reference engine" begin
    using TryIt

    for name in ("fog", "mesh", "dotwave", "phylo", "clado")
        effect = TryIt.selector_background_effect(name; intensity=0.4, preset=2)
        @test hasproperty(effect, :background)
        @test effect.background === nothing ||
              TryIt.animation_name(effect.background) == name
    end
end

@testitem "frontend: selector root fills the backend viewport" begin
    using TryIt
    const ManyUI = TryIt.ManyUI

    mktempdir() do dir
        session = TryIt.open_session(
            TryIt.TriesPath(positional=dir); tachikoma=false)
        stop = Ref(false)
        ui = TryIt.manyui_selector(session; animate=true, animation_stop=stop)
        @test ManyUI.measure(ui, ManyUI.Size(180, 50)) == ManyUI.Size(180, 50)

        app = TryIt.ManyUITUI.launch(() -> ui,
            TryIt.ManyUITUI.HeadlessBackend(ManyUI.Size(180, 50));
            stylesheet=TryIt.manyui_selector_stylesheet(), wait=false)
        sleep(0.15)
        @test ManyUI.region(ui) == ManyUI.Region(1, 1, 180, 50)
        @test ui.tick[] > 0
        stop[] = true
        close(app)
        wait(app)
    end
end

@testitem "frontend: terminal palette follows the active Tachikoma theme" begin
    using TryIt
    const ManyUI = TryIt.ManyUI
    import Tachikoma

    original = Tachikoma.theme().name
    try
        @test TryIt.apply_theme!("paper")
        ui = TryIt.manyui_selector(TryIt.open_session(
            TryIt.TriesPath(positional=mktempdir()); tachikoma=false))
        ManyUI.apply_stylesheet!(TryIt.manyui_selector_stylesheet(), ui)

        screen = ManyUI.query_one(ui, "#screen")
        title = ManyUI.query_one(ui, "#search_title")
        help = ManyUI.query_one(ui, "#key_help")
        legend = ManyUI.query_one(ui, "#legend")
        theme = Tachikoma.theme()
        css_color(c) = let rgb = Tachikoma.to_rgb(c)
            ManyUI.rgb(rgb.r, rgb.g, rgb.b)
        end
        @test ManyUI.computed_style(screen).fg == css_color(theme.text)
        @test ManyUI.computed_style(title).fg == css_color(theme.title)
        @test ManyUI.computed_style(help).fg == css_color(theme.text_dim)
        @test ManyUI.computed_style(legend).fg == css_color(theme.text_dim)
    finally
        TryIt.apply_theme!(original)
    end
end

@testitem "frontend: Ctrl-T opens a centered modal theme picker" begin
    using TryIt
    const ManyUI = TryIt.ManyUI
    const ManyUITUI = TryIt.ManyUITUI
    import Tachikoma

    original = Tachikoma.theme().name
    try
        session = TryIt.open_session(
            TryIt.TriesPath(positional=mktempdir()); tachikoma=false)
        ui = TryIt.manyui_selector(session)
        sheet = TryIt.manyui_selector_stylesheet()
        app = ManyUITUI.App(ui, ManyUITUI.HeadlessDriver(ManyUI.Size(80, 30));
            stylesheet=sheet)
        ManyUI.apply_stylesheet!(sheet, ui)
        ManyUI.layout!(ui, ManyUI.Region(1, 1, 80, 30))

        ManyUITUI.handle!(app, ManyUI.key('t'; ctrl=true))
        popup = ManyUI.popup_of(app)
        @test popup !== nothing
        @test popup.placement === ManyUI.PopupPlacement.CENTER
        @test session.mode === :theme
        ManyUITUI.frame!(app)
        expected = ManyUI.popup_region(ManyUI.region(ui), popup.size,
            ManyUI.PopupPlacement.CENTER, ManyUI.Size(80, 30))
        @test ManyUI.region(popup.content) == expected
        @test ManyUI.is_unset(ManyUI.computed_style(popup.content).bg)

        before = Tachikoma.theme().name
        ManyUITUI.handle!(app, ManyUI.key(ManyUI.Key.DOWN))
        @test Tachikoma.theme().name != before
        ManyUITUI.handle!(app, ManyUI.key(ManyUI.Key.ESCAPE))
        @test ManyUI.popup_of(app) === nothing
        @test Tachikoma.theme().name == original
        @test session.mode === :normal
    finally
        TryIt.apply_theme!(original)
    end
end

@testitem "frontend: About and Help open centered modal windows" begin
    using TryIt
    const ManyUI = TryIt.ManyUI
    const ManyUITUI = TryIt.ManyUITUI

    function open_with(key_event)
        session = TryIt.open_session(
            TryIt.TriesPath(positional=mktempdir()); tachikoma=false)
        ui = TryIt.manyui_selector(session)
        sheet = TryIt.manyui_selector_stylesheet()
        app = ManyUITUI.App(ui, ManyUITUI.HeadlessDriver(ManyUI.Size(80, 30));
            stylesheet=sheet)
        ManyUI.apply_stylesheet!(sheet, ui)
        ManyUI.layout!(ui, ManyUI.Region(1, 1, 80, 30))
        ManyUITUI.handle!(app, key_event)
        return app
    end

    about = open_with(ManyUI.key('a'; ctrl=true))
    @test ManyUI.popup_of(about) !== nothing
    @test ManyUI.popup_of(about).placement === ManyUI.PopupPlacement.CENTER
    @test ManyUI.node(ManyUI.popup_of(about).content).id === :about_dialog
    ManyUITUI.frame!(about)
    @test ManyUI.is_unset(
        ManyUI.computed_style(ManyUI.popup_of(about).content).bg)
    filter = ManyUI.query_one(about.root, "#filter")
    ManyUITUI.focus!(about, filter)
    ManyUITUI.handle!(about, ManyUI.key('x'))
    @test isempty(filter.text[])
    @test ManyUI.popup_of(about) !== nothing

    help = open_with(ManyUI.key('?'))
    @test ManyUI.popup_of(help) !== nothing
    @test ManyUI.popup_of(help).placement === ManyUI.PopupPlacement.CENTER
    @test ManyUI.node(ManyUI.popup_of(help).content).id === :help_dialog
    ManyUITUI.frame!(help)
    @test ManyUI.is_unset(
        ManyUI.computed_style(ManyUI.popup_of(help).content).bg)

    native_session = TryIt.open_session(
        TryIt.TriesPath(positional=mktempdir()); tachikoma=false)
    native_ui = TryIt.manyui_selector(native_session)
    @test TryIt.ManyUIWeb.process_native_event!(native_ui,
        (id="tryit_background", event="key", value="ctrl+a"))
    html = TryIt.ManyUIWeb.to_html(native_ui)
    @test occursin("id=\"modal_layer\"", html)
    @test occursin("id=\"native_about_dialog\"", html)
    @test occursin("#modal_layer .modal", html)
    @test occursin("background: transparent !important", html)
    @test TryIt.ManyUIWeb.process_native_event!(native_ui,
        (id="tryit_background", event="key", value="escape"))
    @test !occursin("id=\"modal_layer\"", TryIt.ManyUIWeb.to_html(native_ui))
end

@testitem "frontend: Ctrl-B opens a centered modal animation picker" begin
    using TryIt
    const ManyUI = TryIt.ManyUI
    const ManyUITUI = TryIt.ManyUITUI

    session = TryIt.open_session(
        TryIt.TriesPath(positional=mktempdir()); tachikoma=false)
    ui = TryIt.manyui_selector(session;
        effect=TryIt.selector_background_effect("fog"))
    sheet = TryIt.manyui_selector_stylesheet()
    app = ManyUITUI.App(ui, ManyUITUI.HeadlessDriver(ManyUI.Size(80, 30));
        stylesheet=sheet)
    ManyUI.apply_stylesheet!(sheet, ui)
    ManyUI.layout!(ui, ManyUI.Region(1, 1, 80, 30))

    ManyUITUI.handle!(app, ManyUI.key('b'; ctrl=true))
    popup = ManyUI.popup_of(app)
    @test popup !== nothing
    @test popup.placement === ManyUI.PopupPlacement.CENTER
    @test ManyUI.node(popup.content).id === :animation_dialog
    @test session.mode === :animation
    ManyUITUI.frame!(app)
    @test ManyUI.is_unset(ManyUI.computed_style(popup.content).bg)

    ManyUITUI.handle!(app, ManyUI.key(ManyUI.Key.DOWN))
    @test TryIt.background_name(ui.effect) == TryIt.BACKGROUND_NAMES[2]
    ManyUITUI.handle!(app, ManyUI.key(ManyUI.Key.ESCAPE))
    @test ManyUI.popup_of(app) === nothing
    @test TryIt.background_name(ui.effect) == "fog"
    @test session.mode === :normal
end
