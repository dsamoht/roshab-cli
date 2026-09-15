process PLOT_GENE_DIAMOND {
    tag "${group_id}"
    label 'process_single'
    label 'error_ignore'

    conda "${moduleDir}/environment.yml"
    container "docker.io/dsamoht/bio-utils@sha256:f0cad0d32d8d8fac7bb971736f158200cf19b4817dd796bd9d76240a054bacf2"

    input:
    tuple val(group_id), path(diamond_tsvs)
    path genes_db

    output:
    tuple val(group_id), path("*_heatmap.pdf"), emit: pdf, optional: true
    tuple val(group_id), path("*_evidence.tsv"), emit: tsv, optional: true
    tuple val(group_id), path("*_multigene_reads.pdf"), emit: multigene_pdf, optional: true
    tuple val(group_id), path("*_multigene_reads.tsv"), emit: multigene_tsv, optional: true
    tuple val("${task.process}"), val('python'), eval("python --version | sed 's/^Python //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "group_${group_id}_cyanotoxins"
    """
    export MPLCONFIGDIR="\$PWD/.mplconfig"

    plot_gene_diamond.py \\
        ${args} \\
        --input ${diamond_tsvs} \\
        --genes-db ${genes_db} \\
        --output ${prefix}_heatmap.pdf \\
        --evidence ${prefix}_evidence.tsv \\
        --multigene-output ${prefix}_multigene_reads.pdf \\
        --multigene-reads ${prefix}_multigene_reads.tsv
    """

    stub:
    def prefix = task.ext.prefix ?: "group_${group_id}_cyanotoxins"
    """
    touch ${prefix}_heatmap.pdf
    touch ${prefix}_evidence.tsv
    touch ${prefix}_multigene_reads.pdf
    touch ${prefix}_multigene_reads.tsv
    """
}
