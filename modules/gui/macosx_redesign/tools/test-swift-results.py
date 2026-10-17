#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest


class SwiftResultsTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).with_name('run-swift-tests.py')
        spec = importlib.util.spec_from_file_location('swift_results', path)
        self.runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.runner)
        self.expected = {'MXRTests.Case/testA', 'MXRTests.Case/testB'}

    def report(self, body):
        return '<testsuites><testsuite>' + body + '</testsuite></testsuites>'

    def test_requires_every_discovered_test_and_no_skips(self):
        case = '<testcase classname="MXRTests.Case" name="testA"/>'
        other = '<testcase classname="MXRTests.Case" name="testB"/>'
        self.assertEqual(self.runner.validate_report(self.report(case + other), self.expected), 2)
        for body in (case, case + '<testcase classname="MXRTests.Case" name="testB"><skipped/></testcase>', case + case):
            with self.assertRaises(ValueError):
                self.runner.validate_report(self.report(body), self.expected)

    def test_console_requires_all_discovered_test_results(self):
        passed = "Test Case '-[MXRTests.Case testA]' passed (0.001 seconds).\n"
        other = "Test Case '-[MXRTests.Case testB]' passed (0.001 seconds).\n"
        self.assertEqual(self.runner.validate_output(passed + other, self.expected), 2)
        for output in (passed, passed + passed, passed + other.replace('passed', 'skipped'), passed + other.replace('passed', 'failed')):
            with self.assertRaises(ValueError):
                self.runner.validate_output(output, self.expected)

    def test_rejects_test_failures_even_with_a_complete_report(self):
        with self.assertRaises(ValueError):
            self.runner.validate_report(self.report('<testcase classname="MXRTests.Case" name="testA"><failure/></testcase>'), {'MXRTests.Case/testA'})


if __name__ == '__main__':
    unittest.main()
