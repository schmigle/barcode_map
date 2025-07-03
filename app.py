import os
import tempfile
import shutil
from flask import Flask, request, Response
import docker

app = Flask(__name__)
client = docker.from_env()

@app.route('/run-barcode-map', methods=['POST'])
def run_barcode_map():
    brackets = request.form.get('brackets', '').strip()
    annotation = request.files.get('annotation')
    reads = request.files.get('reads')
    jobdir = tempfile.mkdtemp()
    try:
        ann_path = os.path.join(jobdir, annotation.filename)
        reads_path = os.path.join(jobdir, reads.filename)
        annotation.save(ann_path)
        reads.save(reads_path)

        command = [
            "/barcode_map.sh",
            "-b", brackets,
            "-a", f"/data/{os.path.basename(ann_path)}",
            "-r", f"/data/{os.path.basename(reads_path)}",
        ]
        result = client.containers.run(
            "moshesteyn/barcode_map:latest",
            command,
            volumes={jobdir: {'bind': '/data', 'mode': 'rw'}},
            working_dir="/data",
            remove=True,
            stdout=True,
            stderr=True
        )
        return Response(result, mimetype='text/plain')
    except docker.errors.ContainerError as e:
        # Print everything from inside the container (error or output)
        return Response((e.stderr or e.stdout or str(e)), status=400, mimetype='text/plain')
    except Exception as e:
        return Response("Internal server error: " + str(e), status=500, mimetype='text/plain')
    finally:
        shutil.rmtree(jobdir)

@app.route('/')
def index():
    return open('index.html').read()

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)
