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
    mv *.html multiqc_roshab-cli.html
    mv *_data multiqc_roshab-cli_data
    """
}
