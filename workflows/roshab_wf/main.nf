#!/usr/bin/env nextflow

include { BRACKEN                             } from '../../modules/bracken'
include { CONCATENATE_READS as CAT_INIT       } from '../../modules/concatenate_reads'
include { CONCATENATE_READS as CAT_PRE_KRAKEN } from '../../modules/concatenate_reads'
include { COVERM as COVERM_ICYATOX            } from '../../modules/coverm'
include { COVERM as COVERM_NCBI               } from '../../modules/coverm'
include { DIAMOND_BLASTX                      } from '../../modules/diamond'
include { DISPATCH                            } from '../dispatch'
include { KRAKEN                              } from '../../modules/kraken/kraken'
include { KRAKENTOOLS_COMBINEMPA              } from '../../modules/krakentools/krakentools_combinempa'
include { KRAKENTOOLS_KREPORT2MPA             } from '../../modules/krakentools/krakentools_kreport2mpa'
include { KRAKENTOOLS_MAKEKREPORT             } from '../../modules/krakentools/krakentools_makekreport'
include { LONGREAD_QC                         } from '../longreads_qc'
//include { MULTIQC                           } from '../../modules/multiqc'
include { PLOT_COVERM                         } from '../../modules/figures/taxonomy_coverm'
include { PLOT_GENE_DIAMOND                   } from '../../modules/figures/gene_diamond'
include { PLOT_KRAKEN                         } from '../../modules/figures/taxonomy_kraken'
include { SEQKIT_SLIDING                      } from '../../modules/seqkit/sliding'
include { SPLIT_STDOUT                        } from '../../modules/kraken/split'


workflow ROSHAB_WF {

    // validate and dispatch input files
    ch_input = DISPATCH()

    // concatenate reads from the same sample
    ch_cat_init_in = ch_input
        .map { meta, reads -> [ [meta, reads], meta.sample_name ] }

    ch_reads = CAT_INIT(
        ch_cat_init_in.map{it[0]},
        ch_cat_init_in.map{it[1]}
    )

    // perform QC
    ch_qc_reads = LONGREAD_QC(ch_reads).long_reads_qc

    // segment reads into illumina-like length windows for `kraken` and `bracken`
    ch_segmented_reads = SEQKIT_SLIDING(ch_qc_reads).fastq

    // group all qc reads into a single channel for `coverm`    
    coverm_ch_in = ch_qc_reads
    .map { meta, reads -> tuple(meta.group, [meta, reads]) }
    .groupTuple()
    .map { group_id, metadata_and_file ->
        
        def sorted_items = metadata_and_file.sort { it[0].sample_name }
        def metas = sorted_items.collect { it[0] }
        def files = sorted_items.collect { it[1] }
        
        return tuple(group_id, metas, files)
    }

    // concatenate all samples into a single fastq for `kraken` input
    ch_cat_pre_kraken_in = ch_segmented_reads
        .collect( {it[1]} )
        .map { files -> 
            def sorted_files = files.sort { it.name }
            return [ [[sample_name: "all"], sorted_files ], "" ] 
        }
    
    ch_kraken_in = CAT_PRE_KRAKEN(
        ch_cat_pre_kraken_in.map{it[0]},
        ch_cat_pre_kraken_in.map{it[1]}
    )
    
    // run `kraken`
    ch_kraken_out = KRAKEN(ch_kraken_in, params.kraken_db)

    // split `kraken` stdout into separate files per sample
    ch_split_kraken_stdout = SPLIT_STDOUT(ch_kraken_out.kraken_stdout)
        .transpose()
        .map { meta, file -> return [ [sample_name: file.simpleName] , file] }
    
    // give back the full metadata to the split channel by joining on sample_name
    ch_input_for_join = ch_input.map { meta, fastq -> [ meta.sample_name, meta ] }
    ch_split_for_join = ch_split_kraken_stdout
        .transpose()
        .map { meta, file -> [ file.simpleName, file ] }
    ch_kraken_stdout = ch_input_for_join
        .join(ch_split_for_join)
        .map { sample_id, full_meta, kraken_file -> 
            return [ full_meta, kraken_file ] 
        }

    // run `make_kreport.py` to generate `kraken` reports per sample
    ch_kraken_report = KRAKENTOOLS_MAKEKREPORT(ch_kraken_stdout, params.kraken_db)
    
    // run `bracken`
    ch_bracken_out = BRACKEN(ch_kraken_report, params.kraken_db)

    // run `coverm` using `icyatox` database
    // ch_coverm_ncbi_out = COVERM_NCBI(coverm_ch_in, params.genomes_db, "icyatox")

    // Convert `bracken` report to MPA format and combine MPA files per group
    ch_krakentools_kreport2mpa_out = KRAKENTOOLS_KREPORT2MPA(ch_bracken_out.report)

    ch_krakentools_combinempa_in = ch_krakentools_kreport2mpa_out
        .map { meta, file -> tuple(meta.group, [meta, file]) }
        .groupTuple()
        .map { group_id, metadata_and_file ->
            
            def sorted_items = metadata_and_file.sort { it[0].sample_name }
            def metas = sorted_items.collect { it[0] }
            def files = sorted_items.collect { it[1] }
            
            return [group_id, metas, files]
        }

    ch_combinempa2_out = KRAKENTOOLS_COMBINEMPA(ch_krakentools_combinempa_in)
    
    // Plot the `kraken + braken` results
    ch_kraken_plot_out = PLOT_KRAKEN(ch_combinempa2_out, file(params.input))
    
    // Aligning reads to cyanotoxin-related genes using `diamond`
    ch_diamond_out = DIAMOND_BLASTX(ch_qc_reads, params.genes_db)
   
    // Extract the TSV files from the `diamond` output channel and collect them into a single list
    ch_heatmaps_in = ch_diamond_out.tsv
        .map { meta, tsv_file -> tsv_file }
        .collect()

    // Plot heatmaps for all samples
    PLOT_GENE_DIAMOND(ch_heatmaps_in)

    ch_coverm_ncbi_out = COVERM_NCBI(coverm_ch_in, params.genomes_db, "ncbi")
    PLOT_COVERM(ch_coverm_ncbi_out, file(params.input))
   
    //MULTIQC(ch_multiqc_files)

}
