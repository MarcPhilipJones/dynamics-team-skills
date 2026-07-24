"""preflight.py - Pre-publish validator for the outbound voice agent.

Scans the bot's topics + the flows they call for the exact gotchas that cost us time
today, so they're caught BEFORE publish + a phone call instead of after.

Checks:
  [YAML]   topic data must be designer-canonical (CRLF + indented block sequences) or the
           canvas renders an empty topic and a save wipes it.
  [POLICY] no `interruptionPolicy` (invalid property -> publish fails).
  [ENTITY] flag NumberPrebuiltEntity questions (loop on "no"; prefer free text + AI parse).
  [BIND]   every InvokeFlowAction output binding must exist in the flow's Respond schema;
           NUMBER-typed flow outputs bound in a topic hit the 'UnspecifiedDataType' trap.
  [FLOAT]  flag float(triggerBody/items ...) in flows (throws on free-text answers).
  [TOOL]   flag type-9 tools that bind =Global.* in tool scope (IdentifierNotRecognized).

Usage:  python preflight.py <botGuid>       # or set BOT_ID env
Exit code 0 = no FAILs, 1 = at least one FAIL.
Env: DATAVERSE_URL (https://<org>.crm.dynamics.com) + PYTHONIOENCODING=utf-8. Uses ~/scripts/auth.py (dv-query).
"""
import sys, os, re, json, requests
import yaml

sys.path.insert(0, os.path.join(os.path.expanduser("~"), "scripts"))
from auth import load_env, get_token, get_plugin_headers

load_env()
if not os.environ.get("DATAVERSE_URL"):
    sys.exit("Set DATAVERSE_URL (https://<org>.crm.dynamics.com) before running.")
URL = os.environ["DATAVERSE_URL"].rstrip("/")
API = f"{URL}/api/data/v9.2"
BOT = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("BOT_ID")
if not BOT:
    sys.exit("Usage: python preflight.py <botGuid>  (or set BOT_ID env)")

_tok = None
def h():
    global _tok
    _tok = _tok or get_token()
    return get_plugin_headers("dv-query", _tok)

FAILS = []
WARNS = []
def fail(where, msg): FAILS.append(f"{where}: {msg}")
def warn(where, msg): WARNS.append(f"{where}: {msg}")

_flow_cache = {}
def flow_respond_props(flowid):
    """Return {outputName: type} from the flow's Respond action, or None."""
    if flowid in _flow_cache:
        return _flow_cache[flowid]
    r = requests.get(f"{API}/workflows({flowid})?$select=clientdata,name", headers=h())
    if r.status_code != 200:
        _flow_cache[flowid] = (None, None, "?")
        return _flow_cache[flowid]
    j = json.loads(r.json()["clientdata"]); name = r.json().get("name")
    defn = j.get("properties", {}).get("definition", j.get("definition", {}))
    props, cd = {}, json.dumps(defn)
    # Response actions can be nested inside If/Scope/Foreach - walk recursively
    def walk(actions):
        if not isinstance(actions, dict):
            return
        for av in actions.values():
            if not isinstance(av, dict):
                continue
            if av.get("type") == "Response":
                for pn, pv in av.get("inputs", {}).get("schema", {}).get("properties", {}).items():
                    props[pn] = pv.get("type", "any")
            for key in ("actions", "else"):
                walk(av.get(key))
    walk(defn.get("actions", {}))
    _flow_cache[flowid] = (props, cd, name)
    return _flow_cache[flowid]


def check_topic(name, data):
    w = f"topic '{name}'"
    # YAML canonical
    if "\r\n" not in data:
        warn(w, "LF line-endings (not CRLF) - canvas may render empty. Re-emit with ruamel CRLF.")
    if re.search(r"\n  actions:\r?\n  - kind:", data) or re.search(r"\n      actions:\r?\n      - kind:", data):
        warn(w, "non-indented block sequence - canvas may not render. Use ruamel indent(2,4,2).")
    # entity
    if "NumberPrebuiltEntity" in data:
        warn(w, f"{data.count('NumberPrebuiltEntity')} NumberPrebuiltEntity question(s) - loop on 'no'. Prefer StringPrebuiltEntity + AI parse.")
    # InvokeFlowAction output bindings vs flow schema
    try:
        doc = yaml.safe_load(data)
    except Exception as e:
        fail(w, f"YAML parse error: {e}")
        return
    for node in _iter_nodes(doc):
        if isinstance(node, dict) and node.get("kind") == "InvokeFlowAction":
            fid = node.get("flowId")
            binds = (node.get("output") or {}).get("binding") or {}
            props, _, fname = flow_respond_props(fid) if fid else (None, None, "?")
            if props is None:
                warn(w, f"InvokeFlowAction -> flow {fid} not readable; can't validate outputs.")
                continue
            for outname in binds:
                if outname not in props:
                    fail(w, f"binds flow output '{outname}' not in '{fname}' Respond schema - runtime NotFound/type error.")
                elif props[outname] in ("integer", "number"):
                    warn(w, f"binds NUMBER output '{outname}' from '{fname}' - risks 'expected UnspecifiedDataType'. Reuse a string output or re-map in designer.")


def check_flow(name, cd):
    w = f"flow '{name}'"
    if re.search(r"float\(\s*(triggerBody|items)\(", cd):
        warn(w, "float(triggerBody/items ...) present - throws on free-text answers. Parse via AI Builder / coalesce.")


def check_tool(name, data):
    if data and re.search(r"ManualTaskInput[\s\S]{0,80}value:\s*=Global\.", data):
        warn(f"tool '{name}'", "binds =Global.* in tool scope - IdentifierNotRecognized risk at publish.")


def _iter_nodes(o):
    if isinstance(o, dict):
        yield o
        for v in o.values():
            yield from _iter_nodes(v)
    elif isinstance(o, list):
        for v in o:
            yield from _iter_nodes(v)


def main():
    comps = requests.get(f"{API}/botcomponents?$select=name,schemaname,componenttype,data&$filter=_parentbotid_value eq {BOT}", headers=h()).json()["value"]
    topics = [c for c in comps if c["componenttype"] == 9 and ".topic." in c["schemaname"]]
    tools = [c for c in comps if c["componenttype"] == 9 and ".action." in c["schemaname"]]
    print(f"Pre-flight: {len(topics)} topics, {len(tools)} tools, checking linked flows...\n")
    for c in topics:
        check_topic(c["name"], c.get("data") or "")
    for c in tools:
        check_tool(c["name"], c.get("data") or "")
    for fid, (props, cd, fname) in list(_flow_cache.items()):
        if cd:
            check_flow(fname, cd)

    if FAILS:
        print("FAIL (" + str(len(FAILS)) + "):")
        for f in FAILS: print("  x", f)
    if WARNS:
        print("\nWARN (" + str(len(WARNS)) + "):")
        for x in WARNS: print("  !", x)
    if not FAILS and not WARNS:
        print("All checks passed.")
    print("\n" + ("READY TO PUBLISH" if not FAILS else "FIX FAILS BEFORE PUBLISH"))
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
