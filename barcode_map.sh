#!/bin/bash

# Trap to clean up temporary files on exit
trap 'rm -f "$temp_file" "$converted_fasta" search_reads.fastq "$cds_info" 2>/dev/null' EXIT

# Function to check if string is a positive integer
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

# Function to read first 300kb of a file, handling compression
read_file_head() {
    local file="$1"
    local check_size=307200  # 300kb in bytes
    local temp_file=$(mktemp)
    
    # Check if file exists
    if [ ! -f "$file" ]; then
        echo "Error: File '$file' not found."
        rm -f "$temp_file"
        return 1
    fi
    
    # Handle different file types
    case "$file" in
        *.gz)
            dd if="$file" bs=300K count=1 2>/dev/null | zcat > "$temp_file" 2>/dev/null
            ;;
        *.bz2)
            dd if="$file" bs=300k count=1 2>/dev/null | bzcat > "$temp_file" 2>/dev/null
            ;;
        *.xz)
            dd if="$file" bs=300k count=1 2>/dev/null | xzcat > "$temp_file" 2>/dev/null
            ;;
        *)
            dd if="$file" of="$temp_file" bs=1M count=1 2>/dev/null
            ;;
    esac
    
    if [ ! -s "$temp_file" ]; then
        echo "Error: Failed to read file '$file'"
        rm -f "$temp_file"
        return 1
    fi
    
    echo "$temp_file"
    return 0
}

# Function to validate FASTA format
check_fasta_format() {
    local temp_file="$1"
    
    if ! head -c 1 "$temp_file" | grep -q '>'; then
        echo "Error: FASTA file must start with '>'"
        return 1
    fi
    
    local in_sequence=true
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then
            continue
        fi
        
        case "$line" in
            '>'*) in_sequence=false ;;
            *)
                if [[ $in_sequence == true ]]; then
                    if ! [[ "$line" =~ ^[ACGTNacgtn*-]+$ ]]; then
                        echo "Error: Invalid sequence line in FASTA file"
                        exit 1
                    fi
                fi
            ;;
        esac
    done < "$temp_file"
    
    return 0
}

# Function to validate FASTQ format
check_fastq_format() {
    local temp_file="$1"
    local line_count=0
    local phase=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        ((line_count++))
        case $((line_count % 4)) in
            1)
                if ! [[ "$line" =~ ^@ ]]; then
                    echo "Error: FASTQ sequence identifier must start with '@'"
                    return 1
                fi
                ;;
            2)
                if ! [[ "$line" =~ ^[A-Za-zN]+$ ]]; then
                    echo "Error: Invalid sequence line in FASTQ file"
                    return 1
                fi
                ;;
            3)
                if ! [[ "$line" =~ ^\+ ]]; then
                    echo "Error: FASTQ quality header must start with '+'"
                    return 1
                fi
                ;;
            0)
                if [ ${#line} -eq 0 ]; then
                    echo "Error: Empty quality score line in FASTQ file"
                    return 1
                fi
                ;;
        esac
    done < "$temp_file"
    
    if [ $((line_count % 4)) -ne 0 ]; then
        echo "Error: Incomplete FASTQ record"
        return 1
    fi
    
    return 0
}

# Function to detect if file is GFF format
is_gff_format() {
    local file="$1"
    
    if ! head -n 1 "$file" 2>/dev/null | grep -q '^##gff-version 3'; then
        return 1
    fi
    
    awk -F'\t' '
        /^#/ { next }  # Skip comment lines
        NF == 9 && $3 != "." && $4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ {
            valid = 1
            exit
        }
        END { exit !valid }
    ' "$file"
    
    return $?
}

is_gbk_format() {
    local file="$1"
    
    if ! head -n 1 "$file" 2>/dev/null | grep -q '^LOCUS\>'; then
        return 1
    fi
    
    if head -n 5 "$file" 2>/dev/null | grep -q -e '^DEFINITION\>' -e '^ACCESSION\>' -e '^VERSION\>'; then
        return 0
    fi
    
    return 1
}

# Function to process mapping results with annotation
process_mapping_results() {
    local sam_file="$1"
    local annotation_file="$2"    
    local positions=$(awk '{print $4}' "$sam_file" | grep -v '[a-zA-Z]' | sort -n | uniq | grep -E '^[0-9]+$')    
    if [ -z "$positions" ]; then
        echo "No valid positions found in SAM file"
        return 1
    fi
    
    if is_gff_format "$annotation_file"; then
        python annotation_parser.py -i "$annotation_file" --gff -p "$positions"
    elif is_gbk_format "$annotation_file"; then
        python annotation_parser.py -i "$annotation_file" --gb -p "$positions"
    rm -f "$cds_info"
    fi
}

# Initialize variables
brackets=''
fasta=''
matches='10'
reads=''
sam='barcode_aln.sam'
threads='4'
annotation=''

# Usage function
usage() {
    echo "Usage: barcode_map.sh [-b brackets] [-f fasta] [-m matches] [-r reads] [-s sam] [-t thread_count] [-a annotation]"
    echo "Options:"
    echo " -a, --annotation Annotation file (GFF3 or GenBank)"
    echo " -b, --brackets Sequences surrounding the barcode (format: 'LEFT_RIGHT')"
    echo " -f, --fasta Reference FASTA file"
    echo " -m, --matches Number of matches to list (default: 10)"
    echo " -r, --reads FASTQ file containing reads"
    echo " -s, --sam Output SAM file name (default: barcode_aln.sam)"
    echo " -t, --threads Thread count (default: 4)"
    echo " -h, --help Display this help"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--annotation)
            annotation="$(readlink -f "$2")"
            shift 2
            ;;
        -b|--brackets)
            brackets=$2
            if [[ ! "$brackets" =~ ^[aAcCgGtT]+_[aAcCgGtT]+$ ]]; then
                echo "Error: Invalid bracket format"
                exit 1
            fi
            shift 2
            ;;
        -f|--fasta)
            fasta="$(readlink -f "$2")"
            temp_file=$(read_file_head "$fasta")
            if [ $? -eq 0 ]; then
                if ! check_fasta_format "$temp_file"; then
                    rm -f "$temp_file"
                    exit 1
                fi
                rm -f "$temp_file"
            else
                exit 1
            fi
            shift 2
            ;;
        -m|--matches)
            if is_positive_integer "$2"; then
                matches=$2
                shift 2
            else
                echo "Error: Invalid match count"
                exit 1
            fi
            ;;
        -r|--reads)
            reads="$(readlink -f "$2")"
            temp_file=$(read_file_head "$reads")
            if [ $? -eq 0 ]; then
                if ! check_fastq_format "$temp_file"; then
                    rm -f "$temp_file"
                    exit 1
                fi
                rm -f "$temp_file"
            else
                exit 1
            fi
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
                echo "Error: Invalid thread count"
                exit 1
            fi
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$brackets" ]; then
    echo "Error: Missing brackets"
    usage
    exit 1
fi

if [ -z "$reads" ]; then
    echo "Error: No reads file provided"
    usage
    exit 1
fi

if ! is_gff_format "$annotation" && ! is_gbk_format "$annotation"; then
    echo "Error: annotation file must be in GenBank or GFF3 format"
    usage
    exit 1
fi
# Handle annotation conversion if needed
if [ -z "$fasta" ] && [ -n "$annotation" ]; then
    ./any2fasta "$annotation" > "reference.fasta" || {
        exit 1
    }
    fasta="reference.fasta"
elif [ -z "$fasta" ] && [ -z "$annotation" ]; then
    echo "Error: no reference or annotation file"
    usage
    exit 1
fi

for pattern in "$brackets" "$(echo "$brackets" | rev)"; do
    first=$(echo "$pattern" | awk -F'_' '{print $1}')
    second=$(echo "$pattern" | awk -F'_' '{print $2}')
    cat "$reads" | seqkit grep -s -i -p "$first" -m 1 -j "$threads" | seqkit grep -s -i -p "$second" -m 1 -j "$threads" >> search_reads.fastq
done


# Perform alignment
minimap2 -ax map-ont -t "$threads" "$fasta" search_reads.fastq -o "$sam"
# Process results
if [ ! -z "$annotation" ]; then
    process_mapping_results "$sam" "$annotation" "$matches"
else
    awk '{print $4}' "$sam" | grep -v '[a-zA-Z]' | sort | uniq -c | sort -nr | head -n "$matches"
fi
