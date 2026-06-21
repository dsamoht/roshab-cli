#!/usr/bin/env nextflow

include { CHOPPER                  } from '../../modules/chopper'
include { NANOPLOT as NANOPLOT_QC  } from '../../modules/nanoplot'
include { NANOPLOT as NANOPLOT_RAW } from '../../modules/nanoplot'

workflow LONGREAD_QC {
    take:
    ch_raw_long_reads
    
    main:
    ch_versions = channel.empty()
    ch_multiqc_files = channel.empty()
    ch_nanoplot_raw_out = [html: channel.empty(), versions: channel.empty()]
    ch_nanoplot_qc_out  = [html: channel.empty(), versions: channel.empty()]
    
    if (!params.skip_qc) {
        if (!params.skip_nanoplot) {
            ch_nanoplot_raw_input = ch_raw_long_reads
                .map { meta, read -> [ meta, "raw", read ] }
            ch_nanoplot_raw_out = NANOPLOT_RAW(ch_nanoplot_raw_input)
            ch_versions = ch_versions.mix(NANOPLOT_RAW.out.versions.first())
        }
        
        CHOPPER(ch_raw_long_reads)
        ch_versions = ch_versions.mix(CHOPPER.out.versions.first())
        ch_choppered_reads = CHOPPER.out.fastq
        
        if (!params.skip_nanoplot) {
            ch_nanoplot_qc_input = ch_choppered_reads
                .map { meta, read -> [ meta, "qc", read ] }
            ch_nanoplot_qc_out = NANOPLOT_QC(ch_nanoplot_qc_input)
            ch_versions = ch_versions.mix(NANOPLOT_QC.out.versions.first())
        }
        
        ch_long_reads_qc = ch_choppered_reads
        
    } else {
        ch_long_reads_qc = ch_raw_long_reads
    }
    
    emit:
    nanoplot_raw_html = ch_nanoplot_raw_out.html
    nanoplot_qc_html  = ch_nanoplot_qc_out.html
    long_reads_qc     = ch_long_reads_qc
    versions          = ch_versions
    multiqc_files     = ch_multiqc_files

}
