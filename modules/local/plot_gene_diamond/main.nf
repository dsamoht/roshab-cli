process PLOT_GENE_DIAMOND {
    tag "${group_id}"
    label 'process_single'
    label 'error_ignore'

    conda "${moduleDir}/environment.yml"
    container "docker.io/dsamoht/bio-utils:latest"

    input:
    tuple val(group_id), path(diamond_tsvs)

    output:
    tuple val(group_id), path("*.pdf"), emit: pdf, optional: true
    tuple val("${task.process}"), val('python'), eval("python --version | sed 's/^Python //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "group_${group_id}_cyanotoxins_heatmap"
    """
    export MPLCONFIGDIR="\$PWD/.mplconfig"

    plot_gene_diamond.py \\
        ${args} \\
        --input ${diamond_tsvs} \\
        --output ${prefix}.pdf
    """

    stub:
    def prefix = task.ext.prefix ?: "group_${group_id}_cyanotoxins_heatmap"
    """
    touch ${prefix}.pdf
    """
}
