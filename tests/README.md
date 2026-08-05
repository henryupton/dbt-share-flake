# Unit Tests

Tests for the package's macros. These need no Snowflake account and no dbt install: the
macros are compiled with plain Jinja2 against a stubbed dbt context, so they run in about
a second and are safe to run in CI.

For tests that need a real warehouse (whether Snowflake actually accepts the generated
DDL, how `SHOW LISTINGS` behaves for organization listings), see `../integration_tests`.

## Running

```bash
pip install -r tests/requirements.txt
pytest tests
```

CI runs exactly this on every pull request and push to `main`, against Python 3.9 and
3.12, in `.github/workflows/test.yml`. No secrets required.

## Layout

| File | Covers |
| --- | --- |
| `macro_harness.py` | The Jinja/dbt stub. Not a test file. |
| `conftest.py` | Fixtures: `ctx`, `pkg`, `drifted_share`. |
| `test_validation.py` | Identifier and account validation, YAML escaping. |
| `test_existence_checks.py` | `share_exists` / `listing_exists` against `SHOW ... LIKE` wildcards. |
| `test_grant_planning.py` | Desired grants, provenance, ordering, plan construction. |
| `test_safety_guards.py` | Dry run, revoke guards, target gating, run-results awareness. |
| `test_share_configuration.py` | Account diffing and `ALTER SHARE` generation. |
| `test_listings.py` | Manifest building and listing orchestration. |
| `test_entrypoint.py` | End-to-end wiring of the `on-run-end` hook. |

## Writing a test

Arrange the stub context, then call a macro. The package reads the context live, so
ordering between `ctx` mutations and `pkg` calls does not matter.

```python
def test_something(ctx, pkg):
    ctx.nodes = [make_node("model.p.orders", "orders", {"shares": ["partner_share"]})]
    ctx.vars["snowflake_shares"] = {"partner_share": {}}
    ctx.on_query(r"SHOW SHARES", [{"name": "PARTNER_SHARE", "kind": "OUTBOUND"}])

    pkg.process_shares()

    assert "GRANT SELECT ON TABLE analytics.public.orders" in ctx.sql
```

`ctx.on_query` answers the first matching pattern, so register specific patterns before
broad ones. Useful assertion helpers: `ctx.sql`, `ctx.ddl` (only mutating statements),
`ctx.log_text`, `ctx.warnings`, `ctx.statements_matching(pattern)`.

## Caveat

The harness reproduces dbt's macro environment, not Snowflake. A test passing here means
the macro's logic and the SQL it generates are correct as intended; it says nothing about
whether Snowflake accepts that SQL. When a change depends on Snowflake's own behaviour,
check the docs and add an integration test.
