process CHOPPER {

    label "medium"
   
    tag "${meta.sample_name}"

    container params.chopper_container

    publishDir "${params.outdir}/group_${meta.group}/reads_qc/chopper/", mode: "copy"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.choppered.fastq.gz"), emit: fastq
    path "versions.yml"                          , emit: versions

    script:
    """
    zcat ${reads} \
        | chopper --headcrop ${params.chopper_headcrop} --threads ${task.cpus} \
        | chopper --tailcrop ${params.chopper_tailcrop} --threads ${task.cpus} \
        | chopper -l ${params.chopper_minlength} --threads ${task.cpus} \
        | chopper -q ${params.chopper_minq} --threads ${task.cpus} \
        | gzip > ${meta.sample_name}.choppered.fastq.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        chopper: \$(chopper --version 2>&1 | cut -d ' ' -f 2)
    END_VERSIONS
    """
}
