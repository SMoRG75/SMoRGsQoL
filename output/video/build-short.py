"""Renders a ~20 s YouTube Short (1080x1920/60) from the 2026-10-18 recording.

Output: output/video/SMoRGsQoL-short-workwork.mp4

Three quest objectives finished in Eversong Woods, each with the peon's
"Work, work.", then the social image as end card. The recording is a
3440x1440/60 HDR (PQ, BT.2020) desktop capture of the game in full screen; it
is converted to SDR with a 240 nit reference white, which matches the game's
own SDR look. The 810x1440 center crop is scaled 1.33x, so UI text stays sharp.

Audio: game audio ducked to 55 % outside each voice line, short fades, then
one measured gain to -16 LUFS and a -1.5 dBFS limiter. The fade-in and the
fixed gain keep the first second from blasting, which the single-pass
loudnorm in the promo short did.

The recording is not in git. Pass another path as the first argument.
Needs ffmpeg 8+ with zscale. Run from anywhere: python output/video/build-short.py
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")
FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
RAW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, "World Of Warcraft 2026.10.18 - 22.53.09.01.mp4")
OUT = os.path.join(HERE, "SMoRGsQoL-short-workwork.mp4")
MASTER = os.path.join(BUILD, "short-master.mkv")

CROP = "810:1440:1316:0"  # character, the green "...: 1/1" text, player frame
TONEMAP = ("zscale=tin=smpte2084:min=bt2020nc:pin=bt2020:rin=tv:t=linear:npl=240,"
           "format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=clip:desat=0,"
           "zscale=t=bt709:m=bt709:r=tv,format=yuv420p")
FONT = "C\\:/Windows/Fonts/palab.ttf"
GOLD = "0xE8C46A"

# (source start s, duration s, voice onset relative to start, top caption id).
# "Work, work." starts at 277.83 s (Tak'lejo and Halduron assisted: 1/1),
# 376.53 s (Liadrin and Orweyna assisted: 1/1) and 520.54 s (Interlocked
# Twilight Runes: 1/1, during the Kursak fight).
SEGMENTS = [
    (274.6, 6.0, 3.23, "hook"),
    (374.3, 5.0, 2.23, "every"),
    (518.3, 5.5, 2.24, "fight"),
]
END = 4.0
CAPTIONS = {
    "hook": "Finish a quest\nobjective in WoW...",
    "every": "Every. Single. One.",
    "fight": "Even mid-boss fight.",
    "quote": "“Work, work.”",
    "search": "Search: SMoRGs QoL",
}


def textfile(key):
    path = os.path.join(BUILD, f"short-{key}.txt")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(CAPTIONS[key])
    return "build/short-" + key + ".txt"


def drawtext(key, size, y, start, end, color=GOLD, box=False):
    extra = ":box=1:boxcolor=black@0.55:boxborderw=24" if box else ""
    return (f"drawtext=fontfile='{FONT}':textfile='{textfile(key)}':fontsize={size}"
            f":fontcolor={color}:borderw=6:bordercolor=black@0.9"
            f":shadowx=4:shadowy=4:shadowcolor=black@0.6{extra}"
            f":text_align=center:line_spacing=10"
            f":x=(w-tw)/2:y={y}:enable='between(t,{start},{end})'")


def duck(voice):
    # Game audio at 55 % except a ramped window around the voice line, so the
    # peon is the loudest thing in each clip.
    ramp = f"max(0,min(1,min((t-{voice - 0.35})/0.2,({voice + 1.5}-t)/0.3)))"
    return f"volume=volume='0.55+0.45*{ramp}':eval=frame"


def build_filter():
    lines = []
    for i, (_, dur, voice, cap) in enumerate(SEGMENTS):
        texts = [drawtext(cap, 70, 150, 0.15, dur, color="white", box=True),
                 drawtext("quote", 128, 1110, voice - 0.05, min(voice + 1.9, dur))]
        lines.append(f"[{i}:v]setpts=PTS-STARTPTS,crop={CROP},{TONEMAP},"
                     f"scale=1080:1920:flags=lanczos,fps=60,setsar=1,{','.join(texts)}[v{i}];")
        fade_in = 0.6 if i == 0 else 0.08
        fade_out = 0.8 if i == len(SEGMENTS) - 1 else 0.08
        lines.append(f"[{i}:a]asetpts=PTS-STARTPTS,aresample=48000,{duck(voice)},"
                     f"afade=t=in:d={fade_in},afade=t=out:st={dur - fade_out}:d={fade_out}[a{i}];")
    n = len(SEGMENTS)
    lines += [
        f"[{n}:v]split[sbg][sfg];",
        "[sbg]scale=3400:3400,crop=1080:1920,boxblur=30:2,eq=brightness=-0.08:saturation=0.9[sblur];",
        "[sfg]scale=1080:1080:flags=lanczos[ssq];",
        "[sblur][ssq]overlay=x=0:y=(H-h)/2-160,setsar=1,fps=60,format=yuv420p,"
        f"{drawtext('search', 92, 1360, 0.3, END)},fade=t=in:st=0:d=0.35[v{n}];",
        f"[{n + 1}:a]anull[a{n}];",
        "".join(f"[v{i}][a{i}]" for i in range(n + 1)) + f"concat=n={n + 1}:v=1:a=1[v][a]",
    ]
    path = os.path.join(BUILD, "short.filter")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    return path


def run(args, **kw):
    print(" ".join(a if " " not in a else f'"{a}"' for a in args[:6]), "...")
    return subprocess.run(args, cwd=HERE, check=True, **kw)


def main():
    os.makedirs(BUILD, exist_ok=True)
    inputs = []
    for start, dur, _, _ in SEGMENTS:
        inputs += ["-ss", str(start), "-t", str(dur), "-i", RAW]
    inputs += ["-loop", "1", "-t", str(END), "-i", "../promo/smorgsqol-social.png",
               "-f", "lavfi", "-t", str(END), "-i", "anullsrc=r=48000:cl=stereo"]
    run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *inputs,
         "-/filter_complex", build_filter(), "-map", "[v]", "-map", "[a]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p",
         "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
         "-c:a", "pcm_s16le", MASTER])

    # Measure, then one fixed gain to -16 LUFS and a peak limiter at -1.5 dBFS.
    # loudnorm's linear mode would give up (the gain pushes combat transients
    # over the ceiling) and fall back to dynamic mode, which squashes the
    # voice lines back down to the level of the fighting around them.
    probe = run([FFMPEG, "-hide_banner", "-nostats", "-i", MASTER, "-vn",
                 "-af", "loudnorm=print_format=json", "-f", "null", "-"],
                capture_output=True, text=True).stderr
    m = json.loads(probe[probe.rindex("{"):probe.rindex("}") + 1])
    gain = -16 - float(m["input_i"])
    print(f"input {m['input_i']} LUFS, {m['input_tp']} dBTP; gain {gain:+.2f} dB")
    af = f"volume={gain:.2f}dB,alimiter=limit=0.84:attack=5:release=60:level=false"
    run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", MASTER,
         "-c:v", "copy", "-af", af, "-c:a", "aac", "-b:a", "192k",
         "-movflags", "+faststart", OUT])
    print("wrote", OUT)


if __name__ == "__main__":
    main()
