#!/bin/bash
# Standalone OoTMM test launcher with SteamOS webkit fixes
# Copy this to your Steam Deck and run: bash ootmm-test.sh

BASEDIR=$(grep '^base_dir=' ~/.config/decomp-depot.conf 2>/dev/null | cut -d= -f2)
BASEDIR=${BASEDIR:-$HOME/Games}
OOTMM_DIR="$BASEDIR/ootmm"

echo "=== OoTMM Diagnostic ==="
echo "OoTMM dir: $OOTMM_DIR"
echo "Display: $DISPLAY"
echo "Session: $XDG_SESSION_TYPE"

echo ""
echo "=== Files ==="
ls -la "$OOTMM_DIR/" 2>/dev/null || echo "NOT FOUND"

echo ""
echo "=== resources.neu size ==="
stat -c%s "$OOTMM_DIR/resources.neu" 2>/dev/null || echo "MISSING"

echo ""
echo "=== Webkit ==="
ldconfig -p 2>/dev/null | grep webkit

echo ""
echo "=== Extract resources.neu to physical directory ==="
cd "$OOTMM_DIR"
python3 - resources.neu << 'PYEOF'
import json, os, sys

with open(sys.argv[1], 'rb') as f:
    data = f.read()

brace_count = 0
json_end = 0
for i, b in enumerate(data):
    if b == 123: brace_count += 1
    elif b == 125:
        brace_count -= 1
        if brace_count == 0:
            json_end = i + 1
            break

manifest = json.loads(data[:json_end])
file_data = data[json_end:]

def extract(node, prefix):
    for name, info in node.get('files', {}).items():
        if 'files' in info:
            extract(info, os.path.join(prefix, name))
        elif 'offset' in info and 'size' in info:
            offset = int(info['offset'])
            size = int(info['size'])
            filepath = os.path.join(prefix, name)
            os.makedirs(os.path.dirname(filepath), exist_ok=True)
            with open(filepath, 'wb') as f:
                f.write(file_data[offset:offset+size])
            print(f"  {filepath}")

extract(manifest, '.')
PYEOF

echo ""
echo "=== Files now in OoTMM dir ==="
find . -name '*.js' -o -name '*.html' | sort

echo ""
echo "=== Enable web inspector for debugging ==="
# Modify the config to enable the inspector
sed -i 's/"enableInspector": false/"enableInspector": true/' neutralino.config.json 2>/dev/null
sed -i 's/"enableInspector":false/"enableInspector":true/' neutralino.config.json 2>/dev/null
echo "Inspector enabled"

echo ""
echo "=== Launching with webkit fixes + inspector ==="
cd "$OOTMM_DIR" || exit 1
echo "Env: GDK_BACKEND=x11 WEBKIT_DISABLE_COMPOSITING_MODE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1"
echo ""
GDK_BACKEND=x11 \
WEBKIT_DISABLE_COMPOSITING_MODE=1 \
WEBKIT_DISABLE_DMABUF_RENDERER=1 \
./ootmm-linux_x64
