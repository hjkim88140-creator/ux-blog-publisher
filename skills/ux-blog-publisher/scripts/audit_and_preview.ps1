param(
  [Parameter(Mandatory = $true)]
  [string]$MarkdownPath,
  [string]$PreviewFileName = "",
  [string]$TagLabel = "#Product Design",
  [string]$MetaLabel = "프로덕트 디자인 케이스 스터디",
  [int]$ImageWidth = 760,
  [int]$JpegQuality = 72
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

if (-not (Test-Path $MarkdownPath)) {
  throw "Markdown file not found: $MarkdownPath"
}

$workspaceDir = Split-Path -Parent (Resolve-Path $MarkdownPath)
$md = Get-Content $MarkdownPath -Raw -Encoding utf8

# 1. Verify image links
$imgs = [regex]::Matches($md, '!\[[^\]]*\]\(([^)]+)\)')
Write-Output "=== IMAGE VERIFICATION ($($imgs.Count)) ==="
$missingCount = 0
foreach ($m in $imgs) {
  $rel = $m.Groups[1].Value
  $full = Join-Path $workspaceDir $rel
  $exists = Test-Path $full
  if (-not $exists) { $missingCount++ }
  Write-Output "  [$exists] $rel"
}

# 2. Deterministic korean-humanizer audit
$emDash = ([regex]::Matches($md, "—|–")).Count
$c11Matches = [regex]::Matches($md, ".{0,12}(고|며|지만|면서|아서|어서|되),.{0,12}")
$i1 = ([regex]::Matches($md, "(인|한)\s*것이(다|죠|에요)")).Count
$d1 = ([regex]::Matches($md, "결론적으로|따라서|이를 통해|요약하면|정리하면")).Count
$a8 = ([regex]::Matches($md, "되어지|보여지|여겨지")).Count
$f2 = ([regex]::Matches($md, "가 아니라|이 아니라")).Count
$a10 = ([regex]::Matches($md, "수 있")).Count
$midDot = ([regex]::Matches($md, "·")).Count
$placeholder = ([regex]::Matches($md, "\[이미지")).Count

Write-Output "`n=== HUMANIZER AUDIT ==="
Write-Output "em/en dash (S1): $emDash"
Write-Output "C-11 connective comma (S1): $($c11Matches.Count)"
foreach ($m in $c11Matches) { Write-Output "  C11: $($m.Value)" }
Write-Output "I-1 것이죠/것이다 (S1): $i1"
Write-Output "D-1 결산피벗 (S1): $d1"
Write-Output "A-8 이중피동 (S1): $a8"
Write-Output "F-2 부정병렬 (S2): $f2"
Write-Output "A-10 수 있다 (S2): $a10"
Write-Output "가운뎃점 (J-2): $midDot"
Write-Output "Leftover placeholders: $placeholder"
Write-Output "Chars (with spaces): $($md.Length) | Chars (no spaces): $(($md -replace '\s', '').Length)"

if ($missingCount -gt 0) {
  Write-Warning "$missingCount image(s) missing!"
}

# 3. Optional: Build inline Orca HTML preview (< 512 KB) when ORCA_CHAT_SCRATCH_DIR is set
if ($PreviewFileName -ne "" -and $env:ORCA_CHAT_SCRATCH_DIR) {
  Add-Type -AssemblyName System.Drawing
  function Get-ResizedDataUrl($path, $targetWidth, $quality) {
    $src = [System.Drawing.Image]::FromFile($path)
    $w = [Math]::Min($targetWidth, $src.Width)
    $h = [int]([math]::Round($src.Height * ($w / $src.Width)))
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.DrawImage($src, 0, 0, $w, $h)
    $g.Dispose(); $src.Dispose()
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$quality)
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, $codec, $encParams)
    $bmp.Dispose()
    $b64 = [Convert]::ToBase64String($ms.ToArray())
    $ms.Dispose()
    return "data:image/jpeg;base64,$b64"
  }

  function Inline-Format($s) {
    $s = [System.Net.WebUtility]::HtmlEncode($s)
    $s = [regex]::Replace($s, '`([^`]+)`', '<code>$1</code>')
    $s = [regex]::Replace($s, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
    $s = [regex]::Replace($s, '\*([^*]+)\*', '<em>$1</em>')
    return $s
  }

  $lines = $md -split "`r?`n"
  $bodyParts = New-Object System.Collections.Generic.List[string]
  $inUl = $false
  $inSubUl = $false
  $isFirstImg = $true
  $docTitle = "Blog Preview"

  foreach ($raw in $lines) {
    $line = $raw.TrimEnd()
    if ($line -eq "" -or $line -eq "---") {
      if ($inSubUl) { $bodyParts.Add("</ul></li>"); $inSubUl = $false }
      if ($inUl) { $bodyParts.Add("</ul>"); $inUl = $false }
      continue
    }
    if ($line -match '^# (.+)$') {
      $docTitle = $Matches[1]
      $bodyParts.Add("<span class=`"tag`">$([System.Net.WebUtility]::HtmlEncode($TagLabel))</span>")
      $bodyParts.Add("<h1>$(Inline-Format $Matches[1])</h1>")
      $bodyParts.Add("<div class=`"meta`">$([System.Net.WebUtility]::HtmlEncode($MetaLabel))</div>")
      continue
    }
    if ($line -match '^## (.+)$') {
      if ($inSubUl) { $bodyParts.Add("</ul></li>"); $inSubUl = $false }
      if ($inUl) { $bodyParts.Add("</ul>"); $inUl = $false }
      $bodyParts.Add("<h2>$(Inline-Format $Matches[1])</h2>")
      continue
    }
    if ($line -match '^### (.+)$') {
      if ($inSubUl) { $bodyParts.Add("</ul></li>"); $inSubUl = $false }
      if ($inUl) { $bodyParts.Add("</ul>"); $inUl = $false }
      $bodyParts.Add("<h3>$(Inline-Format $Matches[1])</h3>")
      continue
    }
    if ($line -match '^!\[([^\]]*)\]\(([^)]+)\)$') {
      $alt = [System.Net.WebUtility]::HtmlEncode($Matches[1])
      $imgFull = Join-Path $workspaceDir $Matches[2]
      if (Test-Path $imgFull) {
        $src = Get-ResizedDataUrl $imgFull $ImageWidth $JpegQuality
        if ($isFirstImg) {
          $bodyParts.Add("<figure><img src=`"$src`" alt=`"$alt`" /></figure>")
          $isFirstImg = $false
        } else {
          $bodyParts.Add("<figure><img src=`"$src`" alt=`"$alt`" /><figcaption>$alt</figcaption></figure>")
        }
      }
      continue
    }
    if ($line -match '^> \(\*\) (.+)$') {
      $bodyParts.Add("<div class=`"footnote`">(*) $(Inline-Format $Matches[1])</div>")
      continue
    }
    if ($line -match '^> (.+)$') {
      $bodyParts.Add("<blockquote class=`"callout`">$(Inline-Format $Matches[1])</blockquote>")
      continue
    }
    if ($line -match '^→ (.+)$') {
      $bodyParts.Add("<div class=`"arrow-note`">→ $(Inline-Format $Matches[1])</div>")
      continue
    }
    if ($line -match '^  - (.+)$') {
      if (-not $inSubUl) {
        $lastIdx = $bodyParts.Count - 1
        if ($lastIdx -ge 0 -and $bodyParts[$lastIdx].EndsWith("</li>")) {
          $bodyParts[$lastIdx] = $bodyParts[$lastIdx].Substring(0, $bodyParts[$lastIdx].Length - 5)
        }
        $bodyParts.Add("<ul>")
        $inSubUl = $true
      }
      $bodyParts.Add("<li>$(Inline-Format $Matches[1])</li>")
      continue
    }
    if ($line -match '^- (.+)$') {
      if ($inSubUl) { $bodyParts.Add("</ul></li>"); $inSubUl = $false }
      if (-not $inUl) { $bodyParts.Add("<ul>"); $inUl = $true }
      $bodyParts.Add("<li>$(Inline-Format $Matches[1])</li>")
      continue
    }
    if ($inSubUl) { $bodyParts.Add("</ul></li>"); $inSubUl = $false }
    if ($inUl) { $bodyParts.Add("</ul>"); $inUl = $false }
    $bodyParts.Add("<p>$(Inline-Format $line)</p>")
  }
  if ($inSubUl) { $bodyParts.Add("</ul></li>") }
  if ($inUl) { $bodyParts.Add("</ul>") }

  $css = @"
<style>
  * { box-sizing: border-box; }
  body { margin: 0; padding: 32px 20px 56px; background: var(--background, #ffffff); color: var(--foreground, #191f28); font-family: var(--font-sans, -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Pretendard", "Malgun Gothic", sans-serif); line-height: 1.78; -webkit-font-smoothing: antialiased; }
  article { max-width: 720px; margin: 0 auto; }
  .tag { display: inline-block; font-size: 13px; font-weight: 600; color: #3182f6; background: rgba(49, 130, 246, 0.1); padding: 4px 10px; border-radius: 999px; margin-bottom: 14px; }
  h1 { font-size: 32px; font-weight: 800; letter-spacing: -0.025em; line-height: 1.3; margin: 0 0 12px; }
  .meta { font-size: 14px; color: var(--muted-foreground, #6b7684); margin-bottom: 28px; }
  h2 { font-size: 23px; font-weight: 700; letter-spacing: -0.02em; margin: 44px 0 14px; padding-top: 22px; border-top: 1px solid var(--border, #e5e8eb); }
  h3 { font-size: 18px; font-weight: 700; letter-spacing: -0.015em; margin: 30px 0 10px; }
  p { font-size: 16px; margin: 0 0 16px; word-break: keep-all; }
  figure { margin: 22px 0 24px; }
  figure img { display: block; width: 100%; height: auto; border-radius: 14px; border: 1px solid var(--border, #e5e8eb); }
  figcaption { font-size: 13px; color: var(--muted-foreground, #6b7684); text-align: center; margin-top: 8px; }
  ul { margin: 10px 0 18px; padding-left: 20px; }
  li { font-size: 16px; margin-bottom: 8px; word-break: keep-all; }
  li ul { margin-top: 6px; margin-bottom: 8px; }
  .arrow-note { background: var(--muted, #f2f4f6); border-left: 3px solid #3182f6; padding: 14px 16px; border-radius: 0 10px 10px 0; margin: 16px 0 20px; font-size: 15.5px; }
  .footnote { font-size: 13.5px; color: var(--muted-foreground, #6b7684); background: var(--card, #f9fafb); border: 1px solid var(--border, #e5e8eb); padding: 12px 14px; border-radius: 10px; margin: 14px 0 20px; line-height: 1.65; }
  blockquote.callout { margin: 26px 0; padding: 20px 22px; background: rgba(49, 130, 246, 0.08); border-left: 4px solid #3182f6; border-radius: 0 12px 12px 0; font-size: 17px; font-weight: 700; line-height: 1.55; }
  code { font-family: var(--font-mono, ui-monospace, SFMono-Regular, Menlo, Consolas, monospace); font-size: 0.88em; background: var(--muted, #f2f4f6); padding: 2px 6px; border-radius: 6px; }
</style>
"@

  $html = "<!DOCTYPE html>`n<html lang=`"ko`"><head><meta charset=`"UTF-8`" /><meta name=`"viewport`" content=`"width=device-width, initial-scale=1.0`" /><title>$([System.Net.WebUtility]::HtmlEncode($docTitle))</title>$css</head><body><article>`n$($bodyParts -join "`n")`n</article></body></html>"
  $outPath = Join-Path $env:ORCA_CHAT_SCRATCH_DIR $PreviewFileName
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($outPath, $html, $utf8NoBom)
  $sizeKB = [math]::Round((Get-Item $outPath).Length / 1KB, 1)
  Write-Output "`nPREVIEW SAVED: $outPath ($sizeKB KB)"
  if ($sizeKB -ge 512) {
    Write-Warning "Preview HTML exceeds 512 KB limit ($sizeKB KB); re-run with lower -ImageWidth or -JpegQuality."
  }
}
