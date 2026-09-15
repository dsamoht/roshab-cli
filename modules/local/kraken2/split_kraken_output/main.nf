process SPLIT_KRAKEN_OUTPUT {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/ubuntu:22.04'
        : 'nf-core/ubuntu:22.04'}"

    input:
    tuple val(meta), path(kraken_output, stageAs: 'input/*')

    output:
    tuple val(meta), path("*.kraken.out"), emit: split

    when:
    task.ext.when == null || task.ext.when

    script:
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

    # sort on the read ID to make this published output reproducible.
    for split_file in *.kraken.out; do
        LC_ALL=C sort -k2,2 "\${split_file}" -o "\${split_file}"
    done
    """

    stub:
    def sample_ids = meta.samples ?: [meta.id]
    """
    touch ${sample_ids.collect { id -> "${id}.kraken.out" }.join(' ')}
    """
}
