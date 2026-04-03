#!/usr/bin/env python3
import argparse
import gzip
from pathlib import Path
from Bio import SeqIO


def concatenate_and_prefix(input_path_list, output_file, prefix=None):
    fastq_files = []
    exts = ['*.fastq', '*.fq', '*.fastq.gz', '*.fq.gz']

    # 1. Gather all files
    for path in input_path_list:
        p = Path(path)
        if p.is_file():
            fastq_files.append(p)
        elif p.is_dir():
            for ext in exts:
                fastq_files.extend(p.rglob(ext))

    if not fastq_files:
        raise FileNotFoundError(f"No FASTQ files found in input path(s): {input_path_list}")

    # 2. Process and Stream
    with gzip.open(output_file, "wt") as out_handle:
        for fastq_file in fastq_files:
            is_gzipped = fastq_file.suffix == '.gz' or '.gz' in fastq_file.suffixes
            
            # Open handle based on compression
            if is_gzipped:
                handle = gzip.open(fastq_file, "rt")
            else:
                handle = open(fastq_file, "r")

            with handle:
                # Use SeqIO.parse to iterate safely through records
                records = SeqIO.parse(handle, "fastq")
                
                if prefix:
                    for record in records:
                        # Prepend prefix to the ID
                        record.id = f"{prefix}_{record.id}"
                        # Clear description to avoid redundant IDs in some FASTQ formats
                        record.description = "" 
                        SeqIO.write(record, out_handle, "fastq")
                else:
                    SeqIO.write(records, out_handle, "fastq")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Concatenate FASTQ files and prefix IDs using Biopython.")
    parser.add_argument('--fastq', nargs='+', required=True, help='fastq file(s) or directories')
    parser.add_argument('--output', required=True, help='name of the output file')
    parser.add_argument('--prefix', required=False, help='Prefix to add to read IDs')
    
    args = parser.parse_args()
    
    output_dir = Path("OUT")
    output_dir.mkdir(exist_ok=True)
    final_output_path = output_dir.joinpath(args.output)    
    
    concatenate_and_prefix(args.fastq, final_output_path, prefix=args.prefix)
