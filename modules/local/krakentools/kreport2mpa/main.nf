process KRAKENTOOLS_KREPORT2MPA {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/krakentools:1.2.1--pyh7e72e81_0'
        : 'quay.io/biocontainers/krakentools:1.2.1--pyh7e72e81_0'}"

    input:
    tuple val(meta), path(report)

    output:
    tuple val(meta), path("*.mpa"), emit: mpa
    tuple val("${task.process}"), val('krakentools'), eval("python -c 'import importlib.metadata; print(importlib.metadata.version(\"krakentools\"))' 2>/dev/null || echo 1.2.1"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    // `kreport2mpa.py` names the MPA rows after the input file, so stage the
    // report under the sample name before converting.
    """
    cp ${report} ${prefix}
    kreport2mpa.py \\
        ${args} \\
        -r ${prefix} \\
        -o ${prefix}.mpa
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.mpa
    """
}
