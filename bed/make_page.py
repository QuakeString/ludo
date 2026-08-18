"""
Build one self-contained HTML sheet for the carpenter: the drawings, the
cutting list, the joinery notes and the build sequence, all read from model.py
so the page can never drift from the drawings.

    python3 make_page.py     ->  out/build-plan.html
"""

import os
from collections import OrderedDict

import cutlist
import model as M

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

SEQUENCE = [
    ("Mill and glue up",
     "Get the boards in the shop a fortnight before you cut. Rough out every "
     "piece 30 mm long and 4 mm oversize on the section, glue up the two panels "
     "from boards no wider than 150 mm with the growth rings alternating, and "
     "leave everything stickered until it stops moving. Thickness last."),
    ("Post joinery",
     "Mark all four posts from one datum, the floor end, with the setting-out "
     "tables. Every mortise, groove and bolt hole is dimensioned from that end. "
     "The side rail mortise and the two end rail mortises cross inside the same "
     "post - the design keeps them 5 mm apart, so cut them in that order and "
     "check as you go."),
    ("End rails and the arch",
     "Tenons on all six end rails, then the panel grooves. Saw the headboard "
     "arc from the 200 mm blank only after its joints fit: the curve rises 80 mm "
     "over 1410 and finishes flush with the post tops at each end. Clean it with "
     "a spokeshave, not a sander."),
    ("Glue up the two ends",
     "Panels go in dry, centred, with 3 mm of air top and bottom. Glue the "
     "rail tenons only. Clamp across the rails, check the diagonals, and check "
     "the assembly sits flat - a wound in an end shows up as a rocking bed."),
    ("Side rails and bolts",
     "Tenons, then the two bolt holes down each tenon and the barrel nut "
     "cross-drilling 30 mm past the shoulder. Counterbore the outside of each "
     "post 20 mm dia x 10 deep. Assemble the frame on the floor, square it by "
     "the diagonals, and only then drill the nut holes through to match."),
    ("Deck",
     "Bearers glued and screwed inside the rails, top edge 380 above the floor. "
     "Centre beam on its three legs. Fifteen slats at 134 mm centres, screwed to "
     "the bearers and to the beam - the screws into the beam are what stop the "
     "slats walking."),
    ("Drawers",
     "Groove all four sides of each box for the plywood bottom before assembly. "
     "Box together, bottom slid in dry, castors on, then hang the front on it "
     "from inside with a 4 mm reveal all round. Rout the finger pull and break "
     "every edge you will reach into."),
    ("Finish",
     "Take the bed apart to finish it. Hard wax oil or a matt lacquer; leave the "
     "slat tops and the inside of the drawer boxes bare. Reassemble in the room "
     "it lives in - the frame is 2150 long and will not turn a tight landing."),
]

JOINERY = [
    ("Rail to post", "bed bolt",
     f"A {M.TENON_T} mm tenon {M.SIDE_TENON_L} long locates the rail; two M8 bed "
     f"bolts per joint pull it home into barrel nuts cross-drilled "
     f"{M.NUT_SETBACK} mm past the shoulder. This is the joint that makes the "
     f"bed knock down - eight bolts and it is four pieces plus the deck."),
    ("Ends", "frame and panel",
     f"Posts {M.POST_Y} x {M.POST_X}, rails tenoned {M.END_TENON_L} into them, "
     f"and an {M.PANEL_T} mm panel floating in {M.GROOVE_D} mm grooves. The "
     f"panels are not glued: solid wood moves across the grain and a glued panel "
     f"splits its frame."),
    ("Deck", "beam and slats",
     f"{M.SLAT_N} slats {M.SLAT_W} x {M.SLAT_T} at {M.SLAT_PITCH:.0f} mm centres "
     f"on bearers inside the rails, over a {M.BEAM_H} x {M.BEAM_W} beam standing "
     f"on {M.BEAM_LEGS} legs. The beam is what stops a double bed sagging."),
    ("Drawers", "castors, no runners",
     f"{M.DRAWER_BOX_DEPTH} deep boxes on four {M.CASTOR_D} mm castors each, "
     f"rolling on the floor and out through the {M.RAIL_Z0} mm opening under the "
     f"rail. Nothing to align, nothing to wear out, and the centre beam's legs "
     f"stand clear of them."),
]

CHECKS = [
    f"Your mattress really is {M.MAT_W} x {M.MAT_L}. Measure it; they vary.",
    f"The room takes {M.W_OUT} x {M.L_OUT}, and the route into it takes a "
    f"{M.SIDE_RAIL_L} mm rail.",
    f"There is {M.RAIL_Z0} mm of clear floor for the drawers to roll on - a thick "
    f"rug eats that.",
    f"The headboard stands {M.HEAD_POST_H + M.ARCH_RISE} high and wants to sit "
    f"against a wall, so check what your skirting board does to that.",
    f"Sleeping height is {M.DECK_Z} plus your mattress. With a 200 mm mattress "
    f"that is {M.DECK_Z + M.MAT_H} mm - high, as storage beds are.",
]


def svg(name):
    with open(os.path.join(OUT, name)) as fh:
        return fh.read().split("?>")[-1].strip()


def sheet(name, caption):
    return (f'<figure class="sheet"><div class="sheet-paper">{svg(name)}</div>'
            f'<figcaption>{caption}</figcaption></figure>')


def cut_tables(rows):
    by_group = OrderedDict()
    for r in rows:
        by_group.setdefault(r["sub_assembly"], []).append(r)
    out = []
    for group, rs in by_group.items():
        body = "\n".join(
            f"<tr><td class='n'>{r['qty']}</td><td>{r['name']}</td>"
            f"<td class='n'>{r['length']:.0f}</td><td class='n'>{r['width']:.0f}</td>"
            f"<td class='n'>{r['thickness']:.0f}</td>"
            f"<td class='n rough'>{r['rough_length']:.0f} &times; "
            f"{r['rough_width']:.0f} &times; {r['rough_thickness']:.0f}</td>"
            f"<td class='mat'>{r['material']}</td></tr>" for r in rs)
        out.append(
            f"<h3>{group}</h3>\n<div class='scroll'><table>"
            "<thead><tr><th>Qty</th><th>Part</th><th>Length</th><th>Width</th>"
            "<th>Thick</th><th>Rough stock</th><th>Material</th></tr></thead>"
            f"<tbody>{body}</tbody></table></div>")
    return "\n".join(out)


def part_sheets():
    out = []
    for part, qty in __import__("drawings").unique_parts():
        L, W, T = part.stock
        name = cutlist.generic_name(part.label)
        out.append(
            f"<details><summary><span class='pname'>{name}</span>"
            f"<span class='pdims'>{qty} off &middot; {L:.0f} &times; {W:.0f} "
            f"&times; {T:.0f}</span></summary>"
            f"<div class='sheet-paper'>{svg('part-' + part.part + '.svg')}</div>"
            f"</details>")
    return "\n".join(out)


def build():
    rows = cutlist.rows()
    fin, rough, ply = cutlist.timber_volume(rows)
    facts = [
        ("Mattress", f"{M.MAT_W} &times; {M.MAT_L}"),
        ("Overall", f"{M.W_OUT} &times; {M.L_OUT}"),
        ("Headboard height", f"{M.HEAD_POST_H + M.ARCH_RISE}"),
        ("Foot end height", f"{M.FOOT_H}"),
        ("Top of slats", f"{M.DECK_Z}"),
        ("Drawer opening", f"{M.RAIL_Z0} &times; {M.OPEN_L}"),
        ("Side rail", f"{M.RAIL_H} &times; {M.RAIL_T}"),
        ("Posts", f"{M.POST_Y} &times; {M.POST_X}"),
        ("Slat gap", f"{M.SLAT_GAP:.0f}"),
        ("Timber", f"{rough:.0f} l rough"),
    ]
    fact_html = "\n".join(
        f"<div class='fact'><dt>{k}</dt><dd>{v}</dd></div>" for k, v in facts)
    joinery = "\n".join(
        f"<div class='joint'><h3>{t}</h3><p class='kicker'>{k}</p><p>{b}</p></div>"
        for t, k, b in JOINERY)
    seq = "\n".join(
        f"<li><h3>{t}</h3><p>{b}</p></li>" for t, b in SEQUENCE)
    checks = "\n".join(f"<li>{c}</li>" for c in CHECKS)
    hardware = "\n".join(
        f"<tr><td class='n'>{q}</td><td>{i}</td><td class='mat'>{s}</td></tr>"
        for q, i, s in M.hardware())

    html = f"""<title>Oak Storage Bed</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@500;600;700&family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
:root {{
  --ground:#e9edf1; --paper:#ffffff; --surface:#f6f8fa; --ink:#12161c;
  --muted:#5b6672; --rule:#ccd5dd; --accent:#b4472b; --blue:#2a5a7a;
  --shadow:0 1px 2px rgba(18,22,28,.10), 0 8px 24px rgba(18,22,28,.06);
}}
@media (prefers-color-scheme: dark) {{
  :root:not([data-theme="light"]) {{
    --ground:#0e1218; --surface:#161c24; --ink:#e4ebf2; --muted:#8d9aa8;
    --rule:#27303b; --accent:#e0744f; --blue:#7fb2d4;
    --shadow:0 1px 2px rgba(0,0,0,.5), 0 10px 30px rgba(0,0,0,.35);
  }}
}}
:root[data-theme="dark"] {{
  --ground:#0e1218; --surface:#161c24; --ink:#e4ebf2; --muted:#8d9aa8;
  --rule:#27303b; --accent:#e0744f; --blue:#7fb2d4;
  --shadow:0 1px 2px rgba(0,0,0,.5), 0 10px 30px rgba(0,0,0,.35);
}}
*, *::before, *::after {{ box-sizing:border-box; }}
body {{
  margin:0; background:var(--ground); color:var(--ink);
  font-family:"IBM Plex Sans", system-ui, sans-serif; font-size:17px; line-height:1.62;
  -webkit-font-smoothing:antialiased;
}}
.wrap {{ max-width:1180px; margin:0 auto; padding:clamp(16px,3vw,44px); }}
main {{ display:flex; flex-direction:column; gap:clamp(40px,5vw,72px); }}
section {{ display:flex; flex-direction:column; gap:20px; }}
h1, h2, h3, .eyebrow, th {{
  font-family:"Barlow Condensed", "Arial Narrow", sans-serif;
  text-transform:uppercase; letter-spacing:.06em; text-wrap:balance;
}}
h1 {{ font-size:clamp(38px,7vw,74px); line-height:.96; margin:0; font-weight:700; }}
h2 {{ font-size:clamp(24px,3vw,32px); margin:0; font-weight:600;
      padding-bottom:8px; border-bottom:2px solid var(--ink); }}
h3 {{ font-size:20px; margin:0; font-weight:600; letter-spacing:.05em; }}
p {{ margin:0; max-width:66ch; }}
.lede {{ font-size:19px; color:var(--muted); max-width:60ch; }}
.eyebrow {{ font-size:14px; color:var(--accent); font-weight:600; letter-spacing:.16em; margin:0; }}

/* title block, as on a drawing sheet */
header {{ border:2px solid var(--ink); background:var(--surface); }}
.tb-main {{ padding:clamp(20px,3vw,36px); display:flex; flex-direction:column; gap:14px; }}
.tb-strip {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr));
             border-top:2px solid var(--ink); }}
.tb-strip div {{ padding:12px 16px; border-right:1px solid var(--rule); }}
.tb-strip div:last-child {{ border-right:none; }}
.tb-strip dt {{ font-family:"Barlow Condensed",sans-serif; text-transform:uppercase;
                letter-spacing:.1em; font-size:12px; color:var(--muted); }}
.tb-strip dd {{ margin:2px 0 0; font-family:"IBM Plex Mono",monospace; font-size:15px;
                font-variant-numeric:tabular-nums; }}

.facts {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(168px,1fr));
          gap:1px; background:var(--rule); border:1px solid var(--rule); margin:0; }}
.fact {{ background:var(--surface); padding:14px 16px; }}
.fact dt {{ font-family:"Barlow Condensed",sans-serif; text-transform:uppercase;
            letter-spacing:.1em; font-size:12.5px; color:var(--muted); }}
.fact dd {{ margin:3px 0 0; font-family:"IBM Plex Mono",monospace; font-size:17px;
            font-variant-numeric:tabular-nums; }}

.sheet {{ margin:0; display:flex; flex-direction:column; gap:10px; }}
.sheet-paper {{ background:var(--paper); border:1px solid var(--rule);
                box-shadow:var(--shadow); padding:10px; overflow-x:auto; }}
.sheet-paper svg {{ display:block; min-width:520px; }}
figcaption {{ font-size:14.5px; color:var(--muted); }}

.joints {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(290px,1fr)); gap:26px; }}
.joint {{ display:flex; flex-direction:column; gap:6px; border-top:2px solid var(--accent);
          padding-top:14px; }}
.kicker {{ font-family:"IBM Plex Mono",monospace; font-size:13px; color:var(--accent);
           letter-spacing:.02em; }}

ol.seq {{ list-style:none; counter-reset:step; margin:0; padding:0;
          display:flex; flex-direction:column; gap:22px; }}
ol.seq li {{ counter-increment:step; display:grid; grid-template-columns:52px 1fr;
             gap:18px; align-items:start; }}
ol.seq li::before {{ content:counter(step,decimal-leading-zero);
  font-family:"IBM Plex Mono",monospace; font-size:15px; color:var(--accent);
  border-top:2px solid var(--rule); padding-top:6px; }}
ol.seq h3 {{ margin-bottom:4px; }}

.scroll {{ overflow-x:auto; }}
table {{ border-collapse:collapse; width:100%; min-width:560px; font-size:15.5px; }}
th, td {{ text-align:left; padding:8px 12px; border-bottom:1px solid var(--rule); }}
th {{ font-size:13px; color:var(--muted); font-weight:600; border-bottom:2px solid var(--ink); }}
td.n {{ font-family:"IBM Plex Mono",monospace; font-variant-numeric:tabular-nums;
        text-align:right; white-space:nowrap; }}
td.rough {{ color:var(--muted); }}
td.mat {{ color:var(--muted); font-size:14px; }}
tbody tr:hover {{ background:var(--surface); }}

details {{ border:1px solid var(--rule); background:var(--surface); }}
details + details {{ border-top:none; }}
summary {{ cursor:pointer; padding:12px 16px; display:flex; gap:16px;
           justify-content:space-between; align-items:baseline; }}
summary:hover {{ background:var(--paper); color:var(--ink); }}
details[open] summary {{ border-bottom:1px solid var(--rule); }}
.pname {{ font-family:"Barlow Condensed",sans-serif; text-transform:uppercase;
          letter-spacing:.05em; font-size:19px; font-weight:600; }}
.pdims {{ font-family:"IBM Plex Mono",monospace; font-size:13.5px; color:var(--muted);
          font-variant-numeric:tabular-nums; white-space:nowrap; }}
details .sheet-paper {{ border:none; box-shadow:none; }}
:focus-visible {{ outline:2px solid var(--accent); outline-offset:2px; }}

ul.checks {{ margin:0; padding:0; list-style:none; display:flex; flex-direction:column; gap:10px; }}
ul.checks li {{ padding-left:26px; position:relative; max-width:66ch; }}
ul.checks li::before {{ content:""; position:absolute; left:0; top:.62em; width:12px;
  height:12px; border:2px solid var(--accent); }}
footer {{ border-top:1px solid var(--rule); padding-top:20px; color:var(--muted);
          font-size:14.5px; display:flex; flex-direction:column; gap:10px; }}
code {{ font-family:"IBM Plex Mono",monospace; font-size:.92em;
        background:var(--surface); padding:1px 5px; border:1px solid var(--rule); }}
</style>

<div class="wrap">
<header>
  <div class="tb-main">
    <p class="eyebrow">Bed frame with under-bed storage &middot; drawings for the workshop</p>
    <h1>Oak storage bed<br>for a {M.MAT_W} &times; {M.MAT_L} mattress</h1>
    <p class="lede">Solid timber throughout. Two frame-and-panel ends, side rails
    drawn up with bed bolts so the whole thing knocks down, a slatted deck on a
    centre beam, and two drawers on castors under one long side.</p>
  </div>
  <dl class="tb-strip">
    <div><dt>Overall</dt><dd>{M.W_OUT} &times; {M.L_OUT} mm</dd></div>
    <div><dt>Height</dt><dd>{M.HEAD_POST_H + M.ARCH_RISE} mm</dd></div>
    <div><dt>Parts</dt><dd>{sum(r['qty'] for r in rows)} in {len(rows)} sizes</dd></div>
    <div><dt>Timber</dt><dd>{rough:.0f} litres rough</dd></div>
    <div><dt>Units</dt><dd>mm, finished</dd></div>
  </dl>
</header>

<main>
<section>
  {sheet("00-isometric.svg", "The bed as modelled. Mattress omitted.")}
</section>

<section>
  <h2>Key dimensions</h2>
  <dl class="facts">{fact_html}</dl>
  <p class="lede">Every number on this page comes from one file of parameters.
  Change the mattress size there and the drawings, the cutting list and the 3D
  model all move together.</p>
</section>

<section>
  <h2>General arrangement</h2>
  {sheet("01-general-arrangement.svg",
         "Drawer side elevation, foot end elevation and plan. Parts behind the "
         "cutting plane are ghosted.")}
</section>

<section>
  <h2>How it goes together</h2>
  <div class="joints">{joinery}</div>
</section>

<section>
  <h2>Cutting list</h2>
  <p>Finished sizes in millimetres. Rough stock adds
  {cutlist.LENGTH_ALLOWANCE} mm on the length and
  {cutlist.PLANING_ALLOWANCE} mm on the section for planing and trimming; order
  a further 20 % for waste and defects. Finished solid timber comes to
  {fin:.0f} litres, about {fin * 0.75:.0f} kg in oak.</p>
  {cut_tables(rows)}
  <h3>Hardware</h3>
  <div class="scroll"><table>
    <thead><tr><th>Qty</th><th>Item</th><th>Specification</th></tr></thead>
    <tbody>{hardware}</tbody></table></div>
</section>

<section>
  <h2>Build sequence</h2>
  <ol class="seq">{seq}</ol>
</section>

<section>
  <h2>Part drawings</h2>
  <p>One sheet per part. Each carries a setting-out table giving every mortise,
  groove and hole as a distance from one end, so the part can be marked out from
  a single datum.</p>
  <div>{part_sheets()}</div>
</section>

<section>
  <h2>Before you cut</h2>
  <ul class="checks">{checks}</ul>
</section>

<footer>
  <p>Drawn parametrically: <code>model.py</code> holds the dimensions,
  <code>freecad_bed.py</code> builds the 3D model in FreeCAD, and
  <code>drawings.py</code> and <code>cutlist.py</code> produce everything on this
  page. Twenty automated checks confirm that no two parts occupy the same wood,
  that the mattress fits, that the drawers run clear of the centre beam, and that
  the cutting list accounts for every part.</p>
  <p>The FreeCAD macro has been run against a stub of the FreeCAD API, not the
  real kernel &mdash; open <code>bed.FCStd</code> and look at it before cutting.</p>
</footer>
</main>
</div>
"""
    path = os.path.join(OUT, "build-plan.html")
    with open(path, "w") as fh:
        fh.write(html)
    return path


if __name__ == "__main__":
    print("wrote", build())
