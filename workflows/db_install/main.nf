//
// Download the reference databases into `--db_dir`
//
// Each database is installed into its own directory under `--db_dir`, and every
// process runs with `storeDir` set to that directory: a database that is already
// installed is left alone instead of being downloaded again. Delete its
// directory to force a fresh download.
//

include { ANTISMASH_DOWNLOAD } from '../../modules/local/antismash/download'
include { DEEPBGC_DOWNLOAD   } from '../../modules/local/deepbgc/download'
include { INSTALL_DB         } from '../../modules/local/install_db'

workflow DB_INSTALL {

    main:

    def catalogue = databaseCatalogue()
    def requested = selectedDatabases()
    def db_dir = file(params.db_dir)

    log.info("Installing into ${db_dir}: ${requested.join(', ')}\n")

    def already_installed = requested.findAll { name -> file("${db_dir}/${catalogue[name].dir}").exists() }
    if (already_installed) {
        log.info("Already present, skipping: ${already_installed.join(', ')}\n")
    }

    // The antiSMASH databases ship a full Pfam release of their own, and it is
    // hmmpress-ed - which is what BiG-SCAPE wants. Installing both, don't pull a
    // second copy of Pfam: `--pfam_db` points into `antismash_db` instead.
    def reuse_antismash_pfam = 'pfam' in requested && 'antismash' in requested
    if (reuse_antismash_pfam) {
        log.info("Pfam comes with the antiSMASH databases - not downloading it a second time\n")
    }

    //
    // MODULE: Databases that are a single download - Nextflow stages the remote
    // file and `INSTALL_DB` unpacks it into `<db_dir>/<name>/`
    //
    ch_downloads = channel.fromList(
        requested
            .findAll { name -> catalogue[name].url && !(reuse_antismash_pfam && name == 'pfam') }
            .collect { name -> tuple(catalogue[name].dir, file(catalogue[name].url, checkIfExists: true)) }
    )

    INSTALL_DB(ch_downloads)
    ch_databases = INSTALL_DB.out.db

    //
    // MODULE: Databases that their own tool fetches
    //
    if ('antismash' in requested) {
        ANTISMASH_DOWNLOAD()
        ch_databases = ch_databases.mix(ANTISMASH_DOWNLOAD.out.db)
    }

    if ('deepbgc' in requested) {
        // antiSMASH and DeepBGC both fetch a (different) Pfam release from
        // ftp.ebi.ac.uk, which truncates or drops the connection when the two
        // run against it at once. Wait for antiSMASH rather than compete with it.
        ch_ready = 'antismash' in requested
            ? ANTISMASH_DOWNLOAD.out.db.map { _db -> 'antismash' }
            : channel.value('')

        DEEPBGC_DOWNLOAD(ch_ready)
        ch_databases = ch_databases.mix(DEEPBGC_DOWNLOAD.out.db)
    }

    // Nothing consumes the installed databases - the workflow ends by reporting
    // the parameter values to use, once every database is in place
    ch_databases
        .collect()
        .subscribe { _databases -> log.info(installSummary(requested)) }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// The databases `--install_databases` accepts. `dir` is the directory created
// under `--db_dir`, `param` is the pipeline parameter the installed database is
// passed to, `url` is the download (null when the tool fetches its own database)
// and `file` marks the databases that are a single file rather than a directory.
//
def databaseCatalogue() {
    return [
        kraken: [dir: 'kraken_db', param: 'kraken_db', url: params.kraken_db_url],
        genomes: [dir: 'genomes_db', param: 'genomes_db', url: params.genomes_db_url],
        genes: [dir: 'genes_db', param: 'genes_db', url: params.genes_db_url, file: true],
        antismash: [dir: 'antismash_db', param: 'antismash_db', url: null],
        deepbgc: [dir: 'deepbgc_db', param: 'deepbgc_db', url: null],
        pfam: [dir: 'pfam_db', param: 'pfam_db', url: params.pfam_db_url, file: true],
    ]
}

//
// The databases asked for with `--install_databases`, in catalogue order
//
def selectedDatabases() {
    def catalogue = databaseCatalogue()
    def valid = "Valid names are `all` or a comma-separated list of: ${catalogue.keySet().join(', ')}."

    def requested = params.install_databases
        .toString()
        .tokenize(',')
        .collect { name -> name.trim() }
        .findAll { name -> name }

    if (!requested) {
        error("`--install_databases` must name at least one database. ${valid}")
    }
    if ('all' in requested) {
        return catalogue.keySet() as List
    }

    def unknown = requested.findAll { name -> !catalogue.containsKey(name) }
    if (unknown) {
        error("Unknown database name(s) in `--install_databases`: ${unknown.join(', ')}. ${valid}")
    }

    return catalogue.keySet().findAll { name -> name in requested }
}

//
// Where a database ends up: the directory itself, or the file inside it for the
// databases that are a single file
//
def installedPath(name) {
    def entry = databaseCatalogue()[name]
    def db_path = "${file(params.db_dir)}/${entry.dir}"

    if (!entry.file) {
        return db_path
    }

    // Pfam is not downloaded separately when the antiSMASH databases, which
    // carry their own release of it, are installed as well
    if (name == 'pfam' && !file(db_path).exists()) {
        def antismash_pfam = files("${file(params.db_dir)}/antismash_db/pfam/*/Pfam-A.hmm")
        if (antismash_pfam) {
            return antismash_pfam.sort().last()
        }
    }

    // `INSTALL_DB` keeps the name of the downloaded file, minus the `.gz` suffix
    return "${db_path}/${entry.url.tokenize('/').last().replaceAll(/\.gz$/, '')}"
}

//
// The parameters to pass to a pipeline run, one per installed database
//
def installSummary(requested) {
    def width = requested.collect { name -> databaseCatalogue()[name].param.length() }.max()
    def lines = requested.collect { name ->
        "    --${databaseCatalogue()[name].param.padRight(width)}  ${installedPath(name)}"
    }
    return "Databases installed. Run the pipeline with:\n\n${lines.join('\n')}\n"
}
