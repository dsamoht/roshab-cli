process MEDAKA {
    tag "${meta.id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/medaka:2.2.2--py312h3050eb1_0'
        : 'quay.io/biocontainers/medaka:2.2.2--py312h3050eb1_0'}"

    input:
    tuple val(meta), path(reads), path(contigs)

    output:
    tuple val(meta), path("*.polished.fasta"), emit: contigs, optional: true
    tuple val("${task.process}"), val('medaka'), eval("medaka --version | sed 's/^medaka //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    export HOME="\$PWD"

    medaka_consensus \\
        ${args} \\
        -i ${reads} \\
        -d ${contigs} \\
        -o medaka_out \\
        -t ${task.cpus}

    if [ -s medaka_out/consensus.fasta ]; then
        mv medaka_out/consensus.fasta ${prefix}.polished.fasta
    else
        echo "medaka produced no polished assembly for ${prefix}" >&2
    fi
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.polished.fasta
    """
}
