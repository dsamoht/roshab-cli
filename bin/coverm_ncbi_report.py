#!/usr/bin/env python3
"""Barplots of the CoverM per-genome coverage of one group.

The trimmed mean is plotted, over sites for a single sampling date and over
dates for several. Genomes with no coverage anywhere in a panel are left out.

Nothing here may fail the run -- the module carries `error_ignore` -- so an
all-zero table has to produce a readable page saying so rather than a PDF with
no pages in it.
"""

import argparse
import sys

import matplotlib
matplotlib.use('Agg')

from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.pyplot as plt
import pandas as pd


# CoverM names every column `<sample> <method>`, in the order given to `--methods`.
TRIMMED_MEAN_SUFFIX = ' Trimmed Mean'

REQUIRED_SAMPLESHEET_COLUMNS = ('sample_id', 'date', 'info')

# Above this many series a bar chart legend stops being readable. Reported, not
# enforced: which genomes to keep is the operator's call, via `--top-n`.
LEGEND_WARNING_THRESHOLD = 25


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('-i', '--input',       help='coverm output table',   required=True)
    parser.add_argument('-n', '--name',        help='name for the output',   required=True)
    parser.add_argument('-s', '--samplesheet', help='samplesheet CSV (sample_id,group,info,date,reads)', required=True)
    parser.add_argument('--top-n', type=int, default=0,
                        help='Draw only the N best-covered genomes per panel. '
                             '0, the default, draws every genome with non-zero coverage. '
                             'The full table is published next to the figure either way.')
    return parser.parse_args()


def load_samplesheet(path):
    ss = pd.read_csv(path)
    missing = [column for column in REQUIRED_SAMPLESHEET_COLUMNS if column not in ss.columns]
    if missing:
        sys.exit(f"ERROR: {path} has no {', '.join(missing)} column(s); "
                 f"the columns present are: {', '.join(map(str, ss.columns))}")
    return {
        str(row['sample_id']): {'date': str(row['date']), 'site': str(row['info'])}
        for _, row in ss.iterrows()
    }


def extract_trimmed_mean(df):
    """Select the trimmed-mean columns by name.

    Selecting by position instead would tie this script to the exact `--methods`
    list in `conf/modules.config`: adding or removing a method there would shift
    every column and silently plot the wrong numbers.
    """
    columns = [column for column in df.columns if str(column).endswith(TRIMMED_MEAN_SUFFIX)]
    if not columns:
        sys.exit("ERROR: the CoverM table has no '... Trimmed Mean' column, so there is nothing "
                 "to plot.\n       `coverm genome` must be run with `trimmed_mean` among its "
                 "`--methods`.\n"
                 f"       Columns present: {', '.join(map(str, df.columns))}")
    return df[columns].copy()


def _sample_name_from_col(col):
    return str(col).replace(TRIMMED_MEAN_SUFFIX, '').strip()


def drop_empty_genomes(table, top_n):
    """Keep the genomes with coverage somewhere in this panel, best first."""
    totals = table.sum()
    covered = totals[totals > 0].sort_values(ascending=False)
    if top_n and len(covered) > top_n:
        print(f"  {len(covered)} genomes covered, drawing the {top_n} best; "
              f"the full table is in the published CoverM TSV.")
        covered = covered.head(top_n)
    elif len(covered) > LEGEND_WARNING_THRESHOLD:
        print(f"  {len(covered)} genomes covered: the legend will be crowded. "
              f"Pass `--top-n` to draw only the best-covered ones.", file=sys.stderr)
    return table[covered.index]


def note_page(pdf_handle, message):
    """A PDF with no pages is invalid, and matplotlib drops support for one in 3.10."""
    fig = plt.figure(figsize=(10, 6))
    fig.text(0.5, 0.5, message, ha='center', va='center', wrap=True, fontsize=12)
    pdf_handle.savefig(fig)
    plt.close(fig)


def coverage_barplot(table, pdf_handle, xlabel, title):
    """Draw one panel. Returns the number of pages written, so 0 when skipped."""
    if table.empty or table.shape[1] == 0:
        print(f"Skipping '{title}': no non-zero coverage values.")
        return 0

    ax = table.plot(
        kind='bar',
        stacked=False,
        edgecolor='black',
        figsize=(10, 6),
        ylabel='coverage',
        xlabel=xlabel,
        title=title,
    )
    try:
        ax.legend(title='', bbox_to_anchor=(1.02, 0.5), loc='center left', borderaxespad=0)
        plt.tight_layout()
        pdf_handle.savefig()
    finally:
        plt.close()
    return 1


def plot_spatial(df, pdf_handle, metadata, top_n):
    sample_names = [_sample_name_from_col(c) for c in df.columns]
    dates = [metadata.get(s, {}).get('date', s) for s in sample_names]
    sites = [metadata.get(s, {}).get('site', s) for s in sample_names]

    if len(set(dates)) > 1:
        return 0

    sorted_pairs = sorted(zip(sites, map(str, df.columns)))
    sorted_cols  = [col for _, col in sorted_pairs]
    table = df[sorted_cols].copy()
    table.columns = [site for site, _ in sorted_pairs]

    table = drop_empty_genomes(table.T, top_n)
    return coverage_barplot(table, pdf_handle, 'site', f'{dates[0]} - genome coverage')


def plot_longitudinal(df, pdf_handle, metadata, top_n):
    sample_names = [_sample_name_from_col(c) for c in df.columns]
    dates = [metadata.get(s, {}).get('date', s) for s in sample_names]
    sites = [metadata.get(s, {}).get('site', s) for s in sample_names]

    if len(set(dates)) <= 1:
        return 0

    order       = sorted(range(len(dates)), key=lambda i: (dates[i], str(df.columns[i])))
    sorted_cols = [df.columns[i] for i in order]
    dates       = [dates[i] for i in order]
    sites       = [sites[i] for i in order]

    pages = 0
    # `sorted`, not `set`: the page order of the report has to be the same on a
    # rerun, and set iteration order varies with the hash seed.
    for site in sorted(set(sites)):
        site_cols  = [sorted_cols[i] for i, s in enumerate(sites) if s == site]
        site_dates = [dates[i] for i, s in enumerate(sites) if s == site]

        site_df = df[site_cols].T.copy()
        site_df.index = site_dates

        site_df = drop_empty_genomes(site_df, top_n)
        pages += coverage_barplot(site_df, pdf_handle, 'Date', f'{site} - genome coverage')

    return pages


def main():
    args     = parse_arguments()
    metadata = load_samplesheet(args.samplesheet)
    name     = args.name.strip().replace(' ', '_')

    df = pd.read_csv(args.input, sep='\t', header=0, index_col=0)
    df = extract_trimmed_mean(df)
    df = df.apply(pd.to_numeric, errors='coerce').fillna(0)

    unknown = [_sample_name_from_col(c) for c in df.columns
               if _sample_name_from_col(c) not in metadata]
    if unknown:
        print(f"Warning: {len(unknown)} sample(s) of {args.input} are not in the samplesheet "
              f"and keep their own name as site and date: {', '.join(unknown[:5])}"
              f"{' ...' if len(unknown) > 5 else ''}", file=sys.stderr)

    output = f"group_{name}_coverm_genome_coverage_barplots.pdf"
    with PdfPages(output) as pdf_out:
        pages  = plot_spatial(df, pdf_out, metadata, args.top_n)
        pages += plot_longitudinal(df, pdf_out, metadata, args.top_n)

        if not pages:
            note_page(pdf_out,
                      f"No coverage barplot could be drawn for group {name}.\n\n"
                      f"{df.shape[0]} genome(s) over {df.shape[1]} sample(s) were read from "
                      f"{args.input},\nand none of them had a non-zero trimmed mean.\n"
                      f"No read of this group mapped to the genome database.")
            print(f"No panel could be drawn; {output} carries an explanatory page instead.",
                  file=sys.stderr)

    print(f"Successfully generated {output} ({pages} chart page(s))")


if __name__ == "__main__":
    main()
