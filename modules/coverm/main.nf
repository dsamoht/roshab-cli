process COVERM {

    label "medium"

    tag "${group_id}"

    container params.coverm_container

    //publishDir "${params.outdir}/group_${group_id}/coverm", mode: 'copy'

    input:
    tuple val(group_id), val(metas), path(reads)
    path genome_directory
    val db_name

    output:
    tuple val(group_id), path('*.coverm.tsv'), emit: coverm_out, optional : true

    script:
    def names = metas.collect { meta -> meta.sample_id }
    def rename_cmds = names.withIndex().collect { name, i ->
        "mv ${reads[i]} ${name}.fastq.gz"
    }.join("\n")

    """
    ${rename_cmds}
    coverm genome \\
        --single *.fastq.gz \\
        --genome-fasta-directory ${genome_directory} \\
        --mapper minimap2-ont \\
        --methods mean trimmed_mean count \\
        --min-covered-fraction 0 \\
        --output-file group_${group_id}_${db_name}.coverm.tsv \\
        --threads ${task.cpus}
    """
}
