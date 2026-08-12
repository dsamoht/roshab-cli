#!/usr/bin/env python3
"""Summarise merged BGC calls (antiSMASH / GECCO / DeepBGC) for a group of samples.

Produces a two-panel figure:
  1. product class x sample heatmap (number of predicted regions)
  2. regions per sample, stacked by how many tools supported each region
"""

import argparse
import os

import matplotlib
matplotlib.use('Agg')

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns

CONFIDENCE_ORDER = ['high', 'low', 'single-tool']
CONFIDENCE_COLORS = {'high': '#225ea8', 'low': '#7fcdbb', 'single-tool': '#c7e9b4'}


def parse_args():
    parser = argparse.ArgumentParser(description="Plot merged BGC predictions for a sample group.")
    parser.add_argument('-i', '--input', nargs='+', required=True, help='Merged BGC TSV files')
    parser.add_argument('-o', '--output', default='bgc_overview.pdf', help='Output figure')
    parser.add_argument('-s', '--summary', default='bgc_summary.tsv', help='Output summary table')
    return parser.parse_args()


def load(paths):
    frames = []
    for path in paths:
        try:
            frame = pd.read_csv(path, sep='\t')
        except Exception as error:
            print(f"Error reading {path}: {error}")
            continue

        if frame.empty:
            continue

        if 'sample' not in frame.columns:
            frame['sample'] = os.path.basename(path).replace('.bgc.tsv', '')

        frames.append(frame)

    if not frames:
        return pd.DataFrame()

    return pd.concat(frames, ignore_index=True)


def explode_products(df):
    """One row per (region, product class); regions with several products count once each."""
    products = df.assign(product=df['products'].fillna('unknown').str.split(','))
    products = products.explode('product')
    products['product'] = products['product'].str.strip().str.lower().replace('', 'unknown')
    return products


def main():
    args = parse_args()
    df = load(args.input)

    if df.empty:
        print("No BGC regions found across the group. Exiting.")
        return

    exploded = explode_products(df)

    counts = (exploded
              .groupby(['sample', 'product'])
              .size()
              .reset_index(name='n_regions'))

    high = (exploded[exploded['confidence'] == 'high']
            .groupby(['sample', 'product'])
            .size()
            .reset_index(name='n_high_confidence'))

    summary = counts.merge(high, on=['sample', 'product'], how='left')
    summary['n_high_confidence'] = summary['n_high_confidence'].fillna(0).astype(int)
    summary = summary.sort_values(['sample', 'n_regions'], ascending=[True, False])
    summary.to_csv(args.summary, sep='\t', index=False)
    print(f"Successfully generated {args.summary}")

    pivot = counts.pivot(index='sample', columns='product', values='n_regions').fillna(0)
    pivot = pivot[pivot.sum().sort_values(ascending=False).index]

    by_confidence = (df.groupby(['sample', 'confidence'])
                     .size()
                     .unstack(fill_value=0))
    for tier in CONFIDENCE_ORDER:
        if tier not in by_confidence.columns:
            by_confidence[tier] = 0
    by_confidence = by_confidence[CONFIDENCE_ORDER]

    n_samples = max(pivot.shape[0], 1)
    n_products = max(pivot.shape[1], 1)

    fig, axes = plt.subplots(
        2, 1,
        figsize=(max(10, 0.8 * n_products + 4), max(8, 0.6 * n_samples + 6)),
        gridspec_kw={'height_ratios': [3, 1]}
    )

    sns.heatmap(
        pivot,
        cmap='YlGnBu',
        annot=True,
        fmt='g',
        linewidths=.5,
        ax=axes[0],
        cbar_kws={'label': 'predicted region count'}
    )
    axes[0].set_title("Biosynthetic gene clusters per product class", fontsize=16, fontweight='bold', pad=15)
    axes[0].set_xlabel("product class", fontsize=12)
    axes[0].set_ylabel("sample(s)", fontsize=12)
    plt.setp(axes[0].get_xticklabels(), rotation=45, ha="right", rotation_mode="anchor")

    bottom = None
    for tier in CONFIDENCE_ORDER:
        values = by_confidence[tier]
        axes[1].bar(by_confidence.index, values, bottom=bottom,
                    label=tier, color=CONFIDENCE_COLORS[tier])
        bottom = values if bottom is None else bottom + values

    axes[1].set_title("Regions per sample by tool support", fontsize=14, fontweight='bold', pad=10)
    axes[1].set_ylabel("region count", fontsize=12)
    axes[1].set_xlabel("sample(s)", fontsize=12)
    axes[1].legend(title='confidence', frameon=False)
    plt.setp(axes[1].get_xticklabels(), rotation=45, ha="right", rotation_mode="anchor")

    plt.tight_layout()
    plt.savefig(args.output, bbox_inches='tight')
    print(f"Successfully generated {args.output}")


if __name__ == '__main__':
    main()
