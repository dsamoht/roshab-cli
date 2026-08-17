process DECOMPRESS {
    tag "${out_name}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://depot.galaxyproject.org/singularity/ubuntu:22.04'
        : 'nf-core/ubuntu:22.04'}"

    input:
    // Staged one directory down: a database installed by `--db_dir` is already
    // called `<out_name>`, and staging it in the task directory under that same
    // name would make the `ln -s` below resolve against the input itself
    path input_path, stageAs: 'input/*'
    val out_name

    output:
    path "${out_name}", emit: db

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    # 1. Already a directory: nothing to extract
    if [ -d "${input_path}" ]; then
        echo "Input is a directory. Linking..."
        ln -s "${input_path}" "${out_name}"

    # 2. Tarball: extract, dropping the macOS resource forks that `tar` on macOS
    #    adds when the archive was created there
    elif [[ "${input_path}" == *.tar.gz ]] || [[ "${input_path}" == *.tgz ]]; then
        echo "Input is an archive. Extracting..."
        mkdir tmp_extracted
        tar -xzf "${input_path}" -C tmp_extracted \\
            --exclude='._*' --exclude='__MACOSX' --exclude='.DS_Store'

        # 3. Collapse a single top-level directory so that `${out_name}` always
        #    points at the database itself rather than at its parent
        TOP_LEVEL_COUNT=\$(ls -1A tmp_extracted | wc -l)
        FIRST_ITEM=\$(ls -1A tmp_extracted | head -n 1)

        if [ "\$TOP_LEVEL_COUNT" -eq 1 ] && [ -d "tmp_extracted/\$FIRST_ITEM" ]; then
            ln -s "tmp_extracted/\$FIRST_ITEM" "${out_name}"
        else
            ln -s tmp_extracted "${out_name}"
        fi

    # 4. Anything else is a user error
    else
        echo "Error: ${input_path} is neither a directory nor a tar.gz archive." >&2
        exit 1
    fi
    """

    stub:
    """
    mkdir ${out_name}
    """
}
