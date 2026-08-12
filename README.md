# dsamoht/roshab-cli

[![GitHub Actions CI Status](https://github.com/dsamoht/roshab-cli/actions/workflows/nf-test.yml/badge.svg)](https://github.com/dsamoht/roshab-cli/actions/workflows/nf-test.yml)
[![GitHub Actions Linting Status](https://github.com/dsamoht/roshab-cli/actions/workflows/linting.yml/badge.svg)](https://github.com/dsamoht/roshab-cli/actions/workflows/linting.yml)
[![nf-test](https://img.shields.io/badge/unit_tests-nf--test-337ab7.svg)](https://www.nf-test.com)

[![Nextflow](https://img.shields.io/badge/version-%E2%89%A525.10.4-green?style=flat&logo=nextflow&logoColor=white&color=%230DC09D&link=https%3A%2F%2Fnextflow.io)](https://www.nextflow.io/)
[![nf-core template version](https://img.shields.io/badge/nf--core_template-4.1.0-green?style=flat&logo=nfcore&logoColor=white&color=%2324B064&link=https%3A%2F%2Fnf-co.re)](https://github.com/nf-core/tools/releases/tag/4.1.0)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)

```
                _           _                _ _
  _ __ ___  ___| |__   __ _| |__         ___| (_)
 | '__/ _ \/ __| '_ \ / _` | '_ \ _____ / __| | |
 | | | (_) \__ \ | | | (_| | |_) |_____| (__| | |
 |_|  \___/|___/_| |_|\__,_|_.__/       \___|_|_|
```

## Introduction

**dsamoht/roshab-cli** is a bioinformatics pipeline that assigns taxonomy to
Oxford Nanopore reads from environmental water samples and evaluates their
cyanotoxin biosynthesis potential.

Taxonomic profiling always runs. The biosynthesis potential is evaluated through
one of two routes, selected with `--mode`:

| `--mode`          | What it does                                                            | Cost               |
| ----------------- | ----------------------------------------------------------------------- | ------------------ |
| `reads` (default) | `diamond blastx` of the QC reads against the cyanotoxin gene database   | minutes            |
| `assembly`        | assembly, then biosynthetic gene cluster (BGC) screening of the contigs | hours, high memory |
| `both`            | both routes on the same reads                                           |                    |

Figures and BiG-SCAPE are computed per `group`; every other step is per sample.

### Pipeline summary

**Always:**

1. Concatenate the reads of each sample ([`biopython`](https://biopython.org/))
2. Read QC ([`NanoPlot`](https://github.com/wdecoster/NanoPlot), [`Chopper`](https://github.com/wdecoster/chopper)) — skippable with `--skip_qc`
3. Segment reads into Bracken-compatible windows ([`SeqKit`](https://bioinf.shenwei.me/seqkit/))
4. Taxonomic classification ([`Kraken2`](https://ccb.jhu.edu/software/kraken2/)) and abundance re-estimation ([`Bracken`](https://ccb.jhu.edu/software/bracken/), [`KrakenTools`](https://github.com/jenniferlu717/KrakenTools))
5. Per-genome coverage against a reference genome set ([`CoverM`](https://github.com/wwood/CoverM))
6. Per-group taxonomy and coverage figures
7. Report generation ([`MultiQC`](http://multiqc.info/))

**`--mode reads` (default):**

8. Align the QC reads to the cyanotoxin gene database ([`DIAMOND`](https://github.com/bbuchfink/diamond)) and draw a per-group heatmap

**`--mode assembly`:**

8. Assemble ([`metaFlye`](https://github.com/mikolmogorov/Flye) or [`metaMDBG`](https://github.com/GaetanBenoitDev/metaMDBG)), optionally polish ([`Medaka`](https://github.com/nanoporetech/medaka)), filter short contigs and report assembly metrics ([`SeqKit`](https://bioinf.shenwei.me/seqkit/))
9. Predict proteins ([`Pyrodigal`](https://github.com/althonos/pyrodigal)) and screen them against the cyanotoxin gene database ([`DIAMOND`](https://github.com/bbuchfink/diamond))
10. BGC detection ([`antiSMASH`](https://antismash.secondarymetabolites.org), [`GECCO`](https://gecco.embl.de), optionally [`DeepBGC`](https://github.com/Merck/deepbgc)), reconciled into one table per sample where regions supported by at least two tools are labelled `high` confidence
11. Optionally cluster the antiSMASH regions of a group into gene cluster families ([`BiG-SCAPE`](https://github.com/medema-group/BiG-SCAPE))

## Usage

> [!NOTE]
> If you are new to Nextflow and nf-core, please refer to [this page](https://nf-co.re/docs/usage/installation) on how to set-up Nextflow.

First, prepare a samplesheet with your input data that looks as follows:

`samplesheet.csv`:

```csv
sample_id,group,info,date,reads
lake1_t1,lake1,north_shore,20260312,/data/lake1_t1.fastq.gz
lake1_t2,lake1,south_shore,20260312,/data/lake1_t2.fastq.gz
```

Each row is one sample. `group` controls how results are aggregated: samples
sharing a group get combined figures, and `--coassemble_by_group` assembles them
together. `reads` may be a single FastQ file or a directory of FastQ files,
which are concatenated.

Now, you can run the pipeline using:

```bash
# fast route (default)
nextflow run dsamoht/roshab-cli \
   -profile <docker/singularity/.../institute> \
   --input samplesheet.csv \
   --outdir <OUTDIR> \
   --kraken_db <PATH> \
   --genomes_db <PATH> \
   --genes_db <PATH>

# assembly + BGC route
nextflow run dsamoht/roshab-cli \
   -profile <docker/singularity/.../institute>,assembly \
   --input samplesheet.csv \
   --outdir <OUTDIR> \
   --kraken_db <PATH> \
   --genomes_db <PATH> \
   --genes_db <PATH> \
   --antismash_db <PATH>
```

> [!WARNING]
> Provide pipeline parameters via the CLI or Nextflow `-params-file` option. Custom config files including those provided by the `-c` Nextflow option can be used to provide any configuration _**except for parameters**_; see [docs](https://nf-co.re/docs/usage/getting_started/configuration#custom-configuration-files).

The reference databases are not downloaded by the pipeline. See
[docs/usage.md](docs/usage.md) for where to get them.

## Pipeline output

Results are grouped by the `group` column of the samplesheet, one directory per
group. For details about the output files see [docs/output.md](docs/output.md).

## Credits

dsamoht/roshab-cli was originally written by Thomas Deschenes.

## Contributions and Support

Bug reports and feature requests are welcome on the
[issue tracker](https://github.com/dsamoht/roshab-cli/issues); questions are best
asked in the [discussions](https://github.com/dsamoht/roshab-cli/discussions).

## Citations

The tools used by the pipeline are cited in the [pipeline summary](#pipeline-summary) above.

This pipeline uses code and infrastructure developed and maintained by the [nf-core](https://nf-co.re) community, reused here under the [MIT license](https://github.com/nf-core/tools/blob/main/LICENSE).

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).
