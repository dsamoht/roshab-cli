process MERGE_BGC {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "docker.io/dsamoht/bio-utils:latest"

    input:
    tuple val(meta), path(antismash_json), path(gecco_clusters), path(deepbgc_tsv)

    output:
    tuple val(meta), path("*.bgc.tsv"), emit: tsv, optional: true
    tuple val("${task.process}"), val('python'), eval("python --version | sed 's/^Python //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def antismash_arg = antismash_json ? "--antismash ${antismash_json}" : ''
    def gecco_arg = gecco_clusters ? "--gecco ${gecco_clusters}" : ''
    def deepbgc_arg = deepbgc_tsv ? "--deepbgc ${deepbgc_tsv}" : ''
    """
    merge_bgc_calls.py \\
        ${args} \\
        --sample ${prefix} \\
        ${antismash_arg} \\
        ${gecco_arg} \\
        ${deepbgc_arg} \\
        --output ${prefix}.bgc.tsv
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.bgc.tsv
    """
}
