#!/bin/bash
is_positive_integer() {
    re='^[0-9]+$'
    if ! [[ $1 =~ $re ]] ; then
       return 1
    fi
    if [ "$1" -le 0 ]; then
        return 1
    fi
    return 0
}

brackets=''
fasta=''
matches='10'
reads=''
sam='barcode_aln.sam'
threads='4'


usage() {
    echo "Usage: barcode_map.sh [-b brackets] [-f fasta] [-m matches] [-r reads] [-s sam] [-t thread_count]"
    echo "Options:"
    echo "  -b, --brackets      Sequences surrounding the barcode"
    echo "  -f, --fasta         Reference fasta"
    echo "  -m, --matches       Number of matches to list at the end (default: 10)" 
    echo "  -r, --reads         FASTQ file containing reads to match"
    echo "  -s, --sam           Name of the alignment file produced at the end (default: barcode_aln.sam)"  
    echo "  -t, --threads       Thread count (default: 4)"
    echo "  -h, --help          Display this help page"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--brackets)
            brackets=$2
            if [[ ! "$brackets" =~ ^[aAcCgGtT]+_[aAcCgGtT]+$ ]]; then
                echo "Error: The value for --brackets must consist of two sections 'A', 'C', 'G', 'T' (case-insensitive) separated by '_'."
                exit 1
            fi
            shift 2
            ;;
        -f|--fasta)
            fasta="$(readlink -f "$2")"
            shift 2
            ;;
        -m|--matches)
            if is_positive_integer "$2"; then
                matches=$2
                shift 2
            else
                echo "Error: match count must be a positive integer."
                exit 1
            fi
            ;;
        -r|--reads)
            reads=$2
            shift 2
            ;;
        -s|--sam)
            sam=$2
            shift 2
            ;;
        -t|--threads)
            if is_positive_integer "$2"; then
                threads=$2
                shift 2
            else
                echo "Error: Thread count must be a positive integer."
                exit 1
            fi
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -eq 1 ]]; then
    usage
fi

if [ -z "$brackets" ]; then
    echo "Error: Missing brackets."
    usage
    exit 1
fi

if [ -z "$fasta" ]; then
    echo "Error: Missing reference file (must be FASTA format)."
    usage
    exit 1
fi

if [ -z "$reads" ]; then
    echo "Error: Missing reads file (must be FASTQ format)."
    usage
    exit 1
fi 

# filtlong --min_length 1000 --keep_percent 90 "$reads" > filtered_reads.fastq.gz
if [ -e "search_reads.fastq" ]; then
    rm "search_reads.fastq"
fi

for pattern in "$brackets" "$(echo "$brackets" | rev)"; do
    first=$(echo "$pattern" | awk -F'_' '{print $1}')
    second=$(echo "$pattern" | awk -F'_' '{print $2}')
    cat "$reads" | seqkit grep -s -i -p "$first" -m 1 -j "$threads" | seqkit grep -s -i -p "$second" -m 1 -j "$threads" >> search_reads.fastq
done

minimap2 -ax map-ont -t "$threads" "$fasta" search_reads.fastq -o "$sam"

awk '{print $4}' "$sam" | grep -v '[a-zA-Z]' | sort | uniq -c | sort -nr | head -n "$matches"
