# CLAMP analyses

## Setup

CLAMP uses three Conda environments: `clamp-analyses` (core CPU modeling/analysis),
`gpu-kmeans` (GPU clustering), and `snakemake` (pipeline orchestrator).

```bash
./setup.sh
```

Installs Conda if needed, creates all three environments, and installs the pinned
[`chikinalab/CLAMP`](https://github.com/chikinalab/CLAMP) R package into
`clamp-analyses`. Safe to re-run. Verify with `nbs/00_setup/00_check_setup.ipynb`.

> [!WARNING]
> Requires CLAMP commit
> [`748559ae6d4a9e2982d8f4488bae616fe390195a`](https://github.com/chikinalab/CLAMP/commit/748559ae6d4a9e2982d8f4488bae616fe390195a) —
> do not update it independently.

<details>
<summary>Manual setup, step by step</summary>

1. Install Conda (Miniconda or Mambaforge).
2. (Optional, for `gpu-kmeans`) verify GPU drivers with `nvidia-smi`.
3. Create the environments:
   ```bash
   conda create --name clamp-analyses --file envs/clamp-analyses.lock
   conda run -n clamp-analyses python -m pip install -r envs/clamp-analyses.pip.lock
   conda create --name gpu-kmeans --file envs/gpu-kmeans.lock
   conda env create -n snakemake -f envs/snakemake.yaml
   ```
4. Install the CLAMP R package:
   ```bash
   conda activate clamp-analyses
   Rscript scripts/install_clamp.R
   Rscript scripts/install_clamp.R --check   # verify only
   ```
</details>

Each notebook states its required environment in its first cell. Run all `snakemake`
commands from the repo root with `conda activate snakemake` and `--use-conda`:

```bash
snakemake --cores 4 --use-conda --snakefile workflow/Snakefile <target>
```

## Pseudobulk

Benchmarks CLAMP against other latent-variable/matrix-decomposition methods on pseudobulk
profiles built from single-cell/single-nucleus RNA-seq cohorts (brain, heart, PBMC, lung),
then projects the fitted latent variables back onto individual cells to check biological
interpretability. A donor-bulk extension collapses the same cells into one real bulk-like
library per donor, as an independent check that results aren't an artifact of pseudobulk
construction. Configuration: `workflow/config/pseudobulk.yaml`.

```bash
# End to end
snakemake --cores 4 --use-conda --snakefile workflow/Snakefile biology_pseudobulk panels_pseudobulk

# Donor-bulk extension
snakemake --cores 8 --resources donor_bulk_io=1 --use-conda \
  --snakefile workflow/Snakefile donor_bulk_report donor_bulk_figure2
```

## GTEx

Fits CLAMP and comparison methods on GTEx v8 bulk tissue expression, then checks whether
the latent variables recover known tissue/subtissue structure and specific biology (e.g.
liver cell-type composition via xCell). Configuration: `workflow/config/gtex.yaml`.

```bash
snakemake --cores 4 --use-conda --snakefile workflow/Snakefile biology_gtex
```

## ARCHS4

CLAMP fit across the full ARCHS4 human RNA-seq compendium (~605k samples). Its largest
fits need ~500 GB RAM and run on Slurm, not a workstation.

The GO:BP coverage and saturation campaigns are maintained independently. Their
published full-data models remain under `output/98_final_models/clampfull/bp/`.

These fits require `data/pathways/go_bp.Hs.symbols.gmt` (SHA-256
`33e559df968d0d8c2028c0f735624555dc2edbebe955648c3351dfa31cfd2e2a`).
Snakemake generates this file when missing from the GOALL Biological Process
mapping in `org.Hs.eg.db` 3.20.0 and term names in `GO.db` 3.20.0, then verifies
its checksum. The `pathway_prior` rule separately downloads the Enrichr file
`GO_Biological_Process_2025.gmt`, which is not interchangeable with this input.

Canonical-prior CLAMPfull models are published under
`output/98_final_models/clampfull/canonical/`, one each for ARCHS4, GTEx, and
recount2. They are evaluated by ORA against GO:BP, canonical, Reactome, and
CellMarker. Drug--disease and projection analyses consume these canonical artifacts
from their dedicated workflows. See [Canonical model + ORA](#canonical-model--ora).

Configuration: `workflow/config/archs4.yaml` and `workflow/config/recount2.yaml`.

### Canonical model + ORA

The canonical workflow is evaluation-only: it consumes the published model RDS,
loadings, model manifest, and adoption-validation record for each compendium. It does
not fit, adopt, or republish a model. ORA results live beside each model at
`output/98_final_models/clampfull/canonical/<compendium>/ora/` and the aggregated
tables are `ora.csv`, `ora_cross.csv`, and `ora_panel.csv`.

LINCS and S-PrediXcan projections are run by the drug--disease workflow against these
published canonical models. To register the existing canonical ORA outputs without
recomputing them:

```bash
snakemake --touch --cores 1 --snakefile workflow/Snakefile archs4_canonical_ora
```

## Running a single notebook

Each notebook-backed rule runs one specific notebook and writes the executed copy
back to it. Target it by rule name like any other rule:

```bash
snakemake --cores 1 --use-conda --snakefile workflow/Snakefile liver_disentangle_xcell_rf_true_labels_gtex
```

Snakemake skips a rule whose outputs are already newer than its inputs, so editing
a notebook's cells alone won't trigger a re-run. Force one with `-f`/`--forcerun`
(add `-R`/`--forceall` to also force everything downstream of it):

```bash
snakemake --cores 4 --use-conda --snakefile workflow/Snakefile -f <target>
```

## Rebuilding publication figures from notebooks

Run these from the repository root in the `clamp-analyses` environment after the
upstream analyses have produced their input files:

```bash
for name in fig2 fig3 supp1 supp2 supp3 supp4 supp5 supp6 supp7; do
  papermill "nbs/99_panels/${name}.ipynb" "nbs/99_panels/${name}.executed.ipynb" -k ir
done
```

Each notebook writes PDF, PNG, and SVG files to `output/99_panels/<name>/`.
Figure 2 can also run through its Snakemake rule:

```bash
snakemake output/99_panels/fig2/fig2.pdf --snakefile workflow/Snakefile --cores 4 --use-conda -R fig2_panel
```

| Figure | Required upstream data |
| --- | --- |
| Figure 2 | Pseudobulk benchmark, grouped cross-validation, cell-type recovery, donor-bulk recovery, and GTEx panel tables listed in its input-path cell and `workflow/rules/panels.smk`. |
| Figure 3 | ARCHS4 coverage, saturation, drug-disease, projection, and CRISPR-Cas9 results under `output/03_model_biology/02_archs4/`. |
| Supplements 1 and 3 | Pseudobulk benchmark and recovery tables, GTEx clustering and biology tables; Supplement 1 also uses pseudobulk runtime data, and Supplement 3 uses GTEx runtime data. |
| Supplement 2 | Donor-bulk recovery and UMAP tables under `output/03_model_biology/00_pseudobulk/06_donor_bulk_recovery/`. |
| Supplement 4 | ARCHS4 coverage and saturation tables under `output/03_model_biology/02_archs4/`. |
| Supplement 5 | ARCHS4 projection aggregate results, model loadings under `output/98_final_models/`, projection benchmark results, and pathway GMT/marker files under `data/pathways/` (or the sibling `clamp-analyses/data/pathways/`). The notebook regenerates its own `source_data` files. |
| Supplement 6 | Drug-disease prediction pickle and per-tissue comparison tables under `output/03_model_biology/02_archs4/02_drug_diseases_canonical/`; the notebook converts the pickle with the environment's Python. |
| Supplement 7 | CRISPR-Cas9 results under `output/03_model_biology/02_archs4/04_crispercas/`. |

Figure 4 is not part of this notebook set; there is no `fig4.ipynb` in
`nbs/99_panels/`.

## Citation

## License

This project is licensed under the [CC-BY 4.0 License](http://creativecommons.org/licenses/by/4.0/).

## Acknowledgments

Supported by the National Human Genome Research Institute,
The Eunice Kennedy Shriver National Institute of Child Health and Human Development,
the National Science Foundation, and the National Eye Institute.
