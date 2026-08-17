process PLOT_KRAKEN {
    tag "${group_id}"
    label 'process_single'
    label 'error_ignore'

    conda "${moduleDir}/environment.yml"
    container "docker.io/dsamoht/bio-utils:latest"

    input:
    tuple val(group_id), path(combined_mpa)
    path samplesheet

    output:
    tuple val(group_id), path("*.pdf"), emit: pdf, optional: true
    tuple val("${task.process}"), val('python'), eval("python --version | sed 's/^Python //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${group_id}"
    """
    export MPLCONFIGDIR="\$PWD/.mplconfig"

    kraken_cyano_report.py \\
        ${args} \\
        -i ${combined_mpa} \\
        -n ${prefix} \\
        -s ${samplesheet}
    """

    stub:
    def prefix = task.ext.prefix ?: "${group_id}"
    """
    touch ${prefix}.pdf
    """
}
