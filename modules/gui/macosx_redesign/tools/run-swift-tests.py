#!/usr/bin/env python3
"""Run SwiftPM tests offscreen and require every discovered XCTest in the report."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


def validate_report(xml, expected):
    cases = ET.fromstring(xml).findall('.//testcase')
    actual = [case.attrib['classname'] + '/' + case.attrib['name'] for case in cases]
    if not expected or set(actual) != expected or len(actual) != len(expected):
        raise ValueError(f'incomplete XCTest run: expected {len(expected)}, executed {len(actual)}; '
                         f'missing={sorted(expected - set(actual))}, unexpected={sorted(set(actual) - expected)}')
    if any(case.find('skipped') is not None or case.find('failure') is not None or case.find('error') is not None for case in cases):
        raise ValueError('XCTest report contains skipped/failed tests')
    return len(actual)


def validate_output(text, expected):
    # Xcode 27's swiftbuild backend accepts --xunit-output but emits no XML for
    # XCTest. Its per-case terminal records still provide exact identities.
    results = re.findall(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped)", text)
    actual = [group + '/' + name for group, name, _ in results]
    if not expected or set(actual) != expected or len(actual) != len(expected):
        raise ValueError(f'incomplete XCTest run: expected {len(expected)}, executed {len(actual)}; '
                         f'missing={sorted(expected - set(actual))}, unexpected={sorted(set(actual) - expected)}')
    if any(status != 'passed' for _, _, status in results):
        raise ValueError('XCTest output contains skipped/failed tests')
    return len(actual)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('scratch', type=Path)
    parser.add_argument('--filter', help='Focused XCTest regular expression; default runs every discovered case')
    args = parser.parse_args()
    scratch = args.scratch.resolve()
    for name in ('cache', 'config', 'security', 'module-cache'):
        (scratch / name).mkdir(parents=True, exist_ok=True)
    env = {key: value for key, value in os.environ.items() if key not in
           ('CC', 'CXX', 'OBJC', 'OBJCXX', 'CFLAGS', 'CXXFLAGS', 'OBJCFLAGS', 'OBJCXXFLAGS',
            'CPPFLAGS', 'LDFLAGS', 'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET')}
    env.update(CLANG_MODULE_CACHE_PATH=str(scratch / 'module-cache'),
               SWIFTPM_MODULECACHE_OVERRIDE=str(scratch / 'module-cache'))
    command = ['xcrun', 'swift', 'test', '--package-path', str(args.package.resolve()), '--scratch-path', str(scratch),
               '--cache-path', str(scratch / 'cache'), '--config-path', str(scratch / 'config'),
               '--security-path', str(scratch / 'security'), '--jobs', '2', '--disable-sandbox']
    discovery = subprocess.run(command + ['--list-tests'], env=env, stdout=subprocess.PIPE, text=True, check=True)
    (scratch / 'discovered-tests.txt').write_text(discovery.stdout)
    expected = {line.strip() for line in discovery.stdout.splitlines()
                if re.fullmatch(r'[\w.]+/test\S+', line.strip())}
    if args.filter:
        expected = {name for name in expected if re.search(args.filter, name)}
        command += ['--filter', args.filter]
    report = scratch / 'results.xml'
    # Remove only the previous report owned by this runner, so process termination
    # cannot accidentally validate a successful report from a previous run.
    report.unlink(missing_ok=True)
    test_command = command + ['--skip-build', '--xunit-output', str(report)]
    output = []
    with (scratch / 'results.log').open('w') as log:
        with subprocess.Popen(test_command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, errors='replace') as process:
            for line in process.stdout:
                print(line, end='', flush=True)
                log.write(line)
                output.append(line)
            if process.wait():
                raise subprocess.CalledProcessError(process.returncode, test_command)
    count = (validate_report(report.read_text(), expected) if report.exists()
             else validate_output(''.join(output), expected))
    print(f'PASS: all {count} discovered XCTest cases executed, none skipped')


if __name__ == '__main__':
    main()
