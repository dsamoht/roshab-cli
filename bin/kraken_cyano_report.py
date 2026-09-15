#!/usr/bin/env python3
"""Stacked barplots of the combined Kraken2/Bracken MPA table of one group.

Two panels are drawn per view: the top phyla relative to everything classified,
and the top genera within Cyanobacteriota. Which view is used depends on the
samplesheet: a single sampling date gives one plot per group across sites, and
several dates give one plot per site across time.

Nothing here may fail the run -- the module carries `error_ignore` -- so a
degenerate table (an index with no cyanobacteria, a sample with no classified
reads) has to produce a readable page saying so rather than a blank chart.
"""

import argparse
import sys

import matplotlib
matplotlib.use('Agg')

from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.pyplot as plt
import pandas as pd


# source : https://sashamaps.net/docs/resources/20-colors/
DISTINCT_COLORS = ['#e6194B', '#3cb44b', '#ffe119', '#4363d8', '#f58231',
                   '#911eb4', '#42d4f4', '#f032e6', '#bfef45', '#fabed4',
                   '#469990', '#dcbeff', '#9A6324', '#fffac8', '#800000',
                   '#aaffc3', '#808000', '#ffd8b1', '#000075', '#a9a9a9',
                   '#000000']

# The rows KrakenTools writes for the unranked top of the tree. They carry the
# classified total, which is what the top phyla are expressed as a fraction of.
ROOT_ROWS = ('x__cellular_organisms', 'x__Viruses')

REQUIRED_SAMPLESHEET_COLUMNS = ('sample_id', 'date', 'info')


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('-i', '--input',       help='combined (multiple samples) kraken report', required=True)
    parser.add_argument('-n', '--name',        help='name associated to the input report',        required=True)
    parser.add_argument('-s', '--samplesheet', help='samplesheet CSV (sample_id,group,info,date,reads)', required=True)
    parser.add_argument('--top-n', type=int, default=10,
                        help='Number of taxa drawn per panel before the rest is pooled as "Others"')
    return parser.parse_args()


def load_samplesheet(path):
    """Return a dict mapping sample_id -> {'date': ..., 'site': ...}."""
    ss = pd.read_csv(path)
    missing = [column for column in REQUIRED_SAMPLESHEET_COLUMNS if column not in ss.columns]
    if missing:
        sys.exit(f"ERROR: {path} has no {', '.join(missing)} column(s); "
                 f"the columns present are: {', '.join(map(str, ss.columns))}")
    return {
        str(row['sample_id']): {'date': str(row['date']), 'site': str(row['info'])}
        for _, row in ss.iterrows()
    }


def relative_abundance(table, label):
    """Column-wise relative abundance, leaving a sample with no reads at zero.

    Dividing by a zero column total would give a column of NaN, which matplotlib
    draws as an empty bar with no hint that the sample simply had nothing to
    classify.
    """
    totals = table.sum()
    empty = [str(column) for column, total in totals.items() if total <= 0]
    if empty:
        print(f"{label}: no classified reads for {', '.join(empty)}; drawn as an empty bar.",
              file=sys.stderr)
    return table.divide(totals.mask(totals <= 0, 1.0), axis=1)


def strip_unranked(index):
    """Drop the `x__` pseudo-ranks from a lineage string."""
    return ["|".join([part for part in str(name).split("|") if "x__" not in part]) for name in index]


def top_n_taxlevel_relative_to_all(df, taxa_level="p", top_n=10):
    """Top phyla as a fraction of everything classified."""
    tax_level_table = df.loc[[str(i) for i in df.index if str(i).split("|")[-1].startswith(f"{taxa_level}__")]]
    if tax_level_table.empty:
        return pd.DataFrame()

    top_n_by_sum = tax_level_table.loc[tax_level_table.sum(axis=1).nlargest(top_n).index]

    # `Others` is whatever the classified total leaves over. A report without the
    # unranked root rows -- a viral-only index, or one built without intermediate
    # ranks -- would otherwise make `Others` the negative of the top ranks, and
    # the column would sum to zero and normalise to infinity. Fall back to the
    # ranks themselves there, and never let rounding push `Others` below zero.
    roots = [name for name in ROOT_ROWS if name in df.index]
    total = df.loc[roots].sum() if roots else tax_level_table.sum()
    others_row = (total - top_n_by_sum.sum()).clip(lower=0)

    result_df = pd.concat([top_n_by_sum, others_row.to_frame('Others').T])
    result_df = relative_abundance(result_df, f"top {top_n} {taxa_level}__")
    result_df.index = strip_unranked(result_df.index)
    return result_df


def top_n_taxlevel_relative_to_parent(df, parent='p__Cyanobacteriota', taxa_level='g', top_n=10):
    """Top genera as a fraction of their parent clade."""
    tax_level_table = df.loc[[str(i) for i in df.index
                              if parent in str(i) and str(i).split("|")[-1].startswith(f"{taxa_level}__")]]
    if tax_level_table.empty:
        return pd.DataFrame()

    top_n_by_sum = tax_level_table.loc[tax_level_table.sum(axis=1).nlargest(top_n).index]
    others_row   = tax_level_table.loc[~tax_level_table.index.isin(top_n_by_sum.index)].sum()

    result_df = pd.concat([top_n_by_sum, others_row.to_frame('Others').T])
    result_df = relative_abundance(result_df, f"top {top_n} {taxa_level}__ within {parent}")
    result_df.index = strip_unranked(result_df.index)
    result_df.index = [str(name).split(f'|{taxa_level}__')[-1] for name in result_df.index]
    return result_df


def note_page(pdf_handle, message):
    """A PDF with no pages is invalid, and matplotlib drops support for one in 3.10."""
    fig = plt.figure(figsize=(10, 6))
    fig.text(0.5, 0.5, message, ha='center', va='center', wrap=True, fontsize=12)
    pdf_handle.savefig(fig)
    plt.close(fig)


def stacked_barplot(df, pdf_handle, title=None):
    """Draw one panel. Returns the number of pages written, so 0 when skipped."""
    if df is None or df.empty or df.shape[1] == 0:
        print(f"Skipping '{title}': the table is empty.", file=sys.stderr)
        return 0
    if not df.to_numpy().any():
        print(f"Skipping '{title}': every value is zero.", file=sys.stderr)
        return 0

    # Cycle the palette rather than indexing past its end: `top_n` is a parameter.
    colors = [DISTINCT_COLORS[i % len(DISTINCT_COLORS)] for i in range(len(df.index))]

    ax = df.T.plot(kind='bar',
                   figsize=(10, 6),
                   stacked=True,
                   legend=False,
                   color=colors,
                   edgecolor='k',
                   title=title)
    try:
        ax.set_ylabel('Relative abundance')
        legend = ax.legend(title='', bbox_to_anchor=(1.02, 0.5), loc='center left', borderaxespad=0)
        if legend is not None:
            for text in legend.get_texts():
                if text.get_text() != 'Others':
                    text.set_fontstyle('italic')
        plt.tight_layout()
        pdf_handle.savefig()
    finally:
        plt.close()
    return 1


def draw_panels(df, pdf_handle, label, top_n):
    """The two panels drawn for every view, each independent of the other."""
    pages = 0
    panels = [
        (top_n_taxlevel_relative_to_all,
         f"{label} - Relative abundance of top {top_n} phyla"),
        (top_n_taxlevel_relative_to_parent,
         f"{label} - Relative abundance of top {top_n} genera within Cyanobacteriota"),
    ]
    for build, title in panels:
        try:
            pages += stacked_barplot(build(df, top_n=top_n), pdf_handle, title=title)
        except Exception as error:  # one bad panel must not cost the whole report
            print(f"Skipping '{title}': {error}", file=sys.stderr)
    return pages


def plot_spatial(df, pdf_handle, metadata, top_n):
    """Single time-point: one plot per group, x-axis = sites."""
    dates = [metadata.get(col, {}).get('date', col) for col in df.columns]
    sites = [metadata.get(col, {}).get('site', col) for col in df.columns]

    # Only run when all samples share the same date
    if len(set(dates)) > 1:
        return 0

    # Sort columns by site name and rename to site labels
    sorted_cols = [col for _, col in sorted(zip(sites, map(str, df.columns)))]
    df = df[sorted_cols].copy()
    df.columns = [metadata.get(col, {}).get('site', col) for col in sorted_cols]

    return draw_panels(df, pdf_handle, dates[0], top_n)


def plot_longitudinal(df, pdf_handle, metadata, top_n):
    """Multiple time-points: one plot per site, x-axis = dates."""
    dates = [metadata.get(col, {}).get('date', col) for col in df.columns]
    sites = [metadata.get(col, {}).get('site', col) for col in df.columns]

    # Only run when there are multiple dates
    if len(set(dates)) <= 1:
        return 0

    # Sort by date
    sorted_cols = [col for _, col in sorted(zip(dates, map(str, df.columns)))]
    df = df[sorted_cols].copy()
    sites = [metadata.get(col, {}).get('site', col) for col in sorted_cols]

    pages = 0
    # `sorted`, not `set`: the page order of the report has to be the same on a
    # rerun, and set iteration order varies with the hash seed.
    for site in sorted(set(sites)):
        site_cols  = [col for col, s in zip(sorted_cols, sites) if s == site]
        site_dates = [metadata.get(col, {}).get('date', col) for col in site_cols]

        site_df = df[site_cols].copy()
        site_df.columns = site_dates  # rename columns to dates for the x-axis

        pages += draw_panels(site_df, pdf_handle, site, top_n)

    return pages


def main():
    args     = parse_arguments()
    metadata = load_samplesheet(args.samplesheet)
    name     = args.name.strip().replace(' ', '_')

    df = pd.read_csv(args.input, sep='\t', header=0, index_col=0)
    df.columns = [str(column) for column in df.columns]
    df = df.apply(pd.to_numeric, errors='coerce').fillna(0)

    unknown = [column for column in df.columns if column not in metadata]
    if unknown:
        print(f"Warning: {len(unknown)} column(s) of {args.input} are not in the samplesheet "
              f"and keep their own name as site and date: {', '.join(unknown[:5])}"
              f"{' ...' if len(unknown) > 5 else ''}", file=sys.stderr)

    output = f"group_{name}_kraken_cyano_barplots.pdf"
    with PdfPages(output) as pdf_out:
        pages  = plot_spatial(df, pdf_out, metadata, args.top_n)
        pages += plot_longitudinal(df, pdf_out, metadata, args.top_n)

        if not pages:
            note_page(pdf_out,
                      f"No taxonomic barplot could be drawn for group {name}.\n\n"
                      f"{df.shape[0]} taxon row(s) over {df.shape[1]} sample(s) were read from "
                      f"{args.input},\nbut none of them carried a phylum or a genus within "
                      f"Cyanobacteriota.\nCheck that the Kraken2 index covers the clades of interest.")
            print(f"No panel could be drawn; {output} carries an explanatory page instead.",
                  file=sys.stderr)

    print(f"Successfully generated {output} ({pages} chart page(s))")


if __name__ == "__main__":
    main()
