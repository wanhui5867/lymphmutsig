#!/usr/bin/env python3
"""
Run SigProfilerAssignment cosmic_fit for one mutation class (SBS, DBS, or ID).
Input: vcf_dir = folder of per-sample .txt (Chr, Pos, SampleID, Ref, Alt, no header).
Output: SPA writes to output_dir; we expect Assignment_Solution/Activities/Assignment_Solution_Activities.txt
Usage: python run_sigprofiler.py <vcf_dir> <output_dir> <genome_build> <ref_sig> <mutation_class> [sig_db_path] [exome]
  ref_sig: LymphMutSig | COSMIC
  mutation_class: SBS | DBS | ID  (context_type 96, DINUC, ID)
  sig_db_path: required if ref_sig=LymphMutSig; else empty
  exome: 0=WGS (default), 1=WES
"""
import os
import sys
import glob

def _txt_to_vcf_dir(txt_dir, vcf_out_dir):
    """Convert 5-col (Chr, Pos, SampleID, Ref, Alt) no-header .txt to minimal VCF per sample."""
    os.makedirs(vcf_out_dir, exist_ok=True)
    for f in glob.glob(os.path.join(txt_dir, "*.txt")):
        base = os.path.splitext(os.path.basename(f))[0]
        vcf_path = os.path.join(vcf_out_dir, base + ".vcf")
        with open(f) as fin, open(vcf_path, "w") as fout:
            fout.write("##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n")
            for line in fin:
                toks = line.strip().split("\t")
                if len(toks) < 5:
                    continue
                chrom, pos, sid, ref, alt = toks[0], toks[1], toks[2], toks[3], toks[4]
                chrom = chrom if chrom.startswith("chr") else "chr" + str(chrom)
                fout.write(f"{chrom}\t{pos}\t{sid}\t{ref}\t{alt}\t.\t.\t.\n")
    return vcf_out_dir

def main():
    if len(sys.argv) < 6:
        print("Usage: run_sigprofiler.py <vcf_dir> <output_dir> <genome_build> <ref_sig> <mutation_class> [sig_db_path]", file=sys.stderr)
        sys.exit(1)
    vcf_dir = os.path.abspath(sys.argv[1])
    output_dir = os.path.abspath(sys.argv[2])
    genome_build = sys.argv[3]
    ref_sig = sys.argv[4].strip()  # LymphMutSig | COSMIC
    mutation_class = sys.argv[5].strip().upper()  # SBS | DBS | ID
    sig_db = sys.argv[6].strip() if len(sys.argv) > 6 else ""
    exome = (sys.argv[7].strip() == "1") if len(sys.argv) > 7 else False
    os.makedirs(output_dir, exist_ok=True)

    # VCF input: context_type 96/DINUC/ID (not 78/83 which are for matrix input)
    context_map = {"SBS": "96", "DBS": "DINUC", "ID": "ID"}
    context_type = context_map.get(mutation_class, "96")

    try:
        from SigProfilerAssignment import Analyzer as Analyze
    except ImportError:
        print("SigProfilerAssignment not installed.", file=sys.stderr)
        sys.exit(2)

    vcf_input = os.path.join(output_dir, "_vcf_input")
    _txt_to_vcf_dir(vcf_dir, vcf_input)

    # DBS/ID 必须 collapse_to_SBS96=False，否则会错误折叠导致无结果
    collapse_sbs = (mutation_class == "SBS")
    kwargs = dict(
        samples=vcf_input,
        output=output_dir,
        input_type="vcf",
        context_type=context_type,
        collapse_to_SBS96=collapse_sbs,
        genome_build=genome_build,
        exome=exome,
        make_plots=False,
        sample_reconstruction_plots="none",
        verbose=False,
    )
    if ref_sig == "LymphMutSig" and sig_db and os.path.isfile(sig_db):
        kwargs["signature_database"] = os.path.abspath(sig_db)
    else:
        kwargs["cosmic_version"] = 3.4

    Analyze.cosmic_fit(**kwargs)
    return 0

if __name__ == "__main__":
    sys.exit(main() or 0)
