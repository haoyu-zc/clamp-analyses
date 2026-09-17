#!/usr/bin/env python3
"""Concatenate per-model phenoplier GLS summaries into one long table.

Each input is a summary published by run_gls.sh, named the way
scripts/archs4/traits/aggregate_*_traits.R expect:

    cov_rs<fraction>_seed<seed>.tsv.gz          ARCHS4 coverage cell
    sat_rs<fraction>_k<k>_seed<seed>.tsv.gz     ARCHS4 saturation cell
    final_<dataset>.tsv.gz                      published full-data model
    canon_<dataset>.tsv.gz                      published canonical model

The model family (CLAMPfull_bp vs CLAMPbase) is not in the filename -- it is
the directory a summary lives in -- so the caller passes each family's files
under its own flag.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import pandas as pd

PATTERNS = {
    "coverage": re.compile(r"^cov_rs(?P<fraction>\d+)_seed(?P<seed>\d+)$"),
    "saturation": re.compile(r"^sat_rs(?P<fraction>\d+)_k(?P<k>\d+)_seed(?P<seed>\d+)$"),
    "final": re.compile(r"^final_(?P<dataset>[A-Za-z0-9]+)$"),
    "canonical": re.compile(r"^canon_(?P<dataset>[A-Za-z0-9]+)$"),
}


def parse_summary_name(path: Path) -> dict:
    stem = path.name[: -len(".tsv.gz")] if path.name.endswith(".tsv.gz") else path.stem
    for study, pattern in PATTERNS.items():
        match = pattern.match(stem)
        if match:
            fields = {"study": study, "dataset": "archs4", "fraction": None, "k": None, "seed": None}
            for key, value in match.groupdict().items():
                fields[key] = int(value) if key in {"fraction", "k", "seed"} else value
            return fields
    raise SystemExit(f"Unrecognised summary name: {path}")


def load(paths: list[str], model: str) -> list[pd.DataFrame]:
    frames = []
    for raw in paths:
        path = Path(raw)
        df = pd.read_csv(path, sep="\t", low_memory=False)
        for field, value in parse_summary_name(path).items():
            df[field] = value
        df["model"] = model
        df["summary"] = str(path)
        frames.append(df)
    return frames


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--clampfull-bp", nargs="*", default=[], help="CLAMPfull_bp summaries")
    parser.add_argument("--clampbase", nargs="*", default=[], help="CLAMPbase summaries")
    parser.add_argument("--canonical", nargs="*", default=[], help="CLAMPfull_canonical summaries")
    args = parser.parse_args()

    frames = (
        load(args.clampfull_bp, "CLAMPfull_bp")
        + load(args.clampbase, "CLAMPbase")
        + load(args.canonical, "CLAMPfull_canonical")
    )
    if not frames:
        raise SystemExit("No summaries given")

    combined = pd.concat(frames, ignore_index=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    combined.to_csv(args.out, index=False)
    print(f"{len(frames)} summaries, {len(combined)} rows -> {args.out}")


if __name__ == "__main__":
    main()
