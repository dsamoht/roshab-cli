#!/usr/bin/env python3
"""Summarise the antiSMASH BGC regions of a group of samples.

Reads the antiSMASH JSON reports directly, one per sample, and produces a
product class x sample heatmap of the number of predicted regions.

A region is counted once per product class it carries, so a hybrid region
(`nrps,t1pks`) contributes to both columns. The sample name is taken from the
JSON filename, which antiSMASH names after `--output-basename`, i.e. `meta.id`.
"""

import argparse
import json
import os
import re

import matplotlib
matplotlib.use('Agg')

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns

LOCATION_RE = re.compile(r'\[?(?P<start>[<>]?\d+):(?P<end>[<>]?\d+)\]?')


def parse_args():
    parser = argparse.ArgumentParser(description="Plot the antiSMASH BGC regions of a sample group.")
    parser.add_argument('-i', '--input', nargs='+', required=True, help='antiSMASH JSON reports')
    parser.add_argument('-o', '--output', default='bgc_overview.pdf', help='Output figure')
    parser.add_argument('-s', '--summary', default='bgc_summary.tsv', help='Output summary table')
    return parser.parse_args()


def clean_int(value):
    """Coordinates may carry biopython fuzzy markers ('<1', '>4200')."""
    return int(str(value).strip().lstrip('<>'))


def parse_antismash(path):
    """antiSMASH >= 6 stores regions per record under 'areas'."""
    regions = []
    with open(path) as handle:
        data = json.load(handle)

    for record in data.get('records', []):
        contig = record.get('id', 'unknown')

        areas = record.get('areas')
        if areas:
            for area in areas:
                try:
                    start = clean_int(area['start'])
                    end = clean_int(area['end'])
                except (KeyError, ValueError):
                    continue
                products = area.get('products') or []
                regions.append((contig, start, end, sorted(set(products))))
            continue

        # Fallback for layouts without 'areas': read the region features.
        for feature in record.get('features', []):
            if feature.get('type') != 'region':
                continue
            match = LOCATION_RE.search(str(feature.get('location', '')))
            if not match:
                continue
            start = clean_int(match.group('start'))
            end = clean_int(match.group('end'))
            products = feature.get('qualifiers', {}).get('product', [])
            regions.append((contig, start, end, sorted(set(products))))

    return regions


def sample_name(path):
    """antiSMASH writes `<meta.id>.json`, so the stem is the sample name."""
    return os.path.basename(path).rsplit('.json', 1)[0]


def load(paths):
    rows = []
    for path in paths:
        sample = sample_name(path)
        try:
            regions = parse_antismash(path)
        except Exception as error:  # a malformed report must not sink the group
            print(f"Error reading {path}: {error}")
            continue

        print(f"{sample}: {len(regions)} region(s)")
        for contig, start, end, products in regions:
            rows.append({
                'sample': sample,
                'contig': contig,
                'start': start,
                'end': end,
                'length': end - start,
                'products': ','.join(products) if products else 'unknown',
            })

    return pd.DataFrame(rows)


def explode_products(df):
    """One row per (region, product class); regions with several products count once each."""
    products = df.assign(product=df['products'].fillna('unknown').str.split(','))
    products = products.explode('product')
    products['product'] = products['product'].str.strip().str.lower().replace('', 'unknown')
    return products


def main():
    args = parse_args()

    # Every input report is a sample that was screened, whether or not it carried a
    # region. A sample missing from the figure is indistinguishable from a sample
    # with no BGC, and those mean very different things.
    samples = sorted({sample_name(path) for path in args.input})

    df = load(args.input)

    counts = pd.DataFrame(columns=['sample', 'product', 'n_regions'])
    if not df.empty:
        counts = (explode_products(df)
                  .groupby(['sample', 'product'])
                  .size()
                  .reset_index(name='n_regions'))

    # Written even when empty: a summary with a header and no rows is the record
    # that the group was screened and nothing was found.
    summary = counts.sort_values(['sample', 'n_regions'], ascending=[True, False])
    summary.to_csv(args.summary, sep='\t', index=False)
    print(f"Successfully generated {args.summary}")

    if counts.empty:
        pivot = pd.DataFrame(0, index=samples, columns=['none detected'])
        print("No BGC region found across the group; drawing a zero heatmap.")
    else:
        pivot = (counts
                 .pivot(index='sample', columns='product', values='n_regions')
                 .reindex(index=samples)
                 .fillna(0))
        pivot = pivot[pivot.sum().sort_values(ascending=False).index]

    n_samples = max(pivot.shape[0], 1)
    n_products = max(pivot.shape[1], 1)

    fig, ax = plt.subplots(figsize=(max(10, 0.8 * n_products + 4), max(6, 0.6 * n_samples + 4)))

    sns.heatmap(
        pivot.astype(int),
        cmap='YlGnBu',
        annot=True,
        fmt='g',
        linewidths=.5,
        ax=ax,
        cbar_kws={'label': 'predicted region count'}
    )
    ax.set_title("Biosynthetic gene clusters per product class", fontsize=16, fontweight='bold', pad=15)
    ax.set_xlabel("product class", fontsize=12)
    ax.set_ylabel("sample(s)", fontsize=12)
    plt.setp(ax.get_xticklabels(), rotation=45, ha="right", rotation_mode="anchor")

    plt.tight_layout()
    plt.savefig(args.output, bbox_inches='tight')
    plt.close(fig)
    print(f"Successfully generated {args.output}")


if __name__ == '__main__':
    main()
