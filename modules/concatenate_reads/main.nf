process CONCATENATE_READS {

    label "small"

    tag "${meta.sample_id}"

    container params.python_container

    input:
    tuple val(meta), path(in_reads)
    val(prefix)

    output:
    tuple val(meta), path('OUT/*.fastq.gz'), emit: out_reads

    script:
    def prefix_arg = prefix ? "--prefix ${prefix}" : ""
    """
    concatenate_reads.py \\
        ${prefix_arg} \\
        --fastq ${in_reads} \\
        --output ${meta.sample_id}.fastq.gz
    """
}
