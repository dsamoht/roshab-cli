//
// Validate the parameters and read the sample sheet
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN   } from '../../nf-core/utils_nfschema_plugin'
include { samplesheetToList       } from 'plugin/nf-schema'
include { UTILS_NFCORE_PIPELINE   } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE } from '../../nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    input             //  string: Path to input samplesheet
    help              // boolean: Display help message and exit
    help_full         // boolean: Show the full help message
    show_hidden       // boolean: Show hidden parameters in the help message

    main:

    ch_versions = channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    def before_text = """
                _           _                _ _
  _ __ ___  ___| |__   __ _| |__         ___| (_)
 | '__/ _ \\/ __| '_ \\ / _` | '_ \\ _____ / __| | |
 | | | (_) \\__ \\ | | | (_| | |_) |_____| (__| | |
 |_|  \\___/|___/_| |_|\\__,_|_.__/       \\___|_|_|

 Taxonomic classification and evaluation of cyanotoxin biosynthesis
 potential from nanopore reads.
"""
    def after_text = ""

    if (monochrome_logs) {
        before_text = before_text.replaceAll(/\033\[[0-9;]*m/, '')
        after_text = after_text.replaceAll(/\033\[[0-9;]*m/, '')
    }

    def command = "nextflow run ${workflow.manifest.name} -profile <docker/singularity/.../institute> --input samplesheet.csv --outdir <OUTDIR> --kraken_db <PATH> --genomes_db <PATH> --genes_db <PATH>"

    UTILS_NFSCHEMA_PLUGIN (
        workflow,
        validate_params,
        null,
        help,
        help_full,
        show_hidden,
        before_text,
        after_text,
        command,
        false
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )

    //
    // Custom validation for pipeline parameters
    //
    validateInputParameters()

    //
    // Create channel from input file provided through params.input
    //
    channel
        .fromList(samplesheetToList(input, "${projectDir}/assets/schema_input.json"))
        .set { ch_samplesheet }

    emit:
    samplesheet = ch_samplesheet
    versions    = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Check and validate pipeline parameters that the JSON schema cannot express on
// its own, because they depend on the value of another parameter.
//
def validateInputParameters() {
    // Checked here as well as in the schema: without it Nextflow would silently publish
    // into its default `results/` directory when `--validate_params false` is used.
    if (!params.outdir) {
        error("`--outdir` is required: it is the only directory results are ever written to.")
    }
    if (params.mode in ['assembly', 'both']) {
        if (!params.antismash_db) {
            error("`--antismash_db` is required by `--mode ${params.mode}`. Build the databases with `download-antismash-databases`.")
        }
        if (params.run_deepbgc && !params.deepbgc_db) {
            error("`--run_deepbgc` requires `--deepbgc_db`.")
        }
        if (params.run_bigscape && !params.pfam_db) {
            error("`--run_bigscape` requires `--pfam_db` pointing at `Pfam-A.hmm`.")
        }
        if (params.assembler == 'metamdbg' && params.polish.toString().toBoolean()) {
            error("`--polish` cannot be used with `--assembler metamdbg`: metaMDBG polishes internally, so Medaka is never run on its assemblies.")
        }
    }
    else {
        if (params.run_deepbgc || params.run_bigscape || params.coassemble_by_group) {
            log.warn("`--run_deepbgc`, `--run_bigscape` and `--coassemble_by_group` only apply to the assembly route and are ignored with `--mode ${params.mode}`.")
        }
    }
}

//
// Whether Medaka polishing runs: off unless `--polish` is given, and only ever
// with `flye` — `metamdbg` polishes internally, so Medaka is never run on its
// assemblies.
//
def runMedakaPolishing() {
    return params.assembler == 'flye' && params.polish.toString().toBoolean()
}

//
// Generate methods description for MultiQC
//
def toolCitationText() {
    def citations = [
        "Tools used in the workflow included:",
        params.skip_qc ? "" : (params.skip_nanoplot ? "" : "NanoPlot (De Coster et al. 2018),"),
        params.skip_qc ? "" : "Chopper (De Coster and Rademakers 2023),",
        "SeqKit (Shen et al. 2016),",
        "Kraken2 (Wood et al. 2019),",
        "Bracken (Lu et al. 2017),",
        "KrakenTools (Lu et al. 2022),",
        "CoverM (Woodcroft and Newell),",
        params.mode in ['reads', 'both'] ? "DIAMOND (Buchfink et al. 2021)," : "",
        params.mode in ['assembly', 'both'] ? (params.assembler == 'metamdbg' ? "metaMDBG (Benoit et al. 2024)," : "metaFlye (Kolmogorov et al. 2020),") : "",
        params.mode in ['assembly', 'both'] && runMedakaPolishing() ? "Medaka (Oxford Nanopore Technologies)," : "",
        params.mode in ['assembly', 'both'] ? "Pyrodigal (Larralde 2022)," : "",
        params.mode in ['assembly', 'both'] ? "antiSMASH (Blin et al. 2023)," : "",
        params.mode in ['assembly', 'both'] ? "GECCO (Carroll et al. 2021)," : "",
        params.mode in ['assembly', 'both'] && params.run_deepbgc ? "DeepBGC (Hannigan et al. 2019)," : "",
        params.mode in ['assembly', 'both'] && params.run_bigscape ? "BiG-SCAPE (Navarro-Munoz et al. 2020)," : "",
        "MultiQC (Ewels et al. 2016)",
        ".",
    ]
    return citations.findAll { entry -> entry }.join(' ').trim()
}

def toolBibliographyText() {
    def references = [
        params.skip_qc || params.skip_nanoplot ? "" : "<li>De Coster W, D'Hert S, Schultz DT, Cruts M, Van Broeckhoven C. NanoPack: visualizing and processing long-read sequencing data. Bioinformatics. 2018;34(15):2666-2669. doi: 10.1093/bioinformatics/bty149</li>",
        params.skip_qc ? "" : "<li>De Coster W, Rademakers R. NanoPack2: population-scale evaluation of long-read sequencing data. Bioinformatics. 2023;39(5):btad311. doi: 10.1093/bioinformatics/btad311</li>",
        "<li>Shen W, Le S, Li Y, Hu F. SeqKit: A Cross-Platform and Ultrafast Toolkit for FASTA/Q File Manipulation. PLoS One. 2016;11(10):e0163962. doi: 10.1371/journal.pone.0163962</li>",
        "<li>Wood DE, Lu J, Langmead B. Improved metagenomic analysis with Kraken 2. Genome Biol. 2019;20(1):257. doi: 10.1186/s13059-019-1891-0</li>",
        "<li>Lu J, Breitwieser FP, Thielen P, Salzberg SL. Bracken: estimating species abundance in metagenomics data. PeerJ Comput Sci. 2017;3:e104. doi: 10.7717/peerj-cs.104</li>",
        "<li>Lu J, Rincon N, Wood DE, et al. Metagenome analysis using the Kraken software suite. Nat Protoc. 2022;17(12):2815-2839. doi: 10.1038/s41596-022-00738-y</li>",
        "<li>Woodcroft BJ, Newell R. CoverM: read coverage calculator for metagenomics. URL: https://github.com/wwood/CoverM</li>",
        params.mode in ['reads', 'both'] ? "<li>Buchfink B, Reuter K, Drost HG. Sensitive protein alignments at tree-of-life scale using DIAMOND. Nat Methods. 2021;18(4):366-368. doi: 10.1038/s41592-021-01101-x</li>" : "",
        params.mode in ['assembly', 'both'] && params.assembler == 'metamdbg' ? "<li>Benoit G, Raguideau S, James R, Phillippy AM, Chikhi R, Quince C. High-quality metagenome assembly from long accurate reads with metaMDBG. Nat Biotechnol. 2024;42(9):1378-1383. doi: 10.1038/s41587-023-01983-6</li>" : "",
        params.mode in ['assembly', 'both'] && params.assembler == 'flye' ? "<li>Kolmogorov M, Bickhart DM, Behsaz B, et al. metaFlye: scalable long-read metagenome assembly using repeat graphs. Nat Methods. 2020;17(11):1103-1110. doi: 10.1038/s41592-020-00971-x</li>" : "",
        params.mode in ['assembly', 'both'] && runMedakaPolishing() ? "<li>Oxford Nanopore Technologies. medaka. URL: https://github.com/nanoporetech/medaka</li>" : "",
        params.mode in ['assembly', 'both'] ? "<li>Larralde M. Pyrodigal: Python bindings and interface to Prodigal. J Open Source Softw. 2022;7(72):4296. doi: 10.21105/joss.04296</li>" : "",
        params.mode in ['assembly', 'both'] ? "<li>Blin K, Shaw S, Augustijn HE, et al. antiSMASH 7.0: new and improved predictions. Nucleic Acids Res. 2023;51(W1):W46-W50. doi: 10.1093/nar/gkad344</li>" : "",
        params.mode in ['assembly', 'both'] ? "<li>Carroll LM, Larralde M, Fleck JS, et al. Accurate de novo identification of biosynthetic gene clusters with GECCO. bioRxiv. 2021. doi: 10.1101/2021.05.03.442509</li>" : "",
        params.mode in ['assembly', 'both'] && params.run_deepbgc ? "<li>Hannigan GD, Prihoda D, Palicka A, et al. A deep learning genome-mining strategy for biosynthetic gene cluster prediction. Nucleic Acids Res. 2019;47(18):e110. doi: 10.1093/nar/gkz654</li>" : "",
        params.mode in ['assembly', 'both'] && params.run_bigscape ? "<li>Navarro-Munoz JC, Selem-Mojica N, Mullowney MW, et al. A computational framework to explore large-scale biosynthetic diversity. Nat Chem Biol. 2020;16(1):60-68. doi: 10.1038/s41589-019-0400-9</li>" : "",
        "<li>Ewels P, Magnusson M, Lundin S, Kaller M. MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics. 2016;32(19):3047-3048. doi: 10.1093/bioinformatics/btw354</li>",
    ]
    return references.findAll { entry -> entry }.join(' ').trim()
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    }
    else {
        meta["doi_text"] = ""
    }
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = toolCitationText().replaceAll(", \\.", ".").replaceAll("\\. \\.", ".").replaceAll(", \\.", ".")
    meta["tool_bibliography"] = toolBibliographyText()

    def methods_text = mqc_methods_yaml.text

    def engine = new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
