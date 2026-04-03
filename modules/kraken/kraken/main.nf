process KRAKEN {

    label "large"

    tag "${meta.sample_name}"

    container params.kraken_container

    input:
    tuple val(meta), path(reads)
    path(db)

    output:
    tuple val(meta), path('*.kraken'), emit: kraken_report
    tuple val(meta), path('*.kraken.out'), emit: kraken_stdout

    script:
    def sample_name = meta.sample_name
    """
    kraken2 \\
        --db ${db} \\
        --report ${sample_name}.kraken \\
        --threads ${task.cpus} \\
        ${reads} \\
        > ${sample_name}.kraken.out
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        kraken2: \$(echo \$(kraken2 --version 2>&1) | sed 's/^.*Kraken version //; s/ .*\$//')
    END_VERSIONS
    """
}
