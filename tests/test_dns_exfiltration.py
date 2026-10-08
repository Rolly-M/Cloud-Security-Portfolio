"""
Unit tests for dns_exfiltration.py

All socket calls are mocked — no real DNS queries are made.
"""

import socket
from unittest.mock import patch, call, MagicMock
import pytest
import dns_exfiltration as dns_sim


# ---------------------------------------------------------------------------
# simulate_dns_query
# ---------------------------------------------------------------------------

class TestSimulateDNSQuery:
    def test_successful_resolution_returns_true(self):
        with patch("socket.gethostbyname", return_value="1.2.3.4"):
            result = dns_sim.simulate_dns_query("example.com")
        assert result is True

    def test_gaierror_still_returns_true(self):
        with patch("socket.gethostbyname", side_effect=socket.gaierror("NXDOMAIN")):
            result = dns_sim.simulate_dns_query("nonexistent.example.com")
        assert result is True

    def test_timeout_still_returns_true(self):
        with patch("socket.gethostbyname", side_effect=socket.timeout()):
            result = dns_sim.simulate_dns_query("slow.example.com")
        assert result is True

    def test_generic_exception_returns_false(self):
        with patch("socket.gethostbyname", side_effect=OSError("unexpected error")):
            result = dns_sim.simulate_dns_query("bad.example.com")
        assert result is False

    def test_verbose_mode_does_not_raise(self):
        with patch("socket.gethostbyname", return_value="1.2.3.4"):
            result = dns_sim.simulate_dns_query("example.com", verbose=True)
        assert result is True

    def test_verbose_gaierror_does_not_raise(self):
        with patch("socket.gethostbyname", side_effect=socket.gaierror("fail")):
            result = dns_sim.simulate_dns_query("x.com", verbose=True)
        assert result is True


# ---------------------------------------------------------------------------
# simulate_data_exfiltration — chunking and subdomain format
# ---------------------------------------------------------------------------

class TestSimulateDataExfiltration:
    def test_short_data_produces_one_query(self):
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_data_exfiltration("hello", "example.com")
        assert mock_q.call_count == 1

    def test_data_longer_than_chunk_produces_multiple_queries(self):
        # chunk_size = 30; 65-char string → 3 chunks
        data = "a" * 65
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_data_exfiltration(data, "example.com")
        assert mock_q.call_count == 3

    def test_exactly_two_chunks(self):
        data = "x" * 60  # exactly 2 × 30
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_data_exfiltration(data, "example.com")
        assert mock_q.call_count == 2

    def test_subdomain_format_contains_base_domain(self):
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_data_exfiltration("test data", "target.org")
        called_domain = mock_q.call_args[0][0]
        assert "target.org" in called_domain

    def test_spaces_replaced_with_dashes_in_subdomain(self):
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_data_exfiltration("hello world", "example.com")
        called_domain = mock_q.call_args[0][0]
        assert " " not in called_domain
        assert "hello-world" in called_domain

    def test_subdomain_is_lowercased(self):
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_data_exfiltration("UPPERCASE", "example.com")
        called_domain = mock_q.call_args[0][0]
        assert "UPPERCASE" not in called_domain
        assert "uppercase" in called_domain

    def test_subdomain_includes_chunk_index(self):
        data = "a" * 65  # 3 chunks → indices 0, 1, 2
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_data_exfiltration(data, "example.com")
        calls = [c[0][0] for c in mock_q.call_args_list]
        assert any(".0.exfil." in d for d in calls)
        assert any(".1.exfil." in d for d in calls)
        assert any(".2.exfil." in d for d in calls)


# ---------------------------------------------------------------------------
# simulate_crypto_mining
# ---------------------------------------------------------------------------

class TestSimulateCryptoMining:
    def test_queries_all_crypto_domains(self):
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_crypto_mining()
        assert mock_q.call_count == len(dns_sim.CRYPTO_MINING_DOMAINS)

    def test_each_domain_queried_exactly_once(self):
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_crypto_mining()
        queried = [c[0][0] for c in mock_q.call_args_list]
        for domain in dns_sim.CRYPTO_MINING_DOMAINS:
            assert domain in queried


# ---------------------------------------------------------------------------
# simulate_c2_communication
# ---------------------------------------------------------------------------

class TestSimulateC2Communication:
    def test_sends_five_beacons(self):
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_c2_communication()
        assert mock_q.call_count == 5

    def test_beacon_domains_match_expected_pattern(self):
        with patch("dns_exfiltration.simulate_dns_query") as mock_q, \
             patch("time.sleep"):
            dns_sim.simulate_c2_communication()
        for c in mock_q.call_args_list:
            domain = c[0][0]
            assert "c2server.example.com" in domain
            assert "beacon-" in domain
