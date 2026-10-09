"""Check the assets/UserApplications regression using a read-only Finder probe log."""
import re
import sys
from pathlib import Path

pair = {"assets", "UserApplications"}
checks = 0


def check(state):
    global checks
    focused, order = state
    if focused not in pair:
        return
    ranks = {title: int(rank) for rank, title in re.findall(r"(\d+):Finder/([^#]+)#\d+", order)}
    others = [int(rank) for rank, owner in re.findall(r"(\d+):([^/]+)/", order) if owner != "Finder"]
    assert pair <= ranks.keys(), "Probe lacks both Finder windows"
    sibling = next(iter(pair - {focused}))
    assert others and ranks[focused] < min(others) < ranks[sibling], f"{focused} also brought {sibling} forward: {order}"
    checks += 1


pending = False
for line in Path(sys.argv[1]).read_text().splitlines():
    match = re.search(r"front=([^;]+); main=([^;]+); focused=([^;]+); .*order=\[(.*)\]", line)
    if not match:
        continue
    front, main, focused, order = match.groups()
    if front != "Finder":
        pending = True
    elif pending and focused in pair:
        assert main == focused, "Finder main and focused windows disagree"
        target = re.search(rf"(\d+):Finder/{re.escape(focused)}#\d+", order)
        other_ranks = [int(rank) for rank, owner in re.findall(r"(\d+):([^/]+)/", order) if owner != "Finder"]
        if target and (not other_ranks or int(target[1]) < min(other_ranks)):
            check((focused, order))
            pending = False
assert checks >= 2, "Capture at least two Finder activations separated by another app"
print(f"PASS: {checks} Finder activations raised only the selected window")
