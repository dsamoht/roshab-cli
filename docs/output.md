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
and the per-read assignments are split back out per sample.
[Bracken](https://ccb.jhu.edu/software/bracken/) re-estimates species-level
abundances from the resulting reports. In parallel,
[CoverM](https://github.com/wwood/CoverM) maps the QC reads against the
reference genome set given with `--genomes_db`.

### Read-level cyanotoxin screening

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/diamond/`
  - `*.diamond.tsv`: tabular `diamond blastx` alignments of the QC reads against the cyanotoxin gene database.

</details>

Produced with `--mode reads` (the default) or `--mode both`. Alignments are
filtered at `--diamond_blastx_id` percent identity.

### Assembly

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/assembly/`
  - `*.fasta`: contigs, polished if Medaka ran, filtered to `--min_contig_length`.
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
  - `*.bgc.tsv`: the antiSMASH, GECCO and DeepBGC calls of a sample reconciled into one table. Regions supported by at least two tools are labelled `high` confidence.
  - `*_bgc_summary.tsv`: per-group summary of the merged calls.
- `group_<group>/bgc/antismash/`
  - `<sample_id>_antismash/`: the complete antiSMASH output directory.
- `group_<group>/bgc/gecco/`
  - `<sample_id>_gecco/`: the complete GECCO output directory.
- `group_<group>/bgc/deepbgc/`
  - `*.deepbgc.tsv`: DeepBGC calls, with `--run_deepbgc`.
- `group_<group>/bgc/bigscape/`
  - `group_<group>_bigscape/`: gene cluster families, with `--run_bigscape`.
- `group_<group>/diamond_contigs/`
  - `*.diamond.tsv`: tabular `diamond blastp` alignments of the predicted proteins against the cyanotoxin gene database.

</details>

Two calls are treated as the same region when they overlap by at least
`--bgc_min_overlap` bases.

### Figures

<details markdown="1">
<summary>Output files</summary>

- `group_<group>/figures/`
  - `*_kraken_cyano_barplots.pdf`: cyanobacterial composition over the samples of the group.
  - `*_coverm_genome_coverage_barplots.pdf`: per-genome coverage over the samples of the group.
  - `*_cyanotoxins_heatmap.pdf`: read-level cyanotoxin gene heatmap.
  - `*_contigs_cyanotoxins_heatmap.pdf`: contig-level cyanotoxin gene heatmap.
  - `*_bgc_overview.pdf`: overview of the merged BGC calls.

</details>

The figures are drawn per group, using the `info` and `date` columns of the
samplesheet as labels. These steps use `errorStrategy 'ignore'`: a figure that
cannot be drawn does not fail the run.

### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single
HTML report summarising all samples in your project. Most of the pipeline QC
results are visualised in the report and further statistics are available in the
report data directory.

Results generated by MultiQC collate pipeline QC from supported tools e.g.
NanoPlot and Kraken2. The pipeline has special steps which also allow the
software versions to be reported in the MultiQC output for future traceability.
For more information about how to use MultiQC reports, see
<http://multiqc.info>.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `roshab-cli_software_mqc_versions.yml`.
  - Parameters used by the pipeline run: `params.json`.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent
functionality for generating various reports relevant to the running and
execution of the pipeline. This will allow you to troubleshoot errors with the
running of the pipeline, and also provide you with other information such as
launch commands, run times and resource usage.
