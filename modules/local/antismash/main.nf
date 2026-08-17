process ANTISMASH {
    tag "${meta.id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    // Same image as `ANTISMASH_DOWNLOAD`: antiSMASH re-checks its packaged profile
    // HMMs on every run and rebuilds them when they are missing, which the
    // biocontainer cannot do as a non-root user. See that module for the details
    container "quay.io/nf-core/antismash:8.0.1--pyhdfd78af_0"

    input:
    tuple val(meta), path(contigs)
    path db

    output:
    tuple val(meta), path("${prefix}_antismash/${prefix}.json"), emit: json, optional: true
    tuple val(meta), path("${prefix}_antismash/*.region*.gbk"), emit: regions, optional: true
    tuple val(meta), path("${prefix}_antismash"), emit: results, optional: true
    tuple val("${task.process}"), val('antismash'), eval("antismash --version | sed 's/^antiSMASH //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    export HOME="\$PWD"
    export MPLCONFIGDIR="\$PWD/.mplconfig"

    antismash \\
        ${args} \\
        --databases ${db} \\
        --output-dir ${prefix}_antismash \\
        --output-basename ${prefix} \\
        --cpus ${task.cpus} \\
        ${contigs}
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir ${prefix}_antismash
    touch ${prefix}_antismash/${prefix}.json
    """
}
