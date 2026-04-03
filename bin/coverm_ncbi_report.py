#!/usr/bin/env python3
import argparse

from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.pyplot as plt
import pandas as pd


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--input',       help='coverm output table',   required=True)
    parser.add_argument('-n', '--name',        help='name for the output',   required=True)
    parser.add_argument('-s', '--samplesheet', help='samplesheet CSV (sample_name,date,info,group,reads)', required=True)
    return parser.parse_args()

def load_samplesheet(path):
    ss = pd.read_csv(path)
    return {
        str(row['sample_name']): {'date': str(row['date']), 'site': str(row['info'])}
        for _, row in ss.iterrows()
    }

def extract_trimmed_mean(df):
    trimmed_mean_cols = [col for i, col in enumerate(df.columns) if i % 3 == 1]
    return df[trimmed_mean_cols].copy()

def _sample_name_from_col(col):
    return col.replace(' Trimmed Mean', '').strip()

def plot_spatial(df, pdf_handle, metadata):
    sample_names = [_sample_name_from_col(c) for c in df.columns]
    dates = [metadata.get(s, {}).get('date', s) for s in sample_names]
    sites = [metadata.get(s, {}).get('site', s) for s in sample_names]

    if len(set(dates)) > 1:
        return

    sorted_pairs = sorted(zip(sites, df.columns))
    sorted_cols  = [col for _, col in sorted_pairs]
    df = df[sorted_cols].copy()
    df.columns = [s for s, _ in sorted_pairs]

    df = df.T
    nonzero = (df != 0).any()
    df = df.loc[:, nonzero[nonzero].index]

    if df.empty:
        print("plot_spatial: no non-zero coverage values found, skipping.")
        return

    date_label = dates[0]
    ax = df.plot(
        kind='bar',
        stacked=False,
        edgecolor='black',
        figsize=(10, 6),
        ylabel='coverage',
        xlabel='site',
        title=f'{date_label} - coverage of Cyanobacteria genomes (NCBI)'
    )
    ax.legend(title='', bbox_to_anchor=(1.02, 0.5), loc='center left', borderaxespad=0)
    plt.tight_layout()
    pdf_handle.savefig()
    plt.close()

def plot_longitudinal(df, pdf_handle, metadata):
    sample_names = [_sample_name_from_col(c) for c in df.columns]
    dates = [metadata.get(s, {}).get('date', s) for s in sample_names]
    sites = [metadata.get(s, {}).get('site', s) for s in sample_names]

    if len(set(dates)) <= 1:
        return

    sorted_idx  = sorted(range(len(dates)), key=lambda i: dates[i])
    sorted_cols = [df.columns[i] for i in sorted_idx]
    df = df[sorted_cols].copy()
    dates = [dates[i] for i in sorted_idx]
    sites = [sites[i] for i in sorted_idx]

    for site in set(sites):
        site_mask  = [i for i, s in enumerate(sites) if s == site]
        site_cols  = [sorted_cols[i] for i in site_mask]
        site_dates = [dates[i] for i in site_mask]

        site_df = df[site_cols].T.copy()
        site_df.index = site_dates

        nonzero = (site_df != 0).any()
        site_df = site_df.loc[:, nonzero[nonzero].index]

        if site_df.empty:
            print(f"plot_longitudinal: no non-zero coverage values found for site '{site}', skipping.")
            continue

        ax = site_df.plot(
            kind='bar',
            stacked=False,
            edgecolor='black',
            figsize=(10, 6),
            ylabel='coverage',
            xlabel='Date',
            title=f'{site} - coverage of Cyanobacteria genomes (NCBI)'
        )
        ax.legend(title='', bbox_to_anchor=(1.02, 0.5), loc='center left', borderaxespad=0)
        plt.tight_layout()
        pdf_handle.savefig()
        plt.close()

def main():
    args     = parse_arguments()
    metadata = load_samplesheet(args.samplesheet)
    name     = args.name.strip().replace(' ', '_')
    df       = pd.read_csv(args.input, sep='\t', header=0, index_col=0)
    df       = extract_trimmed_mean(df)

    with PdfPages(f"{name}_coverm_cyano_ncbi_barplots.pdf") as pdf_out:
        plot_spatial(df,      pdf_out, metadata)
        plot_longitudinal(df, pdf_out, metadata)

if __name__ == "__main__":
    main()
