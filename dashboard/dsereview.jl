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

assetfolder = joinpath(pwd(), "dashboard", "assets")
app = dash(assets_folder = assetfolder, include_assets_files=true)

app.layout = html_div(className = "w3-container") do
    html_div(className = "w3-container w3-light-gray w3-cell w3-mobile w3-border-left  w3-border-right w3-border-gray", children = [dcc_markdown("*Dashboard version*: **$(DASHBOARD_VERSION)** ([version notes](https://homermultitext.github.io/dashboards/alpha-search/))")]),
    
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
      
        html_div(className = "w3-col l4 m4 s12",
        children = [
            dcc_markdown("*Texts to verify*:")
            dcc_dropdown(
                id = "texts",
                options = [
                    (label = "All texts", value = "all"),
                    (label = "Iliad only", value = "Iliad"),
                    (label = "scholia only", value = "scholia")
                ],
                value = "all",
                clearable=false
            )
        ]),
       
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



function hmtdse(triples, surf, ht, textfilter)
    baseurl = "https://www.homermultitext.org/iipsrv"
	root = "/project/homer/pyramidal/deepzoom"
	
    iiif =  IIIFservice(baseurl, root)
    ict =  "https://www.homermultitext.org/ict2/?"


    surfacetriples = filter(row -> urncontains(surf, row.surface), triples)
    iliadtriples = filter(row -> urncontains(CtsUrn("urn:cts:greekLit:tlg0012.tlg001:"), row.passage), surfacetriples)
    iliadrange = "Includes *Iliad* $(iliadtriples[1].passage |> passagecomponent)-$(iliadtriples[end].passage |> passagecomponent)."

    
    textsurfacetriples = surfacetriples
    if textfilter == "Iliad"
        textsurfacetriples = iliadtriples
    elseif textfilter == "scholia"
        textsurfacetriples = filter(row -> urncontains(CtsUrn("urn:cts:greekLit:tlg5026:"), row.passage), surfacetriples)
    end
    images = map(tr -> tr.image, textsurfacetriples)
    ictlink = ict * "urn=" * join(images, "&urn=")
    imgmd = markdownImage(dropsubref(images[1]), iiif; ht = ht)
    verificationlink = string("[", imgmd, "](", ictlink, ")")

    

    hdr = "## Visualizations for verification: page *$(objectcomponent(surf))*; texts included: *$(textfilter)*\n\n### Completeness\n\n$(iliadrange)\n\nThe image is linked to the HMT Image Citation Tool where you can verify the completeness of DSE indexing.\n\n"

    hdr * verificationlink
    

end

function hmtdseaccuracy(pg::Cite2Urn, c::CitableTextCorpus, cat::TextCatalogCollection, triples::Vector{DSETriple})
    surftriples = filter(tr -> tr.surface == pg, triples)
    surfpsgs = map(tr -> tr.passage, surftriples)
    md_textpassages(surfpsgs, c, cat, triples = triples, mode = "illustratedtext")
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
        completeness = dcc_markdown(hmtdse(dsec.data, surfurn, THUMBHEIGHT, txt_choice))
       

        accuracyhdr = "### Verify accuracy of indexing\n*Check that the diplomatic reading and the indexed image correspond.*\n\n"
       
        accuracy =   hmtdseaccuracy(surfurn, corpus, catalog, dsec.data) |> dcc_markdown
        
        #dcc_markdown(md_textpassages(sampleurns, corpus, catalog, triples = dse, mode = "illustratedtext"))
        # dcc_markdown("### Accuracy\n\n" * )
        #hmtdseaccuracy(dsec.data,surfurn, TEXTHEIGHT, txt_choice) |> dcc_markdown
      
        (completeness, accuracy)
    end
end


run_server(app, "0.0.0.0", 8051, debug=true)