process INSTALL_DB {
    tag "${db_name}"
    label 'process_single'
    label 'process_long'
    label 'error_retry'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/ubuntu:22.04'
        : 'nf-core/ubuntu:22.04'}"

    input:
    tuple val(db_name), path(source)

    output:
    path "${db_name}", emit: db

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    # 1. Tarball: extract, dropping the macOS resource forks that `tar` on macOS
    #    adds when the archive was created there
    if [[ "${source}" == *.tar.gz ]] || [[ "${source}" == *.tgz ]]; then
        mkdir tmp_extracted
        tar -xzf "${source}" -C tmp_extracted \\
            --exclude='._*' --exclude='__MACOSX' --exclude='.DS_Store'

        # Collapse a single top-level directory so that `${db_name}` always holds
        # the database itself rather than its parent
        TOP_LEVEL_COUNT=\$(ls -1A tmp_extracted | wc -l)
        FIRST_ITEM=\$(ls -1A tmp_extracted | head -n 1)

        if [ "\$TOP_LEVEL_COUNT" -eq 1 ] && [ -d "tmp_extracted/\$FIRST_ITEM" ]; then
            mv "tmp_extracted/\$FIRST_ITEM" "${db_name}"
            rmdir tmp_extracted
        else
            mv tmp_extracted "${db_name}"
        fi

    # 2. Single gzipped file: decompress it into the database directory
    elif [[ "${source}" == *.gz ]]; then
        mkdir "${db_name}"
        gunzip -c "${source}" > "${db_name}/\$(basename "${source}" .gz)"

    # 3. Anything else is a plain file - the database is the file itself
    else
        mkdir "${db_name}"
        cp -L "${source}" "${db_name}/"
    fi
    """

    stub:
    """
    mkdir ${db_name}
    """
}
