"""Decode and inspect every delivered language version and subtitle file."""
import concurrent.futures
import json
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from build_videos import ROOT, LANGS, SEGMENTS, write_text

def verify(code):
    video=ROOT/f'SMoRGsQoL-{code}.mp4'
    data=json.loads(subprocess.check_output([
        'ffprobe','-v','error','-show_format','-show_streams','-of','json',str(video)
    ],encoding='utf-8'))
    stream=next(s for s in data['streams'] if s['codec_type']=='video')
    sound=next(s for s in data['streams'] if s['codec_type']=='audio')
    assert stream['codec_name']=='h264'
    assert (stream['width'],stream['height'])==(1920,1080)
    assert stream['pix_fmt']=='yuv420p'
    assert stream['r_frame_rate']=='30/1'
    assert int(stream['nb_frames'])==round(sum(s[2] for s in SEGMENTS)*30)
    assert sound['codec_name']=='aac' and sound['channels']==2
    assert abs(float(data['format']['duration'])-99.5)<0.1
    subprocess.run(['ffmpeg','-v','error','-xerror','-threads','2','-i',str(video),
                    '-map','0:v:0','-map','0:a:0','-f','null','-'],check=True,
                   stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    for extension in ['ass','srt']:
        raw=(ROOT/'subtitles'/f'{code}.{extension}').read_bytes()
        assert b'\r\n' in raw and b'\n' not in raw.replace(b'\r\n',b'')
        raw.decode('utf-8')
    for moment in [2,83.5]:
        subprocess.run(['ffmpeg','-v','error','-ss',str(moment),'-i',str(video),
                        '-frames:v','1','-vf','scale=960:540','-update','1','-y',
                        str(ROOT/'work'/f'qa-{code}-{moment}.png')],check=True,
                       stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    print(f'Verified {code}',flush=True)
    return {'locale':code,'language':LANGS[code][0],'file':video.name,
            'bytes':video.stat().st_size,'duration':float(data['format']['duration']),
            'resolution':'1920x1080','fps':30,'video_codec':'H.264',
            'audio_codec':'AAC stereo','full_decode':'passed','utf8_crlf_subtitles':'passed'}

if __name__=='__main__':
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(verify,LANGS))
    write_text(ROOT/'verification.json',json.dumps(results,ensure_ascii=False,indent=2)+'\n')
    font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',25)
    for moment in [2,83.5]:
        for page in range(3):
            codes=list(LANGS)[page*4:(page+1)*4]
            sheet=Image.new('RGB',(1920,2*580),'#0b1421')
            draw=ImageDraw.Draw(sheet)
            for i,code in enumerate(codes):
                x=i%2*960;y=i//2*580
                sheet.paste(Image.open(ROOT/'work'/f'qa-{code}-{moment}.png'),(x,y))
                draw.text((x+20,y+545),code,font=font,fill='white')
            sheet.save(ROOT/'work'/f'languages-{moment}-{page+1}.jpg',quality=94)
    print('All eleven videos passed complete decoding and format checks.',flush=True)
