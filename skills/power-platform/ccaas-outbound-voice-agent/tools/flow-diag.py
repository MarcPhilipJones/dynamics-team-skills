"""flow-diag.py - Fast flow run diagnostics (no phone-call transcript wait).

Turns "place a call, wait 3-4 min for the transcript, hope the error is there" into an
instant PASS/FAIL read straight from the Dataverse `flowruns` table, correlated with the
agent-side error from the latest conversation transcript.

Usage:
  python flow-diag.py <flow name substring | flow guid>   # e.g. "Complete Qualification"
  python flow-diag.py <flow> --watch                       # keep polling for the next run

Env: set DATAVERSE_URL (https://<org>.crm.dynamics.com) + PYTHONIOENCODING=utf-8.
Optional: FLOW env sets a default flow so you can omit the arg.
Uses ~/scripts/auth.py (dv-query). Exit 0 if the latest run succeeded, 1 if it failed.
"""
import sys, os, json, time, requests

sys.path.insert(0, os.path.join(os.path.expanduser("~"), "scripts"))
from auth import load_env, get_token, get_plugin_headers

load_env()
if not os.environ.get("DATAVERSE_URL"):
    sys.exit("Set DATAVERSE_URL (https://<org>.crm.dynamics.com) before running.")
URL = os.environ["DATAVERSE_URL"].rstrip("/")
API = f"{URL}/api/data/v9.2"
FV = "@OData.Community.Display.V1.FormattedValue"

DEFAULT = os.environ.get("FLOW")   # optional default flow (name substring or guid) via env


def h():
    return get_plugin_headers("dv-query", get_token())


def resolve_flow(term):
    """Return (flowid, name). term may be a guid or a name substring."""
    if len(term) == 36 and term.count("-") == 4:
        r = requests.get(f"{API}/workflows({term})?$select=name", headers=h())
        return (term, r.json().get("name")) if r.status_code == 200 else (term, "?")
    q = term.replace("'", "''")
    r = requests.get(f"{API}/workflows?$select=workflowid,name&$filter=category eq 5 and contains(name,'{q}')&$top=5", headers=h()).json()["value"]
    if not r:
        sys.exit(f"No cloud flow matches '{term}'")
    if len(r) > 1:
        print("Multiple matches (using first):", ", ".join(x["name"] for x in r))
    return r[0]["workflowid"], r[0]["name"]


def latest_transcript_error(since_iso):
    r = requests.get(f"{API}/conversationtranscripts?$filter=createdon gt {since_iso}&$orderby=createdon desc&$top=3&$select=content", headers=h()).json().get("value", [])
    for rec in r:
        for a in json.loads(rec["content"]).get("activities", []):
            if a.get("valueType") == "ErrorTraceData":
                v = a["value"]
                return f"{v.get('errorCode')}: {v.get('errorMessage')}"
    return None


def runs(flowid, top=6):
    sel = "createdon,status,errorcode,errormessage,duration,conversationid,starttime"
    return requests.get(f"{API}/flowruns?$filter=_workflow_value eq {flowid}&$orderby=createdon desc&$top={top}&$select={sel}", headers=h()).json().get("value", [])


def show(flowid, name):
    rs = runs(flowid)
    print(f"\n=== {name} ===  ({flowid})")
    if not rs:
        print("  (no runs found)")
        return None
    for i, x in enumerate(rs):
        mark = ">" if i == 0 else " "
        st = x.get("status")
        dur = x.get("duration")
        dur_s = f"{int(dur)/1000:.1f}s" if dur else "?"
        print(f" {mark} {x.get('createdon')}  {st:<10} {dur_s:>6}  err={x.get('errorcode') or '-'}")
    top = rs[0]
    if top.get("status") == "Failed":
        print("\n  LATEST = FAILED.")
        te = latest_transcript_error(top.get("starttime") or top.get("createdon"))
        if te:
            print("  agent-side error (transcript):", te)
        else:
            print("  (agent-side error not in transcript yet - it lags ~3-4 min;")
            print("   open the run in Power Automate for the exact failing action)")
    else:
        print("\n  LATEST = SUCCEEDED.")
    return top.get("status") == "Succeeded"


def main():
    args = [a for a in sys.argv[1:] if a != "--watch"]
    watch = "--watch" in sys.argv
    term = args[0] if args else DEFAULT
    if not term:
        sys.exit("Usage: python flow-diag.py <flow name substring | flow guid>  (or set FLOW env)")
    flowid, name = resolve_flow(term)
    if not watch:
        ok = show(flowid, name)
        sys.exit(0 if ok else 1)
    seen = None
    print("Watching for the next run (Ctrl+C to stop)...")
    while True:
        rs = runs(flowid, top=1)
        cur = rs[0]["createdon"] if rs else None
        if cur and cur != seen:
            seen = cur
            show(flowid, name)
        time.sleep(15)


if __name__ == "__main__":
    main()
