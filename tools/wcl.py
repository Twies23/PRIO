#!/usr/bin/env python
"""Warcraft Logs v2 fetcher for rotation analysis.

Pulls a player's cast events from a public report and summarizes ability usage +
a sample cast sequence, so we can diff real play against PRIO's priority lists.

Auth (client-credentials flow, public data only). Provide either:
  - env vars  WCL_CLIENT_ID / WCL_CLIENT_SECRET, or
  - a gitignored file  tools/.wcl_creds  with two lines: id then secret.
Create a client at https://www.warcraftlogs.com/api/clients/ (redirect https://localhost).

Usage:
  python tools/wcl.py <reportCode> [playerName]
  python tools/wcl.py https://www.warcraftlogs.com/reports/<code> Bilbro
"""
import base64
import json
import os
import re
import sys
import urllib.request
from collections import Counter

TOKEN_URL = "https://www.warcraftlogs.com/oauth/token"
API_URL = "https://www.warcraftlogs.com/api/v2/client"


def creds():
    cid, sec = os.environ.get("WCL_CLIENT_ID"), os.environ.get("WCL_CLIENT_SECRET")
    if cid and sec:
        return cid.strip(), sec.strip()
    path = os.path.join(os.path.dirname(__file__), ".wcl_creds")
    if os.path.exists(path):
        with open(path) as f:
            lines = [ln.strip() for ln in f if ln.strip()]
        if len(lines) >= 2:
            return lines[0], lines[1]
    sys.exit("No credentials: set WCL_CLIENT_ID / WCL_CLIENT_SECRET or write tools/.wcl_creds")


def token():
    cid, sec = creds()
    basic = base64.b64encode(f"{cid}:{sec}".encode()).decode()
    data = b"grant_type=client_credentials"
    req = urllib.request.Request(TOKEN_URL, data=data, method="POST", headers={
        "Authorization": "Basic " + basic,
        "Content-Type": "application/x-www-form-urlencoded",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["access_token"]


def gql(tok, query, variables):
    body = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(API_URL, data=body, method="POST", headers={
        "Authorization": "Bearer " + tok,
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=60) as r:
        out = json.load(r)
    if "errors" in out:
        sys.exit("GraphQL errors: " + json.dumps(out["errors"], indent=2))
    return out["data"]


REPORT_Q = """
query($code:String!){ reportData{ report(code:$code){
  title zone{name}
  masterData{ actors(type:"Player"){ id name subType } }
  fights(killType:Encounters){ id name startTime endTime }
}}}
"""

CASTS_Q = """
query($code:String!,$start:Float!,$end:Float!,$src:Int!){ reportData{ report(code:$code){
  events(dataType:Casts, startTime:$start, endTime:$end, sourceID:$src, limit:5000){
    data nextPageTimestamp
  }
}}}
"""


def report_code(arg):
    m = re.search(r"reports/([A-Za-z0-9]+)", arg)
    return m.group(1) if m else arg


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    code = report_code(sys.argv[1])
    want_player = sys.argv[2].lower() if len(sys.argv) > 2 else None

    tok = token()
    rep = gql(tok, REPORT_Q, {"code": code})["reportData"]["report"]
    print(f"Report: {rep['title']}  ({rep.get('zone', {}).get('name', '?')})")

    actors = rep["masterData"]["actors"]
    players = {a["id"]: a for a in actors}
    if want_player:
        match = [a for a in actors if want_player in a["name"].lower()]
    else:
        # default: Monk players
        match = [a for a in actors if a.get("subType") == "Monk"]
    if not match:
        print("Players:", ", ".join(f"{a['name']}({a['subType']})" for a in actors))
        sys.exit("No matching player; pass a name.")
    src = match[0]
    print(f"Player: {src['name']}  ({src['subType']})   sourceID={src['id']}")

    fights = rep["fights"]
    if not fights:
        sys.exit("No encounter fights in report.")
    counts, seq = Counter(), []
    for f in fights:
        start, end = float(f["startTime"]), float(f["endTime"])
        while start < end:
            d = gql(tok, CASTS_Q, {"code": code, "start": start, "end": end, "src": src["id"]})
            ev = d["reportData"]["report"]["events"]
            for e in ev["data"]:
                if e.get("type") == "cast":
                    aid = e.get("abilityGameID")
                    counts[aid] += 1
                    seq.append((e["timestamp"], aid))
            nxt = ev.get("nextPageTimestamp")
            if not nxt:
                break
            start = float(nxt)

    print(f"\n=== Cast counts ({sum(counts.values())} casts across {len(fights)} fight(s)) ===")
    for aid, n in counts.most_common():
        print(f"  {n:5d}  x  ability {aid}")

    print("\n=== First 40 casts (ms gap, abilityID) ===")
    seq.sort()
    prev = None
    for ts, aid in seq[:40]:
        gap = "" if prev is None else f"+{int(ts - prev):5d}ms"
        print(f"  {gap:>9}  {aid}")
        prev = ts


if __name__ == "__main__":
    main()
