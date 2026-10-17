#!/usr/bin/env python3
"""Prove that configured upstream schema additions, renames and contract drift fail."""
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).with_name('schema-drift.py')


class SchemaDriftTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('schema_drift', PATH)
        self.gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.gate)
        self.option = {'name': 'audio', 'module': 'main', 'type': 1, 'default': True, 'choices': []}
        self.policy = {'options': [dict(self.option, disposition='mapped')], 'absent': {}}

    def test_unchanged_configured_schema_passes(self):
        self.assertEqual(self.gate.validate([self.option], self.policy, {'audio'}), [])

    def test_upstream_additions_and_renames_require_mapping_or_explicit_hidden_policy(self):
        for change in ([self.option, dict(self.option, name='new-option')], [dict(self.option, name='renamed-audio')]):
            self.assertTrue(self.gate.validate(change, self.policy, {'audio'}))

    def test_type_default_and_choices_are_contracts(self):
        for key, value in [('type', 7), ('default', False), ('choices', [False, True])]:
            self.assertTrue(self.gate.validate([dict(self.option, **{key: value})], self.policy, {'audio'}), key)

    def test_hidden_requires_a_specific_reason_and_cannot_silently_hide_new_mapping(self):
        hidden = {'options': [dict(self.option, disposition='hidden', reason='Advanced-only engine option')], 'absent': {}}
        self.assertEqual(self.gate.validate([self.option], hidden, set()), [])
        self.assertTrue(self.gate.validate([self.option], hidden, {'audio'}))
        del hidden['options'][0]['reason']
        self.assertTrue(self.gate.validate([self.option], hidden, set()))

    def test_mapped_option_disappearing_requires_explicit_configured_absence(self):
        self.assertTrue(self.gate.validate([], self.policy, {'audio'}))
        self.assertEqual(self.gate.validate([], {'options': [], 'absent': {'audio': 'Not built for this configuration'}}, {'audio'}), [])


if __name__ == '__main__':
    unittest.main()
