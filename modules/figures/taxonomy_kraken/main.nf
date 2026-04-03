process PLOT_KRAKEN {

    label "small"

    publishDir "${params.outdir}/figures", mode: 'copy'

    container params.python_container

    input:
    tuple val(group_id), path(combined_mpa)
    path samplesheet

    output:
    tuple val(group_id), path('*.pdf'), emit: figure_file

    script:
    """
    kraken_cyano_report.py \\
        -i ${combined_mpa} \\
        -n ${group_id} \\
        -s ${samplesheet}
    """
}
