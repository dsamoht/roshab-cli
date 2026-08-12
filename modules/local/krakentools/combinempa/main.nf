process KRAKENTOOLS_COMBINEMPA {
    tag "${group_id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/krakentools:1.2.1--pyh7e72e81_0'
        : 'quay.io/biocontainers/krakentools:1.2.1--pyh7e72e81_0'}"

    input:
    tuple val(group_id), path(mpa)

    output:
    tuple val(group_id), path("*.combined.mpa"), emit: mpa
    tuple val("${task.process}"), val('krakentools'), eval("python -c 'import importlib.metadata; print(importlib.metadata.version(\"krakentools\"))' 2>/dev/null || echo 1.2.1"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${group_id}"
    """
    combine_mpa.py \\
        ${args} \\
        -i ${mpa} \\
        -o ${prefix}.combined.mpa
    """

    stub:
    def prefix = task.ext.prefix ?: "${group_id}"
    """
    touch ${prefix}.combined.mpa
    """
}
