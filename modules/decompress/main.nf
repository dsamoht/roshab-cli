process DECOMPRESS {

    tag "${input_path.name}"

    input:
    path input_path
    val out_name

    output:
    path "${out_name}", emit: dir

    script:
    """
    # 1. Check if the staged input is already a directory
    if [ -d "${input_path}" ]; then
        echo "Input is a directory. Linking..."
        ln -s "${input_path}" "${out_name}"

    # 2. Check if the input is a tarball
    elif [[ "${input_path}" == *.tar.gz ]] || [[ "${input_path}" == *.tgz ]]; then
        echo "Input is an archive. Extracting..."
        mkdir tmp_extracted
        tar -xzf "${input_path}" -C tmp_extracted \
        --exclude='._*' --exclude='__MACOSX' --exclude='.DS_Store'
        
        # 3. Smart extraction handling
        TOP_LEVEL_COUNT=\$(ls -1A tmp_extracted | wc -l)
        FIRST_ITEM=\$(ls -1A tmp_extracted | head -n 1)
        
        if [ "\$TOP_LEVEL_COUNT" -eq 1 ] && [ -d "tmp_extracted/\$FIRST_ITEM" ]; then
            ln -s "tmp_extracted/\$FIRST_ITEM" "${out_name}"
        else
            ln -s tmp_extracted "${out_name}"
        fi

    # 4. Fail gracefully if it's an unrecognized file type
    else
        echo "Error: ${input_path} is neither a directory nor a tar.gz archive." >&2
        exit 1
    fi
    """
}
