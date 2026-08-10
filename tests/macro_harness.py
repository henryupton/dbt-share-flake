"""Runs this package's macros under plain Jinja2 with a stubbed dbt context.

These tests exercise the macros directly rather than through dbt, so they need no
Snowflake account and no dbt install. That means reproducing the parts of dbt's macro
environment the package actually relies on:

  - the `return()` protocol, which dbt implements by raising an exception that its macro
    dispatcher catches (so `{{ return(x) }}` aborts the rest of the macro)
  - the `dbt_share_flake` namespace, through which every macro calls its siblings
  - `var`, `log`, `run_query`, `graph`, `flags`, `target`, `results`, `api.Relation`,
    `exceptions` and `modules`
  - agate tables as `run_query` results, since some macros use `.columns[0].values()`

The trade-off is that this checks the macros' logic and generated SQL, not whether
Snowflake accepts that SQL. Anything version-specific about Snowflake's own behaviour
belongs in integration_tests/ instead.
"""
import glob
import os
import re
from pathlib import Path
from types import SimpleNamespace

import agate
import jinja2

MACRO_ROOT = Path(__file__).resolve().parent.parent / "macros"

SUCCESSFUL = "success"

# The privilege sets the package checks for, so tests can stub a fully privileged role
# without repeating them.
ALL_SHARE_PRIVILEGES = ["CREATE SHARE", "IMPORT SHARE", "MANAGE GRANTS", "MANAGE SHARE TARGET"]
ALL_LISTING_PRIVILEGES = ["CREATE LISTING", "CREATE SHARE"]


class MacroReturn(Exception):
    """Mirrors dbt's `return()`, which unwinds the macro rather than yielding a value."""

    def __init__(self, value):
        self.value = value
        super().__init__(value)


class CompilerError(Exception):
    """Stands in for exceptions.raise_compiler_error."""


class Package:
    """Stands in for the `dbt_share_flake` namespace. Populated by build_package."""


def agate_table(rows):
    """Build an agate.Table the way dbt's run_query returns one."""
    if not rows:
        return agate.Table([], ["placeholder"], [agate.Text()])
    columns = list(rows[0].keys())
    data = [[row.get(column) for column in columns] for row in rows]
    return agate.Table(data, columns, [agate.Text() for _ in columns])



class _FlagsProxy:
    """Reads through to the live stub so tests can set flags after building."""

    def __init__(self, ctx):
        self._ctx = ctx

    def __getattr__(self, name):
        # Deliberately propagates AttributeError: the macros rely on Jinja's `attr`
        # filter returning undefined for flags absent on the running dbt version.
        return getattr(self._ctx.flags, name)


class _TargetProxy:
    def __init__(self, ctx):
        self._ctx = ctx

    def __getattr__(self, name):
        return getattr(self._ctx.target, name)


class _GraphProxy:
    def __init__(self, ctx):
        self._ctx = ctx

    @property
    def nodes(self):
        return {node.unique_id: node for node in self._ctx.nodes}


class _ResultsProxy:
    def __init__(self, ctx):
        self._ctx = ctx

    def __iter__(self):
        return iter(self._ctx.results)

    def __bool__(self):
        return bool(self._ctx.results)

    def __len__(self):
        return len(self._ctx.results)


class StubContext:
    """The mutable dbt context a test arranges before acting.

    Everything here is read live by the compiled macros, so a test can build the package
    once and still change vars, flags, graph nodes and run results afterwards.
    """

    def __init__(self):
        self.vars = {}
        self.flags = SimpleNamespace(WHICH="run")
        self.target = SimpleNamespace(name="prod")
        self.nodes = []
        self.results = []
        self.executed_sql = []
        self.logs = []
        self.warnings = []
        # Mirrors a project setting `quoting: {database: true, schema: true,
        # identifier: true}`, which makes dbt render relations quoted.
        self.quote_identifiers = False
        self._query_handlers = []

    # -- arrangement ------------------------------------------------------

    def on_query(self, pattern, rows):
        """Answer any query matching `pattern` with `rows`. First match wins, so
        register more specific patterns before broader ones."""
        self._query_handlers.append((pattern, rows))
        return self

    def grant_role_privileges(self, privileges=()):
        """Stub the two queries check_required_privileges issues."""
        self.on_query(r"CURRENT_ROLE", [{"current_role": "DBT_ROLE"}])
        self.on_query(r"SHOW GRANTS TO ROLE", [{"privilege": p} for p in privileges])
        return self

    # -- dbt context callables -------------------------------------------

    def var(self, name, default=None):
        return self.vars.get(name, default)

    def log(self, message, info=False):
        self.logs.append(str(message))
        return ""

    def run_query(self, sql):
        statement = str(sql).strip()
        self.executed_sql.append(statement)
        for pattern, rows in self._query_handlers:
            if re.search(pattern, statement, re.IGNORECASE | re.DOTALL):
                return agate_table(rows)
        return agate_table([])

    def warn(self, message):
        self.warnings.append(str(message))
        return ""

    def raise_compiler_error(self, message):
        raise CompilerError(str(message))

    # -- assertion helpers -----------------------------------------------

    @property
    def ddl(self):
        """Only the statements that change something."""
        return [s for s in self.executed_sql if re.match(r"(GRANT|REVOKE|CREATE|ALTER)", s)]

    @property
    def sql(self):
        return " ".join(self.executed_sql)

    @property
    def log_text(self):
        return "\n".join(self.logs)

    def statements_matching(self, pattern):
        return [s for s in self.executed_sql if re.search(pattern, s, re.IGNORECASE)]


def build_package(ctx, with_results=True):
    """Compile every macro in the package and expose them as a namespace.

    with_results=False omits `results` entirely, reproducing a run-operation where the
    on-run-end context variable does not exist.
    """
    sources = []
    for path in sorted(glob.glob(os.path.join(str(MACRO_ROOT), "**", "*.sql"), recursive=True)):
        with open(path) as handle:
            sources.append(handle.read())

    if not sources:
        raise RuntimeError(f"no macros found under {MACRO_ROOT}")

    # Deliberately a stock Jinja2 environment: registering filters here that real dbt
    # does not provide lets a macro pass the suite and then fail at render time.
    env = jinja2.Environment(extensions=["jinja2.ext.do"])

    package = Package()

    def relation_create(database=None, schema=None, identifier=None):
        parts = (database, schema, identifier)

        def render():
            if ctx.quote_identifiers:
                return ".".join(f'"{part}"' for part in parts)
            return ".".join(parts)

        return SimpleNamespace(render=render)

    def do_return(value=""):
        raise MacroReturn(value)

    context = {
        "dbt_share_flake": package,
        "execute": True,
        "flags": _FlagsProxy(ctx),
        "target": _TargetProxy(ctx),
        "graph": _GraphProxy(ctx),
        "results": _ResultsProxy(ctx),
        "var": ctx.var,
        "log": ctx.log,
        "run_query": ctx.run_query,
        "api": SimpleNamespace(Relation=SimpleNamespace(create=relation_create)),
        "exceptions": SimpleNamespace(warn=ctx.warn, raise_compiler_error=ctx.raise_compiler_error),
        "modules": SimpleNamespace(re=re),
        "return": do_return,
    }

    if not with_results:
        del context["results"]

    module = env.from_string("\n".join(sources)).make_module(context)

    def wrap(macro):
        def call(*args, **kwargs):
            try:
                return macro(*args, **kwargs)
            except MacroReturn as returned:
                return returned.value

        return call

    for name in dir(module):
        attribute = getattr(module, name)
        if isinstance(attribute, jinja2.runtime.Macro):
            setattr(package, name, wrap(attribute))

    return package


def make_node(unique_id, name, meta, materialized="table", database="analytics",
              schema="public", resource_type="model", alias=None):
    return SimpleNamespace(
        unique_id=unique_id,
        name=name,
        alias=alias or name,
        meta=meta,
        database=database,
        schema=schema,
        resource_type=resource_type,
        config=SimpleNamespace(materialized=materialized),
    )


def make_result(unique_id, status=SUCCESSFUL):
    return SimpleNamespace(node=SimpleNamespace(unique_id=unique_id), status=status)
