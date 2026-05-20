"""Replace Logo/Audio ble_service_notify_str calls with dual_notify_str in main.c"""
import re

f = r'c:\Users\Klara\Desktop\4.8\ridewind-esp\main\main.c'
with open(f, 'r', encoding='utf-8') as fp:
    content = fp.read()

# Keywords that identify Logo/Audio upload responses
keywords = [
    'LOGO_ERROR', 'LOGO_FAIL', 'LOGO_OK', 'LOGO_READY', 'LOGO_ACK',
    'OK:LOGO', 'LOGO_SLOTS',
    'AUDIO_ERROR', 'AUDIO_FAIL', 'AUDIO_OK', 'AUDIO_READY', 'AUDIO_ACK',
    'OK:AUDIO', 'AUDIO_RELOAD', 'AUDIO_STATUS',
]

# Variable-based calls in Logo/Audio sections
var_names = ['ack', 'ready', 'ok_resp', 'logo_resp', 'audio_resp', 'fail', 'err']

count = 0
lines = content.split('\n')
new_lines = []

for line in lines:
    if 'ble_service_notify_str(' in line:
        is_logo_audio = False
        for kw in keywords:
            if kw in line:
                is_logo_audio = True
                break
        if not is_logo_audio:
            for var in var_names:
                if f'ble_service_notify_str({var})' in line:
                    is_logo_audio = True
                    break
        
        if is_logo_audio:
            line = line.replace('ble_service_notify_str(', 'dual_notify_str(')
            count += 1
    
    new_lines.append(line)

content = '\n'.join(new_lines)

with open(f, 'w', encoding='utf-8') as fp:
    fp.write(content)

print(f"Replaced {count} calls")
