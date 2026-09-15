# dsamoht/roshab-cli

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

 Taxonomic classification and evaluation of cyanotoxin biosynthesis
 potential from nanopore reads.
```

## Introduction

**roshab-cli** is a pipeline that assigns taxonomy to
long reads and asses the presence of cyanotoxin
biosynthesis genes.

Taxonomic profiling always runs. The biosynthesis potential is evaluated through
one of two routes, selected with `--mode`:

| `--mode`          | What it does                                                               | Cost               |
| ----------------- | -------------------------------------------------------------------------- | ------------------ |
| `reads` (default) | `diamond blastx` of the QC reads against a "core" cyanotoxin gene database | minutes            |
| `assembly`        | assembly + biosynthetic gene cluster (BGC) screening of the contigs        | hours, high memory |
| `both`            | run both                                                                   |                    |

Figures are computed per `group`; every other step is per sample.

### Pipeline summary

**1. QA/QC**

- QA/QC ([`NanoPlot`](https://github.com/wdecoster/NanoPlot), [`Chopper`](https://github.com/wdecoster/chopper)) — skippable with `--skip_qc`

**2. Taxonomy**

- Taxonomic classification ([`Kraken2`](https://ccb.jhu.edu/software/kraken2/)) and abundance re-estimation ([`Bracken`](https://ccb.jhu.edu/software/bracken/), [`KrakenTools`](https://github.com/jenniferlu717/KrakenTools))
- Coverage against a reference genome set ([`CoverM`](https://github.com/wwood/CoverM))

**3. Assessment of toxin biosynthesis potential**

**`--mode reads` (default):**

- Align the QC reads to a "core" cyanotoxin gene database using `blastx` ([`DIAMOND`](https://github.com/bbuchfink/diamond))

**`--mode assembly`:**

- Assemble ([`metaFlye`](https://github.com/mikolmogorov/Flye) or [`metaMDBG`](https://github.com/GaetanBenoitDev/metaMDBG)), filter short contigs and report assembly metrics ([`SeqKit`](https://bioinf.shenwei.me/seqkit/))
- BGC detection ([`antiSMASH`](https://antismash.secondarymetabolites.org)), summarised per group as predicted regions per product class

## Usage

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

An analysis run never downloads a database. Install them once into a directory
of your choice, and pass that same `--db_dir` to every run afterwards.

```bash
# 1. install the databases (once)
nextflow run dsamoht/roshab-cli \
   -profile <docker/singularity/.../> \
   --db_dir <DBDIR> \
   --install_databases

# 2. run
nextflow run dsamoht/roshab-cli \
   -profile <docker/singularity/.../> \
   --input samplesheet.csv \
   --outdir <OUTDIR> \
   --db_dir <DBDIR>
```

`--mode` picks the screening route: `reads` (the default, minutes), `assembly`
(hours, high memory) or `both`. The assembly route needs the antiSMASH databases
as well, so pass the mode to the install too:

```bash
nextflow run dsamoht/roshab-cli \
   -profile <docker/singularity/.../> \
   --db_dir <DBDIR> \
   --install_databases \
   --mode both
```

Installing is safe to repeat: a database already in `--db_dir` is left alone. See
[docs/usage.md](docs/usage.md) for the databases, their sizes and where they come
from.

## Pipeline output

Results are grouped by the `group` column of the samplesheet, one directory per
group. For details about the output files see [docs/output.md](docs/output.md).
