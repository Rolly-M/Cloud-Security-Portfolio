"""
WAF rule logic tests — imported from 4 - AWS_WAF/tests/test_waf_rules.py
into the main test suite so they are picked up by the root pytest run.
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "4 - AWS_WAF", "tests"))

from test_waf_rules import (  # noqa: F401  (re-export for pytest discovery)
    TestWAFRuleLogic,
    is_sqli_payload,
    is_xss_payload,
    is_known_bad_input,
)
