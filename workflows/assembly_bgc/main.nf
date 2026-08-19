//
// Assemble the QC reads and screen the contigs for biosynthetic gene clusters
//

include { ANTISMASH                       } from '../../modules/local/antismash'
include { BIGSCAPE                        } from '../../modules/local/bigscape'
include { CAT_READS as CAT_COASSEMBLY     } from '../../modules/local/cat'
include { DECOMPRESS as PREP_ANTISMASH_DB } from '../../modules/local/decompress'
include { DECOMPRESS as PREP_DEEPBGC_DB   } from '../../modules/local/decompress'
include { DEEPBGC                         } from '../../modules/local/deepbgc'
include { DIAMOND_BLASTP                  } from '../../modules/local/diamond/blastp'
include { FLYE                            } from '../../modules/local/flye'
include { GECCO                           } from '../../modules/local/gecco'
include { MERGE_BGC                       } from '../../modules/local/merge_bgc'
include { METAMDBG                        } from '../../modules/local/metamdbg'
include { PLOT_BGC                        } from '../../modules/local/plot_bgc'
include { PLOT_GENE_DIAMOND as PLOT_GENE_DIAMOND_CONTIGS } from '../../modules/local/plot_gene_diamond'
include { PYRODIGAL                       } from '../../modules/local/pyrodigal'
include { SEQKIT_SEQ                      } from '../../modules/local/seqkit/seq'
include { SEQKIT_STATS                    } from '../../modules/local/seqkit/stats'

workflow ASSEMBLY_BGC {

    take:
    ch_qc_reads // channel: [ val(meta), path(reads) ]
    ch_genes_db // value channel: path(genes_db)

    main:

    // antiSMASH databases: directory or tarball, same handling as the other DBs
    ch_antismash_db = PREP_ANTISMASH_DB(
        channel.fromPath(params.antismash_db, checkIfExists: true),
        'antismash_db',
    ).db.first()

    //
    // One assembly per sample, or one per group when co-assembling
    //
    if (params.coassemble_by_group) {
        ch_coassembly_in = ch_qc_reads
            .map { meta, reads -> tuple(meta.group, [meta, reads]) }
            .groupTuple()
            .map { group_id, metadata_and_file ->
                def sorted_items = metadata_and_file.sort { entry -> entry[0].id }
                def files = sorted_items.collect { entry -> entry[1] }
                def meta = [id: "coassembly_${group_id}", group: group_id, coassembly: true]
                return [meta, files, '']
            }

        ch_assembly_in = CAT_COASSEMBLY(ch_coassembly_in).reads
    }
    else {
        ch_assembly_in = ch_qc_reads
    }

    //
    // Assemble
    //
    if (params.assembler == 'metamdbg') {
        METAMDBG(ch_assembly_in)
        ch_raw_contigs = METAMDBG.out.contigs
    }
    else {
        FLYE(ch_assembly_in)
        ch_raw_contigs = FLYE.out.contigs
    }

    //
    // Drop short contigs before screening, then report assembly metrics
    //
    SEQKIT_SEQ(ch_raw_contigs)
    ch_contigs = SEQKIT_SEQ.out.contigs

    SEQKIT_STATS(ch_contigs)

    //
    // Call proteins and screen them against the cyanotoxin gene database: the
    // contig-level counterpart of the read-level `diamond blastx` route
    //
    PYRODIGAL(ch_contigs)
    DIAMOND_BLASTP(PYRODIGAL.out.faa, ch_genes_db)

    //
    // BGC detection: rule-based (antiSMASH) + CRF (GECCO) + optional deep
    // learning (DeepBGC)
    //
    ANTISMASH(ch_contigs, ch_antismash_db)
    GECCO(ch_contigs)

    if (params.run_deepbgc) {
        ch_deepbgc_db = PREP_DEEPBGC_DB(
            channel.fromPath(params.deepbgc_db, checkIfExists: true),
            'deepbgc_db',
        ).db.first()

        DEEPBGC(ch_contigs, ch_deepbgc_db)
        ch_deepbgc_tsv = DEEPBGC.out.tsv
    }
    else {
        ch_deepbgc_tsv = channel.empty()
    }

    //
    // Reconcile the per-tool calls; the contigs channel is the spine so that
    // samples without any BGC hit still get an (empty) report
    //
    ch_merge_in = ch_contigs
        .join(ANTISMASH.out.json, remainder: true)
        .join(GECCO.out.clusters, remainder: true)
        .join(ch_deepbgc_tsv, remainder: true)
        .map { meta, _contigs, antismash_json, gecco_tsv, deepbgc_tsv ->
            return [meta, antismash_json ?: [], gecco_tsv ?: [], deepbgc_tsv ?: []]
        }

    MERGE_BGC(ch_merge_in)

    //
    // Group-level figures, mirroring the read-level outputs
    //
    ch_bgc_by_group = MERGE_BGC.out.tsv
        .map { meta, tsv -> tuple(meta.group, tsv) }
        .groupTuple()

    PLOT_BGC(ch_bgc_by_group)

    ch_blastp_by_group = DIAMOND_BLASTP.out.tsv
        .map { meta, tsv -> tuple(meta.group, tsv) }
        .groupTuple()

    PLOT_GENE_DIAMOND_CONTIGS(ch_blastp_by_group)

    //
    // Optional gene cluster family clustering across the samples of a group
    //
    if (params.run_bigscape) {
        ch_bigscape_in = ANTISMASH.out.regions
            .map { meta, gbks -> tuple(meta.group, gbks) }
            .groupTuple()
            .map { group_id, gbks -> tuple(group_id, gbks.flatten()) }

        BIGSCAPE(ch_bigscape_in, file(params.pfam_db, checkIfExists: true))
        ch_bigscape_results = BIGSCAPE.out.results
    }
    else {
        ch_bigscape_results = channel.empty()
    }

    emit:
    contigs           = ch_contigs                          // channel: [ val(meta), path(fasta) ]
    assembly_stats    = SEQKIT_STATS.out.tsv                // channel: [ val(meta), path(tsv) ]
    proteins          = PYRODIGAL.out.faa                   // channel: [ val(meta), path(faa) ]
    blastp_tsv        = DIAMOND_BLASTP.out.tsv              // channel: [ val(meta), path(tsv) ]
    blastp_plot       = PLOT_GENE_DIAMOND_CONTIGS.out.pdf   // channel: [ val(group_id), path(pdf) ]
    antismash_results = ANTISMASH.out.results               // channel: [ val(meta), path(dir) ]
    gecco_results     = GECCO.out.results                   // channel: [ val(meta), path(dir) ]
    deepbgc_tsv       = ch_deepbgc_tsv                      // channel: [ val(meta), path(tsv) ]
    bgc_tsv           = MERGE_BGC.out.tsv                   // channel: [ val(meta), path(tsv) ]
    bgc_plot          = PLOT_BGC.out.pdf                    // channel: [ val(group_id), path(pdf) ]
    bgc_summary       = PLOT_BGC.out.tsv                    // channel: [ val(group_id), path(tsv) ]
    bigscape_results  = ch_bigscape_results                 // channel: [ val(group_id), path(dir) ]
}
