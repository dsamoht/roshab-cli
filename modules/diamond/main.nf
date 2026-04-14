process DIAMOND_BLASTX {

    label 'medium'

    tag "${meta.sample_name}"

    container params.diamond_container

    publishDir "${params.outdir}/group_${meta.group}/diamond", mode: 'copy'

    input:
    tuple val(meta), path(reads)
    path(db_file)

    output:
    tuple val(meta), path("*.diamond.tsv"), emit: tsv, optional: true
    path "versions.yml"                   , emit: versions

    script:
    def sample_name = meta.sample_name
    """
    diamond blastx \\
        --db ${db_file} \\
        --query ${reads} \\
        --out ${sample_name}.diamond.tsv \\
        --outfmt 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen slen \\
        --header \\
        --threads ${task.cpus} \\
        --long-reads \\
        --sensitive \\
        --id 70

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        diamond: \$(diamond --version 2>&1 | cut -d ' ' -f 3)
    END_VERSIONS
    """
}
