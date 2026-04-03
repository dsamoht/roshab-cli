process SEQKIT_SLIDING {
    
    label "medium"
   
    tag "${meta.sample_name}"

    container params.seqkit_container

    input:
    tuple val(meta), path(fastq)

    output:
    tuple val(meta), path("*.fastq"), emit: fastq
    path "versions.yml"             , emit: versions

    script:
    """
    seqkit \\
        sliding \\
        ${fastq} \\
        --step ${params.bracken_length} \\
        --window ${params.bracken_length} \\
        --threads ${task.cpus} \\
        -o ${meta.sample_name}.${params.bracken_length}bp.fastq

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqkit: \$( seqkit | sed '3!d; s/Version: //' )
    END_VERSIONS
    """
}
