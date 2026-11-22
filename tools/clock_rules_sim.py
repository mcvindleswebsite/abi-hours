# Python model of the clock-in/out rules (ShiftStore.refresh + ClockActions.toggleShift) with scenario checks.
# Run: python3 tools/clock_rules_sim.py
# Python model of ShiftStore.refresh/startScheduledShifts + ClockActions.toggleShift (mirrors the Swift)
from datetime import datetime as D, timedelta as T
import itertools
STALE, UNDO, DEB = T(hours=16), T(minutes=15), T(seconds=10)
ids = itertools.count(1)
class Ev:
    def __init__(s, name, start, added=None, skipped=False): s.id=next(ids); s.name=name; s.start=start; s.day=start.date(); s.added=added; s.skipped=skipped
class Sh:
    def __init__(s, start, end=None, eid=None, auto=False, missing=False): s.id=next(ids); s.start=start; s.end=end; s.eid=eid; s.auto=auto; s.missing=missing
    def __repr__(s): return f"[{s.start:%a %H:%M}-{s.end.strftime('%a %H:%M') if s.end else 'open'}{' auto' if s.auto else ''}{' MISSING' if s.missing else ''}]"
class Store:
    def __init__(s, events): s.events=events; s.shifts=[]; s.last_tap=None
    def open(s): return next((x for x in reversed(s.shifts) if x.end is None), None)
    def auto_event(s, t):
        c=[e for e in s.events if e.day==t.date()]
        return min(c, key=lambda e: abs((e.start-t).total_seconds())) if c else None
    def event_for(s, sh):
        if sh.eid: 
            e=next((e for e in s.events if e.id==sh.eid),None)
            if e: return e
        return s.auto_event(sh.start)
    def has_shift(s, e, now):
        return any(s.event_for(x) is e for x in s.shifts) or any(x.start<=e.start<=(x.end or now) for x in s.shifts)
    def refresh(s, now):
        for x in s.shifts:
            if x.end is None and now-x.start>STALE: x.end=x.start; x.missing=True
        for e in sorted([e for e in s.events if not e.skipped and e.start<=now and e.start>=now-T(days=7)], key=lambda e:e.start):
            if s.has_shift(e, now): continue
            if now-e.start<=STALE:
                if (e.added or D.min) < e.start and s.open() is None: s.shifts.append(Sh(e.start, eid=e.id, auto=True))
            elif e.added and e.added<e.start:
                s.shifts.append(Sh(e.start, e.start, e.id, True, True))
        s.shifts.sort(key=lambda x:x.start)
    def started_without_shift(s, now):
        c=[e for e in s.events if not e.skipped and e.start<=now and now-e.start<=STALE and not s.has_shift(e, now)]
        return max(c, key=lambda e:e.start) if c else None
    def upcoming(s, now, w=T(hours=12)):
        c=[e for e in s.events if not e.skipped and now<e.start<=now+w]
        return min(c, key=lambda e:e.start) if c else None
    def tap(s, now):
        s.refresh(now)
        if s.last_tap and T(0)<=now-s.last_tap<DEB: return "debounced"
        s.last_tap=now
        o=s.open()
        if o: o.end=now; e=s.event_for(o); return f"clocked out of {e.name if e else '-'} {(now-o.start)}"
        closed=[x for x in s.shifts if x.end and not x.missing]
        if closed:
            last=max(closed, key=lambda x:x.end)
            if now>=last.end and now-last.end<UNDO: last.end=None; return f"undo, open since {last.start:%H:%M}"
        e=s.started_without_shift(now)
        if e:
            if now-e.start<T(hours=1): s.shifts.append(Sh(e.start, eid=e.id, auto=True)); return f"clocked in for {e.name} from {e.start:%H:%M}"
            s.shifts.append(Sh(e.start, now, e.id, True)); return f"clocked out of {e.name} since {e.start:%H:%M}"
        u=s.upcoming(now)
        if u: return f"{u.name} starts {u.start:%a %H:%M}, automatic"
        s.shifts.append(Sh(now)); s.shifts.sort(key=lambda x:x.start); return f"nothing scheduled, clocked in {now:%H:%M}"
    def delete(s, sh):
        if sh.auto and sh.eid:
            for e in s.events:
                if e.id==sh.eid: e.skipped=True
        s.shifts.remove(sh)

def t(day, h, m=0): return D(2026,11,day,h,m)
def check(name, cond, detail):
    print(("PASS " if cond else "FAIL ")+name+("" if cond else f"  -> {detail}"))

# 1 normal day, undo, re-clock-out
s=Store([Ev("Martin Lawrence", t(20,16,30), added=t(19,20))])
s.refresh(t(20,17)); a=repr(s.shifts)
r1=s.tap(t(20,23)); r2=s.tap(t(20,23,5)); r3=s.tap(t(20,23,6)); s.refresh(t(21,10))
check("normal: auto-start 4:30, tap out, undo, tap out", a=="[[Fri 16:30-open auto]]" and r1.startswith("clocked out") and r2.startswith("undo") and r3.startswith("clocked out") and len(s.shifts)==1 and s.shifts[0].end==t(20,23,6), (a,r1,r2,r3,s.shifts))
# 2 never opened app during shift: tap at end still works (materialized at tap)
s=Store([Ev("Reign", t(21,14,30), added=t(19,20))]); r=s.tap(t(21,20,45))
check("no app open all day: tap clocks out from 2:30", r.startswith("clocked out") and s.shifts[0].start==t(21,14,30) and s.shifts[0].end==t(21,20,45), (r,s.shifts))
# 3 early tap before start
s=Store([Ev("Reign", t(22,12,30), added=t(19,20))]); r=s.tap(t(22,12,10)); s.refresh(t(22,13))
check("early tap: no early clock-in, auto at 12:30", "automatic" in r and repr(s.shifts)=="[[Sun 12:30-open auto]]", (r,s.shifts))
# 4 schedule loaded after start, tap at end
s=Store([Ev("Prep", t(19,10), added=t(19,20))]); s.refresh(t(19,20,5)); a=list(s.shifts)
check("loaded late (after shift): no phantom running shift", a==[], a)
s=Store([Ev("Martin", t(20,16,30), added=t(20,18))]); s.refresh(t(20,18,1)); a=list(s.shifts); r=s.tap(t(20,23))
check("loaded mid-shift: tap at end clocks out from 4:30", a==[] and r.startswith("clocked out") and s.shifts[0].start==t(20,16,30), (a,r,s.shifts))
s=Store([Ev("Martin", t(20,16,30), added=t(20,16,40))]); r=s.tap(t(20,16,45))
check("loaded late, tap near start: clocks in from 4:30", r.startswith("clocked in") and s.shifts[0].end is None, (r,s.shifts))
# 5 back-to-back events
s=Store([Ev("Game", t(21,13), added=t(19,1)), Ev("Concert", t(21,20), added=t(19,1))])
s.refresh(t(21,14)); s.refresh(t(21,21)); r=s.tap(t(21,23)); s.refresh(t(22,9))
check("back to back: one shift 1 PM-11 PM, no phantom", len(s.shifts)==1 and s.shifts[0].end==t(21,23), s.shifts)
# 6 forgot to tap out
s=Store([Ev("Martin", t(20,16,30), added=t(19,1))]); s.refresh(t(20,17)); s.refresh(t(21,10))
check("forgot to tap out: flagged, not duplicated", len(s.shifts)==1 and s.shifts[0].missing, s.shifts)
# 7 nothing ran for days
s=Store([Ev("Martin", t(20,16,30), added=t(19,1))]); s.refresh(t(22,10))
check("app untouched for 2 days: flagged record", len(s.shifts)==1 and s.shifts[0].missing, s.shifts)
# 8 called off: delete auto shift
s=Store([Ev("Martin", t(20,16,30), added=t(19,1))]); s.refresh(t(20,17)); s.delete(s.shifts[0]); s.refresh(t(20,18))
check("deleted auto shift isn't recreated", s.shifts==[], s.shifts)
# 9 unscheduled day
s=Store([]); r1=s.tap(t(23,9)); r2=s.tap(t(23,17))
check("unscheduled day: tap in, tap out", r1.startswith("nothing") and r2.startswith("clocked out"), (r1,r2))
# 10 events saved by the old version (no addedAt)
s=Store([Ev("Reign", t(21,14,30)), Ev("Prep", t(19,10))]); s.refresh(t(21,15))
check("old events: today's starts, 2-day-old one doesn't", repr(s.shifts)=="[[Sat 14:30-open auto]]", s.shifts)
# 11 already tapped in manually earlier today (old habit), then auto shouldn't duplicate
s=Store([Ev("Reign", t(21,14,30), added=t(19,1))]); s.shifts.append(Sh(t(21,14,20))); s.refresh(t(21,15)); r=s.tap(t(21,20))
check("manual shift already exists: no duplicate", len(s.shifts)==1 and r.startswith("clocked out of Reign"), (r,s.shifts))
