process SPLIT_STDOUT {

    label "small"

    tag "${meta.sample_id}"

    container params.coreutils_container

    input:
    tuple val(meta), path(kraken_stdout)

    output:
    tuple val(meta), path('*.kraken.out'), emit: split_kraken_stdout

    script:
    """
    mkdir -p OUT
    awk '{ split(\$2, arr, "_"); print >> ("OUT/" arr[1] ".kraken.out") }' ${kraken_stdout}
    mv OUT/*.kraken.out .
    """
}
