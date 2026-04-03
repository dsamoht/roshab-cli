#!/usr/bin/env nextflow

include { ROSHAB_WF             } from './workflows/roshab_wf'

info = """
                _           _                _ _ 
  _ __ ___  ___| |__   __ _| |__         ___| (_)
 | '__/ _ \\/ __| '_ \\ / _` | '_ \\ _____ / __| | |
 | | | (_) \\__ \\ | | | (_| | |_) |_____| (__| | |
 |_|  \\___/|___/_| |_|\\__,_|_.__/       \\___|_|_|
                                                 
 Taxonomic classification and evaluation of cyanotoxin biosynthesis
 potential from nanopore reads.

     github: https://github.com/dsamoht/roshab-cli
     version: 0.1.0

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Usage:

     nextflow run main.nf --exp [NAME] --input [PATH] --outdir [PATH]

Arguments:
    --exp    [NAME] : name of the experiment
    --outdir [PATH] : path to output directory (will be created if non-existant)
    --input  [PATH] : path to a samplesheet (CSV) with the following columns:
                    sample_name,date,site,group,reads

    --kraken_db     : path to decommpressed `kraken` database
    --genomes_db    : path to decommpressed genomes database (https://zenodo.org/records/15659134/files/cyanobacteriota_ncbi_dRep_n220.tar.gz)
    --genes_db      : path to cyanotoxin-related genes database (https://zenodo.org/records/15659134/files/BGC_cyanotoxins_plus_orthologs.fna)

Optional argument:
    --skip_qc           : skip quality control steps (`nanoplot` and `chopper`)
    --chopper_headcrop  : number of bases to trim from the start of each read (default: 80)
    --chopper_tailcrop  : number of bases to trim from the end of each read (default: 80)
    --chopper_minlength : minimum length of reads to keep (default: 500)
    --chopper_minq      : minimum quality score of bases to keep (default: 9)
    
    --help    : print this help message

"""

log.info info

if( params.help ) {
    exit 0
}

if ( !params.input) {
    log.info "Error: input samplesheet not specified."
    exit 1
}

if ( !params.exp) {
    log.info "Error: experiment name not specified."
    exit 1
}

if ( !params.outdir) {
    log.info "Warning: output directory not specified. Using default: `roshab_output`"
    params.outdir = 'roshab_output'
}

workflow {

    ROSHAB_WF()

}
