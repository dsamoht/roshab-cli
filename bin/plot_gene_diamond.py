#!/usr/bin/env python3

import argparse
import math
import os

import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt


def parse_args():
    parser = argparse.ArgumentParser(description="Generate cyanotoxin heatmaps from DIAMOND TSV files using Best-Hit logic.")
    parser.add_argument('-i', '--input', nargs='+', required=True, help='List of DIAMOND TSV files')
    parser.add_argument('-o', '--output', default='cyanotoxins_heatmap.pdf', help='Output figure file')
    return parser.parse_args()

def process_diamond_file(input_file, sample_name):
    """
    1. Filter aln_length < 25
    2. Pick best bit_score per qseqid (read)
    3. Split sseqid by '|': gene is index 0, toxin is index 1
    """
    best_hits = {}

    try:
        with open(input_file, 'r') as f_in:
            for line in f_in:
                if line.startswith('#') or not line.strip():
                    continue
                
                parts = line.strip().split('\t')
                if len(parts) < 12:
                    continue
                
                qseqid = parts[0]
                sseqid = parts[1]
                
                try:
                    aln_length = int(parts[3])
                    bit_score = float(parts[11])
                except ValueError:
                    continue

                if aln_length < 25:
                    continue

                s_parts = sseqid.split('|')
                if len(s_parts) < 2:
                    continue

                gene = s_parts[0]
                toxin = s_parts[1]

                # Update if this is a better hit for the same read
                if qseqid not in best_hits or bit_score > best_hits[qseqid][0]:
                    best_hits[qseqid] = [bit_score, toxin, gene]

    except Exception as e:
        print(f"Error reading {input_file}: {e}")
        return []

    sample_data = []
    for _, toxin, gene in best_hits.values():
        sample_data.append({
            'sample': sample_name,
            'toxin': toxin,
            'gene': gene
        })
    return sample_data

def main():
    args = parse_args()
    all_data = []
    
    for f in args.input:
        sample_name = os.path.basename(f).replace('.diamond.tsv', '').replace('.tsv', '')
        print(f"Processing {sample_name}...")
        all_data.extend(process_diamond_file(f, sample_name))
            
    if not all_data:
        print("No valid hits found across all samples. Exiting.")
        return
        
    df_all = pd.DataFrame(all_data)
    
    # Aggregate counts per sample, toxin, and gene
    counts = df_all.groupby(['toxin', 'sample', 'gene']).size().reset_index(name='count')
    
    toxins = sorted(counts['toxin'].unique())
    n_toxins = len(toxins)
    
    # Layout configuration
    cols_grid = 2
    rows_grid = math.ceil(n_toxins / cols_grid)
    
    fig, axes = plt.subplots(
        rows_grid, 
        cols_grid, 
        figsize=(12 * cols_grid, 8 * rows_grid),
        squeeze=False
    )
    
    flat_axes = axes.flatten()
    
    for i, toxin in enumerate(toxins):
        ax = flat_axes[i]
        toxin_data = counts[counts['toxin'] == toxin]
        pivot_df = toxin_data.pivot(index='sample', columns='gene', values='count').fillna(0)
        
        sns.heatmap(
            pivot_df,
            cmap='YlGnBu',
            annot=True,
            square=True,
            fmt='g',
            ax=ax,
            linewidths=.5,
            cbar_kws={'label': 'read count'}
        )

        ax.set_title(f"toxin: {toxin}", fontsize=16, fontweight='bold', pad=15)
        ax.set_xlabel("gene(s)", fontsize=12)
        ax.set_ylabel("sample(s)", fontsize=12)
        plt.setp(ax.get_xticklabels(), rotation=45, ha="right", rotation_mode="anchor")

    for j in range(i + 1, len(flat_axes)):
        fig.delaxes(flat_axes[j])
        
    plt.tight_layout()
    plt.savefig(args.output, bbox_inches='tight')
    print(f"Successfully generated {args.output}")

if __name__ == '__main__':
    main()
