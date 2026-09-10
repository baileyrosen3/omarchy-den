import importlib.util
import io
import json
import subprocess
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('bridge', Path(__file__).parents[1] / 'collie.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class HelperTests(unittest.TestCase):
    def test_missing_apps_have_install_guidance(self):
        with patch.object(bridge.shutil, 'which', return_value=None):
            result = bridge.prerequisites()
        self.assertFalse(result['ok'])
        self.assertIn('collie', result['missing'])
        self.assertIn('herdr', result['missing'])
        self.assertIn('https://herdr.dev', result['error'])
        self.assertIn('https://github.com/AltanS/collie', result['error'])

    def test_preflight_success(self):
        with patch.object(bridge.shutil, 'which', side_effect=lambda name: '/usr/bin/' + name):
            self.assertTrue(bridge.prerequisites()['ok'])

    def test_missing_apps_block_snapshot(self):
        with patch.object(bridge.shutil, 'which', return_value=None), patch.object(bridge, 'bridge_request') as request:
            self.assertFalse(self.run_action('snapshot')['ok'])
        request.assert_not_called()

    def run_action(self, *args):
        output = io.StringIO()
        with patch('sys.argv', ['collie.py', *args]), redirect_stdout(output):
            bridge.main()
        return json.loads(output.getvalue())

    def test_exact_tab_and_session_arguments(self):
        with patch.object(bridge.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            self.assertTrue(self.run_action('focus-tab', 'http://localhost:8787', 'side project', 'w1:t2')['ok'])
        self.assertEqual(run.call_args.args[0], ['herdr', '--session', 'side project', 'tab', 'focus', 'w1:t2'])

    def test_focus_timeout_is_visible_json_error(self):
        with patch.object(bridge.subprocess, 'run', side_effect=subprocess.TimeoutExpired('herdr', 2.5)):
            self.assertFalse(self.run_action('focus-workspace', '', '', 'w1')['ok'])

    def test_failed_pane_focus_retains_reason(self):
        with patch.object(bridge, 'bridge_request', return_value=({'ok':False, 'error':'Pane closed'}, None)):
            result = self.run_action('focus-pane', '', '', 'w1:p2')
        self.assertEqual(result['error'], 'Pane closed')

    def test_malformed_focus_response(self):
        with patch.object(bridge, 'bridge_request', return_value=([], None)):
            self.assertFalse(self.run_action('focus-pane', '', '', 'w1:p2')['ok'])

    def test_invalid_bridge_url(self):
        with patch.object(bridge, 'prerequisites', return_value={'ok': True}):
            result = self.run_action('snapshot', 'file:///tmp/anything')
        self.assertFalse(result['ok'])
        self.assertIn('http(s)', result['error'])


if __name__ == '__main__':
    unittest.main()
