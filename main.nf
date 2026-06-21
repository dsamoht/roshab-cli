#!/usr/bin/env nextflow
include { ROSHAB_WF } from './workflows/roshab_wf'

def helpMessage() {
log.info """
                _           _                _ _ 
  _ __ ___  ___| |__   __ _| |__         ___| (_)
 | '__/ _ \\/ __| '_ \\ / _` | '_ \\ _____ / __| | |
 | | | (_) \\__ \\ | | | (_| | |_) |_____| (__| | |
 |_|  \\___/|___/_| |_|\\__,_|_.__/       \\___|_|_|

 Taxonomic classification and evaluation of cyanotoxin biosynthesis
 potential from nanopore reads.

     github: https://github.com/dsamoht/roshab-cli
     version: 1.0.0
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Usage:
     nextflow run main.nf --input [PATH] --outdir [PATH]
Arguments:
    --outdir [PATH] : path to output directory (will be created if non-existant)
    --input  [PATH] : path to a samplesheet (CSV) with the following columns:
                    sample_name,date,site,group,reads
    --kraken_db     : path to decommpressed `kraken` database
    --genomes_db    : path to decommpressed genomes database (https://zenodo.org/records/19522349/files/cyanobacteriota_ncbi_dRep_n220.tar.gz)
    --genes_db      : path to cyanotoxin-related genes database (https://zenodo.org/records/19522349/files/core_cyanotoxin-related_gene_mibig-v4_antismash-v8.faa)
Optional argument:
    --skip_qc           : skip quality control steps (`nanoplot` and `chopper`)
    --skip_nanoplot     : skip `nanoplot` quality assessment
    --chopper_headcrop  : number of bases to trim from the start of each read (default: 80)
    --chopper_tailcrop  : number of bases to trim from the end of each read (default: 50)
    --chopper_minlength : minimum length of reads to keep (default: 500)
    --chopper_minq      : minimum quality score of bases to keep (default: 9)
    --help              : print this help message
    """

}

workflow {
    main:
    if (params.help) {
        helpMessage()
        exit(0, "")
    }
    if ( !params.input) {
        log.info "Error: input samplesheet not specified."
        exit 1
    }
    if ( !params.outdir) {
        log.info "outdir directory not specified. Using default: `${params.outdir}`"
    }
    if ( !params.kraken_db) {
        log.info "Error: Kraken database not specified."
        exit 1
    }
    if ( !params.genomes_db) {
        log.info "Error: Genomes database not specified."
        exit 1
    }
    if ( !params.genes_db) {
        log.info "Error: Genes database not specified."
        exit 1
    }

    ROSHAB_WF()

    publish:
    qc_reads          = ROSHAB_WF.out.qc_reads
    nanoplot_raw_html = ROSHAB_WF.out.nanoplot_raw_html
    nanoplot_qc_html  = ROSHAB_WF.out.nanoplot_qc_html
    kraken_stdout     = ROSHAB_WF.out.kraken_stdout
    kraken_report     = ROSHAB_WF.out.kraken_report
    bracken_report    = ROSHAB_WF.out.bracken_report
    bracken_tsv       = ROSHAB_WF.out.bracken_tsv
    bracken_mpa       = ROSHAB_WF.out.bracken_mpa
    combined_mpa      = ROSHAB_WF.out.combined_mpa
    kraken_doc        = ROSHAB_WF.out.kraken_doc
    diamond_tsv       = ROSHAB_WF.out.diamond_tsv
    diamond_plot      = ROSHAB_WF.out.diamond_plot
    coverm_genome_out = ROSHAB_WF.out.coverm_genome_out
    coverm_plot_out   = ROSHAB_WF.out.coverm_plot_out
}


output {

    qc_reads {
    path { meta, _file -> "group_${meta.group}/reads/post_qc" }
    mode "copy"
    }
    nanoplot_raw_html {
    path { meta, _file -> "group_${meta.group}/quality_assessment/nanoplot/raw/${meta.sample_id}" }
    mode "copy"
    }
    nanoplot_qc_html {
    path { meta, _file -> "group_${meta.group}/quality_assessment/nanoplot/post_qc/${meta.sample_id}" }
    mode "copy"
    }
    kraken_stdout {
    path { meta, _file -> "group_${meta.group}/kraken" }
    mode "copy"
    }
    kraken_report {
    path { meta, _file -> "group_${meta.group}/kraken" }
    mode "copy"
    }
    bracken_report {
    path { meta, _file -> "group_${meta.group}/bracken" }
    mode "copy"
    }
    bracken_tsv {
    path { meta, _file -> "group_${meta.group}/bracken" }
    mode "copy"
    }
    bracken_mpa {
    path { meta, _file -> "group_${meta.group}/bracken" }
    mode "copy"
    }
    combined_mpa {
    path { group_id, _file -> "group_${group_id}/bracken" }
    mode "copy"
    }
    kraken_doc {
    path { group_id, _file -> "group_${group_id}/figures" }
    mode "copy"
    }
    diamond_tsv {
    path { meta, _file -> "group_${meta.group}/diamond" }
    mode "copy"
    }
    diamond_plot {
    path { group_id, _file -> "group_${group_id}/figures" }
    mode "copy"
    }
    coverm_genome_out {
    path { group_id, _file -> "group_${group_id}/coverm" }
    mode "copy"
    }
    coverm_plot_out {
    path { group_id, _file -> "group_${group_id}/figures" }
    mode "copy"
    }

}
