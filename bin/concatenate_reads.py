#!/usr/bin/env python3
"""Concatenate FASTQ files, optionally stamping a prefix onto every read ID."""
import argparse
import gzip
import os
import shutil
from pathlib import Path

EXTS = ['*.fastq', '*.fq', '*.fastq.gz', '*.fq.gz']
GZIP_MAGIC = b'\x1f\x8b'


def gather_fastq_files(input_path_list):
    fastq_files = []
    for path in input_path_list:
        p = Path(path)
        if p.is_file():
            fastq_files.append(p)
        elif p.is_dir():
            for ext in EXTS:
                fastq_files.extend(sorted(p.rglob(ext)))

    if not fastq_files:
        raise FileNotFoundError(f"No FASTQ files found in input path(s): {input_path_list}")

    return fastq_files


def is_gzipped(fastq_file):
    with open(fastq_file, 'rb') as handle:
        return handle.read(2) == GZIP_MAGIC


def copy_gzipped(fastq_file, out_handle):
    """Append an already-gzipped file byte for byte: concatenated gzip members
    are themselves a valid gzip stream, so no re-compression is needed."""
    with open(fastq_file, 'rb') as handle:
        shutil.copyfileobj(handle, out_handle, length=1024 * 1024)


def compress(fastq_file, out_handle, level):
    """Append a plain-text file as a new gzip member of the output."""
    with open(fastq_file, 'rb') as handle, gzip.GzipFile(fileobj=out_handle, mode='wb', compresslevel=level) as gz_handle:
        shutil.copyfileobj(handle, gz_handle, length=1024 * 1024)


def prefix_ids(fastq_file, gz_handle, prefix):
    """Write a file out with `prefix` prepended to every read ID. The description
    is dropped so that the ID stays the only field of the header line."""
    tag = b'@' + prefix.encode() + b'_'
    opener = gzip.open if is_gzipped(fastq_file) else open
    with opener(fastq_file, 'rb') as handle:
        for line_no, line in enumerate(handle):
            if line_no % 4 == 0:
                fields = line[1:].split(None, 1)
                gz_handle.write(tag + (fields[0] if fields else b'') + b'\n')
            elif line_no % 4 == 2:
                gz_handle.write(b'+\n')
            else:
                gz_handle.write(line)


def link_or_copy(fastq_file, output_file):
    """Fast path for a single already-gzipped file with nothing to rewrite."""
    try:
        os.link(fastq_file, output_file)
    except OSError:
        shutil.copyfile(fastq_file, output_file)


def concatenate_and_prefix(input_path_list, output_file, prefix=None, level=6):
    fastq_files = gather_fastq_files(input_path_list)

    if not prefix and len(fastq_files) == 1 and is_gzipped(fastq_files[0]):
        link_or_copy(fastq_files[0], output_file)
        return

    with open(output_file, 'wb') as out_handle:
        # Rewriting the IDs means re-compressing anyway, so every file goes into
        # a single gzip member.
        if prefix:
            with gzip.GzipFile(fileobj=out_handle, mode='wb', compresslevel=level) as gz_handle:
                for fastq_file in fastq_files:
                    prefix_ids(fastq_file, gz_handle, prefix)
            return

        for fastq_file in fastq_files:
            if is_gzipped(fastq_file):
                copy_gzipped(fastq_file, out_handle)
            else:
                compress(fastq_file, out_handle, level)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Concatenate FASTQ files and prefix read IDs.")
    parser.add_argument('--fastq', nargs='+', required=True, help='fastq file(s) or directories')
    parser.add_argument('--output', required=True, help='name of the output file')
    parser.add_argument('--prefix', required=False, help='Prefix to add to read IDs')
    parser.add_argument('--compresslevel', type=int, default=6, choices=range(1, 10),
                        help='gzip level used when reads have to be re-compressed (default: 6)')

    args = parser.parse_args()

    # The output is written to its own directory so that it cannot collide with
    # an input file of the same name.
    output_dir = Path("OUT")
    output_dir.mkdir(exist_ok=True)
    final_output_path = output_dir.joinpath(args.output)

    concatenate_and_prefix(args.fastq, final_output_path, prefix=args.prefix, level=args.compresslevel)
