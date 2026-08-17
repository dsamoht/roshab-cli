process ANTISMASH_DOWNLOAD {
    tag "antismash_db"
    label 'process_single'
    label 'process_long'
    label 'error_retry'

    conda "${moduleDir}/environment.yml"
    // Not the biocontainer: `download-antismash-databases` finishes by pressing
    // antiSMASH's own profile HMMs inside the installed Python package, which the
    // image ships read-only and the container does not run as root. The nf-core
    // image is the same conda recipe with that data already prepared at build time
    container "quay.io/nf-core/antismash:8.0.1--pyhdfd78af_0"

    // No `versions` topic: `storeDir` only accepts `val` and `path` outputs, and
    // nothing collects software versions on a database installation run anyway
    output:
    path "antismash_db", emit: db

    when:
    task.ext.when == null || task.ext.when

    script:
    args = task.ext.args ?: ''
    """
    export HOME="\$PWD"
    export MPLCONFIGDIR="\$PWD/.mplconfig"

    mkdir -p antismash_db

    download-antismash-databases \\
        ${args} \\
        --database-dir antismash_db
    """

    stub:
    """
    mkdir antismash_db
    """
}
