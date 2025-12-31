import os
import sys

def install_and_import(package):
    import importlib
    try:
        importlib.import_module(package)
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", package])
    finally:
        globals()[package] = importlib.import_module(package)

try:
    import pypdf
except ImportError:
    print("pypdf not found, attempting to install...")
    try:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pypdf"])
        import pypdf
    except Exception as e:
        print(f"Failed to install pypdf: {e}")

try:
    import docx
except ImportError:
    print("python-docx not found, attempting to install...")
    try:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "python-docx"])
        import docx
    except Exception as e:
        print(f"Failed to install python-docx: {e}")

def extract_pdf(path):
    try:
        reader = pypdf.PdfReader(path)
        text = ""
        for page in reader.pages:
            text += page.extract_text() + "\n"
        return text
    except Exception as e:
        return f"Error reading PDF: {e}"

def extract_docx(path):
    try:
        doc = docx.Document(path)
        text = ""
        for para in doc.paragraphs:
            text += para.text + "\n"
        return text
    except Exception as e:
        return f"Error reading DOCX: {e}"

if __name__ == "__main__":
    pdf_path = r"c:\git\Digital_Cam\FPGA를 활용한 실시간 이미지 프로세싱 .pdf"
    docx_path = r"c:\git\Digital_Cam\프로젝트 플랜.docx"

    print("--- PDF CONTENT ---")
    print(extract_pdf(pdf_path))
    print("\n--- DOCX CONTENT ---")
    print(extract_docx(docx_path))
