process PLOT_COVERM {

    label "small"

    publishDir "${params.outdir}/figures", mode: 'copy'

    container params.python_container

    input:
    tuple val(group_id), path(coverm_tsv)
    path samplesheet

    output:
    tuple val(group_id), path('*.pdf'), emit: figure_file

    script:
    """
    coverm_ncbi_report.py \\
        -i ${coverm_tsv} \\
        -n ${group_id} \\
        -s ${samplesheet}
    """
}
