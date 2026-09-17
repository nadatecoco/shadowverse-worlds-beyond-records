#!/usr/bin/env python3
"""Run simulator tests, with optional development signing for system App Shortcuts."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator', required=True, help='Simulator UDID from xcrun simctl list devices')
parser.add_argument('--identity', help='Existing Apple Development signing identity name or SHA-1')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
if not any(d['udid'] == args.simulator for group in devices['devices'].values() for d in group):
    parser.error('The destination must be an available simulator, not a physical device.')
derived = tempfile.mkdtemp(prefix='ShadowRecordTests-')
base = ['xcodebuild', '-project', str(root / 'シャドバ戦績研究.xcodeproj'), '-scheme', 'ShadowRecord',
        '-destination', 'platform=iOS Simulator,id=' + args.simulator, '-derivedDataPath', derived]
subprocess.run(base + ['CODE_SIGNING_ALLOWED=NO', 'build-for-testing'], check=True)
if args.identity:
    app = Path(derived) / 'Build/Products/Debug-iphonesimulator/ShadowRecord.app'
    for bundle in [*sorted((app / 'PlugIns').glob('*.appex')), app]:
        subprocess.run(['codesign', '--force', '--sign', args.identity,
                        '--preserve-metadata=identifier,entitlements,flags,runtime', str(bundle)], check=True)
subprocess.run(base + ['test-without-building'], check=True)
print('Results: ' + derived + '/Logs/Test')
