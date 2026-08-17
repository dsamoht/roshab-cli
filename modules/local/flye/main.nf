process FLYE {
    tag "${meta.id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/flye:2.9.6--py313h7fbb527_1'
        : 'quay.io/biocontainers/flye:2.9.6--py313h7fbb527_1'}"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.contigs.fasta"), emit: contigs, optional: true
    tuple val(meta), path("*.assembly_info.txt"), emit: info, optional: true
    tuple val("${task.process}"), val('flye'), eval('flye --version'), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    flye \\
        ${args} \\
        ${reads} \\
        --out-dir flye_out \\
        --threads ${task.cpus}

    # A metagenome with no assembled contig is a valid outcome, so emit nothing
    # rather than failing the whole run.
    if [ -s flye_out/assembly.fasta ]; then
        mv flye_out/assembly.fasta ${prefix}.contigs.fasta
        mv flye_out/assembly_info.txt ${prefix}.assembly_info.txt
    else
        echo "flye produced no assembly for ${prefix}" >&2
    fi
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.contigs.fasta
    touch ${prefix}.assembly_info.txt
    """
}
