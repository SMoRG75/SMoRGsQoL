"""Build independent localized showcase videos from the specified recording."""
import json
import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.stdout.reconfigure(encoding='utf-8')

ROOT = Path(__file__).resolve().parent
WORK = ROOT / 'work'
RAW = Path(r'C:\Users\san\Videos\NVIDIA\World Of Warcraft\World Of Warcraft 2026.10.12 - 21.10.24.01.mp4')
GAME = '2400:1350:516:32'
SEGMENTS = [
    ('intro', None, 5.5, None),
    ('objective', 107.5, 7, GAME),
    ('quest', 175.5, 7, GAME),
    ('horde', 214, 5, '1120:630:1150:260'),
    ('nameplates', 265, 7, '1600:900:1030:90'),
    ('progress', 288, 6, '1600:900:1030:90'),
    ('complete', 294, 8, GAME),
    ('autotrack', 33, 8, GAME),
    ('stats', 84, 6, '1440:810:800:550'),
    ('bars', 300.5, 6, '960:540:1200:840'),
    ('tooltip', 378, 6, '1200:675:1716:705'),
    ('ach_before', 344, 4.5, '1440:810:516:240'),
    ('ach_after', 357.5, 4.5, '1440:810:516:240'),
    ('cursor', 337, 6, GAME),
    ('options', 311, 6, '1120:630:1150:260'),
    ('outro', None, 7, None),
]
LANGS = {
    'enUS': ('English', 'eng', 'Segoe UI', 'segoeui.ttf'),
    'deDE': ('Deutsch', 'deu', 'Segoe UI', 'segoeui.ttf'),
    'frFR': ('Français', 'fra', 'Segoe UI', 'segoeui.ttf'),
    'esES': ('Español (España)', 'spa', 'Segoe UI', 'segoeui.ttf'),
    'esMX': ('Español (Latinoamérica)', 'spa', 'Segoe UI', 'segoeui.ttf'),
    'ptBR': ('Português (Brasil)', 'por', 'Segoe UI', 'segoeui.ttf'),
    'itIT': ('Italiano', 'ita', 'Segoe UI', 'segoeui.ttf'),
    'ruRU': ('Русский', 'rus', 'Segoe UI', 'segoeui.ttf'),
    'koKR': ('한국어', 'kor', 'Malgun Gothic', 'malgun.ttf'),
    'zhCN': ('简体中文', 'zho', 'Microsoft YaHei', 'msyh.ttc'),
    'zhTW': ('繁體中文', 'zho', 'Microsoft JhengHei', 'msjh.ttc'),
}

def write_text(path, text):
    with path.open('w', encoding='utf-8', newline='\r\n') as file:
        file.write(text)

def run(args, log):
    with (WORK / log).open('w', encoding='utf-8') as output:
        subprocess.run(['ffmpeg', '-hide_banner', '-y', *args], cwd=ROOT,
                       stdout=output, stderr=subprocess.STDOUT, check=True)

def card(name):
    image = Image.new('RGB', (1920, 1080), '#0b1421')
    draw = ImageDraw.Draw(image)
    for y in range(936):
        glow = max(0, 1 - abs(y - 410) / 520)
        draw.line((0, y, 1920, y), fill=(11+int(5*glow),20+int(12*glow),33+int(17*glow)))
    icon = Image.open(ROOT.parent / 'smorgsqol.png').convert('RGBA')
    icon.thumbnail((290,290), Image.Resampling.LANCZOS)
    image.paste(icon, ((1920-icon.width)//2, 135), icon)
    title_font = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', 100)
    small_font = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', 31)
    draw.text((960,500), "SMoRG's QoL", anchor='mm', font=title_font, fill='#e8c77a')
    draw.line((560,595,1360,595),fill='#58b9ad',width=3)
    draw.text((960,650), 'RETAIL  /  WOW FOREVER', anchor='mm', font=small_font, fill='#c7d6e2')
    footer = 'v1.2.0' if name == 'intro' else 'CurseForge  ·  Wago Addons  ·  WoWInterface  ·  GitHub Releases'
    draw.text((960,743), footer, anchor='mm', font=small_font, fill='#c7d6e2')
    image.save(WORK / f'{name}.png')

def master():
    WORK.mkdir(exist_ok=True)
    for index, (name, start, duration, crop) in enumerate(SEGMENTS):
        print(f'Building scene {index+1}/{len(SEGMENTS)}: {name}', flush=True)
        destination = WORK / f'{index:02}-{name}.mp4'
        if start is None:
            card(name)
            inputs = ['-loop','1','-framerate','30','-i',str(WORK/f'{name}.png'),
                      '-f','lavfi','-i','anullsrc=r=48000:cl=stereo']
            filters = 'format=yuv420p'
        else:
            inputs = ['-ss',str(start),'-i',str(RAW)]
            filters = f'crop={crop},scale=1664:936:flags=lanczos,fps=30,pad=1920:1080:128:0:color=0x0b1421,setsar=1,format=yuv420p'
        run([*inputs,'-t',str(duration),'-vf',filters,
             '-af',f'afade=t=in:d=0.025,afade=t=out:st={duration-0.04}:d=0.04',
             '-c:v','h264_nvenc','-preset','p5','-rc','vbr','-cq','18','-b:v','0',
             '-c:a','aac','-b:a','192k','-ar','48000','-ac','2',
             '-video_track_timescale','90000',str(destination)], f'{name}.log')
    paths = [f"file '{i:02}-{s[0]}.mp4'" for i,s in enumerate(SEGMENTS)]
    write_text(WORK/'concat.txt', '\n'.join(paths)+'\n')
    run(['-f','concat','-safe','0','-i',str(WORK/'concat.txt'),'-c','copy',
         '-movflags','+faststart',str(WORK/'master.mp4')], 'master.log')
    print('Master ready', flush=True)

def ass_time(seconds):
    centis = round(seconds*100)
    return f'{centis//360000}:{centis//6000%60:02}:{centis//100%60:02}.{centis%100:02}'

def srt_time(seconds):
    ms = round(seconds*1000)
    return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'

def wrap(text, fontfile, size, maxwidth=1720):
    font = ImageFont.truetype('C:/Windows/Fonts/'+fontfile, size)
    words = text.split(' ') if ' ' in text else list(text)
    separator = ' ' if ' ' in text else ''
    lines=[]; current=''
    for word in words:
        candidate = current + separator + word if current else word
        if font.getlength(candidate) > maxwidth and current:
            lines.append(current); current=word
        else:
            current=candidate
    if current: lines.append(current)
    if len(lines)>2:
        raise ValueError(f'Caption exceeds two lines: {text}')
    return lines

def subtitles(code, captions):
    label,iso,font,fontfile = LANGS[code]
    header = f'''[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Heading,{font},32,&H007AC7E8,&H000000FF,&H0021140B,&H00000000,-1,0,0,0,100,100,0,0,1,0,0,8,90,90,944,1
Style: Body,{font},34,&H00F2F1ED,&H000000FF,&H0021140B,&H00000000,0,0,0,0,100,100,0,0,1,0,0,8,90,90,990,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
'''
    events=[]; srt=[]; position=0
    assert len(captions)==len(SEGMENTS)
    for i, (segment, caption) in enumerate(zip(SEGMENTS,captions)):
        name,source,duration,crop=segment
        title,body=caption
        start=position+0.12;end=position+duration-0.08
        lines=wrap(body,fontfile,34)
        if ImageFont.truetype('C:/Windows/Fonts/'+fontfile,32).getlength(title)>1720:
            raise ValueError('Heading too wide: '+title)
        events.append(f'Dialogue: 0,{ass_time(start)},{ass_time(end)},Heading,,0,0,0,,{title}')
        events.append(f'Dialogue: 0,{ass_time(start)},{ass_time(end)},Body,,0,0,0,,'+r'\N'.join(lines))
        srt.append(f'{i+1}\n{srt_time(start)} --> {srt_time(end)}\n{title}\n{body}\n')
        position += duration
    write_text(ROOT/'subtitles'/f'{code}.ass',header+'\n'.join(events)+'\n')
    write_text(ROOT/'subtitles'/f'{code}.srt','\n'.join(srt))

def localize():
    captions=json.loads((ROOT/'captions.json').read_text(encoding='utf-8'))
    assert set(captions)==set(LANGS)
    for code in LANGS: subtitles(code,captions[code])
    for code,(label,iso,font,fontfile) in LANGS.items():
        if '--only' in sys.argv and code not in sys.argv[sys.argv.index('--only')+1].split(','):
            continue
        print(f'Rendering {code}: {label}',flush=True)
        temporary = WORK / f'finished-{code}.mp4'
        run(['-i',str(WORK/'master.mp4'),'-vf',f'ass=subtitles/{code}.ass',
             '-c:v','h264_nvenc','-preset','p5','-rc','vbr','-cq','19','-b:v','0',
             '-pix_fmt','yuv420p','-c:a','copy','-movflags','+faststart',
             '-metadata',f'title=SMoRG\'s QoL — {label}',
             '-metadata:s:v:0',f'language={iso}',
             '-metadata:s:a:0','language=eng',
             str(temporary)],f'render-{code}.log')
        temporary.replace(ROOT/f'SMoRGsQoL-{code}.mp4')
        print(f'Finished {code}',flush=True)

if __name__ == '__main__':
    if '--master' in sys.argv: master()
    elif '--localize' in sys.argv: localize()
    else:
        master(); localize()
