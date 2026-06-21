process PLOT_GENE_DIAMOND {

    label "small"

    container params.python_container

    errorStrategy 'ignore'

    //publishDir "${params.outdir}/figures", mode: 'copy'

    input:
    tuple val(group_id), path(diamond_tsvs)

    output:
    tuple val(group_id), path("*_cyanotoxins_heatmap.pdf"), emit: pdf, optional: true

    script:
    """
    plot_gene_diamond.py \\
        --input ${diamond_tsvs} \\
        --output group_${group_id}_cyanotoxins_heatmap.pdf
    """
}
