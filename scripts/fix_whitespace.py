import os

files = ['../scripts/new-app.ps1', '../.github/workflows/new-app.yml']
for file_path in files:
    print(f"Processing {file_path}")
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    with open(file_path, 'w', encoding='utf-8', newline='') as f:
        for line in lines:
            clean = line.rstrip()
            f.write(clean + '\r\n')
