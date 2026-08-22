process BIGSCAPE {
    tag "${group_id}"
    label 'process_medium'
    label 'error_ignore'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/bigscape:2.0.3--pyhdfd78af_0'
        : 'quay.io/biocontainers/bigscape:2.0.3--pyhdfd78af_0'}"

    input:
    tuple val(group_id), path(antismash_dirs)
    path pfam_db

    output:
    tuple val(group_id), path("${prefix}_bigscape"), emit: results, optional: true
    tuple val("${task.process}"), val('bigscape'), eval("bigscape --version | sed 's/^bigscape //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "group_${group_id}"
    // antiSMASH names its region files after the contig, so two samples of the same
    // group collide on e.g. `contig_1.region001.gbk`. The whole antiSMASH directory is
    // staged instead of the bare region files -- `<sample>_antismash` is unique -- and
    // the regions are copied out under a sample-prefixed name.
    """
    export HOME="\$PWD"

    mkdir -p gbk_input
    for dir in ${antismash_dirs}; do
        sample=\$(basename "\${dir}" _antismash)
        for gbk in "\${dir}"/*.region*.gbk; do
            [ -e "\${gbk}" ] || continue
            cp "\${gbk}" "gbk_input/\${sample}_\$(basename "\${gbk}")"
        done
    done

    if ! ls gbk_input/*.gbk > /dev/null 2>&1; then
        echo "No antiSMASH region found for group ${group_id} -- skipping BiG-SCAPE" >&2
        exit 0
    fi

    bigscape cluster \\
        ${args} \\
        -i gbk_input \\
        -o ${prefix}_bigscape \\
        -p ${pfam_db} \\
        --cores ${task.cpus}
    """

    stub:
    prefix = task.ext.prefix ?: "group_${group_id}"
    """
    mkdir ${prefix}_bigscape
    """
}
