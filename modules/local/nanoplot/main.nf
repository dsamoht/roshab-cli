process NANOPLOT {
    tag "${meta.id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/nanoplot:1.46.1--pyhdfd78af_0'
        : 'quay.io/biocontainers/nanoplot:1.46.1--pyhdfd78af_0'}"

    input:
    tuple val(meta), path(fastq)

    output:
    tuple val(meta), path("*.html"), emit: html
    tuple val(meta), path("*.png"), emit: png, optional: true
    tuple val(meta), path("*.txt"), emit: txt
    tuple val("${task.process}"), val('nanoplot'), eval("NanoPlot --version | sed 's/^NanoPlot //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    NanoPlot \\
        ${args} \\
        --prefix ${prefix}_ \\
        --fastq ${fastq} \\
        --threads ${task.cpus}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_NanoPlot-report.html
    touch ${prefix}_NanoStats.txt
    """
}
