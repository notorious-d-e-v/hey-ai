#!/usr/bin/env python3
"""Launch stats for Hey AI, from GitHub.

    python3 scripts/stats.py            # save today's snapshot, then print the summary
    python3 scripts/stats.py --report   # print the summary from saved snapshots only

GitHub keeps repo traffic for only 14 days, so this is meant to run daily (see
scripts/install-stats-job.sh). It needs `gh`, logged in as someone with push access to
the repo (traffic isn't public). Data goes to ~/workspace/hey-ai-stats unless
HEYAI_STATS_DIR says otherwise:

    daily.csv      one row per snapshot: installs (zip downloads), stars, forks, watchers, issues
    test-downloads.txt  how many of those downloads were our own tests (subtracted in reports)
    views.csv      repo views per day (merged from GitHub's rolling 14-day window)
    clones.csv     repo clones per day (same)
    referrers.csv  top referrers over the trailing 14 days, as seen on each snapshot date
    paths.csv      most-viewed repo pages over the trailing 14 days, likewise
"""
import csv
import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path

REPO = os.environ.get("HEYAI_REPO", "notorious-d-e-v/hey-ai")
DATA = Path(os.environ.get("HEYAI_STATS_DIR", Path.home() / "workspace" / "hey-ai-stats"))
ZIP = "Hey-AI.zip"
# Downloads made while testing releases; not real users. Kept in the data folder
# (test-downloads.txt) so it can be bumped after each test install.
_tests_file = DATA / "test-downloads.txt"
TEST_DOWNLOADS = int(os.environ.get("HEYAI_TEST_DOWNLOADS")
                     or (_tests_file.read_text().strip() if _tests_file.exists() else "3"))

# gh lives in Homebrew, which launchd's minimal PATH doesn't include.
os.environ["PATH"] = os.pathsep.join([os.environ.get("PATH", ""), "/opt/homebrew/bin", "/usr/local/bin"])


def gh(path):
    out = subprocess.run(["gh", "api", path], check=True, capture_output=True, text=True).stdout
    return json.loads(out)


def read(name):
    path = DATA / name
    if not path.exists():
        return []
    with path.open() as f:
        return list(csv.DictReader(f))


def write(name, rows, fields):
    with (DATA / name).open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def merge_by_day(name, series):
    """GitHub returns the last 14 days; keep every day we've ever seen, newest wins."""
    rows = {r["date"]: r for r in read(name)}
    for point in series:
        day = point["timestamp"][:10]
        rows[day] = {"date": day, "count": point["count"], "uniques": point["uniques"]}
    write(name, sorted(rows.values(), key=lambda r: r["date"]), ["date", "count", "uniques"])


def snapshot():
    DATA.mkdir(parents=True, exist_ok=True)
    today = dt.date.today().isoformat()

    releases = gh(f"repos/{REPO}/releases")
    installs = sum(a["download_count"] for r in releases for a in r["assets"] if a["name"] == ZIP)
    repo = gh(f"repos/{REPO}")
    issues = gh(f"search/issues?q=repo:{REPO}+type:issue&per_page=1")["total_count"]
    prs = gh(f"search/issues?q=repo:{REPO}+type:pr&per_page=1")["total_count"]

    daily = [r for r in read("daily.csv") if r["date"] != today]
    daily.append({
        "date": today,
        "installs": installs,
        "stars": repo["stargazers_count"],
        "forks": repo["forks_count"],
        "watchers": repo["subscribers_count"],
        "issues_total": issues,
        "prs_total": prs,
        "open_issues_and_prs": repo["open_issues_count"],
    })
    write("daily.csv", daily, list(daily[-1].keys()))

    merge_by_day("views.csv", gh(f"repos/{REPO}/traffic/views")["views"])
    merge_by_day("clones.csv", gh(f"repos/{REPO}/traffic/clones")["clones"])

    for name, path, key in (("referrers.csv", "popular/referrers", "referrer"), ("paths.csv", "popular/paths", "path")):
        rows = [r for r in read(name) if r["snapshot_date"] != today]
        rows += [{"snapshot_date": today, key: item[key], "count": item["count"], "uniques": item["uniques"]}
                 for item in gh(f"repos/{REPO}/traffic/{path}")]
        write(name, rows, ["snapshot_date", key, "count", "uniques"])


def report():
    daily = read("daily.csv")
    if not daily:
        sys.exit("No snapshots yet. Run without --report first.")
    views = read("views.csv")
    last = daily[-1]

    def installs_on_or_before(date):
        rows = [r for r in daily if r["date"] <= date]
        return int(rows[-1]["installs"]) if rows else TEST_DOWNLOADS

    today = dt.date.fromisoformat(last["date"])
    installs = int(last["installs"]) - TEST_DOWNLOADS
    week_ago = (today - dt.timedelta(days=7)).isoformat()
    day_ago = (today - dt.timedelta(days=1)).isoformat()
    installs_7d = int(last["installs"]) - installs_on_or_before(week_ago)
    installs_1d = int(last["installs"]) - installs_on_or_before(day_ago)
    uniques_7d = sum(int(v["uniques"]) for v in views if v["date"] > week_ago)
    views_7d = sum(int(v["count"]) for v in views if v["date"] > week_ago)

    print(f"Hey AI on {last['date']}  (github.com/{REPO})")
    print(f"  installs     {installs} total, {installs_7d} in 7 days, {installs_1d} since yesterday")
    print(f"  stars        {last['stars']}   forks {last['forks']}   watchers {last['watchers']}")
    print(f"  issues       {last['issues_total']} opened ({last['open_issues_and_prs']} issues and PRs open)")
    print(f"  repo views   {views_7d} in 7 days, from about {uniques_7d} unique visitors (daily uniques, summed)")
    if uniques_7d:
        print(f"  conversion   {installs_7d / uniques_7d:.0%} of 7-day visitors installed (rough: updates count as installs)")

    refs = [r for r in read("referrers.csv") if r["snapshot_date"] == last["date"]]
    if refs:
        print("  referrers (last 14 days, unique visitors)")
        for r in sorted(refs, key=lambda r: -int(r["uniques"]))[:8]:
            print(f"    {r['referrer']:<28} {r['uniques']}")
    print(f"  data: {DATA}")


if __name__ == "__main__":
    if "--report" not in sys.argv:
        snapshot()
    report()
