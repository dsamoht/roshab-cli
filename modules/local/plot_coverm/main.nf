process PLOT_COVERM {
    tag "${group_id}"
    label 'process_single'
    label 'error_ignore'

    conda "${moduleDir}/environment.yml"
    container "docker.io/dsamoht/bio-utils:latest"

    input:
    tuple val(group_id), path(coverm_tsv)
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

    coverm_ncbi_report.py \\
        ${args} \\
        -i ${coverm_tsv} \\
        -n ${prefix} \\
        -s ${samplesheet}
    """

    stub:
    def prefix = task.ext.prefix ?: "${group_id}"
    """
    touch ${prefix}.pdf
    """
}
