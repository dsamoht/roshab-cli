//
// Download the reference databases into `--db_dir`
//
// `--mode` decides what gets installed, the same flag that decides which
// screening route a run takes: every run needs the Kraken2 index and the genome
// database, and the assembly routes need the antiSMASH databases on top. Each
// database is installed into its own subdirectory of `--db_dir`, and every
// process runs with `storeDir` set to that directory: a database that is already
// installed is left alone instead of being downloaded again. Delete its
// directory to force a fresh download.
//

include { ANTISMASH_DOWNLOAD } from '../../modules/local/antismash/download'
include { INSTALL_DB         } from '../../modules/local/install_db'

workflow DB_INSTALL {

    main:

    // This route skips `PIPELINE_INITIALISATION`, so there is no schema
    // validation behind it and the two flags it reads are checked here.
    if (!params.db_dir) {
        error("`--install_databases` needs `--db_dir <PATH>`, the directory to install into.")
    }
    if (!(params.mode in ['reads', 'assembly', 'both'])) {
        error("`--mode` must be one of `reads`, `assembly` or `both`, not `${params.mode}`.")
    }

    def db_dir = file(params.db_dir)
    def with_antismash = params.mode in ['assembly', 'both']

    // Databases that are a single download, as `[ subdirectory, url ]`
    def downloads = [
        ['kraken_db', params.kraken_db_url],
        ['genomes_db', params.genomes_db_url],
    ]

    def installed = downloads.collect { name, _url -> name } + (with_antismash ? ['antismash_db'] : [])

    log.info("Installing into ${db_dir}: ${installed.join(', ')}\n")

    def already_present = installed.findAll { name -> file("${db_dir}/${name}").exists() }
    if (already_present) {
        log.info("Already present, skipping: ${already_present.join(', ')}\n")
    }
    if (!with_antismash) {
        log.info("Add `--mode both` to also install the antiSMASH databases, which the assembly route needs.\n")
    }

    //
    // MODULE: Nextflow stages the remote file and `INSTALL_DB` unpacks it into
    // `<db_dir>/<name>/`
    //
    INSTALL_DB(
        channel.fromList(downloads.collect { name, url -> tuple(name, file(url, checkIfExists: true)) })
    )
    ch_databases = INSTALL_DB.out.db

    //
    // MODULE: antiSMASH fetches its own databases
    //
    if (with_antismash) {
        ANTISMASH_DOWNLOAD()
        ch_databases = ch_databases.mix(ANTISMASH_DOWNLOAD.out.db)
    }

    // Nothing consumes the installed databases - the workflow ends by printing
    // the single flag a run needs, once every database is in place
    ch_databases
        .collect()
        .subscribe { _databases ->
            log.info("Databases installed. Run the pipeline with:\n\n    --db_dir ${db_dir}\n")
        }
}
