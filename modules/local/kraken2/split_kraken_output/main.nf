process SPLIT_KRAKEN_OUTPUT {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/ubuntu:22.04'
        : 'nf-core/ubuntu:22.04'}"

    input:
    // Staged in a subdirectory: the per-sample outputs land in the task directory
    // under names that Kraken2 derived from the same sample set, so an input file
    // sitting next to them could shadow one of the outputs
    tuple val(meta), path(kraken_output, stageAs: 'input/*')

    output:
    tuple val(meta), path("*.kraken.out"), emit: split

    when:
    task.ext.when == null || task.ext.when

    script:
    // All the samples are classified in a single Kraken2 run, so `CAT_READS` stamped
    // every read ID with `<sample>_`. Split the classification output back out into
    // one file per sample by matching that stamp against the known sample names:
    // splitting the read ID on "_" would truncate any sample name that contains one.
    // The longest match wins, so a sample name that is a prefix of another one still
    // sends its reads to the right file.
    def sample_ids = meta.samples ?: [meta.id]
    """
    awk -v samples='${sample_ids.join(' ')}' '
        BEGIN { n = split(samples, sample_list, " ") }
        {
            match_id = ""
            for (i = 1; i <= n; i++) {
                if (index(\$2, sample_list[i] "_") == 1 && length(sample_list[i]) > length(match_id)) {
                    match_id = sample_list[i]
                }
            }
            if (match_id == "") {
                print "ERROR: read \\"" \$2 "\\" does not carry any known sample name" > "/dev/stderr"
                exit 1
            }
            print >> (match_id ".kraken.out")
        }
    ' ${kraken_output}
    """

    stub:
    // `meta.samples` lists the samples that went into the combined run: the stub
    // cannot recover them from the (empty) upstream stub output
    def sample_ids = meta.samples ?: [meta.id]
    """
    touch ${sample_ids.collect { id -> "${id}.kraken.out" }.join(' ')}
    """
}
