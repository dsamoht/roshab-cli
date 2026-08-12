process METAMDBG {
    tag "${meta.id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/metamdbg:1.4--h3be2455_0'
        : 'quay.io/biocontainers/metamdbg:1.4--h3be2455_0'}"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.contigs.fasta"), emit: contigs, optional: true
    tuple val(meta), path("*.metamdbg.log"), emit: log, optional: true
    tuple val("${task.process}"), val('metamdbg'), eval("metaMDBG --version 2>&1 | sed -n 's/.*[Vv]ersion: *//p' | head -n 1"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    metaMDBG asm \\
        ${args} \\
        --out-dir metamdbg_out \\
        --in-ont ${reads} \\
        --threads ${task.cpus}

    # metaMDBG writes an internally polished assembly. `contigs.fasta.gz` is the
    # final output of the 1.x releases (`contigs_polished.fasta.gz` is an
    # intermediate there, but was the final name in earlier releases), so keep
    # that order and take the first one that exists.
    CONTIGS=""
    for candidate in metamdbg_out/contigs.fasta.gz \\
                     metamdbg_out/contigs_polished.fasta.gz \\
                     metamdbg_out/contigs.fasta \\
                     metamdbg_out/contigs_polished.fasta; do
        if [ -s "\$candidate" ]; then
            CONTIGS="\$candidate"
            break
        fi
    done

    if [ -z "\$CONTIGS" ]; then
        echo "metaMDBG produced no contigs for ${prefix}" >&2
    else
        case "\$CONTIGS" in
            *.gz) gunzip -c "\$CONTIGS" > ${prefix}.contigs.fasta ;;
            *)    cp "\$CONTIGS" ${prefix}.contigs.fasta ;;
        esac
    fi

    if [ -s metamdbg_out/metaMDBG.log ]; then
        cp metamdbg_out/metaMDBG.log ${prefix}.metamdbg.log
    fi
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.contigs.fasta
    touch ${prefix}.metamdbg.log
    """
}
