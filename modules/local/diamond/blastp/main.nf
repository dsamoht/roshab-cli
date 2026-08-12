process DIAMOND_BLASTP {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/diamond:2.1.23--hf93d47f_0'
        : 'quay.io/biocontainers/diamond:2.1.23--hf93d47f_0'}"

    input:
    tuple val(meta), path(proteins)
    path db

    output:
    tuple val(meta), path("*.tsv"), emit: tsv, optional: true
    tuple val("${task.process}"), val('diamond'), eval("diamond --version | sed 's/^diamond version //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    diamond blastp \\
        ${args} \\
        --db ${db} \\
        --query ${proteins} \\
        --out ${prefix}.tsv \\
        --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen slen \\
        --header \\
        --threads ${task.cpus}
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.tsv
    """
}
