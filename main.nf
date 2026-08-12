#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    dsamoht/roshab-cli
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/dsamoht/roshab-cli
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { ASSEMBLY_BGC                                 } from './workflows/assembly_bgc'
include { LONGREAD_QC                                  } from './workflows/longread_qc'

include { BRACKEN                                      } from './modules/local/bracken'
include { CAT_READS as CAT_INIT                        } from './modules/local/cat'
include { CAT_READS as CAT_PRE_KRAKEN                  } from './modules/local/cat'
include { COVERM                                       } from './modules/local/coverm'
include { DECOMPRESS as PREP_GENOMES_DB                } from './modules/local/decompress'
include { DECOMPRESS as PREP_KRAKEN_DB                 } from './modules/local/decompress'
include { DIAMOND_BLASTX                               } from './modules/local/diamond/blastx'
include { KRAKEN2                                      } from './modules/local/kraken2'
include { KRAKENTOOLS_COMBINEMPA                       } from './modules/local/krakentools/combinempa'
include { KRAKENTOOLS_KREPORT2MPA                      } from './modules/local/krakentools/kreport2mpa'
include { KRAKENTOOLS_MAKEKREPORT                      } from './modules/local/krakentools/makekreport'
include { MULTIQC                                      } from './modules/local/multiqc'
include { PLOT_COVERM                                  } from './modules/local/plot_coverm'
include { PLOT_GENE_DIAMOND as PLOT_GENE_DIAMOND_READS } from './modules/local/plot_gene_diamond'
include { PLOT_KRAKEN                                  } from './modules/local/plot_kraken'
include { SEQKIT_SLIDING                               } from './modules/local/seqkit/sliding'
include { SPLIT_KRAKEN_OUTPUT                          } from './modules/local/kraken2/split_kraken_output'

include { PIPELINE_COMPLETION                          } from './subworkflows/local/pipeline_completion'
include { PIPELINE_INITIALISATION                      } from './subworkflows/local/pipeline_initialisation'
include { methodsDescriptionText                       } from './subworkflows/local/pipeline_initialisation'

include { paramsSummaryMap                             } from 'plugin/nf-schema'
include { paramsSummaryMultiqc                         } from './subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML                       } from './subworkflows/nf-core/utils_nfcore_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow ROSHAB_CLI {

    take:
    ch_samplesheet // channel: samplesheet read in from --input

    main:

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()

    //
    // Reference databases: directories and tarballs are both accepted
    //
    ch_kraken_db = PREP_KRAKEN_DB(
        channel.fromPath(params.kraken_db, checkIfExists: true),
        'kraken_db',
    ).db.first()

    ch_genomes_db = PREP_GENOMES_DB(
        channel.fromPath(params.genomes_db, checkIfExists: true),
        'genomes_db',
    ).db.first()

    ch_genes_db = channel.value(file(params.genes_db, checkIfExists: true))
    ch_samplesheet_file = channel.value(file(params.input, checkIfExists: true))

    //
    // MODULE: Concatenate the reads of a sample and stamp the sample name onto
    // the read IDs, so that the single combined Kraken2 run can be split back
    // out per sample afterwards
    //
    CAT_INIT(ch_samplesheet.map { meta, reads -> [meta, reads, meta.id] })

    //
    // SUBWORKFLOW: Read QC
    //
    LONGREAD_QC(CAT_INIT.out.reads)
    ch_qc_reads = LONGREAD_QC.out.reads
    ch_multiqc_files = ch_multiqc_files.mix(LONGREAD_QC.out.multiqc_files)

    //
    // MODULE: Segment the reads into Illumina-like windows so that their length
    // matches the Bracken k-mer distribution
    //
    SEQKIT_SLIDING(ch_qc_reads)

    //
    // MODULE: Classify every sample in a single Kraken2 run, then split the
    // per-read assignments back out per sample
    //
    ch_kraken_in = SEQKIT_SLIDING.out.fastq
        .toList()
        .map { items ->
            [
                [id: 'all', samples: items.collect { entry -> entry[0].id }.sort()],
                items.collect { entry -> entry[1] }.flatten().sort { read -> read.name },
                '',
            ]
        }

    CAT_PRE_KRAKEN(ch_kraken_in)
    KRAKEN2(CAT_PRE_KRAKEN.out.reads, ch_kraken_db)
    SPLIT_KRAKEN_OUTPUT(KRAKEN2.out.classified_reads_assignment)

    // Give the full sample metadata back to the split files by joining on the
    // sample name that `SPLIT_KRAKEN_OUTPUT` recovered from the read IDs
    ch_kraken_stdout = SPLIT_KRAKEN_OUTPUT.out.split
        .transpose()
        .map { _meta, kraken_file -> [kraken_file.simpleName, kraken_file] }
        .join(ch_samplesheet.map { meta, _reads -> [meta.id, meta] })
        .map { _id, kraken_file, meta -> [meta, kraken_file] }

    //
    // MODULE: Rebuild a per-sample Kraken2 report, then re-estimate abundances
    //
    KRAKENTOOLS_MAKEKREPORT(ch_kraken_stdout, ch_kraken_db)
    BRACKEN(KRAKENTOOLS_MAKEKREPORT.out.report, ch_kraken_db)

    ch_multiqc_files = ch_multiqc_files.mix(BRACKEN.out.report.map { _meta, report -> report })

    //
    // MODULE: Convert the Bracken reports to MPA format and combine them per group
    //
    KRAKENTOOLS_KREPORT2MPA(BRACKEN.out.report)

    ch_combinempa_in = KRAKENTOOLS_KREPORT2MPA.out.mpa
        .map { meta, mpa -> tuple(meta.group, [meta, mpa]) }
        .groupTuple()
        .map { group_id, metadata_and_file ->
            def sorted_items = metadata_and_file.sort { entry -> entry[0].id }
            return [group_id, sorted_items.collect { entry -> entry[1] }]
        }

    KRAKENTOOLS_COMBINEMPA(ch_combinempa_in)
    PLOT_KRAKEN(KRAKENTOOLS_COMBINEMPA.out.mpa, ch_samplesheet_file)

    //
    // MODULE: Per-genome coverage across the samples of a group
    //
    ch_coverm_in = ch_qc_reads
        .map { meta, reads -> tuple(meta.group, [meta, reads]) }
        .groupTuple()
        .map { group_id, metadata_and_file ->
            def sorted_items = metadata_and_file.sort { entry -> entry[0].id }
            return tuple(
                group_id,
                sorted_items.collect { entry -> entry[0] },
                sorted_items.collect { entry -> entry[1] },
            )
        }

    COVERM(ch_coverm_in, ch_genomes_db, 'cyanobacteria')
    PLOT_COVERM(COVERM.out.tsv, ch_samplesheet_file)

    //
    // Read-level screening: align the QC reads to the cyanotoxin gene database
    //
    ch_diamond_tsv = channel.empty()
    ch_diamond_plot = channel.empty()

    if (params.mode in ['reads', 'both']) {
        DIAMOND_BLASTX(ch_qc_reads, ch_genes_db)
        ch_diamond_tsv = DIAMOND_BLASTX.out.tsv

        ch_heatmap_in = ch_diamond_tsv
            .map { meta, tsv -> tuple(meta.group, tsv) }
            .groupTuple()

        PLOT_GENE_DIAMOND_READS(ch_heatmap_in)
        ch_diamond_plot = PLOT_GENE_DIAMOND_READS.out.pdf
    }

    //
    // WORKFLOW: Contig-level screening - assemble, then screen the
    // assemblies for biosynthetic gene clusters
    //
    def ch_assembly = [
        contigs: channel.empty(),
        assembly_stats: channel.empty(),
        proteins: channel.empty(),
        blastp_tsv: channel.empty(),
        blastp_plot: channel.empty(),
        antismash_results: channel.empty(),
        gecco_results: channel.empty(),
        deepbgc_tsv: channel.empty(),
        bgc_tsv: channel.empty(),
        bgc_plot: channel.empty(),
        bgc_summary: channel.empty(),
        bigscape_results: channel.empty(),
    ]

    if (params.mode in ['assembly', 'both']) {
        ch_assembly = ASSEMBLY_BGC(ch_qc_reads, ch_genes_db)
    }

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [process[process.lastIndexOf(':') + 1..-1], "  ${tool}: ${version}"]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'roshab-cli_software_mqc_versions.yml',
            sort: true,
            newLine: true,
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)

    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))

    def ch_multiqc_custom_methods_description = params.multiqc_methods_description
        ? file(params.multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))

    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files -> [[id: 'roshab-cli'], files] },
        params.multiqc_config
            ? file(params.multiqc_config, checkIfExists: true)
            : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
        params.multiqc_logo ? file(params.multiqc_logo, checkIfExists: true) : [],
    )

    emit:
    qc_reads          = ch_qc_reads
    nanoplot_raw_html = LONGREAD_QC.out.nanoplot_raw_html
    nanoplot_qc_html  = LONGREAD_QC.out.nanoplot_qc_html
    kraken_stdout     = ch_kraken_stdout
    kraken_report     = KRAKENTOOLS_MAKEKREPORT.out.report
    bracken_report    = BRACKEN.out.report
    bracken_tsv       = BRACKEN.out.tsv
    bracken_mpa       = KRAKENTOOLS_KREPORT2MPA.out.mpa
    combined_mpa      = KRAKENTOOLS_COMBINEMPA.out.mpa
    kraken_doc        = PLOT_KRAKEN.out.pdf
    diamond_tsv       = ch_diamond_tsv
    diamond_plot      = ch_diamond_plot
    coverm_genome_out = COVERM.out.tsv
    coverm_plot_out   = PLOT_COVERM.out.pdf
    contigs           = ch_assembly.contigs
    assembly_stats    = ch_assembly.assembly_stats
    proteins          = ch_assembly.proteins
    blastp_tsv        = ch_assembly.blastp_tsv
    blastp_plot       = ch_assembly.blastp_plot
    antismash_results = ch_assembly.antismash_results
    gecco_results     = ch_assembly.gecco_results
    deepbgc_tsv       = ch_assembly.deepbgc_tsv
    bgc_tsv           = ch_assembly.bgc_tsv
    bgc_plot          = ch_assembly.bgc_plot
    bgc_summary       = ch_assembly.bgc_summary
    bigscape_results  = ch_assembly.bigscape_results
    multiqc_html      = MULTIQC.out.report
    multiqc_data      = MULTIQC.out.data
    multiqc_report    = MULTIQC.out.report.map { _meta, report -> [report] }.toList()
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN THE WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:

    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    PIPELINE_INITIALISATION(
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.help,
        params.help_full,
        params.show_hidden,
    )

    //
    // WORKFLOW: Run the main analysis
    //
    ROSHAB_CLI(PIPELINE_INITIALISATION.out.samplesheet)

    //
    // SUBWORKFLOW: Run completion tasks
    //
    PIPELINE_COMPLETION(
        params.email,
        params.email_on_fail,
        params.plaintext_email,
        params.outdir,
        params.monochrome_logs,
        ROSHAB_CLI.out.multiqc_report,
    )

    publish:
    qc_reads          = ROSHAB_CLI.out.qc_reads
    nanoplot_raw_html = ROSHAB_CLI.out.nanoplot_raw_html
    nanoplot_qc_html  = ROSHAB_CLI.out.nanoplot_qc_html
    kraken_stdout     = ROSHAB_CLI.out.kraken_stdout
    kraken_report     = ROSHAB_CLI.out.kraken_report
    bracken_report    = ROSHAB_CLI.out.bracken_report
    bracken_tsv       = ROSHAB_CLI.out.bracken_tsv
    bracken_mpa       = ROSHAB_CLI.out.bracken_mpa
    combined_mpa      = ROSHAB_CLI.out.combined_mpa
    kraken_doc        = ROSHAB_CLI.out.kraken_doc
    diamond_tsv       = ROSHAB_CLI.out.diamond_tsv
    diamond_plot      = ROSHAB_CLI.out.diamond_plot
    coverm_genome_out = ROSHAB_CLI.out.coverm_genome_out
    coverm_plot_out   = ROSHAB_CLI.out.coverm_plot_out
    contigs           = ROSHAB_CLI.out.contigs
    assembly_stats    = ROSHAB_CLI.out.assembly_stats
    proteins          = ROSHAB_CLI.out.proteins
    blastp_tsv        = ROSHAB_CLI.out.blastp_tsv
    blastp_plot       = ROSHAB_CLI.out.blastp_plot
    antismash_results = ROSHAB_CLI.out.antismash_results
    gecco_results     = ROSHAB_CLI.out.gecco_results
    deepbgc_tsv       = ROSHAB_CLI.out.deepbgc_tsv
    bgc_tsv           = ROSHAB_CLI.out.bgc_tsv
    bgc_plot          = ROSHAB_CLI.out.bgc_plot
    bgc_summary       = ROSHAB_CLI.out.bgc_summary
    bigscape_results  = ROSHAB_CLI.out.bigscape_results
    multiqc_html      = ROSHAB_CLI.out.multiqc_html
    multiqc_data      = ROSHAB_CLI.out.multiqc_data
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PUBLISHING
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Results are grouped by the `group` column of the samplesheet. The publish
    mode comes from `--publish_dir_mode` via `workflow.output.mode` in
    `nextflow.config`.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

output {

    qc_reads {
        path { meta, _file -> "group_${meta.group}/reads/post_qc" }
    }
    nanoplot_raw_html {
        path { meta, _file -> "group_${meta.group}/quality_assessment/nanoplot/raw/${meta.id}" }
    }
    nanoplot_qc_html {
        path { meta, _file -> "group_${meta.group}/quality_assessment/nanoplot/post_qc/${meta.id}" }
    }
    kraken_stdout {
        path { meta, _file -> "group_${meta.group}/kraken" }
    }
    kraken_report {
        path { meta, _file -> "group_${meta.group}/kraken" }
    }
    bracken_report {
        path { meta, _file -> "group_${meta.group}/bracken" }
    }
    bracken_tsv {
        path { meta, _file -> "group_${meta.group}/bracken" }
    }
    bracken_mpa {
        path { meta, _file -> "group_${meta.group}/bracken" }
    }
    combined_mpa {
        path { group_id, _file -> "group_${group_id}/bracken" }
    }
    kraken_doc {
        path { group_id, _file -> "group_${group_id}/figures" }
    }
    diamond_tsv {
        path { meta, _file -> "group_${meta.group}/diamond" }
    }
    diamond_plot {
        path { group_id, _file -> "group_${group_id}/figures" }
    }
    coverm_genome_out {
        path { group_id, _file -> "group_${group_id}/coverm" }
    }
    coverm_plot_out {
        path { group_id, _file -> "group_${group_id}/figures" }
    }
    contigs {
        path { meta, _file -> "group_${meta.group}/assembly" }
    }
    assembly_stats {
        path { meta, _file -> "group_${meta.group}/assembly" }
    }
    proteins {
        path { meta, _file -> "group_${meta.group}/assembly/proteins" }
    }
    blastp_tsv {
        path { meta, _file -> "group_${meta.group}/diamond_contigs" }
    }
    blastp_plot {
        path { group_id, _file -> "group_${group_id}/figures" }
    }
    antismash_results {
        path { meta, _file -> "group_${meta.group}/bgc/antismash" }
    }
    gecco_results {
        path { meta, _file -> "group_${meta.group}/bgc/gecco" }
    }
    deepbgc_tsv {
        path { meta, _file -> "group_${meta.group}/bgc/deepbgc" }
    }
    bgc_tsv {
        path { meta, _file -> "group_${meta.group}/bgc" }
    }
    bgc_plot {
        path { group_id, _file -> "group_${group_id}/figures" }
    }
    bgc_summary {
        path { group_id, _file -> "group_${group_id}/bgc" }
    }
    bigscape_results {
        path { group_id, _file -> "group_${group_id}/bgc/bigscape" }
    }
    multiqc_html {
        path { _meta, _file -> "multiqc" }
    }
    multiqc_data {
        path { _meta, _file -> "multiqc" }
    }

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
