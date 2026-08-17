#!/usr/bin/env python3
"""Merge BGC predictions from antiSMASH, GECCO and DeepBGC into one table.

Regions from the different tools rarely share exact boundaries, so calls are
merged per contig whenever they overlap by at least `--min-overlap` bases. The
number of tools supporting a merged region is used as a confidence tier.

Only the standard library is used so the script runs in any python container.
"""

import argparse
import csv
import json
import os
import re
import sys

LOCATION_RE = re.compile(r'\[?(?P<start>[<>]?\d+):(?P<end>[<>]?\d+)\]?')


def parse_args():
    parser = argparse.ArgumentParser(description="Merge BGC calls from multiple detection tools.")
    parser.add_argument('-s', '--sample', required=True, help='Sample name')
    parser.add_argument('--antismash', help='antiSMASH JSON output')
    parser.add_argument('--gecco', help='GECCO clusters TSV')
    parser.add_argument('--deepbgc', help='DeepBGC BGC TSV')
    parser.add_argument('--min-overlap', type=int, default=500,
                        help='Minimum overlap (bp) for two calls to be considered the same region')
    parser.add_argument('-o', '--output', default='bgc.tsv', help='Output TSV')
    return parser.parse_args()


def clean_int(value):
    """Coordinates may carry biopython fuzzy markers ('<1', '>4200')."""
    return int(str(value).strip().lstrip('<>'))


def pick_column(header, candidates):
    lowered = {name.lower(): name for name in header}
    for candidate in candidates:
        if candidate in lowered:
            return lowered[candidate]
    return None


def parse_antismash(path):
    """antiSMASH >= 6 stores regions per record under 'areas'."""
    calls = []
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
                calls.append((contig, start, end, sorted(set(products))))
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
            calls.append((contig, start, end, sorted(set(products))))

    return calls


def parse_tabular(path, contig_keys, start_keys, end_keys, product_keys, start_is_one_based):
    calls = []
    with open(path, newline='') as handle:
        reader = csv.DictReader(handle, delimiter='\t')
        if not reader.fieldnames:
            return calls

        contig_col = pick_column(reader.fieldnames, contig_keys)
        start_col = pick_column(reader.fieldnames, start_keys)
        end_col = pick_column(reader.fieldnames, end_keys)
        product_col = pick_column(reader.fieldnames, product_keys)

        if not (contig_col and start_col and end_col):
            print(f"Warning: unexpected columns in {path}: {reader.fieldnames}", file=sys.stderr)
            return calls

        for row in reader:
            try:
                start = clean_int(row[start_col])
                end = clean_int(row[end_col])
            except (TypeError, ValueError):
                continue
            if start_is_one_based:
                start -= 1
            products = []
            if product_col and row.get(product_col):
                products = [p.strip() for p in re.split(r'[;,]', row[product_col]) if p.strip()]
            calls.append((row[contig_col], start, end, sorted(set(products))))

    return calls


def merge_calls(calls_by_tool, min_overlap):
    """Union overlapping intervals per contig, tracking which tools support each."""
    per_contig = {}
    for tool, calls in calls_by_tool.items():
        for contig, start, end, products in calls:
            per_contig.setdefault(contig, []).append((start, end, tool, products))

    merged = []
    for contig in sorted(per_contig):
        intervals = sorted(per_contig[contig], key=lambda item: (item[0], item[1]))
        current = None

        for start, end, tool, products in intervals:
            if current is None:
                current = {'start': start, 'end': end, 'tools': {tool}, 'products': set(products)}
                continue

            overlap = min(current['end'], end) - start
            if overlap >= min_overlap:
                current['end'] = max(current['end'], end)
                current['tools'].add(tool)
                current['products'].update(products)
            else:
                merged.append((contig, current))
                current = {'start': start, 'end': end, 'tools': {tool}, 'products': set(products)}

        if current is not None:
            merged.append((contig, current))

    return merged


def main():
    args = parse_args()

    parsers = {
        'antismash': lambda path: parse_antismash(path),
        'gecco': lambda path: parse_tabular(
            path,
            contig_keys=['sequence_id', 'contig_id', 'seq_id'],
            start_keys=['start'],
            end_keys=['end'],
            product_keys=['type', 'types', 'product', 'product_class'],
            start_is_one_based=True,
        ),
        'deepbgc': lambda path: parse_tabular(
            path,
            contig_keys=['sequence_id', 'contig_id', 'seq_id'],
            start_keys=['nucl_start', 'start'],
            end_keys=['nucl_end', 'end'],
            product_keys=['product_class', 'product_activity', 'detector_label'],
            start_is_one_based=True,
        ),
    }

    calls_by_tool = {}
    for tool, path in (('antismash', args.antismash), ('gecco', args.gecco), ('deepbgc', args.deepbgc)):
        if not path:
            continue
        if not os.path.exists(path):
            print(f"Warning: {tool} output {path} not found, skipping.", file=sys.stderr)
            continue
        try:
            calls_by_tool[tool] = parsers[tool](path)
        except Exception as error:  # a malformed report should not sink the run
            print(f"Error parsing {tool} output {path}: {error}", file=sys.stderr)
            calls_by_tool[tool] = []
        print(f"{tool}: {len(calls_by_tool[tool])} region(s)")

    n_tools_run = len(calls_by_tool)
    if n_tools_run == 0:
        print("No BGC detection output provided. Nothing to merge.", file=sys.stderr)
        return

    merged = merge_calls(calls_by_tool, args.min_overlap)

    with open(args.output, 'w', newline='') as handle:
        writer = csv.writer(handle, delimiter='\t', lineterminator='\n')
        writer.writerow(['sample', 'contig', 'start', 'end', 'length',
                         'n_tools', 'tools', 'products', 'confidence'])

        for contig, region in merged:
            tools = sorted(region['tools'])
            products = sorted(p for p in region['products'] if p)

            if n_tools_run == 1:
                confidence = 'single-tool'
            elif len(tools) >= 2:
                confidence = 'high'
            else:
                confidence = 'low'

            writer.writerow([
                args.sample,
                contig,
                region['start'],
                region['end'],
                region['end'] - region['start'],
                len(tools),
                ','.join(tools),
                ','.join(products) if products else 'unknown',
                confidence,
            ])

    print(f"Wrote {len(merged)} merged region(s) to {args.output}")


if __name__ == '__main__':
    main()
