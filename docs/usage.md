# dsamoht/roshab-cli: Usage

## Samplesheet input
```csv title="samplesheet.csv"
sample_id,group,info,date,reads
lake1_t1,lake1,north_shore,20260312,/data/lake1_t1.fastq.gz
lake1_t2,lake1,south_shore,20260312,/data/lake1_t2.fastq.gz
lake2_t1,lake2,dock,20260319,/data/lake2_t1/
```

| Column      | Description                                                                                                                                                                         |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sample_id` | Sample name. Must not contain spaces. Becomes `meta.id` and is stamped onto the read IDs so that the combined Kraken2 run can be split back out per sample.                         |
| `group`     | Group the sample belongs to. Results are published under `group_<group>/` and per-group figures combine every sample of the group. `--coassemble_by_group` assembles them together. |
| `info`      | Free-text label for the sampling site. Used in the axis labels of the taxonomy and coverage figures.                                                                                |
| `date`      | Sampling date. Used in the figures to order samples over time.                                                                                                                      |
| `reads`     | Nanopore reads: a FastQ file (optionally gzipped) or a directory of FastQ files, which are concatenated before processing.                                                          |

An [example samplesheet](../assets/samplesheet.csv) has been provided with the pipeline.

## Reference databases

An analysis run never downloads a database: point it at databases you already
have, or install them once with `--db_dir` (see
[Installing the databases](#installing-the-databases) below). Where a database is
a directory, a `.tar.gz` or `.tgz` tarball is also accepted and is extracted once
at the start of the run.

| Parameter        | Required                               | Where to get it                                                                                                                                            |
| ---------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--kraken_db`    | always                                 | Pre-built indexes at [benlangmead.github.io/aws-indexes/k2](https://benlangmead.github.io/aws-indexes/k2). Must contain `ktaxonomy.tsv`.                   |
| `--genomes_db`   | always                                 | [cyanobacteriota_ncbi_dRep_n220.tar.gz](https://zenodo.org/records/19522349/files/cyanobacteriota_ncbi_dRep_n220.tar.gz)                                   |
| `--genes_db`     | always                                 | [core_cyanotoxin-related_gene_mibig-v4_antismash-v8.faa](https://zenodo.org/records/19522349/files/core_cyanotoxin-related_gene_mibig-v4_antismash-v8.faa) |
| `--antismash_db` | with `--mode assembly` / `--mode both` | Build with `download-antismash-databases` from the antiSMASH distribution.                                                                                 |
| `--deepbgc_db`   | with `--run_deepbgc`                   | Build with `deepbgc download`.                                                                                                                             |
| `--pfam_db`      | with `--run_bigscape`                  | `Pfam-A.hmm` from [InterPro](https://www.ebi.ac.uk/interpro/download/Pfam/).                                                                               |

## Installing the databases

`--db_dir` switches the run to database installation: the databases are
downloaded into that directory and no analysis step runs. `--input` and
`--outdir` are not needed.

```bash
nextflow run dsamoht/roshab-cli \
   -profile <docker/singularity/.../> \
   --db_dir /the/path
```

Each database is installed into a directory of its own, and the run finishes by
printing the parameters to use:

```text
/the/path/kraken_db/
/the/path/genomes_db/
/the/path/genes_db/core_cyanotoxin-related_gene_mibig-v4_antismash-v8.faa
/the/path/antismash_db/
/the/path/deepbgc_db/
/the/path/antismash_db/pfam/35.0/Pfam-A.hmm    # BiG-SCAPE reuses the antiSMASH copy
```

`--install_databases` picks a subset:

```bash
# only what the default `--mode reads` route needs
nextflow run dsamoht/roshab-cli \
   -profile <docker/singularity/.../institute> \
   --db_dir /the/path \
   --install_databases kraken,genomes,genes
```

| Name        | Installed as    | How it is obtained                                                      |
| ----------- | --------------- | ----------------------------------------------------------------------- |
| `kraken`    | `kraken_db/`    | download of `--kraken_db_url`, by default the 16 GB capped PlusPF index |
| `genomes`   | `genomes_db/`   | download of `--genomes_db_url`                                          |
| `genes`     | `genes_db/`     | download of `--genes_db_url`                                            |
| `antismash` | `antismash_db/` | `download-antismash-databases`                                          |
| `deepbgc`   | `deepbgc_db/`   | `deepbgc download`                                                      |
| `pfam`      | `pfam_db/`      | download of `--pfam_db_url`, skipped when `antismash` is installed too  |

A database that is already present in `--db_dir` is left alone, so an
interrupted install can simply be run again; delete its directory to force a
fresh download.


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


If you wish to repeatedly use the same parameters for multiple runs, rather than specifying each flag in the command, you can specify these in a params file.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

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

