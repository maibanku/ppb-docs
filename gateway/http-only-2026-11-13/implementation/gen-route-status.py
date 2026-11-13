#!/usr/bin/env python3
"""Regenerate progress/ROUTE-STATUS.csv from baseline/routes.csv + api/policies/*.yaml + baseline/specials.json.

P0 tooling: single source of truth for the 148 registry routes + 19 special entries.
Status vocabulary (must not be inflated):
  pending                          - not yet migrated; still executed by gateway gRPC proxy
  http_adapter_exists_auth_still_at_gateway - served by service HTTP today, gateway still verifies credentials
  service_http_done                - served AND authenticated by owning service
  special:<target>                 - special entry categories
"""
import csv, json, sys
from pathlib import Path

DOCS = Path(__file__).resolve().parents[1]
BASE = DOCS.parent  # ppb-base repo root is sibling of this docs tree's parent
CODE = Path("/Users/pipi-ban/Desktop/code/vscode/ppb-base")

def load_policies():
    """Parse the minimal yaml we control (class/owner lines) without a yaml dep."""
    policies = {}
    for y in sorted((CODE / "api/policies").glob("*.yaml")):
        op = None
        for line in y.read_text().splitlines():
            ls = line.strip()
            if ls.endswith(":") and not ls.startswith("#") and " " not in ls and ls[:-1].count(".") >= 1 and not ls.startswith(("domain", "entries")):
                op = ls[:-1]
                policies.setdefault(op, {})
            elif op and ":" in ls:
                k, _, v = ls.partition(":")
                v = v.strip().strip('"').strip("'")
                if k.strip() in ("class", "owner", "audit", "status"):
                    policies[op][k.strip()] = v
    return policies

def main():
    policies = load_policies()
    rows = []
    with open(DOCS / "baseline/routes.csv", newline="") as f:
        for r in csv.DictReader(f):
            op = r["operation_id"]
            pol = policies.get(op, {})
            status = r["migration_status"]
            rows.append({
                "operation_id": op,
                "method": r["method"],
                "legacy_path": r["path"],
                "owner": r["upstream"],
                "target_http": r["path"] if status == "http_adapter_exists_auth_still_at_gateway" else "",
                "identity": r["identity_class"],
                "permission": pol.get("class", r["policy_class"]),
                "audit_location": pol.get("audit", ""),
                "implementation": "server-gateway/proxy (gRPC proxy)" if status == "pending" else "server-im member-http adapter via server-pkg/servicehttp",
                "tests": "",
                "evidence": "",
                "commit": "",
                "status": status,
            })
    specials = json.loads((DOCS / "baseline/specials.json").read_text())
    for s in specials:
        target = {
            "auth-bridge": "iam (member session app)",
            "http-file": "server-file",
            "iam-passthrough": "server-iam (direct)",
            "ws": "server-im realtime",
            "health": "transparent gateway + service healthz",
            "docs": "transparent gateway (static)",
            "static": "transparent gateway (static)",
            "fallback": "transparent gateway",
            "dormant": "transparent gateway (dormant)",
        }.get(s["category"], "TBD")
        rows.append({
            "operation_id": s["operation_id"],
            "method": s["method"],
            "legacy_path": s["path"],
            "owner": target,
            "target_http": s["path"],
            "identity": s["identity"],
            "permission": s["policy_class"],
            "audit_location": "",
            "implementation": s["source"],
            "tests": "",
            "evidence": "",
            "commit": "",
            "status": f"special:{s['category']}:pending",
        })
    out = DOCS / "progress/ROUTE-STATUS.csv"
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["operation_id","method","legacy_path","owner","target_http","identity","permission","audit_location","implementation","tests","evidence","commit","status"])
        w.writeheader()
        w.writerows(rows)
    total = len(rows)
    done = sum(1 for r in rows if r["status"].startswith("special") is False and r["status"] != "pending")
    print(f"wrote {out}: {total} rows ({done} registry migrated, {total-done} remaining)")

if __name__ == "__main__":
    sys.exit(main())
