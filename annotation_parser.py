from Bio import SeqIO
import argparse, csv

parser = argparse.ArgumentParser()
parser.add_argument("-i", "--input", type=str)
group = parser.add_mutually_exclusive_group(required=True)
group.add_argument('--gb', action="store_true")
group.add_argument('--gff', action="store_true")
parser.add_argument("-p", "--position", type=str)
args = parser.parse_args()

def find_locus_gff(gff_file, position):
    with open(gff_file) as gff:
        lines=csv.reader(gff, delimiter="\t")
        for line in lines:
            if not "#" in line[0] and line[2] in ["gene", "pseudogene"] and int(line[3]) < position < int(line[4]):
                return(line[8].split("Name=")[1].split(";")[0])
    return None

def find_locus_genbank(gb_file, position):
    """
    Find first CDS feature containing given position and return its locus_tag
    Returns None if no matching feature found
    """
    for record in SeqIO.parse(gb_file, "genbank"):
        for feature in record.features:
            if feature.type == "CDS":
                if int(feature.location.start) <= position <= int(feature.location.end):
                    return feature.qualifiers.get("locus_tag", [None])[0]
    return None

# Usage example:
for i in args.position.split("\n"):
    i = int(i)
    if i < 1:
        continue
    if args.gff:
        locus = find_locus_gff(args.input, i)
        print(f"{i}\t{locus}" if locus else f"{i}\tNo gene found")
    elif args.gb:
        locus = find_locus_genbank(args.input, i)
        print(f"{i}\t{locus}" if locus else f"{i}\tNo CDS found")
