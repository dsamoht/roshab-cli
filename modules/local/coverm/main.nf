process COVERM {
    tag "${group_id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/coverm:0.7.0--hcb7b614_4'
        : 'quay.io/biocontainers/coverm:0.7.0--hcb7b614_4'}"

    input:
    tuple val(group_id), val(metas), path(reads)
    path genome_directory
    val db_name

    output:
    tuple val(group_id), path("*.coverm.tsv"), emit: tsv, optional: true
    tuple val("${task.process}"), val('coverm'), eval("coverm --version | sed 's/^coverm //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "group_${group_id}_${db_name}"
    // CoverM takes the sample name from the FastQ file name, so restore the
    // sample names that the staged files lost.
    def rename_cmds = metas
        .collect { entry -> entry.id }
        .withIndex()
        .collect { name, i -> "mv ${reads[i]} ${name}.fastq.gz" }
        .join('\n    ')
    """
    ${rename_cmds}

    coverm genome \\
        ${args} \\
        --single *.fastq.gz \\
        --genome-fasta-directory ${genome_directory} \\
        --output-file ${prefix}.coverm.tsv \\
        --threads ${task.cpus}
    """

    stub:
    def prefix = task.ext.prefix ?: "group_${group_id}_${db_name}"
    """
    touch ${prefix}.coverm.tsv
    """
}
