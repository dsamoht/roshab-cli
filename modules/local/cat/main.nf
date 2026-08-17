process CAT_READS {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "docker.io/dsamoht/bio-utils:latest"

    input:
    tuple val(meta), path(reads), val(read_id_prefix)

    output:
    tuple val(meta), path("*.fastq.gz"), emit: reads
    tuple val("${task.process}"), val('python'), eval("python --version | sed 's/^Python //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    // `read_id_prefix` stamps the sample name onto every read ID so that the
    // single combined Kraken2 run can be split back out per sample afterwards.
    def prefix_arg = read_id_prefix ? "--prefix ${read_id_prefix}" : ''
    """
    concatenate_reads.py \\
        ${args} \\
        ${prefix_arg} \\
        --fastq ${reads} \\
        --output ${prefix}.fastq.gz

    mv OUT/${prefix}.fastq.gz .
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "" | gzip > ${prefix}.fastq.gz
    """
}
