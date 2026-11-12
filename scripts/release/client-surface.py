#!/usr/bin/env python3
"""Compare the parts of two OpenAPI specs that become names in generated clients.

oasdiff reports wire-level breaking changes, but a generated client also breaks
when a name it is built from changes while the JSON on the wire stays the same:

  - components/schemas names become model types (Release -> PipelineRelease)
  - operationIds become method names
  - tags become API classes (`Release pipelines (beta)` -> ReleasePipelinesBetaApi)

Usage: client-surface.py BASE.json REVISION.json [--ignore-beta]

Prints JSON: {"removed": {...}, "added": {...}}, each with "schemas",
"operations" and "tags" lists. --ignore-beta leaves out operations and tags
whose tags all end in "(beta)". Schemas are always compared, since a schema
used only by beta endpoints cannot be told apart from the spec alone.
"""

import json
import sys

METHODS = {"get", "put", "post", "delete", "options", "head", "patch", "trace"}


def is_beta(tags):
    return bool(tags) and all(t.rstrip().endswith("(beta)") for t in tags)


def surface(spec, ignore_beta):
    operations, tags = set(), set()
    for path_item in spec.get("paths", {}).values():
        for method, op in path_item.items():
            if method not in METHODS or not isinstance(op, dict):
                continue
            op_tags = op.get("tags", [])
            if ignore_beta and is_beta(op_tags):
                continue
            if "operationId" in op:
                operations.add(op["operationId"])
            tags.update(op_tags)
    schemas = set(spec.get("components", {}).get("schemas", {}))
    return {"schemas": schemas, "operations": operations, "tags": tags}


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    ignore_beta = "--ignore-beta" in argv
    with open(args[0]) as f:
        base = surface(json.load(f), ignore_beta)
    with open(args[1]) as f:
        rev = surface(json.load(f), ignore_beta)
    out = {
        "removed": {k: sorted(base[k] - rev[k]) for k in base},
        "added": {k: sorted(rev[k] - base[k]) for k in base},
    }
    json.dump(out, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main(sys.argv[1:])
