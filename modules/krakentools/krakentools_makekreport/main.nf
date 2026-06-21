process KRAKENTOOLS_MAKEKREPORT {

    label "small"

    tag "${meta.sample_id}"

    container params.krakentools_container

    //publishDir "${params.outdir}/group_${meta.group}/kraken", mode: 'copy'

    input:
    tuple val(meta), path(kraken_stdout)
    path(db)

    output:
    tuple val(meta), path('*.kraken'), emit: kraken_report

    script:
    """
    make_kreport.py \\
        -i ${kraken_stdout} \\
        -t ${db}/ktaxonomy.tsv \\
        -o ${meta.sample_id}.kraken
    """
}
