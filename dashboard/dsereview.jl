#= 
=#
using Pkg
Pkg.activate(joinpath(pwd(), "dashboard"))
Pkg.resolve()
Pkg.instantiate()

DASHBOARD_VERSION = "0.1.0"

using Dash
using HmtDashUtils
using CitableBase
using CitableText
using CitableCorpus
using CitableObject
using CitableImage
using CitablePhysicalText
using HmtArchive, HmtArchive.Analysis
THUMBHEIGHT = 200
TEXTHEIGHT = 600

function loaddata()
    src = hmt_cex()
    dse = hmt_dse(src)[1]
    normed = hmt_normalized(src)
    textcat  = hmt_textcatalog(src)
    info = hmt_releaseinfo(src)

    (dse, normed, textcat, info)
end
(dsec, corpus, catalog, release) = loaddata()


function surfacemenu(triples, mschoice)
    menupairs = []
    mstriples = filter(tr -> collectionid(tr.surface) == mschoice, triples)
    mssurfaces = map(tr -> tr.surface, mstriples)
    uniquesurfs =  mssurfaces .|> string |> unique .|> Cite2Urn
    for surf in uniquesurfs
        lbl = objectcomponent(surf)
        push!(menupairs, (label=lbl, value=string(surf)))
    end
    menupairs
end


function msmenu(triples)
    menupairs = []
    sigla = map(tr -> collectionid(tr.surface), triples)  |> unique
    for siglum in sigla
        push!(menupairs, (label=siglum, value=siglum))
    end
    menupairs
end

function textsmenu(pg, triples)
    surftriples = filter(tr -> tr.surface == pg, triples)
    surfpsgs = map(tr -> droppassage(tr.passage), surftriples) .|>  string |> unique .|> CtsUrn
    opts =  [(label = workcomponent(dropversion(i)), value = string(i)) for i in surfpsgs]
    @debug("Found $(length(opts)) text options for $(pg)")
    opts
end
assetfolder = joinpath(pwd(), "dashboard", "assets")
app = dash(assets_folder = assetfolder, include_assets_files=true)

app.layout = html_div(className = "w3-container") do
    html_div(className = "w3-container w3-light-gray w3-cell w3-mobile w3-border-left  w3-border-right w3-border-gray", children = [dcc_markdown("*Dashboard version*: **$(DASHBOARD_VERSION)**")]),
    
    html_h1("HMT project: DSE verification dashboard"),
    dcc_markdown("Validate and verify content of **$(release)**."),
   
    html_div(className = "w3-container",
        children = [
       
            html_div(className = "w3-col l4 m4 s12",
                children = [
                dcc_markdown("*Choose a manuscript*:"),
                dcc_dropdown(id = "mschoice",
                    options=msmenu(dsec.data))
                ]
                ),             

        html_div(className = "w3-col l4 m4 s12",
        children = [
            dcc_markdown("*Choose a surface*:"),
            dcc_dropdown(id = "surfacepicker")
        ]),
      
        ]
    ),
    html_div(className = "w3-container",
        children = [
            dcc_markdown("*Texts to verify*:")
            dcc_checklist(
                id = "texts",
                labelStyle = Dict("display" => "inline-block")
            )
        ]
    ),
       

    html_div(id="dsecompleteness", className="w3-container"),
    html_div(id="dseaccuracy", className="w3-container")#,

end


# Construct menu of pages for selected MS.
callback!(app,
    Output("surfacepicker", "options"),
    Input("mschoice", "value"),
    prevent_initial_call=true
) do siglum
    surfacemenu(dsec.data, siglum)
end

"""Compose markdown string for DSE coverage block."""
function hmtdsecoverage(triples::Vector{DSETriple}, pg::Cite2Urn, height = 200, textlist = [])
    surfacetriples = filter(row -> urncontains(pg, row.surface), triples)
    iliadtriples = filter(row -> urncontains(CtsUrn("urn:cts:greekLit:tlg0012.tlg001:"), row.passage), surfacetriples)
    iliadrange = isempty(iliadtriples) ? "(No *Iliad* text on $(pg).)" : "Covers *Iliad* $(iliadtriples[1].passage |> passagecomponent)-$(iliadtriples[end].passage |> passagecomponent)."

    isempty(textlist) ? verificationlink = md_dseoverview(pg, triples, ht = height) :
    verificationlink = md_dseoverview(pg, triples, ht = height, textfilter = textlist)

    textmsg = "$(textlist)"
    hdr = "## Visualizations for verification: page *$(objectcomponent(pg))*\n\nTexts included: *$(textmsg)*\n\n### Completeness\n\n$(iliadrange)\n\nThe image is linked to the HMT Image Citation Tool where you can verify the completeness of DSE indexing.\n\n"

    hdr * verificationlink
end


"""Compose markdown string for DSE accuracy block."""
function hmtdseaccuracy(pg::Cite2Urn, c::CitableTextCorpus, cat::TextCatalogCollection, triples::Vector{DSETriple}, textlist = [])
    surftriples = filter(tr -> tr.surface == pg, triples)
    surfpsgs = map(tr -> tr.passage, surftriples)

    if isempty(textlist)
        md_textpassages(surfpsgs, c, cat, triples = triples, mode = "illustratedtext")
    else
        filtered = []
        for ref in textlist
            push!(filtered, filter(u -> urncontains(ref, u), surfpsgs))
        end
        surfacefiltered = filtered |> Iterators.flatten |> collect
        @debug("surfacefiltered: $(surfacefiltered)")
        md_textpassages(surfacefiltered, c, cat, triples = triples, mode = "illustratedtext")
    end
end


# Set choices of checkboxes for texts to include in overlay:
callback!(app,
    Output("texts", "options"),
    Input("surfacepicker", "value")
) do pg
    isnothing(pg) ? [] : textsmenu(Cite2Urn(pg), dsec.data)
end

# Update validation/verification sections of page when surface is selected:
callback!(
    app,
    Output("dsecompleteness", "children"),
    Output("dseaccuracy", "children"),

    Input("surfacepicker", "value"),
    Input("texts", "value")
    
) do newsurface, txt_choice
    if isnothing(newsurface) || isempty(newsurface)
        (dcc_markdown(""), dcc_markdown(""))#, dcc_markdown(""))
    else
        surfurn = Cite2Urn(newsurface)
        txturns = isnothing(txt_choice) ? [] : txt_choice .|> CtsUrn
        completeness = hmtdsecoverage(dsec.data, surfurn, THUMBHEIGHT, txturns) |> dcc_markdown
       

        accuracyhdr = "## Verify accuracy of indexing\n*Check that the diplomatic reading and the indexed image correspond.*\n\n"
       
        accuracy =   accuracyhdr * hmtdseaccuracy(surfurn, corpus, catalog, dsec.data, txturns) |> dcc_markdown
        
        (completeness, accuracy)
    end
end


run_server(app, "0.0.0.0", 8051, debug=true)