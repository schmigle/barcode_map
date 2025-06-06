# app.py - Streamlit interface for barcode_map.sh

import streamlit as st
import subprocess
import tempfile
import os
import pathlib
import textwrap

st.set_page_config(page_title="Barcode Mapping Pipeline", layout="centered")

st.title("🔬 Barcode Mapping Pipeline")

st.markdown(
    textwrap.dedent(
        """
        Upload your **reference FASTA** and **reads FASTQ** files, provide the barcode *brackets* sequence, 
        and click **Run Pipeline**. The app invokes `barcode_map.sh` (and its companion `annotation_parser.py`) 
        inside the current environment (`barcode_env.yml`). When the run finishes you can download the SAM file 
        and view the console log directly below.
        """
    )
)

# --- Input widgets --------------------------------------------------------

brackets = st.text_input("Barcode brackets (e.g. ACGT_TGCA)")

ref_file = st.file_uploader(
    label="Reference FASTA", type=["fa", "fasta"], accept_multiple_files=False
)

reads_file = st.file_uploader(
    label="Reads FASTQ", type=["fastq", "fq"], accept_multiple_files=False
)

cols = st.columns(3)
with cols[0]:
    matches = st.number_input("Top matches", min_value=1, max_value=100, value=10, step=1)
with cols[1]:
    threads = st.number_input("Threads", min_value=1, max_value=64, value=4, step=1)
with cols[2]:
    sam_name = st.text_input("SAM output filename", value="barcode_aln.sam")

run_clicked = st.button("▶️ Run Pipeline")

# --- Execution ------------------------------------------------------------

if run_clicked:
    # Basic input validation (UI‑level only – barcode_map.sh does deeper checks)
    if not brackets:
        st.error("Please enter the barcode brackets sequence (e.g. ACGT_TGCA).")
        st.stop()
    if ref_file is None or reads_file is None:
        st.error("Please upload both a reference FASTA and reads FASTQ file.")
        st.stop()

    with tempfile.TemporaryDirectory() as tmpdir:
        # Save uploads to temporary files
        ref_path = os.path.join(tmpdir, ref_file.name)
        with open(ref_path, "wb") as f:
            f.write(ref_file.getbuffer())

        reads_path = os.path.join(tmpdir, reads_file.name)
        with open(reads_path, "wb") as f:
            f.write(reads_file.getbuffer())

        sam_path = os.path.join(tmpdir, sam_name)

        cmd = [
            "bash", "barcode_map.sh",
            "-b", brackets,
            "-f", ref_path,
            "-r", reads_path,
            "-m", str(matches),
            "-s", sam_path,
            "-t", str(int(threads)),
        ]

        st.markdown("### ⏱️ Running command:")
        st.code(" ".join(cmd))

        # Run the pipeline and capture output
        result = subprocess.run(cmd, capture_output=True, text=True)

        st.markdown("### 📜 Console log")
        st.text(result.stdout)
        if result.stderr:
            st.markdown("**stderr:**")
            st.text(result.stderr)

        if result.returncode == 0 and os.path.exists(sam_path):
            with open(sam_path, "rb") as samf:
                st.download_button(
                    label="💾 Download SAM file", data=samf, file_name=sam_name
                )
        else:
            st.error(f"Pipeline failed with exit code {result.returncode}.")
