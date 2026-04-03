process PLOT_GENE_DIAMOND {

    label "small"

    container params.python_container

    publishDir "${params.outdir}/figures", mode: 'copy'

    input:
    path diamond_tsvs

    output:
    path "cyanotoxins_heatmap.pdf", emit: pdf

    script:
    """
    plot_gene_diamond.py \\
        --input ${diamond_tsvs} \\
        --output cyanotoxins_heatmap.pdf
    """
}
