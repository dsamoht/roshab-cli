# dsamoht/roshab-cli: Output

## Introduction

This document describes the output produced by the pipeline.

The directories listed below will be created in the results directory after the
pipeline has finished. All paths are relative to the top-level results
directory. Results are grouped by the `group` column of the samplesheet: every
group gets its own `group_<group>/` directory.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes
data using the following steps:

- [Read QC](#read-qc) - trimming and quality assessment of the raw reads
- [Taxonomic profiling](#taxonomic-profiling) - Kraken2, Bracken and CoverM
- [Read-level cyanotoxin screening](#read-level-cyanotoxin-screening) - `--mode reads`
- [Assembly](#assembly) - `--mode assembly` / `--mode both`
- [BGC screening](#bgc-screening) - `--mode assembly` / `--mode both`
- [Figures](#figures) - per-group summary figures
- [MultiQC](#multiqc) - aggregate report describing results and QC
- [Pipeline information](#pipeline-information) - report metrics generated during the workflow execution

### Read QC

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/reads/post_qc/`
  - `*.fastq.gz`: reads after trimming and filtering with Chopper.
- `group_<group>/quality_assessment/nanoplot/raw/<sample_id>/`
  - `*.html`: NanoPlot report of the raw reads.
- `group_<group>/quality_assessment/nanoplot/post_qc/<sample_id>/`
  - `*.html`: NanoPlot report of the reads after QC.

</details>

The reads of each sample are concatenated first, then trimmed and filtered with
[Chopper](https://github.com/wdecoster/chopper) using `--chopper_headcrop`,
`--chopper_tailcrop`, `--chopper_minlength` and `--chopper_minq`.
[NanoPlot](https://github.com/wdecoster/NanoPlot) reports read length and
quality distributions before and after. `--skip_qc` skips both steps;
`--skip_nanoplot` keeps Chopper but skips the reports.

### Taxonomic profiling

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/kraken/`
  - `*.kraken`: Kraken2 taxonomic report, one per sample.
  - `*.kraken.out`: per-read Kraken2 classification, one per sample.
- `group_<group>/bracken/`
  - `*.bracken.report`: Kraken-style report with Bracken-corrected abundances.
  - `*.bracken.tsv`: Bracken abundance estimates.
  - `*.mpa`: the Bracken report in MetaPhlAn (MPA) format.
  - `*.combined.mpa`: the MPA profiles of every sample of the group, combined.
- `group_<group>/coverm/`
  - `*.coverm.tsv`: mean, trimmed mean and read count per reference genome.

</details>

Reads are segmented into windows of `--bracken_length` bases so that their
length matches the k-mer distribution Bracken was built for, then all samples
are classified in a single [Kraken2](https://ccb.jhu.edu/software/kraken2/) run
and the per-read assignments are split back out per sample, at the confidence
threshold set with `--kraken_confidence`.
[Bracken](https://ccb.jhu.edu/software/bracken/) re-estimates species-level
abundances from the resulting reports. In parallel,
[CoverM](https://github.com/wwood/CoverM) maps the QC reads against the
reference genome set given with `--genomes_db`.

### Read-level cyanotoxin screening

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/diamond/`
  - `*.diamond.tsv`: tabular `diamond blastx` alignments of the QC reads against the cyanotoxin gene database.
  - `group_<group>_cyanotoxins_evidence.tsv`: per gene, the number of alignment ranges and reads, and how many of those reads carry more than one gene of the same toxin.

</details>

Produced with `--mode reads` (the default) or `--mode both`. Alignments are
filtered at `--diamond_blastx_id` percent identity and `--diamond_min_aln_length`
amino acids.

`--long-reads` puts DIAMOND in range-culling mode, so one long read yields
several alignments along different segments. Those alignments are resolved into
non-overlapping query ranges — two alignments overlapping by at least
`--diamond_range_overlap_frac` of the shorter one compete for the same range and
only the best-scoring one is kept — and it is **ranges, not reads**, that are
counted. A read spanning `mcyA`, `mcyB` and `mcyC` therefore contributes to all
three genes rather than to one.

The evidence table also records co-location: `n_multigene_reads` and
`max_genes_on_one_read` count reads carrying more than one gene of the same
toxin, and `example_gene_order` shows the observed order and orientation
(`mcyB(+)>mcyC(+)`). Several genes of one cluster on a single molecule is much
stronger evidence than the same number of unlinked hits, because a conserved
NRPS domain can match one gene by chance but not several in sequence. Gene order
is reported rather than scored: *mcy* cluster architecture differs between
*Microcystis*, *Planktothrix* and *Anabaena*, so only strand consistency is
evaluated.

### Assembly

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/assembly/`
  - `*.fasta`: contigs, filtered to `--min_contig_length`.
  - `*.assembly_stats.tsv`: SeqKit assembly metrics.
- `group_<group>/assembly/proteins/`
  - `*.faa`: proteins predicted with Pyrodigal.

</details>

Produced with `--mode assembly` or `--mode both`. One assembly per sample, or
one per group with `--coassemble_by_group`.

### BGC screening

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/bgc/`
  - `*.bgc.tsv`: the antiSMASH, GECCO and DeepBGC calls of a sample reconciled into one table, with the per-tool coordinates of each merged region in `component_intervals`.
  - `*_bgc_summary.tsv`: per-group summary of the merged calls.
- `group_<group>/bgc/antismash/`
  - `<sample_id>_antismash/`: the complete antiSMASH output directory.
- `group_<group>/bgc/gecco/`
  - `<sample_id>_gecco/`: the complete GECCO output directory.
- `group_<group>/bgc/deepbgc/`
  - `*.deepbgc.tsv`: DeepBGC calls, with `--run_deepbgc`.
- `group_<group>/diamond_contigs/`
  - `*.diamond.tsv`: tabular `diamond blastp` alignments of the predicted proteins against the cyanotoxin gene database.
  - `group_<group>_contigs_cyanotoxins_evidence.tsv`: the contig-level counterpart of the read-level evidence table.

</details>

Two calls are treated as the same region when they overlap by at least
`--bgc_min_overlap` bases **and** by `--bgc_min_overlap_frac` of the shorter of
the two. The fraction is checked against each call already merged into the
region rather than against the region's running extent, so one long permissive
call cannot chain two distinct clusters into a single region.

Confidence is weighted by method rather than counted, because GECCO and DeepBGC
are both machine-learning models trained on overlapping MIBiG data and their
agreement is not independent evidence:

| `confidence` | Support                                    |
| ------------ | ------------------------------------------ |
| `high`       | antiSMASH and at least one other tool      |
| `medium`     | antiSMASH only                             |
| `candidate`  | two or more tools, none of them antiSMASH  |
| `low`        | a single non-antiSMASH tool                |
| `single-tool`| only one detector ran at all               |

### Figures

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/figures/`
  - `*_kraken_cyano_barplots.pdf`: cyanobacterial composition over the samples of the group.
  - `*_coverm_genome_coverage_barplots.pdf`: per-genome coverage over the samples of the group.
  - `*_cyanotoxins_heatmap.pdf`: read-level cyanotoxin gene heatmap. Every gene of the database is drawn for every sample, so a gene or a sample with no hit shows as an explicit zero.
  - `*_contigs_cyanotoxins_heatmap.pdf`: contig-level cyanotoxin gene heatmap.
  - `*_bgc_overview.pdf`: overview of the merged BGC calls.

</details>


### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `roshab-cli_software_mqc_versions.yml`.
  - Parameters used by the pipeline run: `params.json`.

</details>
