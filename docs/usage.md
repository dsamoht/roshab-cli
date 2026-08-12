# dsamoht/roshab-cli: Usage

## Introduction

dsamoht/roshab-cli profiles the microbial community of Oxford Nanopore reads and
evaluates the cyanotoxin biosynthesis potential of the sample. Taxonomic
profiling always runs; the cyanotoxin screening route is selected with `--mode`.

## Samplesheet input

You will need to create a samplesheet with information about the samples you
would like to analyse before running the pipeline. Use the `--input` parameter
to specify its location. It has to be a comma-separated file with 5 columns and
a header row as shown in the example below.

```bash
--input '[path to samplesheet file]'
```

```csv title="samplesheet.csv"
sample_id,group,info,date,reads
lake1_t1,lake1,north_shore,20260312,/data/lake1_t1.fastq.gz
lake1_t2,lake1,south_shore,20260312,/data/lake1_t2.fastq.gz
lake2_t1,lake2,dock,20260319,/data/lake2_t1/
```

| Column      | Description                                                                                                                                                                       |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sample_id` | Sample name. Must not contain spaces. Becomes `meta.id` and is stamped onto the read IDs so that the combined Kraken2 run can be split back out per sample.                          |
| `group`     | Group the sample belongs to. Results are published under `group_<group>/` and per-group figures combine every sample of the group. `--coassemble_by_group` assembles them together.  |
| `info`      | Free-text label for the sampling site. Used in the axis labels of the taxonomy and coverage figures.                                                                                 |
| `date`      | Sampling date. Used in the figures to order samples over time.                                                                                                                       |
| `reads`     | Nanopore reads: a FastQ file (optionally gzipped) or a directory of FastQ files, which are concatenated before processing.                                                            |

An [example samplesheet](../assets/samplesheet.csv) has been provided with the pipeline.

## Reference databases

None of the databases are downloaded by the pipeline. Where a database is a
directory, a `.tar.gz` or `.tgz` tarball is also accepted and is extracted once
at the start of the run.

| Parameter        | Required                                  | Where to get it                                                                                                                     |
| ---------------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `--kraken_db`    | always                                    | Pre-built indexes at [benlangmead.github.io/aws-indexes/k2](https://benlangmead.github.io/aws-indexes/k2). Must contain `ktaxonomy.tsv`. |
| `--genomes_db`   | always                                    | [cyanobacteriota_ncbi_dRep_n220.tar.gz](https://zenodo.org/records/19522349/files/cyanobacteriota_ncbi_dRep_n220.tar.gz)               |
| `--genes_db`     | always                                    | [core_cyanotoxin-related_gene_mibig-v4_antismash-v8.faa](https://zenodo.org/records/19522349/files/core_cyanotoxin-related_gene_mibig-v4_antismash-v8.faa) |
| `--antismash_db` | with `--mode assembly` / `--mode both`    | Build with `download-antismash-databases` from the antiSMASH distribution.                                                            |
| `--deepbgc_db`   | with `--run_deepbgc`                      | Build with `deepbgc download`.                                                                                                        |
| `--pfam_db`      | with `--run_bigscape`                     | `Pfam-A.hmm` from [InterPro](https://www.ebi.ac.uk/interpro/download/Pfam/).                                                            |

## Cyanotoxin screening routes

| `--mode`          | What it does                                                            | Cost               |
| ----------------- | ----------------------------------------------------------------------- | ------------------ |
| `reads` (default) | `diamond blastx` of the QC reads against the cyanotoxin gene database    | minutes            |
| `assembly`        | assembly, then BGC screening of the contigs                             | hours, high memory |
| `both`            | both routes on the same reads                                           |                    |

`-profile assembly` and `-profile full` are shortcuts for `--mode assembly` and
`--mode both`. `-profile metamdbg` is a shortcut for `--assembler metamdbg`.

The assembly route assembles with `metaFlye` (or `metaMDBG`), polishes with
`Medaka`, calls proteins with `Pyrodigal`, and screens the contigs with
`antiSMASH` and `GECCO` — optionally `DeepBGC` (`--run_deepbgc`). Regions
predicted by several tools are reconciled into a single table per sample
(`*.bgc.tsv`), where regions supported by at least two tools are labelled `high`
confidence. `--run_bigscape` additionally clusters the antiSMASH regions of a
group into gene cluster families.

`Medaka` polishing is off by default; `--polish` turns it on. It applies to
`flye` assemblies only — `metamdbg` polishes internally, so `Medaka` never runs
after it and `--polish` with `--assembler metamdbg` is rejected.

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run dsamoht/roshab-cli \
    --input ./samplesheet.csv \
    --outdir ./results \
    --kraken_db ./k2_standard \
    --genomes_db ./cyanobacteriota_ncbi_dRep_n220 \
    --genes_db ./core_cyanotoxin-related_genes.faa \
    -profile docker
```

This will launch the pipeline with the `docker` configuration profile. See below
for more information about profiles.

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

If you wish to repeatedly use the same parameters for multiple runs, rather than specifying each flag in the command, you can specify these in a params file.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources), other infrastructural tweaks (such as output directories), or module arguments (args).

The above pipeline run specified with a params file in yaml format:

```bash
nextflow run dsamoht/roshab-cli -profile docker -params-file params.yaml
```

with:

```yaml title="params.yaml"
input: "./samplesheet.csv"
outdir: "./results"
kraken_db: "./k2_standard"
genomes_db: "./cyanobacteriota_ncbi_dRep_n220"
genes_db: "./core_cyanotoxin-related_genes.faa"
mode: "both"
```

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull dsamoht/roshab-cli
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [dsamoht/roshab-cli releases page](https://github.com/dsamoht/roshab-cli/releases) and find the latest pipeline version - numeric only (eg. `1.0.0`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.0.0`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future. For example, at the bottom of the MultiQC reports.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Apptainer, Conda) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important! They are loaded in sequence, so later profiles can overwrite earlier profiles.

- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://hpc.github.io/charliecloud/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers.
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer.
- `assembly` / `full` / `metamdbg`
  - Pipeline shortcuts for `--mode assembly`, `--mode both` and `--assembler metamdbg`

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline steps, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

The assembly and antiSMASH steps use the `process_high` label. `--assembly_cpus`
overrides the CPU count for those steps only; memory and time still come from
the label, so set them in a custom config when running on a scheduler:

```groovy title="my.config"
process {
    withName: 'FLYE|METAMDBG|MEDAKA|ANTISMASH' {
        memory = 200.GB
        time   = 72.h
    }
}
```

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/usage/configuration#customising-tool-arguments) section of the nf-core website.

### Custom Containers

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [Bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To learn how to use custom containers, please see the [custom containers](https://nf-co.re/docs/usage/configuration#custom-containers) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/usage/configuration#customising-tool-arguments) section of the nf-core website.

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
