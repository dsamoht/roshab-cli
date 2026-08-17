process KRAKEN2 {
    tag "${meta.id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/kraken2:2.17.1--pl5321h077b44d_0'
        : 'quay.io/biocontainers/kraken2:2.17.1--pl5321h077b44d_0'}"

    input:
    tuple val(meta), path(reads)
    path db

    output:
    tuple val(meta), path("*.kraken"), emit: report
    tuple val(meta), path("*.kraken.out"), emit: classified_reads_assignment
    tuple val("${task.process}"), val('kraken2'), eval("kraken2 --version | sed -n '1s/^.*Kraken version //p'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    kraken2 \\
        ${args} \\
        --db ${db} \\
        --report ${prefix}.kraken \\
        --threads ${task.cpus} \\
        ${reads} \\
        > ${prefix}.kraken.out
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.kraken
    touch ${prefix}.kraken.out
    """
}
