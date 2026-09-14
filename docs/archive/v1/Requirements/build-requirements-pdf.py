#!/usr/bin/env python3
"""
Build requirements PDF from JSON source.
JSON is the single source of truth; LaTeX/PDF are generated outputs.

Usage: python3 build-requirements-pdf.py [json_file]
       If no file specified, processes all REQ-*.json files in directory.
"""

import json
import subprocess
import os
import sys
import hashlib
import glob
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def load_json(json_file):
    with open(json_file, 'r') as f:
        return json.load(f)

def get_json_hash(json_file):
    """Calculate SHA-256 hash of JSON file for traceability."""
    with open(json_file, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()[:16]  # First 16 chars

def escape_latex(text):
    """Escape special LaTeX characters."""
    replacements = [
        ('&', r'\&'),
        ('%', r'\%'),
        ('$', r'\$'),
        ('#', r'\#'),
        ('_', r'\_'),
        ('{', r'\{'),
        ('}', r'\}'),
        ('~', r'\textasciitilde{}'),
        ('^', r'\textasciicircum{}'),
    ]
    for old, new in replacements:
        text = text.replace(old, new)
    return text

def format_standard_id(std_id):
    """Convert JSON standard ID to display format."""
    # 32-CFR-2002 -> 32 CFR Part 2002
    # FIPS-197 -> FIPS 197
    # NIST-SP-800-132 -> NIST SP 800-132
    if std_id.startswith("32-CFR"):
        return "32 CFR Part " + std_id.split("-")[-1]
    elif std_id.startswith("FIPS"):
        return std_id.replace("-", " ")
    elif std_id.startswith("NIST-SP"):
        parts = std_id.split("-")
        return f"NIST SP {parts[2]}-{parts[3]}" + (f"-{parts[4]}" if len(parts) > 4 else "")
    return std_id

def format_date(date_str):
    """Convert 2026-01-22 to January 22, 2026."""
    dt = datetime.strptime(date_str, "%Y-%m-%d")
    return dt.strftime("%B %d, %Y").replace(" 0", " ")

def generate_latex(data, json_hash):
    doc = data["document"]
    standards = data["standards"]
    requirements = data["requirements"]
    summary = data["summary"]

    # Build standards lookup for URLs
    std_lookup = {s["id"]: s for s in standards}

    # Group requirements by category
    categories = {}
    for req in requirements:
        cat = req["category"]
        if cat not in categories:
            categories[cat] = []
        categories[cat].append(req)

    # Format date
    formatted_date = format_date(doc["date"])

    tex = rf"""\documentclass[11pt,letterpaper]{{article}}

% ============================================================================
% PACKAGES
% ============================================================================
\usepackage[margin=1in, top=1.5in, headheight=85pt]{{geometry}}
\usepackage{{fancyhdr}}
\usepackage{{lastpage}}
\usepackage{{enumitem}}
\usepackage{{xcolor}}
\usepackage{{hyperref}}
\usepackage{{tabularx}}
\usepackage{{booktabs}}
\usepackage{{longtable}}

% ============================================================================
% DOCUMENT VARIABLES (Generated from JSON)
% ============================================================================
\newcommand{{\UniqueID}}{{{doc["id"]}}}
\newcommand{{\DocumentDate}}{{{formatted_date}}}
\newcommand{{\AuthorName}}{{SendCUIEmail Development Team}}
\newcommand{{\DocumentTitle}}{{{doc["title"]}}}

% ============================================================================
% DOCUMENT CONFIGURATION
% ============================================================================
\hypersetup{{
    colorlinks=true,
    linkcolor=blue,
    urlcolor=blue,
    pdfborder={{0 0 0}},
    pdftitle={{{doc["id"]} {doc["title"]}}},
    pdfauthor={{SendCUIEmail Project}},
}}

\setlength{{\parindent}}{{0pt}}
\setlength{{\parskip}}{{6pt}}

% ============================================================================
% HEADER AND FOOTER
% ============================================================================
\pagestyle{{fancy}}
\fancyhf{{}}
\fancyhead[L]{{\textbf{{SendCUIEmail}}}}
\fancyhead[R]{{\parbox[b]{{3.5in}}{{\raggedleft\large\textbf{{Requirements Document}}}}}}
\renewcommand{{\headrulewidth}}{{0pt}}
\fancyfoot[L]{{\small \UniqueID}}
\fancyfoot[C]{{\small Page \thepage\ of \pageref{{LastPage}}}}
\fancyfoot[R]{{\small \DocumentDate}}
\renewcommand{{\footrulewidth}}{{0.4pt}}

% Define colors
\definecolor{{mandatory}}{{RGB}}{{220,53,69}}
\definecolor{{recommended}}{{RGB}}{{255,193,7}}

% ============================================================================
% BEGIN DOCUMENT
% ============================================================================
\begin{{document}}

\begin{{center}}
\Large\textbf{{\DocumentTitle}}\\[6pt]
\large\UniqueID\\[12pt]
\normalsize\DocumentDate
\end{{center}}

\vspace{{0.25in}}

% ============================================================================
% DOCUMENT INFO
% ============================================================================
\section*{{Document Information}}

\begin{{tabular}}{{@{{}}ll@{{}}}}
\textbf{{Document ID:}} & \UniqueID \\
\textbf{{Version:}} & {doc["version"]} \\
\textbf{{Status:}} & {doc["status"]} \\
\textbf{{Author:}} & \AuthorName \\
\textbf{{Date:}} & \DocumentDate \\
\textbf{{Source Hash:}} & \texttt{{{json_hash}}} \\
\end{{tabular}}

\vspace{{0.25in}}

% ============================================================================
% PURPOSE
% ============================================================================
\section{{Purpose}}

This document defines the cryptographic requirements for SendCUIEmail to ensure compliance with federal standards for protecting Controlled Unclassified Information (CUI). These requirements establish the minimum security controls that must be implemented and verified.

% ============================================================================
% SCOPE
% ============================================================================
\section{{Scope}}

These requirements apply to:
\begin{{itemize}}[topsep=4pt, itemsep=2pt]
    \item File encryption and decryption operations
    \item Password/key derivation functions
    \item Random number generation for cryptographic material
    \item All platforms where SendCUIEmail operates (Windows, macOS, Linux)
\end{{itemize}}

% ============================================================================
% APPLICABLE STANDARDS (Generated from JSON)
% ============================================================================
\section{{Applicable Standards}}

\begin{{tabularx}}{{\textwidth}}{{lX}}
\toprule
\textbf{{Standard}} & \textbf{{Description}} \\
\midrule
"""

    # Add standards with hyperlinks
    for std in standards:
        display_id = format_standard_id(std["id"])
        name = std["name"]
        url = std.get("url", "")

        # Add (reference) suffix for 800-171 and 800-53
        if "800-171" in std["id"] or "800-53" in std["id"]:
            name += " (reference)"

        if url:
            tex += rf"\href{{{url}}}{{{display_id}}} & {name} \\" + "\n"
        else:
            tex += rf"{display_id} & {name} \\" + "\n"

    tex += r"""\bottomrule
\end{tabularx}

% ============================================================================
% REQUIREMENTS (Generated from JSON)
% ============================================================================
\section{Cryptographic Requirements}

Requirements are categorized as:
\begin{itemize}[topsep=4pt, itemsep=2pt]
    \item \textcolor{mandatory}{\textbf{[M]}} -- Mandatory: Must be implemented
    \item \textcolor{recommended}{\textbf{[R]}} -- Recommended: Should be implemented where feasible
\end{itemize}

"""

    # Add requirements by category
    for cat_name in summary["categories"]:
        if cat_name not in categories:
            continue

        tex += rf"\subsection{{{cat_name} Requirements}}" + "\n\n"
        tex += r"""\begin{longtable}{@{}p{1.2cm}p{12cm}@{}}
\toprule
\textbf{ID} & \textbf{Requirement} \\
\midrule
\endfirsthead
\toprule
\textbf{ID} & \textbf{Requirement} \\
\midrule
\endhead

"""

        for req in categories[cat_name]:
            priority_mark = r"\textcolor{mandatory}{\textbf{[M]}}" if req["priority"] == "Mandatory" else r"\textcolor{recommended}{\textbf{[R]}}"
            desc = escape_latex(req["description"])
            tex += rf"{req['id']} & {priority_mark} {desc} \\[6pt]" + "\n\n"

        tex += r"""\bottomrule
\end{longtable}

"""

    tex += r"""% ============================================================================
% VERIFICATION
% ============================================================================
\section{Verification}

Each requirement SHALL be verified through one or more of the following methods:

\begin{tabularx}{\textwidth}{lX}
\toprule
\textbf{Method} & \textbf{Description} \\
\midrule
Inspection & Code review to verify implementation matches requirement \\
Test & Automated or manual testing to verify correct behavior \\
Analysis & Review of design documentation or cryptographic parameters \\
\bottomrule
\end{tabularx}

\vspace{12pt}

Verification results are documented in the corresponding VER document.

% ============================================================================
% TRACEABILITY (Generated from JSON)
% ============================================================================
\section{Requirements Traceability}

\begin{tabularx}{\textwidth}{llX}
\toprule
\textbf{Requirement} & \textbf{Standard} & \textbf{Section} \\
\midrule
"""

    # Generate traceability rows from requirements
    for req in requirements:
        req_id = req["id"]
        std_display = format_standard_id(req["standard"])
        trace = escape_latex(req.get("trace", ""))
        # Convert § to LaTeX \S
        trace = trace.replace("§", r"\S")
        tex += rf"{req_id} & {std_display} & {trace} \\" + "\n"

    tex += r"""\bottomrule
\end{tabularx}

% ============================================================================
% REVISION HISTORY
% ============================================================================
\section{Revision History}

\begin{tabularx}{\textwidth}{llX}
\toprule
\textbf{Version} & \textbf{Date} & \textbf{Description} \\
\midrule
"""

    tex += rf"{doc['version']} & {formatted_date} & Initial release \\" + "\n"

    tex += r"""\bottomrule
\end{tabularx}

\end{document}
"""

    return tex

def build_pdf(json_file):
    """Build PDF from a single JSON file."""
    # Load JSON first to get version for filename
    data = load_json(json_file)
    version = data["document"]["version"]

    # Derive output filenames: REQ-2026-001_cryptographic_compliance.json -> REQ-2026-001_cryptographic_compliance_v1.0.tex
    base_name = os.path.splitext(json_file)[0]
    versioned_base = f"{base_name}_v{version}"
    tex_file = versioned_base + ".tex"
    pdf_file = versioned_base + ".pdf"

    print(f"Building PDF from {os.path.basename(json_file)} (v{version})...")

    # Calculate hash for traceability
    json_hash = get_json_hash(json_file)
    print(f"  Source hash: {json_hash}")

    # Generate LaTeX
    print(f"  Generating: {os.path.basename(tex_file)}")
    tex = generate_latex(data, json_hash)

    with open(tex_file, 'w') as f:
        f.write(tex)

    # Compile PDF (twice for references)
    print("  Compiling PDF...")
    work_dir = os.path.dirname(json_file) or SCRIPT_DIR
    os.chdir(work_dir)

    for i in range(2):
        result = subprocess.run(
            ["pdflatex", "-interaction=nonstopmode", os.path.basename(tex_file)],
            capture_output=True,
            text=True
        )
        if result.returncode != 0 and i == 1:
            print("  ERROR: pdflatex failed")
            print(result.stdout[-1000:] if len(result.stdout) > 1000 else result.stdout)
            return 1

    # Clean auxiliary files
    for ext in [".aux", ".log", ".out", ".toc"]:
        aux_file = versioned_base + ext
        if os.path.exists(aux_file):
            os.remove(aux_file)

    print(f"  Created: {os.path.basename(pdf_file)}")
    return 0

def main():
    # Determine which JSON files to process
    if len(sys.argv) > 1:
        # Specific file provided
        json_files = [sys.argv[1]]
    else:
        # Find all REQ-*.json files in script directory
        json_files = glob.glob(os.path.join(SCRIPT_DIR, "REQ-*.json"))

    if not json_files:
        print("No JSON files found to process.")
        print("Usage: python3 build-requirements-pdf.py [json_file]")
        return 1

    # Process each file
    for json_file in json_files:
        result = build_pdf(json_file)
        if result != 0:
            return result

    print("Done.")
    return 0

if __name__ == "__main__":
    exit(main())
