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
| `sample_id` | Sample name. Letters, digits, `.`, `_` and `-` only, starting with a letter or digit. Becomes `meta.id` and is stamped onto the read IDs so that the combined Kraken2 run can be split back out per sample.                         |
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
| `--genes_db`     | always                                 | [core_cyanotoxin-related_gene_mibig-v4_antismash-v8.faa](https://zenodo.org/records/19522349/files/core_cyanotoxin-related_gene_mibig-v4_antismash-v8.faa), or build one with `bin/build_cyanotoxin_db.py` (see [Rebuilding the gene database](#rebuilding-the-gene-database)) |
| `--antismash_db` | with `--mode assembly` / `--mode both` | Build with `download-antismash-databases` from the antiSMASH distribution.                                                                                 |
| `--deepbgc_db`   | with `--run_deepbgc`                   | Build with `deepbgc download`.                                                                                                                             |

## Rebuilding the gene database

`bin/build_cyanotoxin_db.py` rebuilds `--genes_db` from MIBiG 4.0 and UniProt.
It is a maintenance script, not a pipeline step: run it by hand, read the
manifest it writes, and publish the FASTA.

```bash
python3 bin/build_cyanotoxin_db.py -o cyanotoxin_db
```

Headers carry six pipe-separated fields, the last of which is the sequence
class:

```text
>mcyA|microcystin|BGC0001017|mibig4.0|AAF00960.1|toxin
>ApnA|anabaenopeptin|BGC0000302|mibig4.0|CAC01604.1|other
```

### Why the database carries non-toxin sequences

DIAMOND assigns each alignment range to its best-scoring subject. In a reference
holding cyanotoxin genes and nothing else, every read that aligns to anything is
assigned to a toxin gene by construction, so the screen cannot return "this read
came from something else". That bites here in particular because the markers are
multi-domain NRPS/PKS proteins whose condensation, adenylation, KS and AT
domains are homologous across essentially every NRPS/PKS in the biosphere.

The `other` class gives those reads somewhere else to land, in three tiers:

1. **Every non-toxin cyanobacterial BGC in MIBiG** — anabaenopeptin,
   cyanopeptolin, aeruginosin, microginin, microviridin, the cyanobactins,
   hassallidin, cryptophycin, the siderophores. The nearest neighbours: `apnA`
   and `mcnA` carry the domains closest to `mcyA`–`mcyC` and occur in the same
   blooms.
2. **Heterocyst glycolipid synthases**, which MIBiG carries as a BGC of their
   own. Large type-I PKSs present in every heterocyst-forming cyanobacterium —
   *Anabaena*, *Nostoc*, *Aphanizomenon*, *Cylindrospermopsis* — i.e. exactly
   the genera carrying the anatoxin, saxitoxin and cylindrospermopsin clusters,
   so they cross-hit `cyrB`/`cyrC`/`mcyD`/`anaE` systematically rather than
   occasionally. Tier 1 collects them automatically; they are easy to overlook
   because they are not "secondary metabolism".
3. **The universal background** — a sample of non-cyanobacterial NRPS/PKS from
   MIBiG, plus reviewed β-ketoacyl-ACP synthases (ancestral relatives of the PKS
   KS domain) and AMP-binding acyl-CoA ligases (ancestral relatives of the NRPS
   adenylation domain) from UniProt. These sit in every genome at several
   copies, so at a permissive threshold a lake *Pseudomonas* `fadD` is a live
   `mcyA` candidate.

The `other` class outnumbers the toxin sequences by roughly fifty to one. That
is deliberate and harmless: DIAMOND's assignment is score-based rather than
prior-based, so these sequences only have to cover the space. It also means
adding them can only ever take a toxin call away, never create one.

The heatmap draws no panel for `other` compounds, but hits against them stay in
the evidence table, where the share of ranges landing on them is a per-sample
specificity readout.

### Gene naming

MIBiG names only about a sixth of the toxin proteins (`NdaA`, `LtxA`, `McyB`);
the rest carry a functional description such as `peptide_synthetase`. The script
seeds names from a small curated `REFERENCE_GENES` table, then transfers them to
the remaining proteins of the same toxin by best-hit orthology with DIAMOND, so
the clusters MIBiG never named still contribute their sequence diversity.

Two consequences worth knowing:

- **Guanitoxin is not in the database.** MIBiG annotates both guanitoxin
  clusters by function only, and there is no named reference to transfer from.
  The script says so loudly rather than dropping the toxin quietly; add entries
  to `REFERENCE_GENES` to include it.
- Two builds from the same MIBiG release are byte-identical, and the
  `*_manifest.tsv` records every source URL, query and release for citation.

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

