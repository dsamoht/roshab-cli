#!/usr/bin/env python3
import argparse

from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.pyplot as plt
import pandas as pd


# source : https://sashamaps.net/docs/resources/20-colors/
DISTINCT_COLORS = ['#e6194B', '#3cb44b', '#ffe119', '#4363d8', '#f58231',
                   '#911eb4', '#42d4f4', '#f032e6', '#bfef45', '#fabed4',
                   '#469990', '#dcbeff', '#9A6324', '#fffac8', '#800000',
                   '#aaffc3', '#808000', '#ffd8b1', '#000075', '#a9a9a9',
                   '#000000']

def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input',       help='combined (multiple samples) kraken report', required=True)
    parser.add_argument('-n', '--name',        help='name associated to the input report',        required=True)
    parser.add_argument('-s', '--samplesheet', help='samplesheet CSV (sample_id,date,info,group,reads)', required=True)
    return parser.parse_args()

def load_samplesheet(path):
    """Return a dict mapping sample_id -> {'date': ..., 'site': ...}."""
    ss = pd.read_csv(path)
    return {
        str(row['sample_id']): {'date': str(row['date']), 'site': str(row['info'])}
        for _, row in ss.iterrows()
    }

def top_n_taxlevel_relative_to_all(df, taxa_level="p", top_n=10):
    tax_level_table = df.loc[[str(i) for i in df.index if str(i).split("|")[-1].startswith(f"{taxa_level}__")]]
    top_n_by_sum = tax_level_table.loc[tax_level_table.sum(axis=1).nlargest(top_n).index]

    cellular = df.loc['x__cellular_organisms'] if 'x__cellular_organisms' in df.index else 0
    viruses  = df.loc['x__Viruses']             if 'x__Viruses'             in df.index else 0
    others_row = (cellular + viruses) - top_n_by_sum.sum()

    result_df = pd.concat([top_n_by_sum, pd.DataFrame(others_row).T.rename(index={0: 'Others'})])
    tax_level_table = result_df / result_df.sum()
    tax_level_table.index = ["|".join([j for j in i.split("|") if "x__" not in j]) for i in tax_level_table.index]
    return tax_level_table

def top_n_taxlevel_relative_to_parent(df, parent='p__Cyanobacteriota', taxa_level='g', top_n=10):
    tax_level_table = df.loc[[str(i) for i in df.index if parent in str(i) and i.split("|")[-1].startswith(f"{taxa_level}")]]
    top_n_by_sum    = tax_level_table.loc[tax_level_table.sum(axis=1).nlargest(top_n).index]
    others_row      = tax_level_table.loc[~tax_level_table.index.isin(top_n_by_sum.index)].sum()
    result_df       = pd.concat([top_n_by_sum, pd.DataFrame(others_row).T.rename(index={0: 'Others'})])
    tax_level_table = result_df / result_df.sum()
    tax_level_table.index = ["|".join([j for j in i.split("|") if "x__" not in j]) for i in tax_level_table.index]
    tax_level_table.index = [i.split(f'|{taxa_level}__')[-1] for i in tax_level_table.index]
    return tax_level_table

def stacked_barplot(df, pdf_handle, title=None):
    ax = df.T.plot(kind='bar',
                   figsize=(10, 6),
                   stacked=True,
                   legend=False,
                   color=DISTINCT_COLORS,
                   edgecolor='k',
                   title=title)
    ax.set_ylabel('Relative abundance')
    ax.legend(title='', bbox_to_anchor=(1.02, 0.5), loc='center left', borderaxespad=0)
    for text in ax.get_legend().get_texts():
        if text.get_text() != 'Others':
            text.set_fontstyle('italic')
    plt.tight_layout()
    pdf_handle.savefig()
    plt.close()

def plot_spatial(df, pdf_handle, metadata):
    """Single time-point: one plot per group, x-axis = sites."""
    dates = [metadata.get(col, {}).get('date', col) for col in df.columns]
    sites = [metadata.get(col, {}).get('site', col) for col in df.columns]

    # Only run when all samples share the same date
    if len(set(dates)) > 1:
        return

    # Sort columns by site name and rename to site labels
    sorted_cols = [col for _, col in sorted(zip(sites, df.columns))]
    df = df[sorted_cols].copy()
    df.columns = [metadata.get(col, {}).get('site', col) for col in sorted_cols]

    date_label = dates[0]
    top_n_taxlevel_relative_to_all_df    = top_n_taxlevel_relative_to_all(df)
    top_n_taxlevel_relative_to_parent_df = top_n_taxlevel_relative_to_parent(df)
    stacked_barplot(top_n_taxlevel_relative_to_all_df,    pdf_handle, title=f"{date_label} - Relative abundance of top 10 phyla")
    stacked_barplot(top_n_taxlevel_relative_to_parent_df, pdf_handle, title=f"{date_label} - Relative abundance of top 10 genera within Cyanobacteriota")

def plot_longitudinal(df, pdf_handle, metadata):
    """Multiple time-points: one plot per site, x-axis = dates."""
    dates = [metadata.get(col, {}).get('date', col) for col in df.columns]
    sites = [metadata.get(col, {}).get('site', col) for col in df.columns]

    # Only run when there are multiple dates
    if len(set(dates)) <= 1:
        return

    # Sort by date
    sorted_cols = [col for _, col in sorted(zip(dates, df.columns))]
    df = df[sorted_cols].copy()
    dates = [metadata.get(col, {}).get('date', col) for col in sorted_cols]
    sites = [metadata.get(col, {}).get('site', col) for col in sorted_cols]

    for site in set(sites):
        site_cols  = [col for col, s in zip(sorted_cols, sites) if s == site]
        site_dates = [metadata.get(col, {}).get('date', col) for col in site_cols]

        site_df = df[site_cols].copy()
        site_df.columns = site_dates  # rename columns to dates for the x-axis

        top_n_taxlevel_relative_to_all_df    = top_n_taxlevel_relative_to_all(site_df)
        top_n_taxlevel_relative_to_parent_df = top_n_taxlevel_relative_to_parent(site_df)
        stacked_barplot(top_n_taxlevel_relative_to_all_df,    pdf_handle, title=f"{site} - Relative abundance of top 10 phyla")
        stacked_barplot(top_n_taxlevel_relative_to_parent_df, pdf_handle, title=f"{site} - Relative abundance of top 10 genera within Cyanobacteriota")

def main():
    args     = parse_arguments()
    metadata = load_samplesheet(args.samplesheet)
    name     = args.name.strip().replace(' ', '_')
    df       = pd.read_csv(args.input, sep='\t', header=0, index_col=0)

    with PdfPages(f"group_{name}_kraken_cyano_barplots.pdf") as pdf_out:
        plot_spatial(df,      pdf_out, metadata)
        plot_longitudinal(df, pdf_out, metadata)

if __name__ == "__main__":
    main()
