process SEQKIT_STATS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/seqkit:2.13.0--he881be0_0'
        : 'quay.io/biocontainers/seqkit:2.13.0--he881be0_0'}"

    input:
    tuple val(meta), path(contigs)

    output:
    tuple val(meta), path("*.tsv"), emit: tsv
    tuple val("${task.process}"), val('seqkit'), eval("seqkit version | sed 's/^seqkit v//'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    seqkit stats \\
        ${args} \\
        --threads ${task.cpus} \\
        -o ${prefix}.tsv \\
        ${contigs}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.tsv
    """
}
