# CLAMP GLS runs — cross-machine progress tracker

_Living doc. Last updated: 2026-09-03 ~16:30 (post-rebalance)._ Status legend: ✅ done+verified · 🔵 running · ⏳ queued/pending · 🛠️ provisioning · ⚪ not started

> **Rebalance 2026-09-03:** cancelled pico's 12 redundant deep-tail coverage tasks (rs25/50/75/100 — all owned by local/lab); freed lab from rs10_s3 (pico keeps it). Then offloaded pico's 4 pending **saturation** models (rs10_s3, rs25_s1/s2/s3) to the freed lab. Pico still baselines rs1–rs10 coverage + the running saturation + finals. **Non-overlapping pico jobs were left untouched.**

## Machines
| machine | role | env | notes |
|---|---|---|---|
| **pico** (DBMILAPPC01) | SLURM baseline; runs **everything** | v0.5.2 | 168 cores / 900 GB, shared `/pividori_lab`. Central collection lives here. |
| **local** (pop-os) | offload runner (no cgroup) | v0.5.2 | 48c/251 GB, `/media/data`. Results stay local. |
| ~~**alpine**~~ (CU HPC) | **retired for CLAMPbase** | v0.5.2 | rs50×3 stuck `QOSGrpNodeLim` on cpu-long → cancelled; rs50 moved to local. |
| **lab** (pivlab01) | offload runner (no cgroup) | v0.5.2 ✅ | 48c/251 GB. Provisioned (env cloned to identical paths + 82 GB data + workspace). Results stay local. |

Pipeline hardening applied to every run: serial **step6** (`n_workers_step6=1`, no fork deadlock),
capped **step7** (cgroup: `6×2`; no-cgroup: `12×1` single-threaded + `OMP=1`), store gated on a
**complete** combined summary (2366 unique phenotypes), atomic RDS stream + atomic store build.

---

## Batch 1 — CLAMPfull_bp  ✅ **41/41 DONE + verified**
All on pico central. Verified: 2366 phenotypes, 0 zero-p, NaN only on flagged degenerate LVs
(2 models each have 1 degenerate LV: cov_rs50_seed2 LV161, sat_rs5_k1728_seed2 LV866 — expected).

| study | count | status | central location on pico |
|---|---|---|---|
| Finals (archs4/gtex/recount2) | 3 | ✅ | stores `clamp_final_stores/`; summaries `projects/final_*_CLAMPfull_bp/results/gls/phenoplier/` |
| Saturation k1728 | 17 | ✅ | stores `clamp_saturation_stores/`; summaries in each `projects/sat_*/…` |
| Coverage (rs1–100 × seed1-3) | 21 | ✅ | `clamp_coverage/summaries/` (21) + `clamp_coverage/stores/` (21) |

Transfer to central: **complete** (local/alpine/ex-Alpine results all folded in; rs100_seed1 = reused finals archs4).

---

## Batch 2 — CLAMPbase  🔵 in progress (41 models)

### On pico (baseline — trimmed to non-offloaded work) — **11/25 done**
After the rebalance the 41 models are partitioned with **no redundancy**: **pico 25 + local 8 + lab 8**.
| study | pico owns | done | status |
|---|---|---|---|
| Finals | 3 | **3 ✅** | archs4/gtex/recount2 all done |
| Saturation k1728 | 13 (17 − 4 offloaded) | **5** | 🔵 8 running (rs10_s3 + rs25×3 offloaded to lab & cancelled here) |
| Coverage | 9 (21 − 12 offloaded) | **3** (rs1×3) | 🔵 rs5×3 + rs10×3 running (deep tail rs25–100 owned by local/lab) |

Central (pico): `/pividori_lab/phenoplier_workspace/clampbase_{finals,saturation,coverage}/{stores,summaries}/`

### Distributed tail (redundant accelerators — results stay on each runner)
Offloaded the 13 deepest-tail coverage models (pico reaches these last). Pico still runs them as baseline.

**Offload COMPLETE: 16/16 done** ✅ — local 8/8 (rs100×3, rs25_s2/s3, rs50×3), lab 4/4 coverage (rs75×3, rs25_s1) + 4/4 saturation (rs10_s3, rs25×3). rs10_s3 handed back to pico. Only pico's own 25 remain (20/25). _(Note: lab's last 2 sat store-builds were redone after an `scp`-over-running-helper race corrupted the script mid-run; GLS results were unaffected.)_

| model | machine | mem | status |
|---|---|---|---|
| cov_rs100_seed1/2/3 | **local** | 88 G | ✅ **all 3 done** (heaviest models cleared first) |
| cov_rs25_seed2 | **local** | 56 G | ✅ done |
| cov_rs25_seed3 | **local** | 56 G | 🔵 running |
| cov_rs50_seed1/2/3 | **local** | 56 G | 🔵 seed1/2 running, seed3 queued |
| cov_rs75_seed1/2/3 | **lab** | 64 G | ✅ **all 3 done** |
| cov_rs25_seed1 | **lab** | 56 G | ✅ done |
| ~~cov_rs10_seed3~~ | ~~lab~~ → **pico** | — | dropped from lab (pico was already running it); pico keeps it |
| **sat** rs10_s3, rs25_s1/s2/s3 (k1728) | **lab** (new) | ~64 G | 🔵 running 2-wide (rs10_s3 + rs25_s1 extracting; rs25_s2/s3 queued). Pico's pending copies cancelled. |

Runner result locations (NOT transferred to pico — user cross-checks later):
- local: `/media/data/clampbase_coverage/{stores,summaries}/` (local's 8: rs100×3, rs25_s2/s3, rs50×3)
- lab coverage: `/home/haoyu/clampbase_coverage/{stores,summaries}/` (rs75×3, rs25_s1)
- lab saturation: `/home/haoyu/clampbase_saturation/{stores,summaries}/` (4 offloaded sat)
- ~~alpine~~: retired (jobs cancelled; no results kept)

Left to pico only (it reaches them soonest): cov rs1×3, rs5×3, rs10_s1/s2.

---

## Batch 3 — CLAMPfull_canonical (urgent, colleague's CRISPR-Cas request) 🔵
3 canonical models: `…/98_final_models/clampfull/canonical/<t>/CLAMPfull_canonical.rds` (archs4 7.6 G/1728 LVs, recount2 155 M, gtex 94 M). Namespace `clampcanonical`.

**Key constraint:** phenoplier-cli has no LV-subset knob (step6 always `1~N`, step7 enumerates all). So the 89-LV prelim is driven **manually**: step1–5 via `snakemake --until step5_filter_by_distance`, then `step6-generate-lv-matrices -l "686 588 …"` + `trait-association-batch --lv-list "LV686 …"`, then summarize. step6 is per-LV idempotent so the full rerun reuses the 89 + step1–5.

| model | machine | LVs | status | output |
|---|---|---|---|---|
| **archs4 — PRELIM (89 LVs)** | local | 89 subset | ✅ **DONE + verified** — 89 LVs × 2366 phenos, 367 sig (FDR<0.05) | `/media/data/clampcanonical/archs4_prelim89/gls-summary-archs4_canonical_prelim89.tsv.gz` |
| **archs4 — FULL** | local | 1728 | ✅ **done + verified** — 1728 LVs × 2366 phenos, 5512 sig, 182 M store. **89 prelim LVs match full run EXACTLY** (Δpvalue = 0) | `/media/data/clampcanonical/{stores,summaries}/canon_archs4_full.*` |
| **recount2** | local | all | ✅ **done** (55 M store) | `/media/data/clampcanonical/{stores,summaries}/canon_recount2_CLAMPfull_canonical.*` |
| **gtex** | lab | all | ✅ **done** | `/home/haoyu/clampcanonical/{stores,summaries}/` |

89 significant LVs from `~/Downloads/significant_lvs_canonical.csv` (LV686…LV1702). Prelim deliverable = GLS summary (89 LVs × 2366 phenotypes).

---

## Transfer-to-central-pico status
| batch | to pico central | notes |
|---|---|---|
| CLAMPfull | ✅ complete (41/41) | all machines' results folded into `clamp_*` collections |
| CLAMPbase — pico baseline | writes central directly | as each model finishes on pico |
| CLAMPbase — local/lab | ⏸️ **held on runners** | per user: cross-check + transfer decided later (alpine retired) |

## Verification gate (per model, before trusting)
Combined summary present · gls-dir = 2366 files · 2366 unique phenotypes · 0 zero-pvalues ·
NaN only where `lv_degenerate=True` · store opens + built from complete data.
Checker: `scripts/phenoplier/clampbase/verify_summary.py`.

## Scripts
`scripts/phenoplier/clampbase/`: `_run_clampbase_model.sh` (hardened per-model), `run_local_clampbase.sh`
(local/lab worklist), `alpine_clampbase.sbatch`, `finals/sat/cov_clampbase.sbatch` (pico), `verify_summary.py`.
