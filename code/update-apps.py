#!/usr/bin/env python3
import os
import xml.etree.ElementTree as ET

def convert_xml_to_md(xml_path, md_path):
    tree = ET.parse(xml_path)
    root = tree.getroot()
    
    # Извлекаем данные из XML (адаптируйте под вашу структуру AppStream)
    name = root.findtext('name', 'Unknown App')
    summary = root.findtext('summary', '')
    description = root.findtext('.//description/p', '')
    homepage = root.findtext('.//url[@type="homepage"]', '')
    
    # Генерируем контент Markdown
    md_content = f"# {name}\n\n"
    md_content += f"**{summary}**\n\n"
    md_content += f"{description}\n\n"
    if homepage:
        md_content += f"[Official Website]({homepage})\n\n"
    
    # Сюда можно добавить логику поиска свежих ссылок через GitHub API
    # md_content += f"## Download\n[Download AppImage]({download_url})\n"

    with open(md_path, 'w', encoding='utf-8') as f:
        f.write(md_content)

def process_directory(directory):
    for filename in os.listdir(directory):
        if filename.endswith('.appdata.xml'):
            xml_path = os.path.join(directory, filename)
            md_path = os.path.join(directory, filename.replace('.appdata.xml', '.md'))
            convert_xml_to_md(xml_path, md_path)
            print(f"Processed: {filename}")

if __name__ == "__main__":
    process_directory('apps')
