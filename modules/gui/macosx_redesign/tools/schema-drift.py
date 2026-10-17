#!/usr/bin/env python3
"""Compare the actual configured module bank with reviewed D013 map/hidden policy.

Run native-tests.py --suite schema --engine-build BUILD. No automatic baseline
update is provided: additions, removals, type/default/range/choice changes and
catalog disposition changes must be reviewed in schema-policy.json.
"""
import argparse
import json
from pathlib import Path
import re

PACKAGE = Path(__file__).resolve().parent.parent
POLICY = PACKAGE / 'module/tests/schema-policy.json'
CATALOG = PACKAGE / 'Sources/MXRCore/Resources/settings-map.json5'


def mapped_options(path=CATALOG):
    # The checked-in JSON5 catalog uses literal option fields, including composites
    # and visibility dependencies. Strip line comments only outside strings.
    text = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',
                  lambda match: '' if match.group().startswith('//') else match.group(), path.read_text())
    return {name for name in re.findall(r'\boption\s*:\s*"([^"]+)"', text)
            if not name.startswith('macosx-redesign-')}


def validate(actual, policy, mapped):
    def indexed(options):
        result = {}
        for option in options:
            key = (option['name'], option['module'])
            if key in result:
                raise ValueError(f'duplicate schema key: {key}')
            result[key] = option
        return result
    live, expected = indexed(actual), indexed(policy['options'])
    errors = []
    for key in sorted(live.keys() - expected.keys()):
        errors.append(f'new upstream option needs mapped/hidden review: {key}')
    for key in sorted(expected.keys() - live.keys()):
        errors.append(f'upstream option removed or renamed: {key}')
    for key in sorted(live.keys() & expected.keys()):
        contract = {k: v for k, v in expected[key].items() if k not in ('disposition', 'reason')}
        if live[key] != contract:
            errors.append(f'type/default/range/choices drift: {key}')
        disposition = expected[key].get('disposition')
        if disposition == 'hidden':
            if not expected[key].get('reason', '').strip():
                errors.append(f'hidden option lacks reason: {key}')
            if key[0] in mapped:
                errors.append(f'catalog now maps hidden option: {key}')
        elif disposition == 'mapped':
            if key[0] not in mapped:
                errors.append(f'mapped option removed from catalog: {key}')
        else:
            errors.append(f'unknown disposition: {key}')
    names = {key[0] for key in live}
    absent = policy.get('absent', {})
    for name in sorted(mapped - names):
        if not absent.get(name, '').strip():
            errors.append(f'catalog option absent from configured bank without policy: {name}')
    for name in sorted(absent):
        if name in names or name not in mapped:
            errors.append(f'obsolete configured-absence policy: {name}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('schema', type=Path)
    parser.add_argument('--policy', type=Path, default=POLICY)
    parser.add_argument('--catalog', type=Path, default=CATALOG)
    args = parser.parse_args()
    errors = validate(json.loads(args.schema.read_text()), json.loads(args.policy.read_text()), mapped_options(args.catalog))
    if errors:
        parser.exit(1, '\n'.join(errors) + '\n')
    print('PASS: configured upstream schema matches mapped/explicit-hidden policy')


if __name__ == '__main__':
    main()
