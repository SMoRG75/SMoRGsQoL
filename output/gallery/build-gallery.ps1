# Renders the CurseForge gallery images for SMoRG's QoL into this folder.
# Run from the repository root:
#   powershell -NoProfile -ExecutionPolicy Bypass -File output\gallery\build-gallery.ps1
# Background: the promo banner, blurred and darkened. Screenshots (in
# screenshots/) sit in gold frames with a label; each slide has a title, a
# subtitle and optional bullets.
Add-Type -AssemblyName System.Drawing

$repo    = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$shots   = Join-Path $PSScriptRoot 'screenshots'
$outDir  = $PSScriptRoot

$W = 1920; $H = 1080
$gold      = [System.Drawing.Color]::FromArgb(255, 222, 184, 96)
$goldDim   = [System.Drawing.Color]::FromArgb(255, 170, 135, 70)
$parchment = [System.Drawing.Color]::FromArgb(255, 238, 226, 200)
$muted     = [System.Drawing.Color]::FromArgb(255, 190, 180, 160)
$teal      = [System.Drawing.Color]::FromArgb(255, 90, 210, 220)

$titleFont = New-Object System.Drawing.Font('Palatino Linotype', 60, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$subFont   = New-Object System.Drawing.Font('Palatino Linotype', 30, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$bulletFont= New-Object System.Drawing.Font('Palatino Linotype', 32, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$labelFont = New-Object System.Drawing.Font('Segoe UI Semibold', 26, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$footFont  = New-Object System.Drawing.Font('Palatino Linotype', 24, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

function Shot($name) {
    return [System.Drawing.Image]::FromFile((Join-Path $shots $name))
}

# Blurred, darkened banner as a shared background.
function New-Background {
    $banner = [System.Drawing.Image]::FromFile((Join-Path $repo 'output\promo\smorgsqol-banner.png'))
    $small = New-Object System.Drawing.Bitmap 48, 27
    $gs = [System.Drawing.Graphics]::FromImage($small)
    $gs.InterpolationMode = 'HighQualityBilinear'
    $gs.DrawImage($banner, 0, 0, 48, 27)
    $gs.Dispose(); $banner.Dispose()

    $bg = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bg)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($small, -20, -20, $W + 40, $H + 40)
    $small.Dispose()

    $shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(170, 8, 12, 26))
    $g.FillRectangle($shade, 0, 0, $W, $H)
    # Darker top and bottom bands for the header and footer text.
    $rectTop = New-Object System.Drawing.Rectangle 0, 0, $W, 260
    $topBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rectTop, ([System.Drawing.Color]::FromArgb(170, 4, 6, 14)), ([System.Drawing.Color]::FromArgb(0, 4, 6, 14)), 90
    $g.FillRectangle($topBrush, $rectTop)
    $rectBot = New-Object System.Drawing.Rectangle 0, ($H - 140), $W, 140
    $botBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rectBot, ([System.Drawing.Color]::FromArgb(0, 4, 6, 14)), ([System.Drawing.Color]::FromArgb(190, 4, 6, 14)), 90
    $g.FillRectangle($botBrush, $rectBot)
    $g.Dispose()
    return $bg
}

$background = New-Background
$logo = [System.Drawing.Image]::FromFile((Join-Path $repo 'smorgsqol.png'))

function New-Canvas {
    $bmp = New-Object System.Drawing.Bitmap $W, $H
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($background, 0, 0, $W, $H)
    return @($bmp, $g)
}

function Draw-Header($g, $title, $subtitle) {
    # Round logo with a gold ring.
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse(70, 50, 130, 130)
    $g.SetClip($path)
    $g.DrawImage($logo, 70, 50, 130, 130)
    $g.ResetClip()
    $g.DrawEllipse((New-Object System.Drawing.Pen $gold, 4), 70, 50, 130, 130)

    $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 0, 0, 0))
    $g.DrawString($title, $titleFont, $shadow, 233, 53)
    $g.DrawString($title, $titleFont, (New-Object System.Drawing.SolidBrush $gold), 230, 50)
    $subRect = New-Object System.Drawing.RectangleF 232, 132, 1620, 80
    $g.DrawString($subtitle, $subFont, (New-Object System.Drawing.SolidBrush $parchment), $subRect)

    # Gold rule that fades out at both ends, with a teal gem in the middle.
    $rule = New-Object System.Drawing.Rectangle 70, 222, 1780, 3
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
    $blend.Colors = @([System.Drawing.Color]::FromArgb(0, $gold), $gold, [System.Drawing.Color]::FromArgb(0, $gold))
    $blend.Positions = @(0.0, 0.5, 1.0)
    $ruleBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rule, $gold, $gold, 0
    $ruleBrush.InterpolationColors = $blend
    $g.FillRectangle($ruleBrush, $rule)
    $gem = @((New-Object System.Drawing.PointF 960, 214), (New-Object System.Drawing.PointF 970, 223.5),
             (New-Object System.Drawing.PointF 960, 233), (New-Object System.Drawing.PointF 950, 223.5))
    $g.FillPolygon((New-Object System.Drawing.SolidBrush $teal), $gem)
}

function Draw-Footer($g) {
    $dot = [string][char]0x00B7
    $text = "SMoRG's QoL  $dot  Retail & WoW Forever  $dot  Every feature is toggleable"
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = 'Center'
    $g.DrawString($text, $footFont, (New-Object System.Drawing.SolidBrush $goldDim), (New-Object System.Drawing.RectangleF 0, 1026, $W, 40), $fmt)
}

# Draws a screenshot scaled to fit the box (up to maxScale), centered, in a gold
# frame with a drop shadow and a label underneath. $crop (x, y, w, h) draws only
# that part of the screenshot.
function Draw-Shot($g, $name, $bx, $by, $bw, $bh, $maxScale, $label, $crop = $null) {
    $img = Shot $name
    if ($crop) {
        $part = New-Object System.Drawing.Bitmap $crop[2], $crop[3]
        $gc = [System.Drawing.Graphics]::FromImage($part)
        $gc.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $crop[2], $crop[3]),
            (New-Object System.Drawing.Rectangle $crop[0], $crop[1], $crop[2], $crop[3]), [System.Drawing.GraphicsUnit]::Pixel)
        $gc.Dispose(); $img.Dispose()
        $img = $part
    }
    $labelH = if ($label) { 46 } else { 0 }
    $scale = [Math]::Min($maxScale, [Math]::Min($bw / $img.Width, ($bh - $labelH) / $img.Height))
    $w = [int]($img.Width * $scale); $h = [int]($img.Height * $scale)
    $x = [int]($bx + ($bw - $w) / 2); $y = [int]($by + ($bh - $labelH - $h) / 2)

    for ($i = 12; $i -ge 2; $i -= 2) {
        $a = [int](26 - $i)
        $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, 0, 0, 0))), $x - $i + 6, $y - $i + 10, $w + 2 * $i, $h + 2 * $i)
    }
    $g.DrawImage($img, $x, $y, $w, $h)
    $g.DrawRectangle((New-Object System.Drawing.Pen $gold, 3), $x - 2, $y - 2, $w + 3, $h + 3)
    $img.Dispose()

    if ($label) {
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = 'Center'
        $g.DrawString($label, $labelFont, (New-Object System.Drawing.SolidBrush $parchment), (New-Object System.Drawing.RectangleF ($bx - 60), ($y + $h + 12), ($bw + 120), 40), $fmt)
    }
}

function Draw-Bullets($g, $x, $y, $w, [string[]]$lines) {
    foreach ($line in $lines) {
        $gem = @((New-Object System.Drawing.PointF ($x + 8), ($y + 12)), (New-Object System.Drawing.PointF ($x + 16), ($y + 20)),
                 (New-Object System.Drawing.PointF ($x + 8), ($y + 28)), (New-Object System.Drawing.PointF $x, ($y + 20)))
        $g.FillPolygon((New-Object System.Drawing.SolidBrush $gold), $gem)
        $rect = New-Object System.Drawing.RectangleF ($x + 34), $y, ($w - 34), 200
        $size = $g.MeasureString($line, $bulletFont, [int]($w - 34))
        $g.DrawString($line, $bulletFont, (New-Object System.Drawing.SolidBrush $parchment), $rect)
        $y += [int]$size.Height + 22
    }
}

# A dark card with a gold frame, a speaker icon, the sound profile name and the
# two voice lines it plays.
function Draw-VoiceCard($g, $x, $y, $w, $h, $profile, $objectiveLine, $completeLine) {
    $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(215, 12, 14, 24))), $x, $y, $w, $h)
    $g.DrawRectangle((New-Object System.Drawing.Pen $gold, 3), $x, $y, $w, $h)

    # Speaker: body, cone and two sound waves.
    $sx = $x + 36; $sy = $y + 34
    $goldBrush = New-Object System.Drawing.SolidBrush $gold
    $g.FillRectangle($goldBrush, $sx, $sy + 14, 14, 20)
    $cone = @((New-Object System.Drawing.PointF ($sx + 14), ($sy + 14)), (New-Object System.Drawing.PointF ($sx + 32), $sy),
              (New-Object System.Drawing.PointF ($sx + 32), ($sy + 48)), (New-Object System.Drawing.PointF ($sx + 14), ($sy + 34)))
    $g.FillPolygon($goldBrush, $cone)
    $wave = New-Object System.Drawing.Pen $teal, 4
    $g.DrawArc($wave, $sx + 26, $sy + 8, 24, 32, -50, 100)
    $g.DrawArc($wave, $sx + 30, $sy - 2, 40, 52, -50, 100)

    $g.DrawString($profile, $labelFont, $goldBrush, $x + 120, $y + 38)

    $small = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $quote = New-Object System.Drawing.Font('Palatino Linotype', 40, [System.Drawing.FontStyle]::Italic, [System.Drawing.GraphicsUnit]::Pixel)
    $mutedBrush = New-Object System.Drawing.SolidBrush $muted
    $textBrush = New-Object System.Drawing.SolidBrush $parchment
    # Typographic quotes and apostrophes (char codes: the script is read as ANSI).
    $open = [string][char]0x201C; $close = [string][char]0x201D; $apos = [string][char]0x2019
    $g.DrawString('Objective done', $small, $mutedBrush, $x + 40, $y + 110)
    $g.DrawString($open + $objectiveLine.Replace("'", $apos) + $close, $quote, $textBrush, $x + 40, $y + 138)
    $g.DrawString('Quest done', $small, $mutedBrush, $x + 40, $y + 210)
    $g.DrawString($open + $completeLine.Replace("'", $apos) + $close, $quote, $textBrush, $x + 40, $y + 238)
}

function Save-Slide($pair, $file) {
    $pair[1].Dispose()
    $pair[0].Save((Join-Path $outDir $file), [System.Drawing.Imaging.ImageFormat]::Png)
    $pair[0].Dispose()
    "saved $file"
}

# 1. Quest sounds (the idea the addon started from)
$s = New-Canvas; $g = $s[1]
Draw-Header $g 'Hear your progress' 'A worker voice line for every finished objective, and another when the whole quest is done.'
Draw-Shot $g 'options-window.png' 80 270 860 620 2.2 'Toggle each sound and pick Horde or Alliance' @(18, 240, 360, 228)
Draw-VoiceCard $g 1030 280 760 320 'Horde (Peon)' 'Work, work.' 'Work complete.'
Draw-VoiceCard $g 1030 640 760 320 'Alliance (Human worker)' 'More work?' 'Job''s done!'
Draw-Footer $g
Save-Slide $s '01-quest-sounds.png'

# 2. Options window
$s = New-Canvas; $g = $s[1]
Draw-Header $g 'Every setting in one window' 'All options grouped into sections, and changes apply immediately.'
Draw-Shot $g 'options-window.png' 100 250 900 770 1.0 ''
Draw-Shot $g 'ldb-tooltip.png' 1110 300 700 240 2.5 'Launcher in Bazooka and other LDB displays'
Draw-Bullets $g 1110 600 720 @(
    'Open from LibDataBroker displays, the addon compartment, the minimap button or /sqol config',
    'Right-click the launcher for Blizzard Settings',
    'Stays in sync with Blizzard Settings and /sqol commands')
Draw-Footer $g
Save-Slide $s '02-options-window.png'

# 3. Quest progress
$s = New-Canvas; $g = $s[1]
Draw-Header $g 'Quest progress at a glance' 'Objective counts turn from red to green, in the tracker and in progress messages.'
Draw-Shot $g 'quest-tracker.png' 80 300 860 520 2.7 'Objective tracker, including world quests'
Draw-Shot $g 'progress-messages.png' 980 300 860 520 2.7 'Colored progress messages'
Draw-Footer $g
Save-Slide $s '03-quest-progress.png'

# 4. Range
$s = New-Canvas; $g = $s[1]
Draw-Header $g 'Know your range' 'Distance to your target in yards, and an icon when none of your abilities can reach it.'
Draw-Shot $g 'range-out.png' 80 260 860 380 2.1 'Out of range'
Draw-Shot $g 'range-in.png' 980 260 860 380 2.1 'In range, with quest progress'
Draw-Shot $g 'range-quest-count.png' 530 640 860 380 2.1 'Quest objective count above the name'
Draw-Footer $g
Save-Slide $s '04-range.png'

# 5. Tooltip target
$s = New-Canvas; $g = $s[1]
Draw-Header $g 'See who they target' 'A Target line in unit tooltips, updated live while you hover.'
Draw-Shot $g 'tooltip-target.png' 120 260 820 740 3.2 'Unit tooltip'
Draw-Bullets $g 1060 380 760 @(
    'Class-colored names for players',
    'Reaction colors for NPCs',
    'A red "You" when the unit is targeting you')
Draw-Footer $g
Save-Slide $s '05-tooltip-target.png'

# 6. Player frame stats
$s = New-Canvas; $g = $s[1]
Draw-Header $g 'Item level and speed' 'Your equipped item level and movement speed on the player frame, each toggled on its own.'
Draw-Shot $g 'player-frame-retail.png' 80 300 880 520 2.6 'Retail: above your name'
Draw-Shot $g 'forever-player-frame.png' 960 300 880 520 2.6 'WoW Forever: below the bars'
Draw-Footer $g
Save-Slide $s '06-player-stats.png'

# 7. XP and reputation
$s = New-Canvas; $g = $s[1]
Draw-Header $g 'XP and reputation, colored' 'Current values from red to green, with percentage left and standing, plus floating reputation gains.'
Draw-Shot $g 'xp-rep-bars.png' 100 280 1720 260 2.4 'XP and reputation bars'
Draw-Shot $g 'rep-gain.png' 120 600 820 380 2.4 'Floating reputation gains'
Draw-Shot $g 'combat-text-font.png' 980 600 820 380 2.4 'Custom combat text font'
Draw-Footer $g
Save-Slide $s '07-xp-reputation.png'

# 8. Group
$s = New-Canvas; $g = $s[1]
Draw-Header $g 'Ready for the group' 'Countdowns for queue pops and ready checks, and levels on the party frames.'
Draw-Shot $g 'queue-pop-countdown.png' 160 250 1000 740 2.3 'Queue pop countdown'
Draw-Shot $g 'party-levels.png' 1280 250 480 740 3.6 'Party member levels'
Draw-Footer $g
Save-Slide $s '08-group.png'

# 9. WoW Forever
$s = New-Canvas; $g = $s[1]
Draw-Header $g 'Also in WoW Forever' 'The same features, placed to fit the WoW Forever interface.'
Draw-Shot $g 'forever-player-frame.png' 100 260 820 420 3.0 'Player frame'
Draw-Shot $g 'forever-xp.png' 1000 260 820 420 3.4 'Colored XP numbers'
Draw-Shot $g 'forever-rep.png' 460 660 1000 360 3.0 'Reputation with percentage left and standing'
Draw-Footer $g
Save-Slide $s '09-wow-forever.png'

$background.Dispose(); $logo.Dispose()
