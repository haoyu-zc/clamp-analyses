# PhenoPLIER GLS integration — LV–trait association for CLAMP models

Runs `phenoplier shortcut gls` (the GLS module–trait regression from
[pivlab/phenoplier-cli](https://github.com/pivlab/phenoplier-cli)) against the CLAMP
models this repo's ARCHS4 workflow fits, and publishes one GLS summary per model
where `workflow/rules/archs4_traits.smk` picks them up for the coverage /
saturation / final-model trait-recovery reports.

**Contents**

1. [How it is wired](#1-how-it-is-wired)
2. [Requirements](#2-requirements)
3. [phenoplier-cli environment and workspace](#3-phenoplier-cli-environment-and-workspace)
4. [Configuration](#4-configuration)
5. [Running locally](#5-running-locally)
6. [Running on a Slurm cluster](#6-running-on-a-slurm-cluster)
7. [Targets and outputs](#7-targets-and-outputs)
8. [Verifying a run](#8-verifying-a-run)
9. [Troubleshooting](#9-troubleshooting)
10. [Layout](#10-layout)
11. [As-run record (pico)](#11-as-run-record-pico)

> Sections marked **`[MARC: …]`** cover CLAMP-side inputs this integration consumes
> but does not produce; please fill them in.

---

## 1. How it is wired

`workflow/rules/phenoplier.smk` is included by `workflow/Snakefile` (config:
`workflow/config/phenoplier.yaml`). It has one rule per model family, and each
takes its model from the rule file that builds that model — no model path is
written down here:

| rule | model, from | summary, into (`archs4.yaml: traits.*`) |
|---|---|---|
| `gls_bp_coverage_full` | `a4_cov_model_dir()` CLAMPfull_bp, after `validate_bp_coverage_model` | `coverage.clampfull_bp_dir/cov_rs<f>_seed<s>.tsv.gz` |
| `gls_bp_coverage_base` | `a4_cov_cell()/CLAMPbase.rds` | `coverage.clampbase_dir/cov_rs<f>_seed<s>.tsv.gz` |
| `gls_bp_saturation_full` | `a4_sat_model_dir()` CLAMPfull_bp, after `validate_bp_saturation_model` | `saturation.clampfull_bp_dir/sat_rs<f>_k<k>_seed<s>.tsv.gz` |
| `gls_bp_saturation_base` | `a4_sat_base_rds()` | `saturation.clampbase_dir/sat_rs<f>_k<k>_seed<s>.tsv.gz` |
| `gls_bp_final_full` | gtex / recount2: `final_models.clampfull.bp.<ds>`, after `publish_bp_model` | `finals.clampfull_bp_dir/final_<ds>.tsv.gz` |
| `gls_final_base` | gtex / recount2: `coverage.clampbase_source.<ds>` (`clamp_gtex`, `clampbase_recount2`) | `finals.clampbase_dir/final_<ds>.tsv.gz` |
| `link_bp_final_full`, `link_final_base` | archs4: the finals *are* the coverage rs100/seed1 cells, so their summaries are copied, not re-run | `finals.*_dir/final_archs4.tsv.gz` |
| `gls_canonical` | `A4_CAN_FINAL_ROOT/<ds>/CLAMPfull_canonical.rds` | beside the model: `<ds>/traits/canon_<ds>.tsv.gz` |
| `store_bp_final_full`, `store_final_base` | the finals above | `finals.*_dir/../stores/final_<ds>_<model>.h5` |

The filenames are the ones `scripts/archs4/traits/aggregate_*_traits.R` parse; the
directory, not the filename, says whether a summary is CLAMPfull_bp or CLAMPbase.
`aggregate_archs4_{coverage,saturation}_traits` list these files as inputs, so
`snakemake archs4_traits` fits any missing model, runs GLS on it and renders the
trait-recovery reports in one DAG.

Each GLS job is one shell step (`run_gls.sh`) that drives phenoplier-cli's own
pipeline in one workspace project per model: register + init once, pin the step-6/7
pools, resume-safe run, completeness gate, atomic publish. Workspace project names
(`cov_rs5_seed2_CLAMPfull_bp`, …) match the as-run pico names, so a workspace that
already holds a finished project is reused. `run_gls.sh` fingerprints the `.rds` it
registered (`<project>/clamp_source.sha256`); if a model is refit, the next run moves
the old project aside (`<project>.stale.<timestamp>`), re-registers and starts over.
Projects made before this wiring carry no fingerprint and are reused as-is (with a
warning) — delete the project to recompute.

## 2. Requirements

| what | where it comes from |
|---|---|
| Snakemake 8 (`envs/snakemake.yaml`) | `./setup.sh` or `conda env create -n snakemake -f envs/snakemake.yaml`. Includes `snakemake-executor-plugin-slurm` for cluster runs. |
| `clamp-analyses` conda env | `./setup.sh` (see the top-level README). Needed by every rule that fits, validates or publishes a CLAMP model and by the R aggregators / report notebooks. |
| phenoplier-cli **v0.5.2** in its own env | §3. Pinned in `phenoplier.yaml: version`; every GLS/store job refuses any other release. |
| phenoplier reference data bundle (`phenoplier_full_data`) | §3. Provided per site; not downloaded by this workflow. |
| CLAMP models to test | produced by the ARCHS4 / GTEx / recount2 rules, or already published. **`[MARC: which of `output/98_final_models/**`, `output/01_model_building/02_archs4/00_preprocess/*` and `data/pathways/*.gmt` are published inputs that must be staged before a fresh checkout can run, and where they come from.]`** |

phenoplier-cli needs `snakemake>=9` / Python ≥3.12, which is incompatible with this
repo's own `snakemake=8` / Python 3.11. That is why it lives in a separate env and
why each GLS run is a shell job rather than rules of this DAG.

## 3. phenoplier-cli environment and workspace

### 3.1 Environment (once per machine or cluster)

```bash
bash scripts/phenoplier/setup_env.sh       # creates conda env `phenoplier-cli-neo` with phenoplier-cli v0.5.2 + rpy2/R
conda activate phenoplier-cli-neo
phenoplier --version                        # must print v0.5.2
```

`setup_env.sh` delegates to phenoplier-cli's own installer and pins the tag that
`phenoplier.yaml: version` requires. To use another release, bump both together and
re-run the whole model set — results from different releases are not comparable.
On an air-gapped cluster install from wheels transferred from a networked host (see
`final_models/README.md`). Reading a CLAMP `.rds` (registration, `store build`) goes
through rpy2 → R, which the env ships.

### 3.2 Workspace (once per site)

A phenoplier workspace is a directory with `config.toml`, `data/`, `models/`,
`projects/`. GLS reads ~6 GB of reference data from `data/` (PhenomeXcan GWAS,
S-PrediXcan / S-MultiXcan results, the GTEx v8 reference panel, MASHR models, the
4,049 phenotype files) and writes one project per model under `projects/`.

```bash
conda activate phenoplier-cli-neo
export PHENOPLIER_HOME=/shared/phenoplier_workspace           # any writable path on the shared filesystem
phenoplier workspace init
phenoplier workspace link /path/to/phenoplier_full_data        # symlinks data/, software/ (and models/) from the bundle
```

Known bundle locations: Alpine `/pl/active/pivlab/projects/hzhang/data/phenoplier_full_data.tar.gz`,
server_cu (pico) `/pividori_lab/data/phenoplier_full_data.tar.gz`; the pico workspace
is `/pividori_lab/phenoplier_workspace`. `workspace link` also links `models/` and
re-bootstraps the registry inside the bundle, so link from a copy you own, not from a
bundle another group is using.

Tell the workflow where the workspace is with **`phenoplier.yaml: workspace`**
(recommended for clusters: every job resolves the same path whatever environment
`sbatch` hands it). If it is empty, the jobs use `$PHENOPLIER_HOME`, then
`~/phenoplier`. A job fails early with a clear message if the workspace has no
`config.toml`.

## 4. Configuration

All keys live in `workflow/config/phenoplier.yaml` (comments there are the
authoritative reference). The ones you are likely to touch:

| key | meaning |
|---|---|
| `version` | phenoplier-cli release every job must run (`0.5.2`). |
| `workspace` | phenoplier workspace path (§3.2). Empty → `$PHENOPLIER_HOME` → `~/phenoplier`. |
| `conda_env` | the phenoplier-cli conda env name (`phenoplier-cli-neo`). |
| `namespace` | registry namespace models are registered under (`clamp`). |
| `cohort` | GWAS cohort (`phenomexcan_rapid_gwas`); also names the per-phenotype results dir stores read. |
| `lv_percentile` | top gene percentile per LV for the GLS binarisation (`0.01`, = `archs4.yaml: ora.top_pct`). |
| `trait_filter` | `biomedical` (2,366 of 4,049 phenotypes) or `all`. Keep it fixed across a comparison: it changes the BH test count. |
| `expected_phenotypes` | unique phenotypes a complete summary must contain per filter; the completeness gate. |
| `saturation_k_values` | saturation ranks to run (`[1728]`, what the report uses). |
| `workers` | phenoplier-cli's step-6/7 pools: `step6: 1` (serial; the forked pool deadlocks), `step7 × blas_step7` = the job's threads. On a host without a cgroup prefer `step7: 12, blas_step7: 1`. |
| `resources.gls` / `resources.store` | threads, memory and wall clock this repo's scheduler requests per job. |
| `clusters` / `target` | which of phenoplier-cli's *own* Slurm profiles `shortcut gls` submits to. `local` (default and the validated path) runs each model's whole pipeline inside the allocation this repo gives the job. See §6. |
| `report_root` | where the cross-model long table lands. |

Overrides without editing the checked-in YAML: `snakemake <target> --configfile my.yaml`
(merged recursively; lists replace, dict keys can only be added; put the target
*before* `--configfile`, which otherwise swallows it as another file) or
`snakemake <target> --config phenoplier_target=server_cu` for the target.

## 5. Running locally

From the repo root, in the `snakemake` env:

```bash
conda activate snakemake
snakemake --profile workflow/profiles/local -n phenoplier_finals     # always dry-run first
snakemake --profile workflow/profiles/local phenoplier_finals
```

`workflow/profiles/local/config.yaml` caps the run at 24 cores / 96 GB. A GLS job
takes hours to a day per model (it scales with the model's **gene** count: ~15 h for
the 21k-gene GTEx final on 32 cores, ~2.7 h for the 6k-gene recount2 final), so a
workstation is for one or two models, not the sweep. `resources.gls.mem_mb` must be
≤ the profile's `mem_mb` or Snakemake refuses to schedule the job; lower it with a
`--configfile` override on a small machine.

## 6. Running on a Slurm cluster

There are two Slurm layers to keep apart:

1. **This repo's Snakemake** submits each rule (CLAMP fits, `gls_*`, `store_*`,
   aggregations) as a Slurm job via `snakemake-executor-plugin-slurm`. This is the
   layer you configure with a site profile.
2. **phenoplier-cli's pipeline inside a `gls_*` job.** With `phenoplier.yaml:
   target: local` (default) it runs entirely inside that job's allocation, sized by
   `resources.gls.threads` and pinned by `workers` — the path all 86 as-run models
   used. Only switch `target` to `server_cu` / `alpine` if you want phenoplier-cli to
   spawn its own sub-jobs from inside the allocation; account/partition for those
   live in phenoplier-cli's profiles (`phenoplier/workflow/clusters.py`), not here.

### 6.1 Site profile

`workflow/profiles/slurm/config.yaml` is the portable part (executor, job limits,
memory pools, per-rule overrides for the ARCHS4 fits). Site specifics — account,
partition, QOS — stay out of the repo. Create a user-owned profile that starts from
it and adds them, e.g. `~/.config/snakemake/clamp-slurm/config.yaml`:

```yaml
# Site profile for <cluster>. Everything not listed here comes from
# workflow/profiles/slurm/config.yaml, which you copy in or keep in step with.
executor: slurm
jobs: 20                      # concurrent Slurm jobs
use-conda: true
printshellcmds: true
rerun-incomplete: true
retries: 2
rerun-triggers: [mtime]
latency-wait: 120             # shared filesystems lag; avoid false "missing output"

resources:                    # cluster-wide pools this workflow's rules draw from
  - mem_mb=800000
  - fit_mem_mb=800000
  - ora_mem_mb=64000
  - fit_slots=20
  - ora_slots=8
  - large_fit_slot=1

default-resources:
  - slurm_account=<account>
  - slurm_partition=<partition>
  - mem_mb=8000
  - runtime=5760
  - tasks=1

set-resources:
  # phenoplier GLS: one node, one task, `threads` cpus; 100 GB covers the 8 GB
  # archs4 .rds (~88 GB to load). Wall clock 3 days > the ~20 h archs4 final.
  gls_bp_coverage_full:   {slurm_partition: <long-partition>, mem_mb: 100000, runtime: 4320}
  gls_bp_coverage_base:   {slurm_partition: <long-partition>, mem_mb: 100000, runtime: 4320}
  gls_bp_saturation_full: {slurm_partition: <long-partition>, mem_mb: 100000, runtime: 4320}
  gls_bp_saturation_base: {slurm_partition: <long-partition>, mem_mb: 100000, runtime: 4320}
  gls_bp_final_full:      {slurm_partition: <long-partition>, mem_mb: 100000, runtime: 4320}
  gls_final_base:         {slurm_partition: <long-partition>, mem_mb: 100000, runtime: 4320}
  gls_canonical:          {slurm_partition: <long-partition>, mem_mb: 100000, runtime: 4320}
  # [MARC: the ARCHS4 fit overrides from workflow/profiles/slurm/config.yaml
  # (preprocess_archs4 / svd_archs4 / clampbase_archs4 / clampfull_archs4) and any
  # high-memory partition they need.]

set-threads:
  preprocess_archs4: 30
  svd_archs4: 30
```

Notes:

- `slurm_account` / `slurm_partition` are ordinary Snakemake resources; put them in
  `default-resources` and override per rule in `set-resources`. Any `mem_mb`,
  `runtime` (minutes) and `threads` a rule declares are translated to `--mem`,
  `--time` and `--cpus-per-task` by the plugin.
- `gls_*` jobs need **one node**: phenoplier-cli's pools are process pools, not MPI.
  The plugin submits `tasks=1` by default; keep it.
- The job's cgroup is what pins phenoplier-cli: `workers.step7 × blas_step7` should
  equal `resources.gls.threads` (default 6 × 2 = 12). Un-pinned it over-detects the
  node's cores and thrashes.
- `phenoplier.yaml: workspace` should be set to the shared-filesystem workspace so
  jobs never depend on `PHENOPLIER_HOME` being exported through `sbatch`.
- The conda envs (`snakemake`, `clamp-analyses`, `phenoplier-cli-neo`) must be
  visible on the compute nodes (same `$HOME`/shared conda install). `use-conda`
  resolves them by name; nothing is created on the fly.

### 6.2 Submitting

Run the scheduler itself from a login node inside a persistent session (`tmux` /
`screen`, or a small long-running Slurm job), since it stays alive for the whole
DAG:

```bash
conda activate snakemake
cd /path/to/clamp-analyses
snakemake --profile ~/.config/snakemake/clamp-slurm -n phenoplier_finals            # dry-run
snakemake --profile ~/.config/snakemake/clamp-slurm phenoplier_finals                # 6 GLS jobs (3 datasets x 2 models)
snakemake --profile ~/.config/snakemake/clamp-slurm phenoplier_final_stores          # + 6 HDF5 stores
snakemake --profile ~/.config/snakemake/clamp-slurm archs4_traits                    # everything the trait reports need
```

Monitoring: `squeue -u $USER`, the per-model log next to each summary
(`…/summaries/<name>.log`), and inside the workspace project
`projects/<name>/pipeline_results/*/sentinels/step{1..7}.done` and
`results/gls/phenoplier/<cohort>/` (one file per phenotype, 2,366 when complete).

Interrupted runs resume: re-issue the same command. `run_gls.sh` re-enters
phenoplier-cli's pipeline where its sentinels stopped; a summary that fails the
completeness gate is deleted so the requeue finishes step 7 instead of skipping.

### 6.3 Throughput

Registration + init of concurrent jobs is serialised by a lock on
`<workspace>/.clamp_registry.lock` (phenoplier-cli rewrites its registry without
one); the hours-long pipeline phase is not. `jobs:` in the profile bounds how many
GLS runs are in flight; each holds ~100 GB on its node. The as-run sweep ran
~6 concurrent on pico (168 cores / 900 GB) at 22–32 cores per job.

## 7. Targets and outputs

| target | what |
|---|---|
| `phenoplier_coverage` / `phenoplier_saturation` / `phenoplier_finals` | GLS summaries for one family (CLAMPfull_bp + CLAMPbase) |
| `phenoplier_canonical` | GLS summaries for the three canonical-prior models |
| `phenoplier_final_stores` | one HDF5 composite study store per final model (`phenoplier store build`) |
| `phenoplier_traits` | every per-model summary (coverage, saturation, finals, canonical) |
| `phenoplier_long_table` | every LV × trait row of every summary, streamed into one gzipped CSV under `report_root` (tens of GB) |
| `archs4_traits` | the trait-recovery reports (`archs4_traits.smk`); pulls the GLS runs it needs |

Per model, next to the summary (`<name>.tsv.gz`): `<name>.pkl.gz` (same table as
pickle), `<name>_trait_filter_excluded.tsv` (which traits the filter dropped and
why), `<name>.log`. Summary columns: `phenotype, phenotype_desc, lv, pvalue,
binarized_n_pos, lv_se_ratio, lv_degenerate, degenerate_reason, fdr`.

Inputs the ARCHS4 families need that this integration does not produce. The
CLAMPfull_bp prior `data/pathways/go_bp.Hs.symbols.gmt` is generated by
`generate_archs4_go_bp_gmt` (`workflow/rules/archs4.smk`, checksum-verified). Still to
document: **`[MARC: ARCHS4 raw h5 + preprocess outputs
(`00_preprocess/metadata_filtered.rds`, `fbm_filtered.bk`), the coverage cells'
`fbm_subsampled.bk` (written by `subsample_cells.R` but undeclared),
`scripts/archs4/clamp.R` referenced by `clampbase_bp_coverage_cell`, and the other
gene-set files under `data/pathways/` (`c2.cp.*`, `c5.go.cc.*`, `c8.all.*`, `h.all.*`,
`Cell_marker_Human.xlsx`) — where they come from and how to stage them.]`**

## 8. Verifying a run

- Every summary passes the gate the runner already applied:
  `python scripts/phenoplier/verify_summary.py <summary.tsv.gz> 2366` → `OK`
  (expected phenotype count, full phenotype × LV grid, p-values in (0, 1], NaN only
  on LVs flagged degenerate).
- Stores open: `python -c "import h5py,sys; h5py.File(sys.argv[1]).close()" <store.h5>`.
- Long table rows = Σ over models of (phenotypes × LVs); `model` ∈ {CLAMPfull_bp,
  CLAMPbase, CLAMPfull_canonical}.
- `snakemake -n <target>` afterwards reports nothing to do.
- Workspace: `<workspace>/models/registry.toml` lists `clamp/<name>` per model and
  each project carries `clamp_source.sha256` matching its `.rds`.

## 9. Troubleshooting

| symptom | cause / fix |
|---|---|
| `[ERROR] phenoplier-cli X in env … but 0.5.2 is required` | wrong release in the env; re-run `setup_env.sh` (or bump `phenoplier.yaml: version` deliberately). |
| `[ERROR] no phenoplier workspace at …` | set `phenoplier.yaml: workspace` (or `PHENOPLIER_HOME`) to a directory with `config.toml`. |
| `ModuleNotFoundError: rich` / `h5py` inside a job | a `phenoplier`/`python` shim earlier on PATH than the env; the runner prepends the env's bin, so check the job's shell startup files. |
| `[stale] model changed since this project was initialised` | expected after a refit: the old project is moved aside and the model re-registered. |
| `summary failed the completeness gate` | partial step 7 or wrong `trait_filter` for the project; the summary was deleted, re-run the target to resume. |
| `BrokenProcessPool` in step 7 | pools not matching the cgroup; lower `workers.step7` (keep `step7 × blas_step7 ≤ threads`). |
| Snakemake: `Job needs mem_mb=100000 but only … available` | local profile pool smaller than `resources.gls.mem_mb`; override the latter. |
| Zero p-values in a summary | the SE-collapse artifact fixed in v0.5.2 (#85); the gate refuses them — check the version. |

## 10. Layout

| path | what |
|---|---|
| `setup_env.sh` | one-time: build the `phenoplier-cli-neo` env (phenoplier-cli **v0.5.2** + rpy2/R) |
| `run_gls.sh` | one model → one GLS summary (version gate, fingerprint, register + init, pin pools, run, gate, publish); driven by the rules |
| `store_build.sh` | one model → one HDF5 study store; driven by the rules |
| `verify_summary.py` | completeness gate |
| `aggregate_traits.{py,sh}` | stream per-model summaries into one long cross-model table (chunked, gzipped) |
| `final_models/`, `saturation_k1728/`, `coverage/`, `clampbase/` | the as-run pico `sbatch` recipes (§11) |
| `RUN_SUMMARY.md` | what was actually run (86 models across 3 CLAMP families) + reproduce-on-pico index |

## 11. As-run record (pico)

The 86 models in `RUN_SUMMARY.md` were produced with the `sbatch` recipes under
`final_models/`, `saturation_k1728/`, `coverage/` and `clampbase/` before this module
was wired into the Snakefile. They remain the record of what ran; the rules above
are the reproducible path from here on and go through the same hardened flow
(`run_gls.sh` ≡ `clampbase/_run_clampbase_model.sh` minus the store step).
