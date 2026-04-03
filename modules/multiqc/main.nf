process MULTIQC {

    label "medium"

    publishDir "${params.outdir}/multiqc", mode: 'copy'

    input:
    path multiqc_files, stageAs: "?/*"

    output:
    path "*.html", emit: report
    path "*_data", emit: data

    """
    cp ${projectDir}/assets/* .
    multiqc -c ./multiqc_config.yml .
    mv *.html multiqc_${params.exp}.html
    mv *_data multiqc_${params.exp}_data
    """
}

process MULTIQC {
    
    label 'small'

    tag "${meta.group}"
    
    container params.multiqc_container

    publishDir "${params.outdir}/multiqc", mode: 'copy'

    input:
    tuple val(meta), path(multiqc_files, stageAs: "?/*")

    output:
    tuple val(meta), path("*.html"), emit: report
    tuple val(meta), path("*_data"), emit: data

    script:
    """
    cp ${projectDir}/assets/* .
    multiqc -c ./multiqc_config.yml .
    mv *.html multiqc_${params.exp}.html
    mv *_data multiqc_${params.exp}_data
    """
}
