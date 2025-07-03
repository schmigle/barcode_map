import os
import tempfile
import shutil
from flask import Flask, request, Response, send_from_directory
import subprocess

app = Flask(__name__)

@app.route('/')
def serve_index():
    return send_from_directory('.', 'index.html')

@app.route('/run-barcode-map', methods=['POST'])
def run_barcode_map():
    brackets = request.form.get('brackets', '').strip()
    annotation = request.files.get('annotation')
    reads = request.files.get('reads')
    fasta = request.files.get('fasta')  # Get the optional FASTA file
    
    jobdir = tempfile.mkdtemp()
    try:
        ann_path = os.path.join(jobdir, annotation.filename)
        reads_path = os.path.join(jobdir, reads.filename)
        annotation.save(ann_path)
        reads.save(reads_path)
        
        command = [
            "/app/barcode_map.sh",
            "-b", brackets,
            "-a", ann_path,
            "-r", reads_path,
        ]
        
        # Add FASTA file to command if it was uploaded
        if fasta and fasta.filename:
            fasta_path = os.path.join(jobdir, fasta.filename)
            fasta.save(fasta_path)
            command.extend(["-f", fasta_path])
        
        proc = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd="/app")
        return Response(proc.stdout, mimetype='text/plain')
    except Exception as e:
        return Response("Internal server error: " + str(e), status=500, mimetype='text/plain')
    finally:
        shutil.rmtree(jobdir)

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
