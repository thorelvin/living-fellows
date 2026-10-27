# SPDX-License-Identifier: MIT
# Original local audio; no hosted service, API key or downloaded samples.
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$soundRoot = Join-Path $project 'SurvivorCompanion\42\media\sound'
@'
import math, struct, wave
from pathlib import Path
out=Path('SurvivorCompanion/42/media/sound/LFBuildingSiren.wav')
rate=22050
phase=0.0
frames=[]
for n in range(rate*4):
    t=n/rate
    hz=650+280*math.sin(2*math.pi*t/2)
    phase+=2*math.pi*hz/rate
    envelope=min(1,t/0.025,(4-t)/0.025)
    value=0.45*envelope*(math.sin(phase)+0.12*math.sin(3*phase))/1.12
    frames.append(struct.pack('<h',round(32767*value)))
with wave.open(str(out),'wb') as f:
    f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate);f.writeframes(b''.join(frames))
'@ | & python -
if ($LASTEXITCODE -ne 0) { throw 'Siren synthesis failed' }
Add-Type -AssemblyName System.Speech
$speech = [System.Speech.Synthesis.SpeechSynthesizer]::new()
try {
    $speech.SelectVoice('Microsoft Zira Desktop')
    $speech.Rate = -1
    $speech.SetOutputToWaveFile((Join-Path $soundRoot 'LFBuildingAnnouncement.wav'))
    $speech.Speak('Attention. This building is being evacuated. Leave by the nearest safe exit. Do not use the loading bay until the shutter is fully open. This is an automated announcement.')
} finally { $speech.Dispose() }
