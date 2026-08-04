"""Identifier validation and manifest escaping.

Share, listing and role names are interpolated straight into DDL, and listing titles and
descriptions are interpolated into a YAML manifest inside a dollar-quoted SQL block.
Both are user-supplied, so both are guarded.
"""
import pytest

from macro_harness import CompilerError


class TestValidateIdentifier:
    @pytest.mark.parametrize("name", ["partner_share", "_leading", "with$dollar", "a1", "A_B_C"])
    def test_accepts_plain_identifiers(self, pkg, name):
        assert pkg.validate_identifier(name) == name

    @pytest.mark.parametrize("name", [
        "x TO SHARE y; DROP SHARE z",
        'a" OR "1',
        "has space",
        "has-hyphen",
        "1leading_digit",
        "",
        "trailing;",
    ])
    def test_rejects_anything_else(self, pkg, name):
        with pytest.raises(CompilerError):
            pkg.validate_identifier(name)

    def test_error_names_the_kind_and_value(self, pkg):
        with pytest.raises(CompilerError) as excinfo:
            pkg.validate_identifier("bad name", "share name")
        assert "share name" in str(excinfo.value)
        assert "bad name" in str(excinfo.value)


class TestValidateAccount:
    @pytest.mark.parametrize("account", ["ABC12345", "MYORG.MY_ACCOUNT", "my-org.acct1", "AB1"])
    def test_accepts_account_identifier_forms(self, pkg, account):
        assert pkg.validate_account(account) == account

    @pytest.mark.parametrize("account", [
        "a, b REMOVE ACCOUNTS = c",
        "acct'; DROP SHARE x; --",
        "has space",
        "",
        ".leading_dot",
    ])
    def test_rejects_anything_else(self, pkg, account):
        with pytest.raises(CompilerError):
            pkg.validate_account(account)


class TestEscapeYamlValue:
    def test_escapes_double_quotes(self, pkg):
        assert pkg.escape_yaml_value('My "Great" Data') == 'My \\"Great\\" Data'

    def test_escapes_backslashes_before_quotes(self, pkg):
        assert pkg.escape_yaml_value("a\\b") == "a\\\\b"
        assert pkg.escape_yaml_value('a\\"b') == 'a\\\\\\"b'

    @pytest.mark.parametrize("raw,expected", [
        ("a\nb", "a\\nb"),
        ("a\r\nb", "a\\nb"),
        ("a\rb", "a\\nb"),
        ("a\tb", "a\\tb"),
    ])
    def test_folds_whitespace_onto_one_line(self, pkg, raw, expected):
        assert pkg.escape_yaml_value(raw) == expected

    def test_rejects_dollar_quote_terminator(self, pkg):
        # '$$' would close the enclosing block and let the rest execute as SQL.
        with pytest.raises(CompilerError):
            pkg.escape_yaml_value("x $$; DROP SHARE y; SELECT $$")

    def test_error_names_the_field(self, pkg):
        with pytest.raises(CompilerError) as excinfo:
            pkg.escape_yaml_value("$$", "description")
        assert "description" in str(excinfo.value)

    def test_leaves_ordinary_text_alone(self, pkg):
        assert pkg.escape_yaml_value("Internal Analytics Data") == "Internal Analytics Data"


class TestIdentifierMatches:
    @pytest.mark.parametrize("candidate", [
        "MYORG.MYACCT.PARTNER_SHARE",
        "PARTNER_SHARE",
        "partner_share",
        '"PARTNER_SHARE"',
    ])
    def test_matches_on_the_final_segment_case_insensitively(self, pkg, candidate):
        assert pkg.identifier_matches(candidate, "partner_share") is True

    @pytest.mark.parametrize("candidate", ["X.OTHER_SHARE", "partner_share_2", "", "partner"])
    def test_rejects_different_names(self, pkg, candidate):
        assert pkg.identifier_matches(candidate, "partner_share") is False

    def test_empty_never_matches_empty(self, pkg):
        assert pkg.identifier_matches("", "") is False
