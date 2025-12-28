#!/usr/bin/env python3
"""
Avorion API Documentation HTML to YAML Converter
Converts HTML documentation files to YAML format for better readability

Usage: python convert_html_to_yaml.py
"""

import os
import re
from pathlib import Path


def extract_class_info(html_content):
    """Extract basic class information from HTML"""
    data = {
        "name": None,
        "base_class": None,
        "availability": "both",
        "type": "class"
    }

    # Extract class name and base class from h1 (NOT the documentationheader)
    # Pattern: <h1>ClassName : <a href="BaseClass.html">BaseClass</a></h1>
    # or just: <h1>ClassName</h1>
    # Must NOT match: <h1 class="documentationheader">

    # Find all h1 tags that don't have a class attribute
    h1_pattern = r'<h1>([^<:]+?)(?:\s*:\s*<a[^>]*>([^<]+)</a>)?</h1>'
    h1_matches = re.finditer(h1_pattern, html_content)

    for match in h1_matches:
        class_name = match.group(1).strip()
        # Skip the documentation header
        if "Avorion" not in class_name and "Documentation" not in class_name:
            data["name"] = class_name
            if match.group(2):
                data["base_class"] = match.group(2).strip()
            break

    # Check for availability warnings
    if "only available on the client" in html_content:
        data["availability"] = "client-only"
    elif "only available on the server" in html_content:
        data["availability"] = "server-only"

    return data


def extract_constructor(html_content, class_name):
    """Extract constructor information"""
    if not class_name:
        return None

    # Pattern: <span class="keyword">function </span> ClassName(<params>)
    pattern = rf'<span class="keyword">function\s+</span>\s*{re.escape(class_name)}\s*\(([^)]*)\)'
    match = re.search(pattern, html_content)

    if not match:
        return None

    params_html = match.group(1)
    parameters = []

    if params_html.strip():
        # Extract parameters: <span class="type">type</span> <span class="parameter">name</span>
        param_pattern = r'<span class="type">([^<]+)</span>\s*<span class="parameter">([^<]+)</span>'
        param_matches = re.finditer(param_pattern, params_html)

        for pm in param_matches:
            param_type = pm.group(1).strip()
            param_name = pm.group(2).strip()
            parameters.append({
                "name": param_name,
                "type": param_type
            })

    # Build signature
    param_sig = ", ".join([f"{p['type']} {p['name']}" for p in parameters])

    return {
        "signature": f"{class_name}({param_sig})",
        "parameters": parameters
    }


def extract_properties(html_content, base_class):
    """Extract all properties from HTML"""
    properties = []
    seen_props = set()

    # Find all property links in the sidebar
    # <a href="#propName">propName</a> or <a class="inheritedproperty" href="#propName">propName</a>
    link_pattern = r'<a\s+(?:class="(inheritedproperty)"\s+)?href="#([a-zA-Z_][a-zA-Z0-9_]*)"[^>]*>(?:[^<]+)</a>'

    for match in re.finditer(link_pattern, html_content):
        is_inherited = match.group(1) == "inheritedproperty"
        prop_name = match.group(2)

        # Skip navigation and method names
        if prop_name in seen_props:
            continue

        # Try to find the property definition
        prop_def = find_property_definition(html_content, prop_name)

        if prop_def:
            seen_props.add(prop_name)
            prop_def["inherited"] = is_inherited
            if is_inherited and base_class:
                prop_def["inherited_from"] = base_class
            properties.append(prop_def)

    return properties


def find_property_definition(html_content, prop_name):
    """Find detailed property definition by name"""
    # Pattern: <div id="propName">...<span class="type">Type</span> <span class="property">propName</span>...
    # Also capture access modifier: [read-only], [write-only], or nothing (read-write)

    pattern = rf'<div id="{re.escape(prop_name)}"[^>]*>.*?<span class="type">\s*([^<]+?)\s*</span>\s*<span class="property">\s*{re.escape(prop_name)}\s*</span>'
    match = re.search(pattern, html_content, re.DOTALL)

    if not match:
        return None

    prop_type = match.group(1).strip()

    # Find access modifier in the same section
    access_pattern = rf'<div id="{re.escape(prop_name)}"[^>]*>.*?<td align="right">.*?<b>\[([^\]]+)\]</b>'
    access_match = re.search(access_pattern, html_content, re.DOTALL)

    if access_match:
        access = access_match.group(1).strip()
    else:
        access = "read-write"

    return {
        "name": prop_name,
        "type": prop_type,
        "access": access
    }


def extract_methods(html_content, base_class):
    """Extract all methods from HTML"""
    methods = []
    seen_methods = set()

    # Find all method links in the sidebar
    # <a class="code" href="#methodName">methodName</a> or <a class="inheritedcode" href="#methodName">methodName</a>
    link_pattern = r'<a\s+class="(code|inheritedcode)"\s+href="#([a-zA-Z_][a-zA-Z0-9_]*)"[^>]*>(?:[^<]+)</a>'

    for match in re.finditer(link_pattern, html_content):
        is_inherited = match.group(1) == "inheritedcode"
        method_name = match.group(2)

        if method_name in seen_methods:
            continue

        # Try to find the method definition
        method_def = find_method_definition(html_content, method_name)

        if method_def:
            seen_methods.add(method_name)
            method_def["inherited"] = is_inherited
            if is_inherited and base_class:
                method_def["inherited_from"] = base_class
            methods.append(method_def)

    return methods


def find_method_definition(html_content, method_name):
    """Find detailed method definition by name"""
    # Pattern: <div id="methodName">...<span class="keyword">function returnType</span> methodName(<params>)

    pattern = rf'<div id="{re.escape(method_name)}"[^>]*>.*?<span class="keyword">function\s+([^<]+?)</span>\s*{re.escape(method_name)}\s*\(([^)]*)\)'
    match = re.search(pattern, html_content, re.DOTALL)

    if not match:
        return None

    return_type = match.group(1).strip()
    params_html = match.group(2).strip()

    # Convert "var" to "void" for consistency
    if return_type == "var":
        return_type = "void"

    parameters = []
    if params_html:
        # Extract parameters
        param_pattern = r'<span class="type">([^<]+)</span>\s*<span class="parameter">([^<]+)</span>'
        param_matches = re.finditer(param_pattern, params_html)

        for pm in param_matches:
            param_type = pm.group(1).strip()
            param_name = pm.group(2).strip()
            parameters.append({
                "name": param_name,
                "type": param_type
            })

    # Build signature
    param_sig = ", ".join([f"{p['type']} {p['name']}" for p in parameters])
    signature = f"{method_name}({param_sig})"

    return {
        "name": method_name,
        "signature": signature,
        "returns": return_type,
        "parameters": parameters
    }


def generate_yaml_content(data):
    """Generate YAML content from parsed data"""
    lines = []

    # Header
    lines.append(f"# {data['name']} API Documentation")
    lines.append(f"name: {data['name']}")
    lines.append(f"type: {data['type']}")

    if data.get('base_class'):
        lines.append(f"extends: {data['base_class']}")

    lines.append(f"availability: {data['availability']}")
    lines.append(f"description: {data['name']} class")
    lines.append("")

    # Constructor
    if data.get('constructor'):
        ctor = data['constructor']
        lines.append("constructor:")
        lines.append(f"  signature: {ctor['signature']}")

        if ctor.get('parameters'):
            lines.append("  parameters:")
            for param in ctor['parameters']:
                lines.append(f"    - name: {param['name']}")
                lines.append(f"      type: {param['type']}")
                lines.append(f"      description: {param['name']} parameter")

        lines.append(f"  returns: {data['name']} instance")
        lines.append("")

    # Properties
    if data.get('properties'):
        lines.append("properties:")

        # Separate own and inherited
        own_props = [p for p in data['properties'] if not p.get('inherited')]
        inherited_props = [p for p in data['properties'] if p.get('inherited')]

        # Own properties first
        for prop in own_props:
            lines.append(f"  - name: {prop['name']}")
            lines.append(f"    type: {prop['type']}")
            lines.append(f"    access: {prop['access']}")
            lines.append(f"    description: {prop['name']} property")
            lines.append("")

        # Inherited properties
        for prop in inherited_props:
            lines.append(f"  - name: {prop['name']}")
            lines.append(f"    type: {prop['type']}")
            lines.append(f"    access: {prop['access']}")
            if prop.get('inherited_from'):
                lines.append(f"    inherited: {prop['inherited_from']}")
            lines.append(f"    description: {prop['name']} property")
            lines.append("")

    # Methods
    if data.get('methods'):
        lines.append("methods:")

        # Separate own and inherited
        own_methods = [m for m in data['methods'] if not m.get('inherited')]
        inherited_methods = [m for m in data['methods'] if m.get('inherited')]

        # Own methods first
        for method in own_methods:
            lines.append(f"  - name: {method['name']}")
            lines.append(f"    signature: {method['signature']}")

            if method.get('parameters'):
                lines.append("    parameters:")
                for param in method['parameters']:
                    lines.append(f"      - name: {param['name']}")
                    lines.append(f"        type: {param['type']}")
                    lines.append(f"        description: {param['name']} parameter")

            lines.append(f"    returns: {method['returns']}")
            lines.append(f"    description: {method['name']} method")
            lines.append("")

        # Inherited methods
        for method in inherited_methods:
            lines.append(f"  - name: {method['name']}")
            lines.append(f"    signature: {method['signature']}")

            if method.get('parameters'):
                lines.append("    parameters:")
                for param in method['parameters']:
                    lines.append(f"      - name: {param['name']}")
                    lines.append(f"        type: {param['type']}")
                    lines.append(f"        description: {param['name']} parameter")

            lines.append(f"    returns: {method['returns']}")
            if method.get('inherited_from'):
                lines.append(f"    inherited: {method['inherited_from']}")
            lines.append(f"    description: {method['name']} method")
            lines.append("")

    # Notes
    lines.append("notes:")
    lines.append("  - Auto-converted from HTML documentation")

    if data['availability'] == 'client-only':
        lines.append("  - Client-only - not available on server")
    elif data['availability'] == 'server-only':
        lines.append("  - Server-only - not available on client")

    if data.get('base_class'):
        lines.append(f"  - Inherits from {data['base_class']}")

    return "\n".join(lines)


def parse_html_file(file_path):
    """Parse HTML file and extract all documentation data"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Extract basic class info
        data = extract_class_info(content)

        if not data['name']:
            return None

        # Skip non-class files
        if data['name'] in ['Avorion Script API Documentation', 'Avorion Documentation']:
            return None

        # Extract constructor
        data['constructor'] = extract_constructor(content, data['name'])

        # Extract properties and methods
        data['properties'] = extract_properties(content, data.get('base_class'))
        data['methods'] = extract_methods(content, data.get('base_class'))

        return data

    except Exception as e:
        print(f"    ERROR parsing file: {str(e)}")
        return None


def convert_html_to_yaml(html_file, output_dir):
    """Convert a single HTML file to YAML"""
    try:
        data = parse_html_file(html_file)

        if not data:
            return False

        # Generate YAML content
        yaml_content = generate_yaml_content(data)

        # Write to file
        yaml_file = output_dir / f"{html_file.stem}.yaml"
        with open(yaml_file, 'w', encoding='utf-8') as f:
            f.write(yaml_content)

        return True

    except Exception as e:
        print(f"    ERROR converting {html_file.name}: {str(e)}")
        return False


def main():
    """Main conversion function"""
    # Get script directory
    script_dir = Path(__file__).parent

    print("=" * 70)
    print("Avorion API Documentation HTML to YAML Converter")
    print("=" * 70)
    print(f"\nWorking directory: {script_dir}")

    # Find all HTML files
    html_files = list(script_dir.glob("*.html"))

    # Filter out special files
    skip_files = {'index.html', 'Search.html', 'Functions.html', 'stylesheet.css'}
    html_files = [f for f in html_files if f.name not in skip_files]

    print(f"Found {len(html_files)} HTML files to convert\n")

    # Convert each file
    converted = 0
    skipped = 0
    errors = 0

    for i, html_file in enumerate(html_files, 1):
        print(f"[{i}/{len(html_files)}] {html_file.name}")

        if convert_html_to_yaml(html_file, script_dir):
            print(f"    [OK] Created {html_file.stem}.yaml")
            converted += 1
        else:
            print(f"    [SKIP] Skipped")
            skipped += 1

    # Summary
    print("\n" + "=" * 70)
    print("Conversion Summary:")
    print("=" * 70)
    print(f"  Converted: {converted}")
    print(f"  Skipped:   {skipped}")
    print(f"  Errors:    {errors}")
    print(f"  Total:     {len(html_files)}")
    print("\nDone!")


if __name__ == "__main__":
    main()
