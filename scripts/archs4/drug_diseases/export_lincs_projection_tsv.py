#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lincs-projection", required=True, type=Path)
    parser.add_argument("--drugbank", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    projection = pd.read_pickle(args.lincs_projection)
    print(f"LINCS projection shape: {projection.shape}")

    drug_names = (
        pd.read_csv(args.drugbank, sep="\t", usecols=["drugbank_id", "name"])
        .rename(columns={"name": "drug_name"})
    )
    assert drug_names["drugbank_id"].is_unique
    missing = set(projection.columns) - set(drug_names["drugbank_id"])
    assert not missing, f"{len(missing)} drugs without a DrugBank name: {sorted(missing)[:10]}"

    lv_order = sorted(projection.index, key=lambda lv: int(lv.removeprefix("LV")))
    table = (
        projection.loc[lv_order]
        .rename_axis(index="LV", columns="drugbank_id")
        .stack()
        .rename("score")
        .reset_index()
        .merge(drug_names, on="drugbank_id", how="left")
        [["LV", "drugbank_id", "drug_name", "score"]]
    )
    assert len(table) == projection.size
    print(f"Rows: {len(table)} ({projection.shape[0]} LVs x {projection.shape[1]} drugs)")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    table.to_csv(args.output, sep="\t", index=False)
    print(f"Saved to: {args.output}")


if __name__ == "__main__":
    main()
