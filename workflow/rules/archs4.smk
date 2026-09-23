import os

# Shared ARCHS4 workflow context. Final models are published under
# output/98_final_models and consumed by their dedicated analyses.
A4_CFG = config["archs4"]
A4_PROD = A4_CFG["paths"]["production"]
A4_BIO = A4_CFG["paths"]["biology"]
A4_MODEL_NB = os.path.join(REPO_ROOT, A4_CFG["paths"]["model_notebooks"])
A4_BIO_NB = os.path.join(REPO_ROOT, A4_CFG["paths"]["biology_notebooks"])
A4_PREP = f"{A4_PROD}/00_preprocess"

rule generate_archs4_go_bp_gmt:
    input:
        script="scripts/archs4/generate_go_bp_gmt.R",
    output:
        A4_CFG["coverage"]["prior_gmt"],
    params:
        sha256="33e559df968d0d8c2028c0f735624555dc2edbebe955648c3351dfa31cfd2e2a",
    resources:
        mem_mb=8000,
        runtime=60,
    conda: "clamp-analyses"
    shell:
        "mkdir -p $(dirname {output:q}) && "
        "tmp=$(mktemp {output:q}.XXXXXX) && "
        "trap 'if test -e \"$tmp\"; then unlink \"$tmp\"; fi' EXIT && "
        "Rscript {input.script:q} \"$tmp\" && "
        "printf '%s  %s\\n' '{params.sha256}' \"$tmp\" | sha256sum --check --status && "
        "mv \"$tmp\" {output:q}"
