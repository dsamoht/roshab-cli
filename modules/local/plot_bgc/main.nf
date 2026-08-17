process PLOT_BGC {
    tag "${group_id}"
    label 'process_single'
    label 'error_ignore'

    conda "${moduleDir}/environment.yml"
    container "docker.io/dsamoht/bio-utils:latest"

    input:
    tuple val(group_id), path(bgc_tsvs)

    output:
    tuple val(group_id), path("*_bgc_overview.pdf"), emit: pdf, optional: true
    tuple val(group_id), path("*_bgc_summary.tsv"), emit: tsv, optional: true
    tuple val("${task.process}"), val('python'), eval("python --version | sed 's/^Python //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "group_${group_id}"
    """
    export MPLCONFIGDIR="\$PWD/.mplconfig"

    plot_bgc.py \\
        ${args} \\
        --input ${bgc_tsvs} \\
        --output ${prefix}_bgc_overview.pdf \\
        --summary ${prefix}_bgc_summary.tsv
    """

    stub:
    def prefix = task.ext.prefix ?: "group_${group_id}"
    """
    touch ${prefix}_bgc_overview.pdf
    touch ${prefix}_bgc_summary.tsv
    """
}
