process DEEPBGC {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/deepbgc:0.1.31--pyhca03a8a_0'
        : 'quay.io/biocontainers/deepbgc:0.1.31--pyhca03a8a_0'}"

    input:
    tuple val(meta), path(contigs)
    path db

    output:
    tuple val(meta), path("*.deepbgc.tsv"), emit: tsv, optional: true
    tuple val(meta), path("${prefix}_deepbgc"), emit: results, optional: true
    tuple val("${task.process}"), val('deepbgc'), eval("deepbgc --version"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    export HOME="\$PWD"
    export DEEPBGC_DOWNLOADS_DIR="\$(readlink -f ${db})"

    deepbgc pipeline \\
        ${args} \\
        --output ${prefix}_deepbgc \\
        ${contigs}

    for tsv in ${prefix}_deepbgc/*.bgc.tsv; do
        if [ -s "\$tsv" ]; then
            cp "\$tsv" ${prefix}.deepbgc.tsv
            break
        fi
    done
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir ${prefix}_deepbgc
    touch ${prefix}.deepbgc.tsv
    """
}
