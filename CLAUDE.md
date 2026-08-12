# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`dsamoht/roshab-cli` is a Nextflow (DSL2, nf-core template 4.1.0) pipeline that taxonomically
profiles Oxford Nanopore reads from water samples and evaluates their cyanotoxin biosynthesis
potential. Requires Nextflow `>=25.10.4`.

## Commands

```bash
# Run the bundled test dataset (downloads a viral Kraken2 index + small CoverM db)
nextflow run . -profile test,docker --outdir results

# Assembly/BGC route — needs an antiSMASH database, which the test profile does not supply
nextflow run . -profile test,docker,assembly --outdir results --antismash_db <PATH>

# Tests. nf-test.config sets testsDir="." and profile="test"; tests/nextflow.config
# points pipelines_testdata_base_path at tests/data/ on the `main` branch (i.e. remote,
# not local — pushing test data is what makes it visible to a test run).
nf-test test
nf-test test tests/default.nf.test
nf-test test --update-snapshot     # tests/default.nf.test.snap is not committed yet

# Linting
nf-core pipelines lint             # must stay at 0 failures
prek run --all-files               # prettier + whitespace + nextflow-lint (pre-commit also works)
```

`--outdir` is mandatory. Never point it inside the repo: `.hooks/block_pipeline_outdir.sh` blocks
any commit containing a directory with a `pipeline_info/` child.

## Layout

Every Nextflow script is a `main.nf` inside a directory named after what it defines — there are no
loose `*.nf` files. Same convention as the sibling `mag-ont` pipeline.

```
main.nf                             ROSHAB_CLI + entry workflow + publish:/output{} targets
workflows/longread_qc/              NanoPlot(raw) → Chopper → NanoPlot(qc)
workflows/assembly_bgc/             assembly, gene calling and BGC screening
subworkflows/local/pipeline_initialisation/   help, validation, sample sheet, shared helper functions
subworkflows/local/pipeline_completion/       completion email and run summary
subworkflows/nf-core/               vendored nf-core utils (tracked in modules.json)
modules/local/<tool>[/<subtool>]/   main.nf + environment.yml + meta.yml
bin/*.py                            helper scripts, on PATH inside the bio-utils container
conf/, assets/, docs/, tests/
```

## Architecture

`main.nf` holds `ROSHAB_CLI`, the main analysis workflow, and calls `workflows/longread_qc/` and
`workflows/assembly_bgc/`. The entry `workflow {}` below it wires `PIPELINE_INITIALISATION` /
`PIPELINE_COMPLETION` around `ROSHAB_CLI` and declares publishing. There is no wrapper workflow
between the two.

**`--mode` gates the two screening routes.** Taxonomic profiling always runs. `reads` (default)
adds `DIAMOND_BLASTX` on the QC reads; `assembly` runs the `ASSEMBLY_BGC` workflow; `both` runs
each. `ASSEMBLY_BGC` always emits its full output map — `ROSHAB_CLI` initialises the same keys as
`channel.empty()` when the route is off, so the `emit:`/`publish:`/`output {}` lists stay identical
in every mode. Adding an output means touching all three lists.

**`meta.group` is the fan-in key.** Per-sample channels are `[meta, file]`; group-level channels are
`[group_id, files]` after `.map { meta, f -> tuple(meta.group, ...) }.groupTuple()`. Sort by
`meta.id` inside the group before collecting, so results are reproducible. Figures and BiG-SCAPE are
group-level; everything else is per-sample. All results publish under `group_<group>/`.

**One Kraken2 run for all samples.** `CAT_INIT` stamps `meta.id` onto every read ID, `CAT_PRE_KRAKEN`
concatenates every sample into one `[id: 'all']` channel item, and `SPLIT_KRAKEN_OUTPUT` recovers the
per-sample files from those IDs. The full `meta` is re-attached by joining on `kraken_file.simpleName`
against the samplesheet. Anything that alters read IDs breaks this round trip.

**Reference databases.** `--kraken_db`, `--genomes_db`, `--antismash_db` and `--deepbgc_db` all accept
a directory or a `.tar.gz`/`.tgz`, normalised by the `DECOMPRESS` module (aliased once per database)
and pinned with `.first()` into a value channel. None are downloaded by the pipeline.

**Publishing uses the workflow output definition**, not `publishDir`. Paths live in the `output {}`
block of `main.nf`; `conf/modules.config` carries only `ext.args` / `ext.prefix` / resource overrides.
Do not add `publishDir` to a module.

**Software versions** come from the `versions` topic channel — each process emits
`tuple val("${task.process}"), val('tool'), eval("<version cmd>"), topic: versions`.

## Conventions

- **Modules are hand-written under `modules/local/` — do not install nf-core modules.** Each is a
  directory with `main.nf` + `environment.yml` + `meta.yml`. `subworkflows/nf-core/` is the only
  vendored code (tracked in `modules.json`); don't hand-edit it.
- **A module directory is the snake_case of its process name** (`PLOT_KRAKEN` → `plot_kraken`), and
  nests under a tool directory when it belongs to a tool that already has one: `diamond/blastx`,
  `krakentools/combinempa`, `seqkit/sliding`, `kraken2/split_kraken_output`. The `name:` field of
  `meta.yml` is that same snake_case process name.
- Copy an existing module (e.g. `modules/local/bracken/`) for the shape: `tag`, `label`,
  `conda "${moduleDir}/environment.yml"`, singularity/quay container ternary, `task.ext.when` guard,
  `args`/`prefix` from `task.ext`, and a `stub`.
- Tool flags belong in `conf/modules.config` under `withName:`, not hardcoded in the module script.
  Resource labels (`process_low` … `process_high`) come from `conf/base.config`.
- New parameters must be added to `nextflow_schema.json` (`nf-core pipelines schema build`) or
  validation rejects them. Cross-parameter rules the schema cannot express go in
  `validateInputParameters()` in `subworkflows/local/pipeline_initialisation/main.nf`. That file also
  holds the pipeline-level helper functions (`runMedakaPolishing`, `methodsDescriptionText` and the
  citation text builders): `nf-core pipelines lint` crashes on a local subworkflow whose `main.nf`
  has no `workflow` block, so they cannot live in a directory of their own.
- This pipeline deliberately diverges from the nf-core template (hyphenated name, no nf-core logo,
  no `CITATIONS.md`/`CHANGELOG.md`/`docs/CONTRIBUTING.md`, no igenomes). Those divergences are
  declared in `.nf-core.yml`; when you change a template-tracked file, add it to the relevant
  ignore list there rather than reverting the change.
- Figure modules carry `label 'error_ignore'` on top of their resource label: a plot that fails
  must not fail the run.
