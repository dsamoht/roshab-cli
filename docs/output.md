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
  - `group_<group>_cyanotoxins_multigene_reads.tsv`: one row per read carrying more than one gene of the same toxin, with the gene count and the observed order and orientation.

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
is reported rather than scored: _mcy_ cluster architecture differs between
_Microcystis_, _Planktothrix_ and _Anabaena_, so only strand consistency is
evaluated.

Because the evidence table counts a multi-gene read once per gene it carries,
it cannot answer "how many distinct reads" without double counting.
`group_<group>_cyanotoxins_multigene_reads.tsv` lists those reads individually
instead, and `*_multigene_reads.pdf` (see [Figures](#figures)) plots the count
per sample and toxin. The figure only draws `class: toxin` entries of the gene
database -- the same restriction the heatmap applies -- since co-location on
an 'other' compound such as an anabaenopeptin or a cyanopeptolin is not
evidence of cyanotoxin biosynthesis; those hits stay in the TSV.

### Assembly

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/assembly/`
  - `*.fasta`: contigs, filtered to `--min_contig_length`.
  - `*.assembly_stats.tsv`: SeqKit assembly metrics.

</details>

Produced with `--mode assembly` or `--mode both`. One assembly per sample, or
one per group with `--coassemble_by_group`.

### BGC screening

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/bgc/`
  - `*_bgc_summary.tsv`: number of predicted regions per product class, one row per sample and product class of the group.
- `group_<group>/bgc/antismash/`
  - `<sample_id>_antismash/`: the complete antiSMASH output directory, including the per-region GenBank files (which carry the translated CDS of each region) and the HTML report.

</details>

antiSMASH is the only BGC caller, and its own region boundaries are taken as
the result: the group summary counts the regions of each JSON report rather
than re-deriving them. A region carrying several product classes (`nrps,t1pks`)
is counted once under each.

A sample contributes rows only for the regions it has, so one with no regions at
all is absent from the summary and the heatmap rather than present as a zero. Two
different situations look identical there: antiSMASH ran and found nothing, or the
sample assembled no contig above `--min_contig_length` and was never screened. The
second is a missing result, not a negative one. `assembly_stats` distinguishes
them, and the run log names every skipped sample.

### Figures

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/figures/`
  - `*_kraken_cyano_barplots.pdf`: cyanobacterial composition over the samples of the group.
  - `*_coverm_genome_coverage_barplots.pdf`: per-genome coverage over the samples of the group.
  - `*_cyanotoxins_heatmap.pdf`: read-level cyanotoxin gene heatmap. Every gene of the database is drawn for every sample, so a gene or a sample with no hit shows as an explicit zero.
  - `*_cyanotoxins_multigene_reads.pdf`: reads carrying more than one gene of the same toxin, counted per sample and toxin -- the strongest read-level evidence of a biosynthesis gene cluster.
  - `*_bgc_overview.pdf`: heatmap of predicted regions per product class over the samples of the group. Every screened sample is drawn, so one with no predicted region shows as a row of zeros.

A figure is never allowed to fail the run. When a group has nothing to draw -- an
index without the clades of interest, no read mapping to the genome database --
the PDF carries a page saying so instead of a blank chart, and the reason is in
the task log.

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
