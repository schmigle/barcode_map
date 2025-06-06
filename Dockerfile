FROM ubuntu:24.04

# Ensure the script is executable and install required packages
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y python3 minimap2 seqkit wget python3-biopython && \
    wget https://raw.githubusercontent.com/tseemann/any2fasta/master/any2fasta && \
    wget https://raw.githubusercontent.com/schmigle/barcode_map/refs/heads/main/annotation_parser.py && \ 
    wget https://raw.githubusercontent.com/schmigle/barcode_map/refs/heads/main/barcode_map.sh && \
    chmod +x /barcode_map.sh /annotation_parser.py /any2fasta && \
    apt-get clean && rm -rf /var/lib/apt/lists/* barcode_map

# Set the default entrypoint to mimic %runscript behavior
ENTRYPOINT ["/bin/bash", "/barcode_map.sh"]