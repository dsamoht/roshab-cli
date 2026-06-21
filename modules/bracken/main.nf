process BRACKEN {
    
    label "medium"

    tag "${meta.sample_id}"
    
    container params.bracken_container

    //publishDir "${params.outdir}/group_${meta.group}/bracken", mode: 'copy'

    input:
    tuple val(meta), path(kraken_report)
    path database

    output:
    tuple val(meta), path("*.bracken.tsv")    , emit: bracken_tsv
    tuple val(meta), path("*.bracken.report") , emit: report
    path "versions.yml", emit: versions

    script:
    """
    bracken \\
        -r ${params.bracken_length} \\
        -d ${database} \\
        -i ${kraken_report} \\
        -l S \\
        -o ${meta.sample_id}.bracken.tsv \\
        -w ${meta.sample_id}.bracken.report

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bracken: \$(echo \$(bracken -v | cut -f2 -d"v"))
    END_VERSIONS
    """
}
