process KRAKENTOOLS_KREPORT2MPA {

    label "small"

    tag "${meta.sample_id}"

    container params.krakentools_container

    //publishDir "${params.outdir}/group_${meta.group}/bracken", mode: 'copy'

    input:
    tuple val(meta), path(bracken_report)

    output:
    tuple val(meta), path('*.mpa'), emit: mpa_report

    script:
    """
    mv ${bracken_report} ${meta.sample_id}
    kreport2mpa.py \\
        -r ${meta.sample_id} \\
        -o ${meta.sample_id}.mpa \\
        --intermediate-ranks \\
        --display-header
    """
}
