"""Abre o mesmo PDF autorizado online e offline no Android com uma sessão já iniciada."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
from uuid import uuid4
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('document', type=Path, help='JSON com cell, project e title do documento existente.')
    parser.add_argument('--serial', required=True, help='Número de série do Android, conforme adb devices.')
    parser.add_argument('--usb-device', action='store_true',
                        help='Executa no aparelho físico conectado via USB. O teste desliga Wi-Fi e dados temporariamente.')
    args = parser.parse_args()
    is_emulator = bool(re.fullmatch(r'emulator-\d+', args.serial))
    if args.usb_device:
        if is_emulator or not re.fullmatch(r'[A-Za-z0-9._-]+', args.serial):
            parser.error('Informe o serial USB do aparelho físico, conforme adb devices.')
    elif not is_emulator:
        parser.error('Informe um emulador dedicado ou habilite --usb-device com o serial do aparelho conectado.')

    document = json.loads(args.document.read_text(encoding='utf-8-sig'))
    for key in ('cell', 'project'):
        if not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', document[key]):
            parser.error(f'UUID inválido no campo {key}.')
    if not isinstance(document['title'], str) or not document['title'].strip():
        parser.error('Informe o título exato do documento no catálogo.')

    adb_path = Path(os.environ.get('ANDROID_HOME', Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk')) / 'platform-tools/adb.exe'
    scan_file = f'/sdcard/em-workshop-document-test-{uuid4().hex}.xml'
    package = 'br.com.mielectric.rmconnect'
    cached = 'Disponível neste dispositivo, inclusive offline.'
    uncached = 'Ao abrir com conexão, uma cópia fica disponível offline.'

    def run_adb(*commands):
        return subprocess.run([str(adb_path), *commands], check=True,
                              capture_output=True, timeout=25).stdout.decode('utf-8')

    def adb(*commands):
        return run_adb('-s', args.serial, *commands)

    if args.usb_device:
        try:
            usb_serial = run_adb('-d', 'get-serialno').strip()
        except subprocess.SubprocessError:
            parser.error('Conecte exatamente um aparelho por USB e autorize a depuração no Android.')
        if usb_serial != args.serial:
            parser.error('O serial informado é diferente do aparelho conectado por USB.')
    try:
        device_ready = adb('get-state').strip() == 'device'
    except subprocess.SubprocessError:
        device_ready = False
    if not device_ready:
        parser.error('O Android precisa aparecer com estado device em adb devices.')

    def wait_for(check, failure):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            value = check()
            if value:
                return value
            time.sleep(.6)
        raise RuntimeError(failure)

    def labels():
        try:
            adb('shell', 'uiautomator', 'dump', scan_file)
            root = ET.fromstring(adb('exec-out', 'cat', scan_file))
        except (subprocess.SubprocessError, ET.ParseError):
            return []
        return [(node.get('text') or node.get('content-desc', ''), node) for node in root.iter('node')]

    def visible(label):
        return any(text == label for text, _ in labels())

    width, height = map(int, re.findall(r'(\d+)x(\d+)', adb('shell', 'wm', 'size'))[-1])

    def find_document():
        screen = labels()
        after_title = False
        button = None
        # Android flattens the accessibility tree. Read the button and status
        # in order after the exact title, ignoring the text child of the button.
        for text, node in screen:
            if text == document['title']:
                after_title = True
            elif after_title and text == 'Abrir documento' and node.get('class') == 'android.widget.Button':
                if button is not None:
                    raise RuntimeError('O teste não conseguiu distinguir o botão do documento.')
                button = node
            elif after_title and button is not None and text in (cached, uncached):
                return button, text == cached
        if any(text == 'Documentos do projeto' for text, _ in screen):
            adb('shell', 'input', 'swipe', str(width // 2), str(height * 85 // 100),
                str(width // 2), str(height // 2), '500')
        return None

    def open_catalog():
        params = f"celula={document['cell']}&projeto={document['project']}"
        for route, label in (('projeto', 'Acesse as informações e atividades deste projeto.'), ('documentos', 'Documentos do projeto')):
            adb('shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d',
                f"'rm-mi-connect://{route}?{params}'", package)
            wait_for(lambda: visible(label), 'A rota do projeto ou do catálogo não abriu no aplicativo.')

    def active_activity():
        return next((line for line in adb('shell', 'dumpsys', 'activity', 'activities').splitlines()
                     if 'topResumedActivity' in line), '')

    def open_pdf(require_cache):
        button, is_cached = wait_for(find_document, 'O documento não apareceu com seu botão de abertura.')
        if require_cache and not is_cached:
            raise RuntimeError('A cópia do PDF não está disponível no catálogo offline.')
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', button.attrib['bounds']))
        adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
        wait_for(lambda: 'PdfViewerActivity' in active_activity(), 'O visualizador de PDF não abriu.')
        adb('shell', 'input', 'keyevent', '4')
        wait_for(lambda: package in active_activity(), 'O aplicativo não retomou após fechar o PDF.')

    radios = {'wifi': 'wifi_on', 'data': 'mobile_data'}

    def radio_states():
        return {radio: adb('shell', 'settings', 'get', 'global', key).strip() for radio, key in radios.items()}

    initial = radio_states()
    if set(initial.values()) - {'0', '1'} or '1' not in initial.values():
        raise RuntimeError('Inicie o teste com Wi-Fi ou dados móveis ativos e com a sessão do EM aberta.')
    touched_radios = []
    try:
        open_catalog()
        open_pdf(require_cache=False)
        wait_for(lambda: (pair := find_document()) and pair[1], 'O cache não foi confirmado após abrir o PDF.')
        for radio in radios:
            touched_radios.append(radio)
            adb('shell', 'svc', radio, 'disable')
        wait_for(lambda: visible('Sem conexão'), 'O aplicativo não entrou em modo offline.')
        open_pdf(require_cache=True)
        open_catalog()
        open_pdf(require_cache=True)
    finally:
        restoration_errors = []
        for radio in reversed(touched_radios):
            try:
                adb('shell', 'svc', radio, 'enable' if initial[radio] == '1' else 'disable')
            except subprocess.SubprocessError as exc:
                restoration_errors.append(exc)
        try:
            if touched_radios:
                wait_for(lambda: radio_states() == initial, 'O estado original de Wi-Fi e dados móveis não foi confirmado.')
        except (RuntimeError, subprocess.SubprocessError) as exc:
            restoration_errors.append(exc)
        try:
            adb('shell', 'rm', '-f', scan_file)
        finally:
            if restoration_errors:
                raise RuntimeError(
                    'Confira Wi-Fi e dados móveis no Android. Houve falha ao verificar ou restaurar a rede.'
                ) from restoration_errors[0]
    print('PASS: PDF aberto online, offline e após reabrir o catálogo offline. Rede restaurada.')


if __name__ == '__main__':
    main()
