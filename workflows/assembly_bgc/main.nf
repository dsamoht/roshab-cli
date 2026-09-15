//
// Assemble the QC reads and screen the contigs for biosynthetic gene clusters
//

include { ANTISMASH                       } from '../../modules/local/antismash'
include { CAT_READS as CAT_COASSEMBLY     } from '../../modules/local/cat'
include { DECOMPRESS as PREP_ANTISMASH_DB } from '../../modules/local/decompress'
include { FLYE                            } from '../../modules/local/flye'
include { METAMDBG                        } from '../../modules/local/metamdbg'
include { PLOT_BGC                        } from '../../modules/local/plot_bgc'
include { SEQKIT_SEQ                      } from '../../modules/local/seqkit/seq'
include { SEQKIT_STATS                    } from '../../modules/local/seqkit/stats'

include { databasePath                     } from '../../subworkflows/local/pipeline_initialisation'

workflow ASSEMBLY_BGC {

    take:
    ch_qc_reads // channel: [ val(meta), path(reads) ]

    main:

    // antiSMASH databases: `--db_dir/antismash_db` unless `--antismash_db` names
    // another one; directory or tarball, same handling as the other DBs
    ch_antismash_db = PREP_ANTISMASH_DB(
        channel.fromPath(databasePath(params.antismash_db, 'antismash_db')),
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

    // Assembly metrics are worth having even for a sample that assembled nothing:
    // an empty row is the evidence that it was tried and came up empty.
    SEQKIT_STATS(SEQKIT_SEQ.out.contigs)

    // A sample too shallow to assemble a single contig above `--min_contig_length`
    // leaves an empty FASTA. There is nothing to screen in it, and handing an empty
    // assembly to antiSMASH risks failing the whole run over it, so drop those here
    // and name them in the log: the rest of the batch still finishes. Such a sample
    // is MISSING, not negative -- it carries no contig-level evidence either way --
    // so exclude it when scoring the read-level route against these calls rather
    // than counting it as "no BGCs".
    ch_contigs = SEQKIT_SEQ.out.contigs.filter { meta, contigs ->
        def has_contigs = contigs.size() > 0
        if (!has_contigs) {
            log.warn("${meta.id}: no contigs >= ${params.min_contig_length} bp, skipping contig-level screening")
        }
        return has_contigs
    }

    //
    // BGC detection: rule-based, with antiSMASH's own region boundaries taken as
    // the result. `PLOT_BGC` reads these JSON reports directly; a sample with no
    // regions still has a report, it simply contributes no rows to the figure.
    //
    ANTISMASH(ch_contigs, ch_antismash_db)

    //
    // Group-level figure: one heatmap of regions per product class over the group
    //
    ch_bgc_by_group = ANTISMASH.out.json
        .map { meta, json -> tuple(meta.group, [meta, json]) }
        .groupTuple()
        .map { group_id, metadata_and_file ->
            def sorted_items = metadata_and_file.sort { entry -> entry[0].id }
            return tuple(group_id, sorted_items.collect { entry -> entry[1] })
        }

    PLOT_BGC(ch_bgc_by_group)

    emit:
    contigs           = ch_contigs                          // channel: [ val(meta), path(fasta) ]
    assembly_stats    = SEQKIT_STATS.out.tsv                // channel: [ val(meta), path(tsv) ]
    antismash_results = ANTISMASH.out.results               // channel: [ val(meta), path(dir) ]
    bgc_plot          = PLOT_BGC.out.pdf                    // channel: [ val(group_id), path(pdf) ]
    bgc_summary       = PLOT_BGC.out.tsv                    // channel: [ val(group_id), path(tsv) ]
}
