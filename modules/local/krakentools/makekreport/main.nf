process KRAKENTOOLS_MAKEKREPORT {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/krakentools:1.2.1--pyh7e72e81_0'
        : 'quay.io/biocontainers/krakentools:1.2.1--pyh7e72e81_0'}"

    input:
    tuple val(meta), path(kraken_output)
    path db

    output:
    tuple val(meta), path("*.kraken"), emit: report
    tuple val("${task.process}"), val('krakentools'), eval("python -c 'import importlib.metadata; print(importlib.metadata.version(\"krakentools\"))' 2>/dev/null || echo 1.2.1"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    make_kreport.py \\
        ${args} \\
        -i ${kraken_output} \\
        -t ${db}/ktaxonomy.tsv \\
        -o ${prefix}.kraken
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.kraken
    """
}
