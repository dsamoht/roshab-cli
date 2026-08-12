process DEEPBGC_DOWNLOAD {
    tag "deepbgc_db"
    label 'process_single'
    label 'process_long'
    label 'error_retry'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/deepbgc:0.1.31--pyhca03a8a_0'
        : 'quay.io/biocontainers/deepbgc:0.1.31--pyhca03a8a_0'}"

    input:
    val ready // ordering token only - nothing is read from it

    // No `versions` topic: `storeDir` only accepts `val` and `path` outputs, and
    // nothing collects software versions on a database installation run anyway
    output:
    path "deepbgc_db", emit: db

    when:
    task.ext.when == null || task.ext.when

    script:
    args = task.ext.args ?: ''
    """
    export HOME="\$PWD"

    mkdir -p deepbgc_db
    export DEEPBGC_DOWNLOADS_DIR="\$PWD/deepbgc_db"

    deepbgc download ${args}
    """

    stub:
    """
    mkdir deepbgc_db
    """
}
