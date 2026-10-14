"""Renders the ~75 s feature showcase from the raw gameplay recording.

Outputs in output/video/showcase/:
  SMoRGsQoL-showcase.mp4        clean video, all languages as soft subtitles
  SMoRGsQoL-showcase-<lang>.mp4 subtitles burned in (Reddit, Discord, X ...)
  subs/<lang>.srt               for YouTube's subtitle upload
  subs/<lang>.ass               styled subtitles used for the burned versions

There is no voice-over: the worker voice lines are the headline feature, so
the game audio stays untouched and the captions do the talking.

The recording (a 3440x1440/60 fps SDR desktop capture with the game in a
2406x1353 window at 516,31) is not in git. Pass another path as the first
argument or set SHOWCASE_RAW. Needs ffmpeg 8+ with libass.
The output is 2560x1440/60 fps (YouTube streams 1440p at a much higher bitrate
than 1080p). No crop is scaled up more than about 2.2x, so the UI text stays sharp.
Run from anywhere: python output/video/build-showcase.py [raw.mp4]
  --only en,da     burn only these languages
  --reuse-master   skip the cut step and reuse build/showcase-master.mp4
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "showcase")
SUBS = os.path.join(OUT, "subs")
BUILD = os.path.join(HERE, "build")
FFMPEG = os.environ.get("FFMPEG", "ffmpeg")
DEFAULT_RAW = os.path.join(HERE, "World Of Warcraft 2026.10.12 - 21.10.24.01.mp4")

# (id, source start s, duration s, crop w:h:x:y in the 3440x1440 source).
# Every crop is 16:9 and is scaled to 2560x1440. GAME is the whole game window.
GAME = "2406:1353:516:31"
WINDOW = "1280:720:1065:250"  # the options window
ACH = "1280:720:516:56"       # the achievement panel
BARS = "1152:648:1140:736"    # player frame, action bars, XP/rep bars
SEGMENTS = [
    ("title", 59.5, 4.5, GAME),                       # running north with Garrick, blurred
    ("morework", 106.5, 5.5, GAME),                   # "Tamed Beast learned 1/1" -> "More work?"
    ("jobsdone", 175.0, 6.0, GAME),                   # goat tamed, quest done -> "Job's done!"
    ("horde", 214.0, 4.0, WINDOW),                    # sound profile switched to Horde (Peon)
    ("nameplates", 265.0, 4.5, "1280:720:1186:0"),    # 1/7 and 5-40 yd on the target
    ("colors", 288.5, 5.0, "1600:900:990:0"),         # green "Quilboar slain 6/7"
    ("workcomplete", 293.5, 6.5, GAME),               # 7/7 -> "Work complete."
    ("autotrack", 47.5, 5.0, "1152:648:516:736"),     # chat: "And SQoL auto-tracked it"
    ("ilvl", 72.0, 5.0, "1280:720:825:468"),          # item level and speed switched on
    ("bars_before", 205.5, 2.0, BARS),                # plain XP/rep text
    ("bars_after", 300.5, 4.0, BARS),                 # colored numbers, % left, standing
    ("tooltip", 378.2, 4.0, "1280:720:1642:664"),     # "Target: You"
    ("ach_before", 344.5, 4.5, ACH),                  # completed achievements everywhere
    ("ach_after", 357.3, 3.7, ACH),                   # only the unearned one
    ("options", 312.5, 5.0, WINDOW),                  # ready check, queue pop, party tooltips
    ("end", None, 5.0, None),                         # promo banner
]

LANGS = [
    # code, ISO 639-2, track title, font
    ("en", "eng", "English", "Segoe UI"),
    ("da", "dan", "Dansk", "Segoe UI"),
    ("de", "ger", "Deutsch", "Segoe UI"),
    ("fr", "fre", "Français", "Segoe UI"),
    ("es", "spa", "Español", "Segoe UI"),
    ("pt-BR", "por", "Português (Brasil)", "Segoe UI"),
    ("it", "ita", "Italiano", "Segoe UI"),
    ("ru", "rus", "Русский", "Segoe UI"),
    ("ko", "kor", "한국어", "Malgun Gothic"),
    ("zh-CN", "chi", "简体中文", "Microsoft YaHei"),
    ("zh-TW", "chi", "繁體中文", "Microsoft JhengHei"),
]

# (segment, start, end relative to the segment, style, caption id). A cue may
# run on into the next segment. Source event times: objective text 108.8 s and
# "More work?" 109.4 s; "Job's done!" 178.8 s; 7/7 at 296.6 s, "Work complete." 296.9 s.
CUES = [
    ("title", 0.4, 2.5, "Tag", "c1"),
    ("title", 2.5, 4.5, "Tag", "c2"),
    ("morework", 0.2, 2.6, "Cap", "c3"),
    ("morework", 2.6, 5.5, "Cap", "c4"),
    ("jobsdone", 0.2, 3.4, "Cap", "c5"),
    ("jobsdone", 3.4, 6.0, "Cap", "c6"),
    ("horde", 0.0, 4.0, "Cap", "c7"),
    ("nameplates", 0.0, 4.5, "Cap", "c8"),
    ("colors", 0.0, 5.0, "Cap", "c9"),
    ("workcomplete", 0.0, 3.2, "Cap", "c10"),
    ("workcomplete", 3.2, 6.5, "Cap", "c11"),
    ("autotrack", 0.0, 5.0, "CapTop", "c12"),
    ("ilvl", 0.0, 5.0, "CapTop", "c13"),
    ("bars_before", 0.0, 6.0, "CapTop", "c14"),
    ("tooltip", 0.0, 4.0, "Cap", "c15"),
    ("ach_before", 0.0, 4.5, "Cap", "c16"),
    ("ach_after", 0.0, 3.7, "Cap", "c17"),
    ("options", 0.0, 5.0, "Cap", "c18"),
    ("end", 0.2, 2.6, "Cap", "c19"),
    ("end", 2.6, 5.0, "Cap", "c20"),
]

# {{...}} marks a quoted voice line; it is drawn in gold in the burned versions.
TEXT = {
    "en": {
        "c1": "Auto-repair. Auto-loot. Selling junk. Your UI already does that.",
        "c2": "SMoRG's QoL does the little things nobody else does.",
        "c3": "Finish a quest objective…",
        "c4": "…and the Human worker asks: {{“More work?”}}",
        "c5": "Finish the whole quest…",
        "c6": "{{“Job's done!”}} Ready to turn in.",
        "c7": "Playing Horde? Switch to the Peon.",
        "c8": "Above the mob: your quest count (1/7) and your range in yards.",
        "c9": "Progress messages go from red through yellow to green.",
        "c10": "The last quilboar…",
        "c11": "{{“Work complete.”}} Each sound has its own on/off switch.",
        "c12": "New quests are tracked automatically.",
        "c13": "Item level and speed on your player frame.",
        "c14": "Colored XP and rep numbers. The rep bar shows % left and standing.",
        "c15": "Tooltips show who a unit is targeting. Here: you.",
        "c16": "Achievements usually open on a wall of finished ones…",
        "c17": "…now they open on the ones you haven't earned yet.",
        "c18": "Ready check and queue pop timers, party levels: every tweak is its own checkbox.",
        "c19": "Also inside: floating rep gains, cursor shake highlight, a hand-drawn combat font.",
        "c20": "Free for Retail and WoW Forever. Search for “SMoRGs QoL”.",
    },
    "da": {
        "c1": "Auto-reparation. Auto-loot. Sælg skrammel. Det klarer din UI allerede.",
        "c2": "SMoRG's QoL gør de små ting, som ingen andre gør.",
        "c3": "Fuldfør et quest-mål…",
        "c4": "…og Human worker spørger: {{“More work?”}}",
        "c5": "Fuldfør hele questen…",
        "c6": "{{“Job's done!”}} Klar til at aflevere.",
        "c7": "Spiller du Horde? Skift til Peon.",
        "c8": "Over monstret: din quest-tæller (1/7) og afstanden i yards.",
        "c9": "Fremskridt skifter farve fra rød over gul til grøn.",
        "c10": "Den sidste quilboar…",
        "c11": "{{“Work complete.”}} Hver lyd slås til og fra for sig.",
        "c12": "Nye quests bliver tracket automatisk.",
        "c13": "Item level og fart på din spillerramme.",
        "c14": "Farvede XP- og rep-tal. Rep-baren viser % tilbage og standing.",
        "c15": "Tooltips viser, hvem en enhed har i target. Her: dig.",
        "c16": "Achievements åbner normalt med en mur af færdige…",
        "c17": "…nu åbner de på dem, du mangler.",
        "c18": "Nedtælling til ready check og kø, gruppens levels: hver finesse har sin egen boks.",
        "c19": "Også med: svævende rep, markør der lyser op, når du ryster musen, håndtegnet kampskrift.",
        "c20": "Gratis til Retail og WoW Forever. Søg efter “SMoRGs QoL”.",
    },
    "de": {
        "c1": "Auto-Reparatur. Auto-Plündern. Schrott verkaufen. Kann dein UI längst.",
        "c2": "SMoRG's QoL macht die kleinen Dinge, die sonst keiner macht.",
        "c3": "Schließ ein Questziel ab…",
        "c4": "…und der menschliche Arbeiter fragt: {{„More work?“}}",
        "c5": "Schließ die ganze Quest ab…",
        "c6": "{{„Job's done!“}} Bereit zum Abgeben.",
        "c7": "Du spielst Horde? Nimm den Peon.",
        "c8": "Über dem Gegner: dein Questzähler (1/7) und deine Entfernung zu ihm.",
        "c9": "Fortschrittsmeldungen wechseln von Rot über Gelb zu Grün.",
        "c10": "Der letzte Stacheleber…",
        "c11": "{{„Work complete.“}} Jeder Sound lässt sich einzeln abschalten.",
        "c12": "Neue Quests werden automatisch verfolgt.",
        "c13": "Gegenstandsstufe und Tempo am Spielerrahmen.",
        "c14": "Farbige EP- und Rufzahlen. Die Rufleiste zeigt % übrig und Rufstufe.",
        "c15": "Tooltips zeigen, wen eine Einheit anvisiert. Hier: dich.",
        "c16": "Erfolge öffnen sich sonst mit einer Wand aus erledigten…",
        "c17": "…jetzt mit denen, die dir noch fehlen.",
        "c18": "Countdowns für Bereitschaftscheck und Warteschlange, Gruppenstufen: jede Verbesserung hat ihr eigenes Häkchen.",
        "c19": "Außerdem: schwebende Rufgewinne, Cursor-Hervorhebung beim Schütteln, handgezeichnete Kampfschrift.",
        "c20": "Kostenlos für Retail und WoW Forever. Such nach „SMoRGs QoL“.",
    },
    "fr": {
        "c1": "Réparation auto. Butin auto. Vente des déchets. Votre interface le fait déjà.",
        "c2": "SMoRG's QoL fait les petites choses que personne d'autre ne fait.",
        "c3": "Terminez un objectif de quête…",
        "c4": "…et le paysan humain demande : {{« More work? »}}",
        "c5": "Terminez toute la quête…",
        "c6": "{{« Job's done! »}} Prête à être rendue.",
        "c7": "Vous jouez Horde ? Choisissez le péon.",
        "c8": "Au-dessus du monstre : votre compteur de quête (1/7) et la distance qui vous en sépare.",
        "c9": "Les messages de progression passent du rouge au jaune puis au vert.",
        "c10": "Le dernier huran…",
        "c11": "{{« Work complete. »}} Chaque son s'active ou se coupe séparément.",
        "c12": "Les nouvelles quêtes sont suivies automatiquement.",
        "c13": "Niveau d'objet et vitesse sur votre cadre de joueur.",
        "c14": "Chiffres d'XP et de réputation en couleur. La barre de réputation affiche le % restant et le rang.",
        "c15": "Les infobulles montrent qui une unité cible. Ici : vous.",
        "c16": "D'habitude, les hauts faits s'ouvrent sur un mur de hauts faits terminés…",
        "c17": "…désormais, sur ceux qu'il vous reste à obtenir.",
        "c18": "Comptes à rebours de l'appel et de la file, niveaux du groupe : chaque option a sa propre case.",
        "c19": "Aussi : gains de réputation flottants, curseur mis en évidence quand on secoue la souris, police de combat manuscrite.",
        "c20": "Gratuit pour Retail et WoW Forever. Cherchez « SMoRGs QoL ».",
    },
    "es": {
        "c1": "Autorreparar. Autodespojar. Vender chatarra. Tu interfaz ya lo hace.",
        "c2": "SMoRG's QoL hace las pequeñas cosas que nadie más hace.",
        "c3": "Completa un objetivo de misión…",
        "c4": "…y el trabajador humano pregunta: {{«More work?»}}",
        "c5": "Completa la misión entera…",
        "c6": "{{«Job's done!»}} Lista para entregar.",
        "c7": "¿Juegas con la Horda? Cambia al peón.",
        "c8": "Sobre el enemigo: tu contador de misión (1/7) y a qué distancia está.",
        "c9": "Los mensajes de progreso pasan de rojo a amarillo y a verde.",
        "c10": "El último jabaespín…",
        "c11": "{{«Work complete.»}} Cada sonido se activa o desactiva por separado.",
        "c12": "Las misiones nuevas se siguen automáticamente.",
        "c13": "Nivel de objeto y velocidad en tu marco de jugador.",
        "c14": "Números de experiencia y reputación en color. La barra de reputación muestra el % restante y el nivel.",
        "c15": "Las descripciones muestran a quién apunta una unidad. Aquí: a ti.",
        "c16": "Los logros suelen abrirse con un muro de logros terminados…",
        "c17": "…ahora se abren en los que aún te faltan.",
        "c18": "Cuentas atrás de comprobación y de cola, niveles del grupo: cada mejora tiene su propia casilla.",
        "c19": "Además: reputación flotante, cursor resaltado al agitar el ratón, fuente de combate dibujada a mano.",
        "c20": "Gratis para Retail y WoW Forever. Busca «SMoRGs QoL».",
    },
    "pt-BR": {
        "c1": "Reparo automático. Saque automático. Vender lixo. Sua interface já faz isso.",
        "c2": "O SMoRG's QoL faz as pequenas coisas que ninguém mais faz.",
        "c3": "Conclua um objetivo de missão…",
        "c4": "…e o trabalhador humano pergunta: {{“More work?”}}",
        "c5": "Conclua a missão inteira…",
        "c6": "{{“Job's done!”}} Pronta para entregar.",
        "c7": "Joga de Horda? Troque para o peão.",
        "c8": "Acima do inimigo: seu contador de missão (1/7) e a que distância ele está.",
        "c9": "As mensagens de progresso vão do vermelho ao amarelo e ao verde.",
        "c10": "O último javatusco…",
        "c11": "{{“Work complete.”}} Cada som liga e desliga separadamente.",
        "c12": "Missões novas são rastreadas automaticamente.",
        "c13": "Nível de item e velocidade no seu quadro de jogador.",
        "c14": "Números de XP e reputação coloridos. A barra de reputação mostra o % restante e o nível.",
        "c15": "As dicas mostram quem a unidade está mirando. Aqui: você.",
        "c16": "As conquistas costumam abrir num paredão de conquistas concluídas…",
        "c17": "…agora abrem nas que ainda faltam.",
        "c18": "Contagens regressivas de prontidão e de fila, níveis do grupo: cada ajuste tem sua própria caixa.",
        "c19": "Também: reputação flutuante, cursor destacado ao chacoalhar o mouse, fonte de combate desenhada à mão.",
        "c20": "Grátis para Retail e WoW Forever. Procure “SMoRGs QoL”.",
    },
    "it": {
        "c1": "Riparazione automatica. Bottino automatico. Vendita della robaccia. La tua interfaccia lo fa già.",
        "c2": "SMoRG's QoL fa le piccole cose che nessun altro fa.",
        "c3": "Completa un obiettivo di missione…",
        "c4": "…e il lavoratore umano chiede: {{«More work?»}}",
        "c5": "Completa l'intera missione…",
        "c6": "{{«Job's done!»}} Pronta da consegnare.",
        "c7": "Giochi con l'Orda? Passa al peone.",
        "c8": "Sopra il nemico: il contatore della missione (1/7) e quanto è lontano.",
        "c9": "I messaggi di avanzamento passano dal rosso al giallo al verde.",
        "c10": "L'ultimo verrospino…",
        "c11": "{{«Work complete.»}} Ogni suono si attiva o disattiva da solo.",
        "c12": "Le nuove missioni vengono tracciate automaticamente.",
        "c13": "Livello oggetti e velocità sul riquadro del giocatore.",
        "c14": "Numeri di esperienza e reputazione colorati. La barra della reputazione mostra il % mancante e il grado.",
        "c15": "I tooltip mostrano chi sta prendendo di mira un'unità. Qui: te.",
        "c16": "Di solito le imprese si aprono su un muro di imprese completate…",
        "c17": "…ora si aprono su quelle che ti mancano.",
        "c18": "Conti alla rovescia per l'appello e la coda, livelli del gruppo: ogni ritocco ha la sua casella.",
        "c19": "Inoltre: reputazione fluttuante, cursore evidenziato quando scuoti il mouse, carattere di combattimento disegnato a mano.",
        "c20": "Gratis per Retail e WoW Forever. Cerca «SMoRGs QoL».",
    },
    "ru": {
        "c1": "Авторемонт. Автосбор добычи. Продажа хлама. Ваш интерфейс это уже умеет.",
        "c2": "SMoRG's QoL делает мелочи, которых больше нигде нет.",
        "c3": "Выполните цель задания…",
        "c4": "…и человек-рабочий спросит: {{«More work?»}}",
        "c5": "Выполните всё задание…",
        "c6": "{{«Job's done!»}} Можно сдавать.",
        "c7": "Играете за Орду? Выберите батрака.",
        "c8": "Над противником: счётчик задания (1/7) и расстояние до него.",
        "c9": "Сообщения о прогрессе меняют цвет с красного на жёлтый и зелёный.",
        "c10": "Последний иглогрив…",
        "c11": "{{«Work complete.»}} Каждый звук включается и выключается отдельно.",
        "c12": "Новые задания отслеживаются автоматически.",
        "c13": "Уровень предметов и скорость на рамке игрока.",
        "c14": "Цветные цифры опыта и репутации. Полоса репутации показывает, сколько % осталось, и уровень отношения.",
        "c15": "Подсказки показывают, кого выбрал целью персонаж. Здесь: вас.",
        "c16": "Обычно достижения открываются стеной уже полученных…",
        "c17": "…теперь — на тех, что ещё не получены.",
        "c18": "Отсчёт проверки готовности и очереди, уровни группы: у каждой мелочи свой флажок.",
        "c19": "А ещё: всплывающая репутация, подсветка курсора при встряхивании мыши, рукописный шрифт боя.",
        "c20": "Бесплатно для Retail и WoW Forever. Ищите «SMoRGs QoL».",
    },
    "ko": {
        "c1": "자동 수리. 자동 전리품. 잡동사니 판매. 그런 건 이미 있죠.",
        "c2": "SMoRG's QoL은 아무도 안 하는 작은 것들을 합니다.",
        "c3": "퀘스트 목표를 하나 완료하면…",
        "c4": "…인간 일꾼이 묻습니다: {{“More work?”}}",
        "c5": "퀘스트 전체를 완료하면…",
        "c6": "{{“Job's done!”}} 이제 보고하세요.",
        "c7": "호드인가요? 오크 일꾼으로 바꾸세요.",
        "c8": "몹 위에는 퀘스트 진행도(1/7)와 몹까지의 거리가 표시됩니다.",
        "c9": "진행 메시지는 빨강에서 노랑, 초록으로 바뀝니다.",
        "c10": "마지막 가시멧돼지…",
        "c11": "{{“Work complete.”}} 소리마다 따로 켜고 끌 수 있습니다.",
        "c12": "새 퀘스트는 자동으로 추적됩니다.",
        "c13": "플레이어 창에 아이템 레벨과 이동 속도.",
        "c14": "경험치와 평판 숫자에 색이 입혀지고, 평판 바에는 남은 %와 평판 단계가 표시됩니다.",
        "c15": "툴팁에 대상이 누구를 노리는지 표시됩니다. 여기서는 당신.",
        "c16": "업적 창은 보통 완료한 업적으로 가득하지만…",
        "c17": "…이제 아직 못 딴 업적부터 보여줍니다.",
        "c18": "전투 준비 확인·대기열 카운트다운, 파티원 레벨: 기능마다 체크박스가 따로 있습니다.",
        "c19": "그 밖에: 떠오르는 평판 획득, 마우스를 흔들면 강조되는 커서, 손글씨 전투 글꼴.",
        "c20": "Retail과 WoW Forever에서 무료. “SMoRGs QoL”을 검색하세요.",
    },
    "zh-CN": {
        "c1": "自动修理、自动拾取、卖垃圾——你的界面早就有了。",
        "c2": "SMoRG's QoL 做的是别人没做的小事。",
        "c3": "完成一个任务目标……",
        "c4": "……人类工人会问：{{“More work?”}}",
        "c5": "完成整个任务……",
        "c6": "{{“Job's done!”}} 可以交任务了。",
        "c7": "玩部落？换成兽人苦工的语音。",
        "c8": "怪物头顶：你的任务计数（1/7）以及你和它的距离。",
        "c9": "进度提示从红色变黄，再变绿。",
        "c10": "最后一只野猪人……",
        "c11": "{{“Work complete.”}} 每个音效都能单独开关。",
        "c12": "新任务自动追踪。",
        "c13": "玩家头像上显示物品等级和移动速度。",
        "c14": "经验和声望数字带颜色；声望条显示剩余百分比和声望等级。",
        "c15": "鼠标提示显示单位的目标是谁。这里：你。",
        "c16": "成就界面平时满是已完成的成就……",
        "c17": "……现在默认只显示还没拿到的。",
        "c18": "就位确认和排队倒计时、队友等级：每项改动都有自己的勾选框。",
        "c19": "还有：浮动声望提示、晃动鼠标时高亮光标、手写风格的战斗字体。",
        "c20": "正式服与 WoW Forever 均免费。搜索 “SMoRGs QoL”。",
    },
    "zh-TW": {
        "c1": "自動修裝、自動拾取、賣垃圾——你的介面早就有了。",
        "c2": "SMoRG's QoL 做的是別人沒做的小事。",
        "c3": "完成一個任務目標……",
        "c4": "……人類工人會問：{{「More work?」}}",
        "c5": "完成整個任務……",
        "c6": "{{「Job's done!」}}可以回報任務了。",
        "c7": "玩部落？換成獸人苦工的語音。",
        "c8": "怪物頭上：你的任務計數（1/7）以及你和牠的距離。",
        "c9": "進度提示從紅色變黃，再變綠。",
        "c10": "最後一隻野豬人……",
        "c11": "{{「Work complete.」}}每個音效都能單獨開關。",
        "c12": "新任務自動追蹤。",
        "c13": "玩家頭像上顯示物品等級和移動速度。",
        "c14": "經驗和聲望數字帶顏色；聲望條顯示剩餘百分比和聲望等級。",
        "c15": "滑鼠提示顯示單位的目標是誰。這裡：你。",
        "c16": "成就視窗平常滿是已完成的成就……",
        "c17": "……現在預設只顯示還沒拿到的。",
        "c18": "準備確認和排隊倒數、隊友等級：每項調整都有自己的勾選框。",
        "c19": "還有：浮動聲望提示、搖晃滑鼠時強調游標、手寫風格的戰鬥字型。",
        "c20": "正式服與 WoW Forever 皆免費。搜尋「SMoRGs QoL」。",
    },
}

GOLD = "&H6AC4E8&"  # #E8C46A in ASS's BGR order
WHITE = "&HFFFFFF&"
SCALE = "scale=2560:1440:flags=lanczos,format=yuv420p"


def run(args):
    print(">", " ".join(a if " " not in a else f'"{a}"' for a in args[:6]), "...")
    subprocess.run(args, check=True, cwd=HERE)


def offsets():
    t, res = 0.0, {}
    for seg_id, _, dur, _ in SEGMENTS:
        res[seg_id] = t
        t += dur
    return res, t


def write_crlf(path, text):
    with open(path, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(text)


def render_master(raw, master):
    inputs, chains, pairs = [], [], []
    n = 0
    for seg_id, start, dur, crop in SEGMENTS:
        if seg_id == "end":
            continue
        inputs += ["-ss", f"{start:.3f}", "-t", f"{dur:.3f}", "-i", raw]
        blur = ",gblur=sigma=20" if seg_id == "title" else ""
        v = f"[{n}:v]crop={crop}{blur},{SCALE},fps=60,setsar=1,setpts=PTS-STARTPTS"
        a = (f"[{n}:a]asetpts=PTS-STARTPTS,aresample=48000,"
             f"afade=t=in:d=0.05,afade=t=out:st={dur - 0.08:.3f}:d=0.08")
        if seg_id == "title":
            v += (",eq=brightness=-0.1:saturation=0.8,noise=alls=2:allf=t,fade=t=in:d=0.6,"
                  "drawtext=fontfile='C\\:/Windows/Fonts/palab.ttf':textfile='build/showcase-title.txt':"
                  "fontsize=200:fontcolor=0xE8C46A:borderw=8:bordercolor=black@0.9:"
                  "shadowx=5:shadowy=5:shadowcolor=black@0.6:x=(w-tw)/2:y=h*0.26:"
                  "alpha='min(1,t/0.6)'")
            a += ",volume=0.6"
        chains += [v + f"[v{n}];", a + f"[a{n}];"]
        pairs.append(f"[v{n}][a{n}]")
        n += 1
    end_dur = SEGMENTS[-1][2]
    inputs += ["-loop", "1", "-t", f"{end_dur}", "-i", "../promo/smorgsqol-banner.png",
               "-f", "lavfi", "-t", f"{end_dur}", "-i", "anullsrc=r=48000:cl=stereo"]
    chains += [
        f"color=c=0x0a0f1c:s=2560x1440:r=60:d={end_dur}[bg];",
        f"[{n}:v]scale=1920:1080:flags=lanczos,setsar=1[ban];",
        f"[bg][ban]overlay=320:53,format=yuv420p,setsar=1,fade=t=in:d=0.4,"
        f"fade=t=out:st={end_dur - 0.8}:d=0.8[v{n}];",
        f"[{n + 1}:a]anull[a{n}];",
    ]
    pairs.append(f"[v{n}][a{n}]")
    chains.append("".join(pairs) + f"concat=n={n + 1}:v=1:a=1[v][acat];")
    chains.append("[acat]loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]")
    filt = os.path.join(BUILD, "showcase.filter")
    write_crlf(filt, "\n".join(chains) + "\n")
    with open(os.path.join(BUILD, "showcase-title.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("SMoRG's QoL")
    run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *inputs,
         "-/filter_complex", "build/showcase.filter", "-map", "[v]", "-map", "[a]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", master])


def ts_srt(t):
    ms = round(t * 1000)
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"


def ts_ass(t):
    cs = round(t * 100)
    return f"{cs // 360000}:{cs // 6000 % 60:02d}:{cs // 100 % 60:02d}.{cs % 100:02d}"


def write_subs(lang, font):
    offs, _ = offsets()
    srt, events = [], []
    for i, (seg, a, b, style, cid) in enumerate(CUES, 1):
        text = TEXT[lang][cid]
        start, end = offs[seg] + a, offs[seg] + b
        srt.append(f"{i}\n{ts_srt(start)} --> {ts_srt(end)}\n"
                   f"{text.replace('{{', '').replace('}}', '')}\n")
        ass = text.replace("{{", "{\\c" + GOLD + "}").replace("}}", "{\\c" + WHITE + "}")
        events.append(f"Dialogue: 0,{ts_ass(start)},{ts_ass(end)},{style},,0,0,0,,"
                      f"{{\\fad(120,120)}}{ass}")
    write_crlf(os.path.join(SUBS, f"{lang}.srt"), "\n".join(srt))
    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,{font},50,&H00FFFFFF,&H00FFFFFF,&H5A000000,&H00000000,-1,0,0,0,100,100,0,0,3,14,0,2,200,200,64,1
Style: CapTop,{font},50,&H00FFFFFF,&H00FFFFFF,&H5A000000,&H00000000,-1,0,0,0,100,100,0,0,3,14,0,8,200,200,64,1
Style: Tag,{font},58,&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,4,3,2,220,220,330,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    write_crlf(os.path.join(SUBS, f"{lang}.ass"), header + "\n".join(events) + "\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1].split(",")
        args = [a for a in args if a != sys.argv[sys.argv.index("--only") + 1]]
    raw = args[0] if args else os.environ.get("SHOWCASE_RAW", DEFAULT_RAW)
    os.makedirs(SUBS, exist_ok=True)
    os.makedirs(BUILD, exist_ok=True)
    langs = [l for l in LANGS if only is None or l[0] in only]

    master = os.path.join(BUILD, "showcase-master.mp4")
    if "--reuse-master" not in sys.argv or not os.path.exists(master):
        render_master(raw, master)
    for code, _, _, font in LANGS:
        write_subs(code, font)

    # Clean video with every language as a selectable track (English on by default).
    cmd = [FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", "build/showcase-master.mp4"]
    for code, *_ in LANGS:
        cmd += ["-i", f"showcase/subs/{code}.srt"]
    cmd += ["-map", "0:v", "-map", "0:a"]
    for i in range(len(LANGS)):
        cmd += ["-map", str(i + 1)]
    cmd += ["-c:v", "copy", "-c:a", "copy", "-c:s", "mov_text"]
    for i, (code, iso, title, _) in enumerate(LANGS):
        cmd += [f"-metadata:s:s:{i}", f"language={iso}", f"-metadata:s:s:{i}", f"title={title}",
                f"-disposition:s:{i}", "default" if i == 0 else "0"]
    cmd += ["-movflags", "+faststart", "showcase/SMoRGsQoL-showcase.mp4"]
    run(cmd)

    for code, *_ in langs:
        run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", "build/showcase-master.mp4",
             "-vf", f"ass=showcase/subs/{code}.ass",
             "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
             "-c:a", "copy", "-movflags", "+faststart", f"showcase/SMoRGsQoL-showcase-{code}.mp4"])
    print("wrote", OUT)


if __name__ == "__main__":
    main()
