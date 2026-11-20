"""Python copy of ABIHours/ScheduleParser.swift, line for line, so the parser can be tested on a computer.

Run:  python3 tools/parser_reference.py
Keep it in sync with the Swift file when either changes.
"""
import re
import sys
from datetime import date, datetime, timedelta

I = re.IGNORECASE

WEEKDAY = r"(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:s|nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)"
T12 = r"(?<![\d:])\d{1,2}(?::[0-5]\d)?\s?[ap]\.?(?:m\.?)?(?![a-z])"
T24 = r"(?<![\d:])(?:[01]?\d|2[0-3]):[0-5]\d(?!\d)"

NUMERIC_DATE = re.compile(r"(?<![\d/])(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?(?![\d/])", I)
NAMED_DATE = re.compile(
    r"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?!\d)(?:,?\s+(\d{4})(?!\d))?",
    I,
)
TIME_RE = re.compile(
    r"(?:(?<![\d:])(\d{1,2})(?::([0-5]\d))?\s?([ap])\.?(?:m\.?)?(?![a-z]))|(?:(?<![\d:])([01]?\d|2[0-3]):([0-5]\d)(?!\d))",
    I,
)
_ANY = "(?:" + T12 + "|" + T24 + ")"
_PREFIX = r"(?:\b(?:call\s*time|call|doors?|show\s*time|showtime|show|start\s*time|starts?|arrive|arrival|report|shift|work|hours|(?:check|clock|load)[\s-]*(?:in|out)|in|at)\b\s*:?\s*|@\s*)?"
_RANGE = r"(?:\s*(?:-|–|—|to|until|till|til)\s*" + _ANY + ")?"
TIME_REMOVAL = re.compile(_PREFIX + _ANY + _RANGE, I)
LEADING_WD = re.compile(r"^[\s,.(\[\-–—:|·•]*" + WEEKDAY + r"\b\.?[)\]]?", I)
TRAILING_WD = re.compile(r"[\s,(\[\-–—:|·•]*\b" + WEEKDAY + r"\b\.?[)\]]?[\s,.\-–—:|·•]*$", I)
BULLET = re.compile(r"^\s*(?:[-*•+>▪◦‣–—]|\d{1,2}[.)])\s+", I)
HEADING = re.compile(r"^\s*#+\s*", I)
CHECKBOX = re.compile(r"^\s*\[[ x]?\]\s*", I)
EMPTY_BRACKETS = re.compile(r"[(\[]\s*[)\]]", I)
SPACE_BEFORE_CLOSE = re.compile(r"\s+\)", I)
SPACE_AFTER_OPEN = re.compile(r"\(\s+", I)
MULTI_SPACE = re.compile(r"\s{2,}", I)
STATUS_WORDS = re.compile(r"\b(?:not\s+confirmed|unconfirmed|confirmed|pending|accepted|declined|tentative)\b", I)
# ABI prints events as "TA- MARTIN LAWRENCE" (venue code, dash, name). Case-sensitive on purpose.
CODED = re.compile(r"(?:^|\s)[A-Z]{2,3}-\s+(\S.*)$")
RULE = re.compile(r"^\s*[-_=*]{3,}\s*$")
NAME_LABEL = re.compile(r"^(?:event|show|artist|performer|name|title|act)\s*:\s*(.+)$", I)

SEPS = " \t-–—:|,;·•*_#>~=/\n\r "
MONTHS = {"jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12}
HEADER_WORDS = {"schedule", "my schedule", "work schedule", "events", "upcoming", "upcoming events", "calendar", "month", "shifts", "my shifts", "work"}
DAY_OFF = {"off", "day off", "off day", "no event", "no events", "no shift", "no shifts", "not scheduled", "none", "nothing", "free", "rest", "n/a", "na", "x"}
NOTE_LABELS = {"position", "role", "job", "location", "where", "gate", "section", "area", "post", "stand", "uniform", "dress", "dress code", "attire", "wear", "note", "notes", "parking", "supervisor", "manager", "lead", "dept", "department", "pay", "rate", "details", "address", "venue", "meet", "entrance", "bring", "duties", "assignment", "hours", "shift", "doors", "show", "call", "end", "out"}


def make_day(month, day, year, today):
    if not (1 <= month <= 12 and 1 <= day <= 31):
        return None

    def build(y):
        try:
            return date(y, month, day)
        except ValueError:
            return None

    if year is not None:
        if year < 100:
            year += 2000
        return build(year)
    opts = [d for d in (build(today.year - 1), build(today.year), build(today.year + 1)) if d]
    return min(opts, key=lambda d: abs((d - today).days)) if opts else None


def find_dates(line, today):
    hits = []
    for m in NUMERIC_DATE.finditer(line):
        y = int(m.group(3)) if m.group(3) else None
        d = make_day(int(m.group(1)), int(m.group(2)), y, today)
        if d:
            hits.append((m.start(), m.end(), d))
    for m in NAMED_DATE.finditer(line):
        if any(s < m.end() and m.start() < e for s, e, _ in hits):
            continue
        month = MONTHS.get(m.group(1).lower()[:3])
        if not month:
            continue
        y = int(m.group(3)) if m.group(3) else None
        d = make_day(month, int(m.group(2)), y, today)
        if d:
            hits.append((m.start(), m.end(), d))
    return sorted(hits)


def first_time(text, day):
    m = TIME_RE.search(text)
    if not m:
        return None
    if m.group(1):
        hour, minute = int(m.group(1)), int(m.group(2) or 0)
        pm = m.group(3).lower() == "p"
        if not 1 <= hour <= 12:
            return None
        if hour == 12:
            hour = 12 if pm else 0
        elif pm:
            hour += 12
    elif m.group(4):
        hour, minute = int(m.group(4)), int(m.group(5) or 0)
        if 1 <= hour <= 6:
            hour += 12
    else:
        return None
    return datetime(day.year, day.month, day.day, hour, minute)


def tidy(s):
    t = EMPTY_BRACKETS.sub(" ", s)
    t = SPACE_BEFORE_CLOSE.sub(")", t)
    t = SPACE_AFTER_OPEN.sub("(", t)
    t = MULTI_SPACE.sub(" ", t)
    t = t.strip(SEPS)
    while t.endswith("(") or t.endswith("["):
        t = t[:-1].strip(SEPS)
    while t.startswith(")") or t.startswith("]"):
        t = t[1:].strip(SEPS)
    if t.startswith("(") and ")" not in t:
        t = t[1:]
    if t.endswith(")") and "(" not in t:
        t = t[:-1]
    t = t.strip(SEPS)
    m = NAME_LABEL.match(t)
    if m:
        t = m.group(1).strip(SEPS)
    if not any(c.isalpha() for c in t):
        return ""
    return t


def clean(text, leading, trailing):
    t = TIME_REMOVAL.sub(" ", text)
    t = STATUS_WORDS.sub(" ", t)
    if leading:
        t = LEADING_WD.sub(" ", t)
    if trailing:
        t = TRAILING_WD.sub(" ", t)
    return tidy(t)


def coded_name(name):
    m = CODED.search(name)
    return m.group(1).strip(SEPS) if m else None


def prettify(name):
    """MARTIN LAWRENCE -> Martin Lawrence, REIGN VS COACHELLA -> Reign vs Coachella."""
    if any(c.islower() for c in name):
        return name
    words = []
    for w in name.split():
        lw = w.lower()
        words.append(lw if lw in ("vs", "vs.") else lw[:1].upper() + lw[1:])
    return " ".join(words)


def final_name(name):
    """Returns (name, came_from_code)."""
    c = coded_name(name)
    return (prettify(c), True) if c else (prettify(name), False)


def strip_markdown(s):
    t = s.replace("**", "").replace("__", "").replace("`", "")
    t = HEADING.sub("", t)
    t = BULLET.sub("", t)
    t = CHECKBOX.sub("", t)
    return t


def is_header(lower):
    return lower.startswith("week") or lower.startswith("schedule for") or lower.startswith("pay period") or lower in HEADER_WORDS


def is_note(lower):
    if ":" not in lower:
        return False
    return lower.split(":", 1)[0].strip() in NOTE_LABELS


def parse(text, today):
    results = []  # [day, name, time]
    current_day = pending = last = soft = None
    for raw in text.splitlines():
        if RULE.match(raw):  # "---" between screenshots or sections: start fresh
            current_day = pending = last = soft = None
            continue
        line = strip_markdown(raw)
        if not line.strip():
            continue
        hits = find_dates(line, today)
        if hits:
            prefix = line[: hits[0][0]]
            segments = []
            for i, (s, e, d) in enumerate(hits):
                to = hits[i + 1][0] if i + 1 < len(hits) else len(line)
                segments.append(line[e:to])
            prefix_name = clean(prefix, True, True)
            seg_names = [clean(seg, True, i < len(segments) - 1) for i, seg in enumerate(segments)]
            per_date = len(hits) > 1 and not prefix_name and all(seg_names)
            shared = " ".join(n for n in [prefix_name] + seg_names if n)
            sl = shared.lower()
            if not per_date and (is_header(sl) or (len(hits) > 1 and not shared) or sl in DAY_OFF):
                current_day = pending = last = soft = None
                continue
            shared, shared_coded = final_name(shared)
            seg_names = [final_name(n)[0] for n in seg_names]
            for i, (s, e, d) in enumerate(hits):
                name = seg_names[i] if per_date else shared
                src = segments[i] if per_date else prefix + " " + " ".join(segments)
                results.append([d, name, first_time(src, d)])
            current_day = hits[0][2] if len(hits) == 1 else None
            last = len(results) - 1
            pending = last if (len(hits) == 1 and not shared) else None
            # a plain name here can still be replaced by a "TA- NAME" line under it
            soft = last if (len(hits) == 1 and shared and not shared_coded) else None
            continue
        if current_day is None:
            continue
        t = first_time(line, current_day)
        name, is_coded = final_name(clean(line, False, False))
        if not name:
            if t and last is not None and results[last][2] is None:
                results[last][2] = t
            continue
        lower = name.lower()
        if is_note(lower) or is_header(lower):
            continue
        if lower in DAY_OFF:
            if pending is not None:
                results.pop()
            pending = last = current_day = soft = None
            continue
        if pending is not None:
            results[pending][1] = name
            if results[pending][2] is None:
                results[pending][2] = t
            soft = None if is_coded else pending  # e.g. "ENTIRE ARENA" until "TA- ..." shows up
            pending = None
        elif soft is not None and is_coded:
            results[soft][1] = name
            soft = None
        elif t:
            results.append([current_day, name, t])
            last = len(results) - 1
            soft = None
    for r in results:
        if not r[1]:
            r[1] = "Shift"
    named_days = {d for d, n, t in results if n != "Shift"}
    results = [r for r in results if not (r[1] == "Shift" and r[0] in named_days)]
    seen, out = set(), []
    for d, n, t in results:
        k = (d, n.lower())
        if k not in seen:
            seen.add(k)
            out.append((d, n, t))
    out.sort(key=lambda r: r[2] or datetime(r[0].year, r[0].month, r[0].day))
    return out


def fmt(events):
    return [f"{d:%a %m/%d} | {n} | {t:%I:%M %p}" if t else f"{d:%a %m/%d} | {n} | -" for d, n, t in events]


TODAY = date(2026, 11, 19)

CASES = {
    "one line, dashes": (
        """Fri 11/20 — Martin Lawrence — call 5:00 PM
Fri 11/21 – Ontario Reign vs. Tucson Roadrunners – 4:30 PM
Sat 11/22 - OFF
Sun 11/23 — Disney On Ice (call 9:30 AM)""",
        ["Fri 11/20 | Martin Lawrence | 05:00 PM",
         "Sat 11/21 | Ontario Reign vs. Tucson Roadrunners | 04:30 PM",
         "Mon 11/23 | Disney On Ice | 09:30 AM"],
    ),
    "claude markdown, details on next lines": (
        """**Week of Nov 17 – Nov 23**

**Thursday, November 20**
- Event: Martin Lawrence
- Call: 5:00 PM
- Position: Usher, Section 104

**Saturday, November 22**
- Ontario Reign vs. San Diego Gulls
- Call time: 3:30 PM
- Wear black""",
        ["Fri 11/20 | Martin Lawrence | 05:00 PM",
         "Sun 11/22 | Ontario Reign vs. San Diego Gulls | 03:30 PM"],
    ),
    "name first, date after": (
        """Martin Lawrence - Thu 11/20 - 5pm
Reign vs Gulls — 11/22 (Sat) @ 4p
Bad Bunny: Dec 3, 2026 at 6:30pm""",
        ["Fri 11/20 | Martin Lawrence | 05:00 PM",
         "Sun 11/22 | Reign vs Gulls | 04:00 PM",
         "Thu 12/03 | Bad Bunny | 06:30 PM"],
    ),
    "times as ranges and no am/pm": (
        """11/20 Martin Lawrence 5:30-11:30
11/21 Ontario Reign 4:00 PM – 10:00 PM
11/28: Trans-Siberian Orchestra (shift 2:00pm to 11pm)""",
        ["Fri 11/20 | Martin Lawrence | 05:30 PM",
         "Sat 11/21 | Ontario Reign | 04:00 PM",
         "Sat 11/28 | Trans-Siberian Orchestra | 02:00 PM"],
    ),
    "two events one day + table-ish": (
        """Sun 11/22
- Reign vs. Gulls 1:00 PM
- Tyler Childers 8:00 PM
Sun 11/23 | Harlem Globetrotters | Call 12:30 PM""",
        ["Sun 11/22 | Reign vs. Gulls | 01:00 PM",
         "Sun 11/22 | Tyler Childers | 08:00 PM",
         "Mon 11/23 | Harlem Globetrotters | 12:30 PM"],
    ),
    "january schedule pasted in november, numbered list": (
        """1. Jan 2 — Monster Jam — call 10am
2. 1/3/27 — Monster Jam — call 10am
3. 12/31 New Year's Eve Concert 7pm""",
        ["Thu 12/31 | New Year's Eve Concert | 07:00 PM",
         "Sat 01/02 | Monster Jam | 10:00 AM",
         "Sun 01/03 | Monster Jam | 10:00 AM"],
    ),
    "per-date on one line": (
        "Fri 11/20: Martin Lawrence, Fri 11/21: Ontario Reign",
        ["Fri 11/20 | Martin Lawrence | -", "Sat 11/21 | Ontario Reign | -"],
    ),
    "ABI ESS screenshot (read by OCR)": (
        """7:49
Schedule
View
Confirm
Accept Dates
Thursday, November 19, 2026
10:00am - 5:00pm
Confirmed
ENTIRE ARENA
TA- MARTIN PREP DAY
Friday, November 20, 2026
4:30pm - 12:00pm
Confirmed
ENTIRE ARENA
TA- MARTIN LAWRENCE
Saturday, November 21, 2026
2:30pm - 8:30pm
Confirmed
ENTIRE ARENA
TA- REIGN VS COACHELLA
Sunday, November 22, 2026
12:30pm - 6:30pm
ENTIRE ARENA
Confirmed
TA- REIGN VS HENDERSON
Department Notes
If you have any conflicts with the days that you have been
scheduled, please contact your manager immediately so
they can try to accomodate. Be advised that all schedule
conflicts may not be accomodated due to business
needs.Thanks you
Home
Schedule
Availability
Time
More""",
        ["Thu 11/19 | Martin Prep Day | 10:00 AM",
         "Fri 11/20 | Martin Lawrence | 04:30 PM",
         "Sat 11/21 | Reign vs Coachella | 02:30 PM",
         "Sun 11/22 | Reign vs Henderson | 12:30 PM"],
    ),
    "ABI card copied as one line": (
        "Friday, November 20, 2026 4:30pm - 12:00pm ENTIRE ARENA TA- MARTIN LAWRENCE Confirmed",
        ["Fri 11/20 | Martin Lawrence | 04:30 PM"],
    ),
    "two screenshots, card cut at the bottom of the first": (
        """Friday, November 20, 2026
4:30pm - 12:00pm
ENTIRE ARENA
TA- MARTIN LAWRENCE
Saturday, November 21, 2026
---
7:49
Schedule
Saturday, November 21, 2026
2:30pm - 8:30pm
ENTIRE ARENA
TA- REIGN VS COACHELLA""",
        ["Fri 11/20 | Martin Lawrence | 04:30 PM",
         "Sat 11/21 | Reign vs Coachella | 02:30 PM"],
    ),
    "date only, no name": (
        "Tue 11/24 5:00 PM\nTue 11/25 — Check in: 4:30 PM",
        ["Tue 11/24 | Shift | 05:00 PM", "Wed 11/25 | Shift | 04:30 PM"],
    ),
}

if __name__ == "__main__":
    failed = 0
    for title, (text, expected) in CASES.items():
        got = fmt(parse(text, TODAY))
        ok = got == expected
        failed += not ok
        print(("PASS " if ok else "FAIL ") + title)
        if not ok:
            print("  expected:", *expected, sep="\n    ")
            print("  got:", *got, sep="\n    ")
    sys.exit(1 if failed else 0)
