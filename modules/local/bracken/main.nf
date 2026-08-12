process BRACKEN {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/bracken:3.1--h9948957_0'
        : 'quay.io/biocontainers/bracken:3.1--h9948957_0'}"

    input:
    tuple val(meta), path(kraken_report)
    path db

    output:
    tuple val(meta), path("*.bracken.tsv"), emit: tsv
    tuple val(meta), path("*.bracken.report"), emit: report
    tuple val("${task.process}"), val('bracken'), eval("bracken -v | sed 's/^Bracken v//'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    bracken \\
        ${args} \\
        -d ${db} \\
        -i ${kraken_report} \\
        -o ${prefix}.bracken.tsv \\
        -w ${prefix}.bracken.report
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.bracken.tsv
    touch ${prefix}.bracken.report
    """
}
