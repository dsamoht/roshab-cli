process GECCO {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/gecco:0.11.0--pyhdfd78af_0'
        : 'quay.io/biocontainers/gecco:0.11.0--pyhdfd78af_0'}"

    input:
    tuple val(meta), path(contigs)

    output:
    tuple val(meta), path("*.gecco_clusters.tsv"), emit: clusters, optional: true
    tuple val(meta), path("${prefix}_gecco"), emit: results, optional: true
    tuple val("${task.process}"), val('gecco'), eval("gecco --version | sed 's/^gecco //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    export HOME="\$PWD"

    gecco run \\
        ${args} \\
        -g ${contigs} \\
        -o ${prefix}_gecco \\
        -j ${task.cpus}

    # GECCO names its outputs after the input file; normalise so the merge step
    # gets a predictable name. No clusters found means no TSV is written.
    for tsv in ${prefix}_gecco/*.clusters.tsv; do
        if [ -s "\$tsv" ]; then
            cp "\$tsv" ${prefix}.gecco_clusters.tsv
            break
        fi
    done
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir ${prefix}_gecco
    touch ${prefix}.gecco_clusters.tsv
    """
}
