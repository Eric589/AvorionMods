#!/usr/bin/env python3
"""
Convert Avorion Callbacks HTML files to YAML format
"""

import re
from pathlib import Path


def extract_callbacks(html_content):
    """Extract all callback definitions from HTML"""
    callbacks = []

    # Find all callback definitions
    # Pattern: <div id="callbackName" class="codecontainer">...<callback> signature
    pattern = r'<div id="([^"]+)" class="codecontainer">.*?<span class="keyword">callback</span>\s+([^<]+)<br/>'
    matches = re.finditer(pattern, html_content, re.DOTALL)

    for match in matches:
        callback_id = match.group(1)
        signature = match.group(2).strip()

        # Find description for this callback
        desc_pattern = rf'<div id="{re.escape(callback_id)}" class="code">.*?<p>(.*?)</p>'
        desc_match = re.search(desc_pattern, html_content, re.DOTALL)
        description = ''
        if desc_match:
            description = desc_match.group(1).strip()
            # Remove HTML tags
            description = re.sub(r'<[^>]+>', '', description).strip()
            # Clean up extra whitespace
            description = ' '.join(description.split())

        # Extract parameter descriptions
        param_desc_pattern = rf'<div id="{re.escape(callback_id)}" class="code">.*?<span class="parameter">Parameters</span>.*?<div class="indented">(.*?)</div>'
        param_desc_match = re.search(param_desc_pattern, html_content, re.DOTALL)

        param_descriptions = {}
        if param_desc_match:
            params_section = param_desc_match.group(1)
            # Find all parameter descriptions
            param_pattern = r'<span class="parameter">([^<]+)</span>\s*(.*?)<br/>'
            for pm in re.finditer(param_pattern, params_section):
                param_name = pm.group(1).strip()
                param_desc = pm.group(2).strip()
                param_desc = re.sub(r'<[^>]+>', '', param_desc).strip()
                param_descriptions[param_name] = param_desc

        # Extract parameters from signature
        param_match = re.search(r'\(([^)]*)\)', signature)
        params_str = param_match.group(1) if param_match else ''
        params = [p.strip() for p in params_str.split(',') if p.strip()]

        callbacks.append({
            'name': callback_id,
            'signature': signature,
            'description': description,
            'parameters': params,
            'param_descriptions': param_descriptions
        })

    return callbacks


def extract_title(html_content):
    """Extract callback file title"""
    h1_pattern = r'<h1>([^<]+)</h1>'
    match = re.search(h1_pattern, html_content)
    if match:
        return match.group(1).strip()
    return None


def extract_notes(html_content):
    """Extract any notes from the HTML"""
    # Look for note paragraph
    note_pattern = r'<p>\s*Note:(.*?)</p>'
    match = re.search(note_pattern, html_content, re.DOTALL)
    if match:
        note = match.group(1).strip()
        note = re.sub(r'<[^>]+>', '', note).strip()
        note = ' '.join(note.split())
        return note
    return None


def generate_yaml(title, callbacks, note=None):
    """Generate YAML content for callbacks"""
    lines = []

    # Header
    lines.append(f"# {title} Documentation")
    lines.append(f"name: {title}")
    lines.append("type: callbacks")
    lines.append(f"description: Callback functions for {title.replace(' Callbacks', '').strip()} scripts")
    lines.append("")

    if note:
        lines.append("note: |")
        lines.append(f"  {note}")
        lines.append("")

    # Callbacks
    if callbacks:
        lines.append("callbacks:")
        for cb in callbacks:
            lines.append(f"  - name: {cb['name']}")
            lines.append(f"    signature: {cb['signature']}")

            if cb['parameters']:
                lines.append("    parameters:")
                for param in cb['parameters']:
                    lines.append(f"      - name: {param}")
                    if param in cb['param_descriptions']:
                        lines.append(f"        description: {cb['param_descriptions'][param]}")
                    else:
                        lines.append(f"        description: {param} parameter")

            if cb['description']:
                lines.append(f"    description: {cb['description']}")
            else:
                lines.append(f"    description: {cb['name']} callback")

            lines.append("")

    lines.append("notes:")
    lines.append("  - Manually converted from HTML callbacks documentation")
    lines.append("  - Callbacks may be buffered and won't always execute immediately")

    return "\n".join(lines)


def convert_callback_file(html_file):
    """Convert a single callback HTML file to YAML"""
    try:
        with open(html_file, 'r', encoding='utf-8') as f:
            content = f.read()

        title = extract_title(content)
        if not title:
            print(f"  ERROR: No title found")
            return False

        callbacks = extract_callbacks(content)
        note = extract_notes(content)

        yaml_content = generate_yaml(title, callbacks, note)

        # Write YAML file
        yaml_file = html_file.with_suffix('.yaml')
        with open(yaml_file, 'w', encoding='utf-8') as f:
            f.write(yaml_content)

        return True

    except Exception as e:
        print(f"  ERROR: {str(e)}")
        return False


def main():
    """Convert all callback HTML files"""
    doc_dir = Path(__file__).parent

    print("=" * 70)
    print("Avorion Callbacks Documentation HTML to YAML Converter")
    print("=" * 70)

    # Find all callback files
    callback_files = list(doc_dir.glob("*Callbacks.html"))

    print(f"\nFound {len(callback_files)} callback files\n")

    converted = 0
    for i, html_file in enumerate(callback_files, 1):
        print(f"[{i}/{len(callback_files)}] {html_file.name}")

        if convert_callback_file(html_file):
            print(f"    [OK] Created {html_file.stem}.yaml")
            converted += 1
        else:
            print(f"    [FAIL] Conversion failed")

    print("\n" + "=" * 70)
    print(f"Converted {converted}/{len(callback_files)} callback files")
    print("Done!")


if __name__ == "__main__":
    main()
