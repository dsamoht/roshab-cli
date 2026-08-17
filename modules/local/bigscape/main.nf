process BIGSCAPE {
    tag "${group_id}"
    label 'process_medium'
    label 'error_ignore'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/bigscape:2.0.3--pyhdfd78af_0'
        : 'quay.io/biocontainers/bigscape:2.0.3--pyhdfd78af_0'}"

    input:
    tuple val(group_id), path(region_gbks)
    path pfam_db

    output:
    tuple val(group_id), path("${prefix}_bigscape"), emit: results, optional: true
    tuple val("${task.process}"), val('bigscape'), eval("bigscape --version | sed 's/^bigscape //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "group_${group_id}"
    """
    export HOME="\$PWD"

    mkdir -p gbk_input
    cp ${region_gbks} gbk_input/

    bigscape cluster \\
        ${args} \\
        -i gbk_input \\
        -o ${prefix}_bigscape \\
        -p ${pfam_db} \\
        --cores ${task.cpus}
    """

    stub:
    prefix = task.ext.prefix ?: "group_${group_id}"
    """
    mkdir ${prefix}_bigscape
    """
}
