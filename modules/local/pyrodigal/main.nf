process PYRODIGAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/pyrodigal:3.7.1--py312h247cb63_1'
        : 'quay.io/biocontainers/pyrodigal:3.7.1--py312h247cb63_1'}"

    input:
    tuple val(meta), path(contigs)

    output:
    tuple val(meta), path("*.faa"), emit: faa, optional: true
    tuple val(meta), path("*.gff"), emit: gff, optional: true
    tuple val("${task.process}"), val('pyrodigal'), eval("pyrodigal --version | sed 's/^pyrodigal v//'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    pyrodigal \\
        ${args} \\
        -i ${contigs} \\
        -a ${prefix}.faa \\
        -o ${prefix}.gff \\
        -f gff \\
        -j ${task.cpus}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.faa
    touch ${prefix}.gff
    """
}
