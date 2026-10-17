#!/usr/bin/env python3
"""Prove that a missed native-harness deadline names the slow step.

Compiles a tiny harness against module/bridge/tests/MXRNativeTestDiagnostics.h
(no VLC needed): a worker thread stays inside a named function after logging
"removing keystore memory", exactly the silent stretch the audio-preferences
shutdown check used to fail on with nothing but "FAIL: native engine shuts down
cleanly". The failure output must carry the running phase, the last engine log
line and a call graph that shows the stuck function.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PACKAGE = Path(__file__).resolve().parent.parent
HEADER_DIR = PACKAGE / 'module/bridge/tests'

HARNESS = r'''
#import <Foundation/Foundation.h>
#import "MXRNativeTestDiagnostics.h"
__attribute__((noinline)) static void MXRFixtureStuckInModuleEndBank(void) { sleep(30); }
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL hang = argc > 1 && !strcmp(argv[1], "--hang");
        __block BOOL stopped = NO;
        MXRNativeDiagnosticsPhase("shutdown requested");
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            MXRNativeDiagnosticsPhase("libvlc_InternalCleanup");
            MXRNativeDiagnosticsNoteLog("removing keystore memory");
            if (hang) MXRFixtureStuckInModuleEndBank();
            dispatch_async(dispatch_get_main_queue(), ^{ stopped = YES; });
        });
        if (!MXRNativeDiagnosticsPumpUntil(^BOOL { return stopped; }, 1, "native engine shuts down cleanly")) {
            fprintf(stderr, "FAIL: native engine shuts down cleanly\n");
            return 1;
        }
        return 0;
    }
}
'''


class NativeDeadlineDiagnosticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = tempfile.TemporaryDirectory(prefix='mxr-native-diagnostics-')
        root = Path(cls.root.name)
        (root / 'harness.m').write_text(HARNESS)
        cls.binary = root / 'harness'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-g', '-O0', '-I' + str(HEADER_DIR),
                        str(root / 'harness.m'), '-framework', 'Foundation', '-o', str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.root.cleanup()

    def run_harness(self, *arguments):
        evidence = Path(tempfile.mkdtemp(dir=self.root.name))
        result = subprocess.run([str(self.binary), *arguments], capture_output=True, text=True, timeout=60,
                                env={**os.environ, 'MXR_NATIVE_EVIDENCE_DIR': str(evidence)})
        return result, evidence

    def test_missed_deadline_reports_phase_last_log_and_stuck_frame(self):
        result, evidence = self.run_harness('--hang')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('DEADLINE MISSED', result.stderr)
        self.assertIn('current phase: libvlc_InternalCleanup (running for', result.stderr)
        self.assertIn('last engine log: "removing keystore memory"', result.stderr)
        # The call graph shows the step that is still running, on its own thread.
        self.assertIn('MXRFixtureStuckInModuleEndBank', result.stderr)
        samples = list(evidence.glob('deadline-sample-*.txt'))
        self.assertEqual(len(samples), 1, 'call graph is kept in the evidence directory')
        self.assertIn('MXRFixtureStuckInModuleEndBank', samples[0].read_text())

    def test_met_deadline_reports_duration_without_sampling(self):
        result, evidence = self.run_harness()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stderr, r'done in \d+ ms: native engine shuts down cleanly')
        self.assertIn('phase: libvlc_InternalCleanup', result.stderr)
        self.assertNotIn('DEADLINE MISSED', result.stderr)
        self.assertEqual(list(evidence.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
