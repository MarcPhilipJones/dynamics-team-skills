"""call-check.py - One-shot post-call diagnostics (replaces the manual transcript hunt).

After a test call, shows in one place:
  - latest qualification: parsed numbers + Completed/Scored/Routed timestamps
  - Complete flow: last run PASS/FAIL + timing
  - latest transcript: the spoken turns + any ErrorTraceData (the agent-side error)

Usage:
  python call-check.py <leadGuid>            # a specific lead (or set LEAD_ID env)
  python call-check.py <leadGuid> --watch    # poll until a new transcript lands

Env: DATAVERSE_URL (https://<org>.crm.dynamics.com) + PYTHONIOENCODING=utf-8.
Optional: LEAD_ID (default lead), COMPLETE_FLOW (completion flow name substring or guid).
Uses ~/scripts/auth.py (dv-query).
"""
import sys, os, json, time, requests

sys.path.insert(0, os.path.join(os.path.expanduser("~"), "scripts"))
from auth import load_env, get_token, get_plugin_headers

load_env()
if not os.environ.get("DATAVERSE_URL"):
    sys.exit("Set DATAVERSE_URL (https://<org>.crm.dynamics.com) before running.")
URL = os.environ["DATAVERSE_URL"].rstrip("/")
API = f"{URL}/api/data/v9.2"
DEFAULT_LEAD = os.environ.get("LEAD_ID")                        # lead guid via arg or LEAD_ID env
COMPLETE_FLOW_TERM = os.environ.get("COMPLETE_FLOW", "Complete Qualification")  # name or guid


def h():
    return get_plugin_headers("dv-query", get_token())


def qual(lead):
    sel = ("mse_name,createdon,mse_oceanteuspermonth,mse_airtonnespermonth,"
           "mse_localtransportspendusd,mse_warehousingspendusd,mse_preferredcontactmethod,"
           "mse_completedon,mse_scoredon,mse_routedon,mse_mqlstatus")
    r = requests.get(f"{API}/mse_leadqualifications?$select={sel}&$filter=_mse_leadid_value eq {lead}&$orderby=createdon desc&$top=1", headers=h()).json().get("value", [])
    return r[0] if r else None


def resolve_flow(term):
    """term may be a flow guid or a name substring -> flow guid (or None)."""
    if term and len(term) == 36 and term.count("-") == 4:
        return term
    q = (term or "").replace("'", "''")
    r = requests.get(f"{API}/workflows?$select=workflowid&$filter=category eq 5 and contains(name,'{q}')&$top=1", headers=h()).json().get("value", [])
    return r[0]["workflowid"] if r else None


def last_flow_run(flowid):
    if not flowid:
        return None
    r = requests.get(f"{API}/flowruns?$filter=_workflow_value eq {flowid}&$orderby=createdon desc&$top=1&$select=createdon,status,errorcode,duration", headers=h()).json().get("value", [])
    return r[0] if r else None


def latest_transcript():
    r = requests.get(f"{API}/conversationtranscripts?$orderby=createdon desc&$top=1&$select=content,createdon", headers=h()).json().get("value", [])
    return r[0] if r else None


def show(lead, flowid):
    q = qual(lead)
    print("\n--- QUALIFICATION ---")
    if q:
        fv = lambda k: q.get(k + "@OData.Community.Display.V1.FormattedValue")
        print(f"  {q.get('mse_name')}  ({q.get('createdon')})")
        print(f"  ocean={q.get('mse_oceanteuspermonth')} air={q.get('mse_airtonnespermonth')} "
              f"local={q.get('mse_localtransportspendusd')} warehouse={q.get('mse_warehousingspendusd')} "
              f"contact={q.get('mse_preferredcontactmethod')}")
        print(f"  completed={q.get('mse_completedon')} scored={q.get('mse_scoredon')} routed={q.get('mse_routedon')} mql={fv('mse_mqlstatus')}")
    else:
        print("  (none)")

    fr = last_flow_run(flowid)
    print("\n--- COMPLETE FLOW (last run) ---")
    if fr:
        d = fr.get("duration")
        print(f"  {fr.get('createdon')}  {fr.get('status')}  {int(d)/1000:.1f}s  err={fr.get('errorcode') or '-'}" if d else f"  {fr.get('createdon')}  {fr.get('status')}")
    else:
        print("  (none)")

    t = latest_transcript()
    print("\n--- LATEST TRANSCRIPT ---")
    if t:
        acts = json.loads(t["content"]).get("activities", [])
        msgs = [a for a in acts if a.get("type") == "message"]
        print(f"  {t['createdon']}  ({len(msgs)} messages)")
        for a in acts:
            if a.get("type") == "message" and (a.get("text") or "").strip():
                who = "bot" if a.get("from", {}).get("role") == 0 else "usr"
                print(f"    [{who}] {(a.get('text') or '')[:100]}")
            if a.get("valueType") == "ErrorTraceData":
                v = a["value"]
                print(f"    *** ERROR: {v.get('errorCode')}: {v.get('errorMessage')}")
    else:
        print("  (none)")
    return t["createdon"] if t else None


def main():
    args = [a for a in sys.argv[1:] if a != "--watch"]
    watch = "--watch" in sys.argv
    lead = args[0] if args else DEFAULT_LEAD
    if not lead:
        sys.exit("Usage: python call-check.py <leadGuid>  (or set LEAD_ID env)")
    flowid = resolve_flow(COMPLETE_FLOW_TERM)
    if not watch:
        show(lead, flowid)
        return
    seen = None
    print("Watching for a new transcript (Ctrl+C to stop)...")
    while True:
        cur = latest_transcript()
        c = cur["createdon"] if cur else None
        if c and c != seen:
            seen = c
            show(lead, flowid)
        time.sleep(20)


if __name__ == "__main__":
    main()
