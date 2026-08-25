#!/usr/bin/env python3
"""Build the cyanotoxin gene database used by `--genes_db`.

This is a maintenance script, not a pipeline step: run it by hand, check the
manifest, and publish the FASTA as a new Zenodo version.

Why the database carries non-toxin sequences
--------------------------------------------
`diamond blastx` assigns each alignment range to its best-scoring subject. When
the reference contains cyanotoxin genes and nothing else, every read that aligns
to anything is assigned to a toxin gene by construction, so the method cannot
return "this read came from something else". That matters more here than in most
gene screens because the markers are multi-domain NRPS/PKS proteins whose
condensation, adenylation, KS and AT domains are homologous across essentially
every NRPS/PKS in the biosphere.

The database therefore carries two classes:

  toxin  the cyanotoxin biosynthesis genes themselves
  other  sequences a non-toxin read should prefer, in three tiers:

         1. every non-toxin cyanobacterial BGC in MIBiG - anabaenopeptin,
            cyanopeptolin, aeruginosin, microginin, microviridin, the
            cyanobactins, hassallidin, cryptophycin, the siderophores. These are
            the nearest neighbours: apnA and mcnA carry the A and C domains
            closest to mcyA-C and co-occur with mcy in the same blooms.
         2. heterocyst glycolipid synthases, which MIBiG carries as a BGC of
            their own. Large type-I PKSs present in every heterocyst-forming
            cyanobacterium - Anabaena, Nostoc, Aphanizomenon, Cylindrospermopsis
            - i.e. exactly the genera carrying the anatoxin, saxitoxin and
            cylindrospermopsin clusters, so they cross-hit cyrB/cyrC/mcyD/anaE
            systematically rather than occasionally. Tier 1 picks these up
            automatically; they are called out because they are easy to forget,
            not being "secondary metabolism".
         3. the universal background: a sample of non-cyanobacterial NRPS/PKS
            from MIBiG, plus reviewed beta-ketoacyl-ACP synthases (the ancestral
            relatives of PKS KS domains) and AMP-binding acyl-CoA ligases (the
            ancestral relatives of NRPS adenylation domains) from UniProt. These
            sit in every genome at several copies, so under a permissive
            threshold a lake Pseudomonas fadD is a live mcyA candidate.

The `other` class deliberately outnumbers the toxin sequences. DIAMOND's
assignment is score-based rather than prior-based, so the imbalance does not
bias anything - these sequences only need to cover the space.

Header format
-------------
    >gene|compound|bgc_accession|source|protein_accession|class

The first two fields are what the pipeline reads, so this stays compatible with
databases built before the class field existed.
"""

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import date

MIBIG_RELEASE = '4.0'
MIBIG_JSON_URL = f'https://dl.secondarymetabolites.org/mibig/mibig_json_{MIBIG_RELEASE}.tar.gz'
MIBIG_PROT_URL = f'https://dl.secondarymetabolites.org/mibig/mibig_prot_seqs_{MIBIG_RELEASE}.fasta'

UNIPROT_STREAM = 'https://rest.uniprot.org/uniprotkb/stream'

# Reviewed entries only, so the background stays small and well annotated.
UNIPROT_QUERIES = {
    # PF00109: beta-ketoacyl synthase, N-terminal - the KS domain of every type-I
    # PKS and of the fatty acid synthases it descends from.
    'ketoacyl_synthase': '(reviewed:true) AND (xref:pfam-PF00109)',
    # PF00501: AMP-binding - the ANL superfamily the NRPS adenylation domain
    # belongs to, including the long-chain acyl-CoA ligases (fadD).
    'amp_binding': '(reviewed:true) AND (xref:pfam-PF00501)',
}

# Genera used to decide whether a MIBiG entry is cyanobacterial. MIBiG records a
# taxon name but no lineage, so the genus is what there is to match on.
CYANOBACTERIA = re.compile(
    r'\b(Microcystis|Planktothrix|Anabaena|Dolichospermum|Nostoc|Aphanizomenon'
    r'|Cylindrospermopsis|Raphidiopsis|Nodularia|Oscillatoria|Lyngbya|Moorea|Moorena'
    r'|Trichodesmium|Synechocystis|Synechococcus|Prochlorococcus|Fischerella|Scytonema'
    r'|Calothrix|Tolypothrix|Hapalosiphon|Stigonema|Leptolyngbya|Microcoleus|Phormidium'
    r'|Cyanothece|Crocosphaera|Okeania|Symploca|Hassallia|Chroococcidiopsis|Rivularia'
    r'|Gloeocapsa|Westiella|Cylindrospermum|Sphaerospermopsis|Kamptonema|Nocuolate'
    r'|Anabaenopsis|Limnothrix|Pseudanabaena|Cuspidothrix|Chrysosporum)\b',
    re.I,
)

# Compound name -> canonical toxin label, with the gene-name prefix that marks a
# protein as part of the core cluster rather than a transporter or a hypothetical
# neighbour. MIBiG spells microcystin five different ways ("microcystin",
# "microcystin LR", "microcystin-LR", "MC-LR", "mc-lhty,..."), which is why the
# current database renders microcystin and microcystin-LR as two separate panels.
TOXINS = [
    (re.compile(r'microcystin|^mc-', re.I), 'microcystin', 'mcy'),
    (re.compile(r'nodularin', re.I), 'nodularin', 'nda'),
    (re.compile(r'cylindrospermopsin', re.I), 'cylindrospermopsin', 'cyr'),
    (re.compile(r'saxitoxin', re.I), 'saxitoxin', 'sxt'),
    (re.compile(r'anatoxin-a(?!\(s\))', re.I), 'anatoxin-a', 'ana'),
    (re.compile(r'guanitoxin|anatoxin-a\(s\)', re.I), 'guanitoxin', 'gnt'),
    (re.compile(r'lyngbyatoxin', re.I), 'lyngbyatoxin', 'ltx'),
]

# MIBiG annotates most toxin proteins with a function ("peptide_synthetase")
# rather than a gene name. Where it does give a name, that name is used; these
# are the reference clusters that seed the rest by orthology. Accessions and
# names verified against the GenBank records behind each MIBiG entry.
REFERENCE_GENES = {
    # BGC0001015 - Planktothrix agardhii NIVA-CYA 126/8, AJ441056
    'CAD29793.1': 'mcyD', 'CAD29794.1': 'mcyE', 'CAD29795.1': 'mcyG',
    'CAD29797.1': 'mcyA', 'CAD29798.1': 'mcyB', 'CAD29799.1': 'mcyC',
    'CAD29792.1': 'mcyT', 'CAD29800.2': 'mcyJ',
    # BGC0000978 - Cylindrospermopsis raciborskii AWT205
    'ABX60152.1': 'cyrD', 'ABX60153.1': 'cyrF', 'ABX60161.1': 'cyrB',
    'ABX60162.1': 'cyrE', 'ABX60163.1': 'cyrC',
    # BGC0000017 - Oscillatoria sp. PCC 6506, anatoxin-a
    'ACR33077.1': 'anaE', 'ACR33078.1': 'anaF', 'ACR33079.1': 'anaG',
    'ACR33074.1': 'anaB', 'ACR33075.1': 'anaC', 'ACR33076.1': 'anaD',
    # BGC0000188 - Cylindrospermopsis raciborskii T3, saxitoxin
    'ABI75099.1': 'sxtI', 'ABI75110.1': 'sxtS', 'ABI75090.1': 'sxtA',
    'ABI75089.1': 'sxtB', 'ABI75096.1': 'sxtG',
}

GENE_LIKE = re.compile(r'^[A-Za-z]{2,5}[A-Z]\d?$')


def parse_args():
    parser = argparse.ArgumentParser(
        description="Build the cyanotoxin protein database and its non-toxin comparison set.")
    parser.add_argument('-o', '--output', default='cyanotoxin_db',
                        help='Output prefix; writes <prefix>.faa and <prefix>_manifest.tsv')
    parser.add_argument('--cache', default='.mibig_cache',
                        help='Directory for the downloaded MIBiG release')
    parser.add_argument('--tier3-bgcs', type=int, default=150,
                        help='Non-cyanobacterial NRPS/PKS clusters sampled from MIBiG')
    parser.add_argument('--skip-uniprot', action='store_true',
                        help='Skip the UniProt background (tier 3 keeps the MIBiG sample only)')
    parser.add_argument('--no-orthology', action='store_true',
                        help='Do not run DIAMOND to transfer gene names to unnamed toxin proteins')
    return parser.parse_args()


def fetch(url, path):
    if os.path.exists(path) and os.path.getsize(path):
        print(f"  cached: {os.path.basename(path)}")
        return path
    print(f"  downloading {url}")
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with urllib.request.urlopen(url, timeout=600) as response, open(path, 'wb') as handle:
        shutil.copyfileobj(response, handle)
    return path


def load_mibig_metadata(cache):
    """Return {accession: {compounds, taxon, classes}} for every MIBiG entry."""
    archive = fetch(MIBIG_JSON_URL, os.path.join(cache, 'mibig_json.tar.gz'))
    metadata = {}

    # Iterate the archive in order and read each member as it comes past:
    # `getmembers()` followed by random `extractfile()` calls makes tarfile
    # re-decompress the gzip stream for every entry, which is quadratic over the
    # ~3000 records in a MIBiG release.
    with tarfile.open(archive, mode='r|gz') as tar:
        for member in tar:
            if not member.name.endswith('.json'):
                continue
            handle = tar.extractfile(member)
            if handle is None:
                continue
            # `r|gz` gives a non-seekable stream, so read the member outright
            record = json.loads(handle.read().decode('utf-8'))
            accession = record.get('accession')
            if not accession:
                continue
            metadata[accession] = {
                'compounds': [c.get('name', '') for c in (record.get('compounds') or [])],
                'taxon': (record.get('taxonomy') or {}).get('name', ''),
                'classes': sorted({
                    entry.get('class', '')
                    for entry in (record.get('biosynthesis') or {}).get('classes', [])
                }),
            }

    print(f"  {len(metadata)} MIBiG entries")
    return metadata


def load_mibig_proteins(cache):
    """Return {accession: [(protein_id, annotation, sequence)]}."""
    path = fetch(MIBIG_PROT_URL, os.path.join(cache, 'mibig_prot.faa'))
    per_bgc = defaultdict(list)
    header = None
    chunks = []

    def flush():
        if header is None:
            return
        fields = header.split('|')
        if len(fields) < 6:
            return
        accession = fields[0].split('.')[0]
        per_bgc[accession].append((fields[4], fields[5], ''.join(chunks)))

    with open(path) as handle:
        for line in handle:
            if line.startswith('>'):
                flush()
                header = line[1:].strip()
                chunks = []
            else:
                chunks.append(line.strip())
    flush()

    print(f"  proteins for {len(per_bgc)} clusters")
    return per_bgc


def classify_toxin(compounds):
    """Canonical toxin label and core gene prefix, or (None, None)."""
    for pattern, label, prefix in TOXINS:
        if any(pattern.search(name) for name in compounds):
            return label, prefix
    return None, None


def resolve_names(entries, prefix, use_orthology):
    """Assign gene names to a toxin's proteins.

    MIBiG names roughly a sixth of them; the curation table covers the reference
    clusters; the rest are named by best-hit orthology against those, which is
    what keeps this reproducible instead of hand-maintained.
    """
    named, unnamed = {}, {}

    for accession, annotation, sequence in entries:
        gene = REFERENCE_GENES.get(accession)
        if not gene and GENE_LIKE.match(annotation):
            gene = annotation[0].lower() + annotation[1:]
        if gene and gene.lower().startswith(prefix):
            named[accession] = (gene, sequence)
        else:
            unnamed[accession] = sequence

    if not (use_orthology and named and unnamed):
        return named

    transferred = transfer_by_orthology(named, unnamed)
    named.update(transferred)
    return named


def transfer_by_orthology(named, unnamed):
    """Name a protein after its best hit among the already-named references."""
    if shutil.which('diamond') is None:
        print("  ! diamond not on PATH: skipping orthology transfer", file=sys.stderr)
        return {}

    with tempfile.TemporaryDirectory() as tmp:
        ref = os.path.join(tmp, 'ref.faa')
        query = os.path.join(tmp, 'query.faa')
        hits = os.path.join(tmp, 'hits.tsv')

        with open(ref, 'w') as handle:
            for accession, (gene, sequence) in sorted(named.items()):
                handle.write(f">{gene}__{accession}\n{sequence}\n")
        with open(query, 'w') as handle:
            for accession, sequence in sorted(unnamed.items()):
                handle.write(f">{accession}\n{sequence}\n")

        try:
            result = subprocess.run(
                # No subject-coverage requirement: orthologous NRPS differ in
                # module count and so in length, and requiring most of the
                # reference to align rejects every genuine pair. Identity plus
                # best-hit is what discriminates here.
                ['diamond', 'blastp', '--quiet', '--db', ref, '--query', query,
                 '--out', hits, '--outfmt', '6', 'qseqid', 'sseqid', 'pident',
                 'qcovhsp', '--max-target-seqs', '1', '--id', '40',
                 '--query-cover', '30', '--threads', '4'],
                capture_output=True, text=True, timeout=600,
            )
        except subprocess.TimeoutExpired:
            print("  ! diamond timed out: skipping orthology transfer", file=sys.stderr)
            return {}
        if result.returncode != 0:
            print(f"  ! diamond failed: {result.stderr.strip()[:200]}", file=sys.stderr)
            return {}

        transferred = {}
        with open(hits) as handle:
            for row in csv.reader(handle, delimiter='\t'):
                if len(row) < 2 or row[0] in transferred:
                    continue
                transferred[row[0]] = (row[1].split('__')[0], unnamed[row[0]])

    print(f"    orthology transfer named {len(transferred)} further protein(s)")
    return transferred


def uniprot_background():
    """Reviewed KS-domain and AMP-binding proteins: the universal background."""
    records = []
    for label, query in sorted(UNIPROT_QUERIES.items()):
        url = f"{UNIPROT_STREAM}?" + urllib.parse.urlencode(
            {'format': 'fasta', 'query': query})
        print(f"  UniProt: {label}")
        try:
            with urllib.request.urlopen(url, timeout=600) as response:
                text = response.read().decode()
        except OSError as error:
            print(f"  ! UniProt query failed ({error}); continuing without it", file=sys.stderr)
            continue

        accession = gene = None
        chunks = []
        for line in text.splitlines():
            if line.startswith('>'):
                if accession:
                    records.append((gene or accession, label, accession, ''.join(chunks)))
                parts = line[1:].split('|')
                accession = parts[1] if len(parts) > 2 else line[1:].split()[0]
                match = re.search(r'\bGN=(\S+)', line)
                gene = match.group(1) if match else None
                chunks = []
            else:
                chunks.append(line.strip())
        if accession:
            records.append((gene or accession, label, accession, ''.join(chunks)))

    print(f"  {len(records)} background protein(s)")
    return records


def main():
    args = parse_args()

    print("MIBiG metadata:")
    metadata = load_mibig_metadata(args.cache)
    print("MIBiG proteins:")
    proteins = load_mibig_proteins(args.cache)

    rows = []

    cyano = sorted(
        accession for accession, entry in metadata.items()
        if CYANOBACTERIA.search(entry['taxon'])
    )
    print(f"\nCyanobacterial clusters: {len(cyano)}")

    toxin_clusters, other_clusters = [], []
    for accession in cyano:
        label, _prefix = classify_toxin(metadata[accession]['compounds'])
        (toxin_clusters if label else other_clusters).append(accession)

    # --- toxin class -------------------------------------------------------
    by_toxin = defaultdict(list)
    for accession in toxin_clusters:
        label, prefix = classify_toxin(metadata[accession]['compounds'])
        by_toxin[(label, prefix)].append(accession)

    print(f"Toxin clusters: {len(toxin_clusters)} across {len(by_toxin)} toxin(s)")
    for (label, prefix), accessions in sorted(by_toxin.items()):
        entries = [(pid, ann, seq)
                   for accession in accessions
                   for pid, ann, seq in proteins.get(accession, [])]
        owner = {pid: accession
                 for accession in accessions
                 for pid, _ann, _seq in proteins.get(accession, [])}

        named = resolve_names(entries, prefix, not args.no_orthology)
        genes = sorted({gene for gene, _seq in named.values()})
        print(f"  {label:20s} {len(accessions)} cluster(s), "
              f"{len(named)} core protein(s): {' '.join(genes)}")
        if not named:
            print(f"  ! {label}: no protein carries a '{prefix}*' gene name, so this toxin "
                  f"is absent from the database. MIBiG annotates its cluster(s) "
                  f"({', '.join(accessions)}) by function only - add entries to "
                  f"REFERENCE_GENES to include it.", file=sys.stderr)

        for accession, (gene, sequence) in sorted(named.items()):
            rows.append((gene, label, owner[accession],
                         f'mibig{MIBIG_RELEASE}', accession, 'toxin', sequence))

    # --- `other` tier 1 and 2: every non-toxin cyanobacterial cluster ------
    tier12 = 0
    for accession in other_clusters:
        compounds = metadata[accession]['compounds']
        compound = re.sub(r'[|\s]+', '_', (compounds[0] if compounds else 'unknown'))
        for pid, annotation, sequence in proteins.get(accession, []):
            gene = annotation if GENE_LIKE.match(annotation) else (annotation or pid)
            rows.append((re.sub(r'[|\s]+', '_', gene) or pid, compound, accession,
                         f'mibig{MIBIG_RELEASE}', pid, 'other', sequence))
            tier12 += 1
    print(f"Tier 1+2 non-toxin cyanobacterial BGCs: "
          f"{len(other_clusters)} cluster(s), {tier12} protein(s)")

    # --- `other` tier 3a: non-cyanobacterial NRPS/PKS ----------------------
    others = sorted(
        accession for accession, entry in metadata.items()
        if accession not in set(cyano)
        and {'NRPS', 'PKS'} & set(entry['classes'])
    )
    # Evenly spaced rather than random: the same release always gives the same set.
    step = max(1, len(others) // max(1, args.tier3_bgcs))
    sampled = others[::step][:args.tier3_bgcs]
    tier3 = 0
    for accession in sampled:
        compounds = metadata[accession]['compounds']
        compound = re.sub(r'[|\s]+', '_', (compounds[0] if compounds else 'unknown'))
        for pid, annotation, sequence in proteins.get(accession, []):
            gene = annotation if GENE_LIKE.match(annotation) else (annotation or pid)
            rows.append((re.sub(r'[|\s]+', '_', gene) or pid, compound, accession,
                         f'mibig{MIBIG_RELEASE}', pid, 'other', sequence))
            tier3 += 1
    print(f"Tier 3a non-cyanobacterial NRPS/PKS: "
          f"{len(sampled)}/{len(others)} cluster(s), {tier3} protein(s)")

    # --- `other` tier 3b: universal domain background ----------------------
    if not args.skip_uniprot:
        for gene, label, accession, sequence in uniprot_background():
            rows.append((re.sub(r'[|\s]+', '_', gene), label, '-',
                         'uniprot', accession, 'other', sequence))

    # --- write -------------------------------------------------------------
    rows = [row for row in rows if row[6]]
    rows.sort(key=lambda row: (row[5], row[1], row[0], row[4]))

    fasta_path = f"{args.output}.faa"
    manifest_path = f"{args.output}_manifest.tsv"

    seen = set()
    written = 0
    with open(fasta_path, 'w') as fasta, open(manifest_path, 'w', newline='') as manifest:
        writer = csv.writer(manifest, delimiter='\t', lineterminator='\n')
        writer.writerow(['gene', 'compound', 'bgc_accession', 'source',
                         'protein_accession', 'class', 'length'])

        for gene, compound, bgc, source, accession, klass, sequence in rows:
            key = (accession, gene, compound)
            if key in seen:
                continue
            seen.add(key)
            fasta.write(f">{gene}|{compound}|{bgc}|{source}|{accession}|{klass}\n{sequence}\n")
            writer.writerow([gene, compound, bgc, source, accession, klass, len(sequence)])
            written += 1

        writer.writerow([])
        writer.writerow([f"# built {date.today().isoformat()}"])
        writer.writerow([f"# mibig {MIBIG_RELEASE}: {MIBIG_JSON_URL} , {MIBIG_PROT_URL}"])
        for label, query in sorted(UNIPROT_QUERIES.items()):
            writer.writerow([f"# uniprot {label}: {query}"])

    counts = defaultdict(int)
    for row in rows:
        counts[row[5]] += 1
    print(f"\nWrote {written} sequence(s) to {fasta_path} "
          f"({counts['toxin']} toxin, {counts['other']} other) and {manifest_path}")


if __name__ == '__main__':
    main()
