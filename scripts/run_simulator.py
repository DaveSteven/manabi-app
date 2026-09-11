#!/usr/bin/env python3
"""Build/run Manabi with an installed iOS simulator, restoring any temporary SDK match override."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)


def output(*args):
    return run(*args, capture_output=True, text=True).stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', help='Existing simulator UUID; defaults to newest available iPhone')
    parser.add_argument('--test', action='store_true')
    parser.add_argument('--only-testing', help='Run one test target/class/method (requires --test)')
    args = parser.parse_args()
    if args.only_testing and not args.test:
        parser.error('--only-testing requires --test')
    inventory = json.loads(output('xcrun', 'simctl', 'list', '-j'))
    runtimes = sorted((r for r in inventory['runtimes'] if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS')),
                      key=lambda r: tuple(map(int, r['version'].split('.'))), reverse=True)
    candidates = [(r, d) for r in runtimes for d in inventory['devices'].get(r['identifier'], [])
                  if d.get('isAvailable') and ('iPhone' in d['name'] or args.device == d['udid'])]
    if args.device:
        candidates = [(r, d) for r, d in candidates if d['udid'] == args.device]
    if not candidates:
        raise SystemExit('No available iPhone simulator. Install an iOS runtime in Xcode Settings → Components.')
    runtime, device = candidates[0]
    mappings = json.loads(output('xcrun', 'simctl', 'runtime', 'match', 'list', '-j'))
    sdk, matching = next((k, v) for k, v in mappings.items() if k.startswith('iphoneos'))
    available_builds = {r['buildversion'] for r in runtimes}
    changed = matching['chosenRuntimeBuild'] not in available_builds
    prior = matching.get('userOverriddenBuild') or '--default'
    try:
        if changed:
            print(f'Using installed iOS {runtime["version"]} for asset compilation; SDK matching will be restored.', flush=True)
            run('xcrun', 'simctl', 'runtime', 'match', 'set', sdk, runtime['buildversion'])
        command = ['xcodebuild', '-project', 'Manabi.xcodeproj', '-scheme', 'Manabi',
                   '-destination', f'platform=iOS Simulator,id={device["udid"]}',
                   '-derivedDataPath', 'build', 'CODE_SIGN_IDENTITY=-', 'test' if args.test else 'build']
        if args.only_testing:
            command.append(f'-only-testing:{args.only_testing}')
        run(*command)
    finally:
        if changed:
            run('xcrun', 'simctl', 'runtime', 'match', 'set', sdk, prior)
    if not args.test:
        if device['state'] != 'Booted':
            run('xcrun', 'simctl', 'boot', device['udid'])
        run('xcrun', 'simctl', 'bootstatus', device['udid'], '-b')
        run('xcrun', 'simctl', 'install', device['udid'], str(ROOT/'build/Build/Products/Debug-iphonesimulator/Manabi.app'))
        run('xcrun', 'simctl', 'launch', device['udid'], 'app.manabi.ios')
        run('open', '-a', 'Simulator')


if __name__ == '__main__':
    main()
