FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y python3 python3-pip minimap2 seqkit wget perl python3-biopython && \
    pip3 install flask flask-cors

WORKDIR /app
COPY . /app

# Download helper scripts
RUN wget https://raw.githubusercontent.com/tseemann/any2fasta/master/any2fasta && \
    wget https://raw.githubusercontent.com/schmigle/barcode_map/refs/heads/main/annotation_parser.py && \
    wget https://raw.githubusercontent.com/schmigle/barcode_map/refs/heads/main/barcode_map.sh && \
    chmod +x /app/barcode_map.sh /app/annotation_parser.py /app/any2fasta

EXPOSE 5000
CMD ["python3", "app.py"]
