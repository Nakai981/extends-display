"""Windows-friendly syntax/config checks. This does NOT replace an Xcode build."""
from pathlib import Path
import re
import subprocess
import tempfile
import sys
import json
import yaml
from tree_sitter import Language, Parser
import tree_sitter_swift

root = Path(__file__).resolve().parents[1]
parser = Parser(Language(tree_sitter_swift.language()))
errors = []
sources = list(root.glob('Sources/*.swift')) + list(root.glob('MacCompanion/Sources/*.swift')) + list(root.glob('Tests/*.swift'))
for path in sources:
    data = path.read_bytes()
    tree = parser.parse(data)
    def visit(node):
        if node.type == 'ERROR' or node.is_missing:
            errors.append(f'{path.relative_to(root)}:{node.start_point.row+1}: {node.type}: {data[node.start_byte:node.end_byte][:120]!r}')
        for child in node.children:
            visit(child)
    visit(tree.root_node)
for relative in ['project.yml', 'MacCompanion/project.yml', '.github/workflows/apple-build.yml']:
    config = yaml.safe_load((root / relative).read_text(encoding='utf-8'))
    if not isinstance(config, dict):
        errors.append(f'{relative}: expected YAML mapping')
for path in [root / 'project.yml', root / 'MacCompanion/project.yml']:
    config = yaml.safe_load(path.read_text(encoding='utf-8'))
    for target in config['targets'].values():
        for source in target.get('sources', []):
            source_path = source if isinstance(source, str) else source['path']
            if not (path.parent / source_path).exists():
                errors.append(f'Missing target source: {source_path}')
http = (root / 'Sources/LocalHTTPServer.swift').read_text(encoding='utf-8')
html = http.split('static let html = """', 1)[1].split('"""', 1)[0]
script = re.search(r'<script>(.*?)</script>', html, re.S).group(1).replace('\\\\', '\\')
browser_source = (root / 'Sources/BrowserController.swift').read_text(encoding='utf-8')
browser_scripts = [s.replace('\\\\', '\\') for s in re.findall(r'script\("""\n(.*?)""", arguments:', browser_source, re.S)]
if len(browser_scripts) != 3:
    errors.append('Expected 3 browser control scripts')
with tempfile.TemporaryDirectory() as directory:
    js = Path(directory) / 'viewer.js'
    js.write_text(script, encoding='utf-8')
    result = subprocess.run(['node', '--check', str(js)], capture_output=True, text=True)
    if result.returncode:
        errors.append(result.stderr)
    fixture = Path(directory) / 'fixtures.json'
    fixture.write_text(json.dumps({'viewer': script, 'browser': browser_scripts}), encoding='utf-8')
    result = subprocess.run(['node', str(root / 'Tests/WebControlTests.cjs'), str(fixture)], capture_output=True, text=True, encoding='utf-8')
    if result.returncode:
        errors.append(result.stderr)
    else:
        print(result.stdout.strip())
    preview = root / 'preview/desktop.html'
    if preview.exists():
        blocks = re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>', preview.read_text(encoding='utf-8'), re.S | re.I)
        for index, block in enumerate(blocks):
            preview_js = Path(directory) / f'preview-{index}.js'
            preview_js.write_text(block, encoding='utf-8')
            result = subprocess.run(['node', '--check', str(preview_js)], capture_output=True, text=True, encoding='utf-8')
            if result.returncode:
                errors.append(result.stderr)
        if blocks:
            print(f'PASS: syntax checked {len(blocks)} offline design-preview JavaScript block(s).')
if errors:
    print('\n'.join(errors)); sys.exit(1)
print(f'PASS: parsed {len(sources)} Swift files, 3 YAML files, target source paths, and LAN viewer JavaScript.')
print('Apple SDK type checking, XCTest, simulator, UI and device behavior remain unverified until run on a Mac.')
