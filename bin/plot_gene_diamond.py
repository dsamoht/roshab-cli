#!/usr/bin/env python3
"""Summarise DIAMOND alignments against the cyanotoxin gene database.

`diamond blastx --long-reads` enables range culling, which reports several
alignments along different segments of one long read. Collapsing a read to its
single best hit therefore throws away exactly what long reads provide: a 30 kb
read spanning mcyA-mcyB-mcyC would be counted as one gene. This script keeps
every HSP, resolves them into non-overlapping query ranges (the per-range best
hit that range culling intends), and counts ranges rather than reads.

It also records gene co-location: how many distinct genes of the same toxin sit
on a single molecule, and in what order and orientation. Co-location is the
strongest read-level evidence available, because a conserved NRPS domain can hit
one toxin gene by chance but several genes of the same cluster on one read
cannot.

Note on ordering: gene order is reported, not scored. mcy cluster architecture
differs between Microcystis (bidirectional mcyABC / mcyDEFGHIJ), Planktothrix
and Anabaena, so requiring a reference order would reject true positives from
the genera that differ. Only strand consistency is evaluated.
"""

import argparse
import math
import os
import sys
from collections import defaultdict

import matplotlib
matplotlib.use('Agg')

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


# DIAMOND writes human-readable field descriptions on its `# Fields:` line
# (`--header` is set in the module). Map them back to the short codes so the
# column order of `--outfmt` can change without silently shifting every value.
FIELD_DESCRIPTIONS = {
    'Query Seq - id': 'qseqid',
    'Subject Seq - id': 'sseqid',
    'Percentage of identical matches': 'pident',
    'Alignment length': 'length',
    'Number of mismatches': 'mismatch',
    'Number of gap openings': 'gapopen',
    'Start of alignment in query': 'qstart',
    'End of alignment in query': 'qend',
    'Start of alignment in subject': 'sstart',
    'End of alignment in subject': 'send',
    'Expect value': 'evalue',
    'Bit score': 'bitscore',
    'Query sequence length': 'qlen',
    'Subject sequence length': 'slen',
    'Query frame': 'qframe',
    'Query coverage per HSP': 'qcovhsp',
    'Subject coverage per HSP': 'scovhsp',
}

# Used when a file carries no `# Fields:` line: the order the modules request.
DEFAULT_FIELDS = ['qseqid', 'sseqid', 'pident', 'length', 'mismatch', 'gapopen',
                  'qstart', 'qend', 'sstart', 'send', 'evalue', 'bitscore',
                  'qlen', 'slen']

EVIDENCE_COLUMNS = ['sample', 'toxin', 'gene', 'n_ranges', 'n_reads',
                    'n_multigene_reads', 'max_genes_on_one_read', 'example_gene_order']


def parse_args():
    parser = argparse.ArgumentParser(
        description="Summarise cyanotoxin gene hits from DIAMOND TSV files.")
    parser.add_argument('-i', '--input', nargs='+', required=True,
                        help='DIAMOND TSV files, one per sample')
    parser.add_argument('-g', '--genes-db', required=True,
                        help='The cyanotoxin gene FASTA the alignments were made against. '
                             'Its headers define the full gene panel, so that genes with no '
                             'hit are still drawn as zeros.')
    parser.add_argument('-o', '--output', default='cyanotoxins_heatmap.pdf',
                        help='Output figure file')
    parser.add_argument('-e', '--evidence', default=None,
                        help='Output TSV of per-gene evidence (default: alongside --output)')
    parser.add_argument('--min-aln-length', type=int, default=25,
                        help='Minimum alignment length in amino acids')
    parser.add_argument('--range-overlap-frac', type=float, default=0.5,
                        help='Two HSPs are the same query range when they overlap by at least '
                             'this fraction of the shorter one')
    return parser.parse_args()


def load_gene_panel(path):
    """Read `gene|toxin|...` FASTA headers into {toxin: [genes]}.

    A sixth `class` field separates `toxin` sequences from `other` ones. The
    `other` class exists so that a read from a non-toxin NRPS/PKS has somewhere
    to land instead of being forced onto a toxin gene; those sequences are not
    toxins, so they get no heatmap panel. Hits against them still reach the
    evidence table, where the share of ranges landing on them is a per-sample
    specificity readout. Databases without the field are all treated as toxin
    sequences, so older ones keep working unchanged.
    """
    panel = defaultdict(set)
    malformed = 0
    skipped = 0

    with open(path) as handle:
        for line in handle:
            if not line.startswith('>'):
                continue
            fields = line[1:].strip().split('|')
            if len(fields) < 2 or not fields[0] or not fields[1]:
                malformed += 1
                continue
            if len(fields) > 5 and fields[5] and fields[5] != 'toxin':
                skipped += 1
                continue
            panel[fields[1]].add(fields[0])

    if not panel:
        sys.exit(
            f"ERROR: no 'gene|toxin' headers recovered from {path}.\n"
            f"       {malformed} header(s) were present but did not parse. The gene database "
            f"must use pipe-separated headers whose first two fields are the gene name and the "
            f"toxin name, e.g. '>mcyA|microcystin|BGC0001015|mibig4|CAD29797.1'."
        )

    if malformed:
        print(f"Warning: {malformed} header(s) in {path} did not parse and were skipped.",
              file=sys.stderr)
    if skipped:
        print(f"  {skipped} non-toxin ('other') sequence(s) in the database: "
              f"no panel is drawn for them.")

    return {toxin: sorted(genes) for toxin, genes in panel.items()}


def field_index(header_line):
    """Map short field codes to column indices from a DIAMOND `# Fields:` line."""
    descriptions = [part.strip() for part in header_line.split(':', 1)[1].split(',')]
    index = {}
    for position, description in enumerate(descriptions):
        code = FIELD_DESCRIPTIONS.get(description)
        if code:
            index[code] = position
    return index


def read_hsps(path, min_aln_length):
    """Yield every HSP of a DIAMOND TSV, grouped per read."""
    per_read = defaultdict(list)
    index = {code: position for position, code in enumerate(DEFAULT_FIELDS)}
    saw_header = False

    with open(path) as handle:
        for line in handle:
            if line.startswith('#'):
                if line.startswith('# Fields:'):
                    parsed = field_index(line)
                    if 'qseqid' in parsed and 'sseqid' in parsed:
                        index = parsed
                        saw_header = True
                continue

            if not line.strip():
                continue

            parts = line.rstrip('\n').split('\t')
            if len(parts) <= max(index.values()):
                continue

            try:
                aln_length = int(parts[index['length']])
                bitscore = float(parts[index['bitscore']])
                qstart = int(parts[index['qstart']])
                qend = int(parts[index['qend']])
            except (KeyError, ValueError):
                continue

            if aln_length < min_aln_length:
                continue

            subject = parts[index['sseqid']].split('|')
            if len(subject) < 2:
                continue

            frame = None
            if 'qframe' in index:
                try:
                    frame = int(parts[index['qframe']])
                except ValueError:
                    frame = None

            low, high = (qstart, qend) if qstart <= qend else (qend, qstart)
            strand = '+' if (frame > 0 if frame is not None else qstart <= qend) else '-'

            per_read[parts[index['qseqid']]].append({
                'gene': subject[0],
                'toxin': subject[1],
                'bitscore': bitscore,
                'start': low,
                'end': high,
                'strand': strand,
            })

    if not saw_header:
        print(f"Warning: {os.path.basename(path)} carries no '# Fields:' line; "
              f"assuming the default column order.", file=sys.stderr)

    return per_read


def resolve_ranges(hsps, overlap_frac):
    """Reduce a read's HSPs to non-overlapping query ranges, best bitscore first.

    This is the per-range best hit that `--range-culling` produces alignments
    for; taking a single best hit per read instead would discard every gene
    beyond the highest-scoring one.
    """
    accepted = []

    for hsp in sorted(hsps, key=lambda item: -item['bitscore']):
        length = hsp['end'] - hsp['start'] + 1
        conflicts = False

        for taken in accepted:
            overlap = min(taken['end'], hsp['end']) - max(taken['start'], hsp['start']) + 1
            if overlap <= 0:
                continue
            shorter = min(length, taken['end'] - taken['start'] + 1)
            if shorter > 0 and overlap >= overlap_frac * shorter:
                conflicts = True
                break

        if not conflicts:
            accepted.append(hsp)

    return sorted(accepted, key=lambda item: item['start'])


def describe_order(ranges):
    """Render the observed gene order along a read, e.g. 'mcyA(+)>mcyB(+)'."""
    return '>'.join(f"{item['gene']}({item['strand']})" for item in ranges)


def summarise_sample(path, sample, min_aln_length, overlap_frac):
    """Per-(toxin, gene) counts and co-location statistics for one sample."""
    stats = defaultdict(lambda: {
        'n_ranges': 0,
        'reads': set(),
        'multigene_reads': set(),
        'max_genes': 0,
        'example_order': '',
    })

    for read, hsps in read_hsps(path, min_aln_length).items():
        ranges = resolve_ranges(hsps, overlap_frac)
        if not ranges:
            continue

        # Co-location is only meaningful within one toxin: two genes of the same
        # cluster on one molecule is evidence, two unrelated toxins is not.
        by_toxin = defaultdict(list)
        for item in ranges:
            by_toxin[item['toxin']].append(item)

        for toxin, items in by_toxin.items():
            genes = {item['gene'] for item in items}
            order = describe_order(items)

            for item in items:
                entry = stats[(toxin, item['gene'])]
                entry['n_ranges'] += 1
                entry['reads'].add(read)
                if len(genes) > 1:
                    entry['multigene_reads'].add(read)
                if len(genes) > entry['max_genes']:
                    entry['max_genes'] = len(genes)
                    entry['example_order'] = order

    rows = []
    for (toxin, gene), entry in stats.items():
        rows.append({
            'sample': sample,
            'toxin': toxin,
            'gene': gene,
            'n_ranges': entry['n_ranges'],
            'n_reads': len(entry['reads']),
            'n_multigene_reads': len(entry['multigene_reads']),
            'max_genes_on_one_read': entry['max_genes'],
            'example_gene_order': entry['example_order'],
        })

    return rows


def sample_name(path):
    return os.path.basename(path).replace('.diamond.tsv', '').replace('.tsv', '')


def draw(evidence, panel, samples, output):
    """One heatmap panel per toxin, over the full gene list of the database."""
    toxins = sorted(panel)
    cols_grid = min(2, len(toxins))
    rows_grid = math.ceil(len(toxins) / cols_grid)

    fig, axes = plt.subplots(
        rows_grid,
        cols_grid,
        figsize=(12 * cols_grid, 8 * rows_grid),
        squeeze=False,
    )
    flat_axes = axes.flatten()

    for position, toxin in enumerate(toxins):
        ax = flat_axes[position]
        genes = panel[toxin]

        observed = evidence[evidence['toxin'] == toxin]
        if observed.empty:
            pivot = pd.DataFrame(0, index=samples, columns=genes)
        else:
            pivot = (observed
                     .pivot_table(index='sample', columns='gene',
                                  values='n_ranges', aggfunc='sum')
                     # Genes and samples with no hit must still be drawn: a panel
                     # where 1 of 6 mcy genes was found is the classic false
                     # positive signature and has to be visible as such.
                     .reindex(index=samples, columns=genes)
                     .fillna(0))

        sns.heatmap(
            pivot.astype(int),
            cmap='YlGnBu',
            annot=True,
            square=True,
            fmt='g',
            ax=ax,
            linewidths=.5,
            vmin=0,
            cbar_kws={'label': 'alignment ranges'},
        )

        ax.set_title(f"toxin: {toxin}", fontsize=16, fontweight='bold', pad=15)
        ax.set_xlabel("gene(s)", fontsize=12)
        ax.set_ylabel("sample(s)", fontsize=12)
        plt.setp(ax.get_xticklabels(), rotation=45, ha="right", rotation_mode="anchor")

    for position in range(len(toxins), len(flat_axes)):
        fig.delaxes(flat_axes[position])

    plt.tight_layout()
    plt.savefig(output, bbox_inches='tight')
    print(f"Successfully generated {output}")


def main():
    args = parse_args()

    panel = load_gene_panel(args.genes_db)
    print(f"Gene panel: {sum(len(g) for g in panel.values())} gene(s) "
          f"across {len(panel)} toxin(s) from {os.path.basename(args.genes_db)}")

    # Every input file is a sample, whether or not it produced a hit: a sample
    # missing from the figure is indistinguishable from a sample with no toxin
    # genes, and those mean very different things.
    samples = sorted(sample_name(path) for path in args.input)

    rows = []
    for path in args.input:
        sample = sample_name(path)
        try:
            sample_rows = summarise_sample(path, sample, args.min_aln_length,
                                           args.range_overlap_frac)
        except OSError as error:
            print(f"Error reading {path}: {error}", file=sys.stderr)
            continue
        print(f"{sample}: {sum(row['n_ranges'] for row in sample_rows)} range(s) "
              f"over {len(sample_rows)} gene(s)")
        rows.extend(sample_rows)

    evidence = pd.DataFrame(rows, columns=EVIDENCE_COLUMNS)
    evidence = evidence.sort_values(['sample', 'toxin', 'gene']).reset_index(drop=True)

    off_panel = set(evidence['toxin']) - set(panel)
    if off_panel:
        other_ranges = int(evidence[evidence['toxin'].isin(off_panel)]['n_ranges'].sum())
        toxin_ranges = int(evidence[~evidence['toxin'].isin(off_panel)]['n_ranges'].sum())
        total = other_ranges + toxin_ranges
        share = 100.0 * other_ranges / total if total else 0.0
        print(f"Non-toxin assignments: {other_ranges}/{total} range(s) ({share:.1f}%) "
              f"went to sequences of the 'other' class. They stay in the evidence "
              f"table and are not drawn.")

    evidence_path = args.evidence or f"{os.path.splitext(args.output)[0]}_read_evidence.tsv"
    evidence.to_csv(evidence_path, sep='\t', index=False)
    print(f"Successfully generated {evidence_path}")

    draw(evidence, panel, samples, args.output)


if __name__ == '__main__':
    main()
