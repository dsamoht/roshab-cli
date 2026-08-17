//
// Quality assessment and trimming of Oxford Nanopore reads
//

include { CHOPPER                  } from '../../modules/local/chopper'
include { NANOPLOT as NANOPLOT_RAW } from '../../modules/local/nanoplot'
include { NANOPLOT as NANOPLOT_QC  } from '../../modules/local/nanoplot'

workflow LONGREAD_QC {

    take:
    ch_raw_reads // channel: [ val(meta), path(reads) ]

    main:

    ch_multiqc_files = channel.empty()
    ch_nanoplot_raw_html = channel.empty()
    ch_nanoplot_qc_html = channel.empty()

    if (params.skip_qc) {
        ch_qc_reads = ch_raw_reads
    }
    else {
        if (!params.skip_nanoplot) {
            NANOPLOT_RAW(ch_raw_reads)
            ch_nanoplot_raw_html = NANOPLOT_RAW.out.html
            ch_multiqc_files = ch_multiqc_files.mix(NANOPLOT_RAW.out.txt.map { _meta, txt -> txt })
        }

        CHOPPER(ch_raw_reads)
        ch_qc_reads = CHOPPER.out.fastq

        if (!params.skip_nanoplot) {
            NANOPLOT_QC(ch_qc_reads)
            ch_nanoplot_qc_html = NANOPLOT_QC.out.html
            ch_multiqc_files = ch_multiqc_files.mix(NANOPLOT_QC.out.txt.map { _meta, txt -> txt })
        }
    }

    emit:
    reads             = ch_qc_reads          // channel: [ val(meta), path(reads) ]
    nanoplot_raw_html = ch_nanoplot_raw_html // channel: [ val(meta), path(html) ]
    nanoplot_qc_html  = ch_nanoplot_qc_html  // channel: [ val(meta), path(html) ]
    multiqc_files     = ch_multiqc_files     // channel: path(NanoStats.txt)
}
