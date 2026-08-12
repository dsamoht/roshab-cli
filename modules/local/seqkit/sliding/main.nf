process SEQKIT_SLIDING {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/seqkit:2.13.0--he881be0_0'
        : 'quay.io/biocontainers/seqkit:2.13.0--he881be0_0'}"

    input:
    tuple val(meta), path(fastq)

    output:
    tuple val(meta), path("*.fastq"), emit: fastq
    tuple val("${task.process}"), val('seqkit'), eval("seqkit version | sed 's/^seqkit v//'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    seqkit sliding \\
        ${args} \\
        --threads ${task.cpus} \\
        -o ${prefix}.fastq \\
        ${fastq}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.fastq
    """
}
