"""Open the same authorized PDF online and offline in a logged-in Android emulator."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('document', type=Path, help='JSON com cell, project e title do documento existente.')
    parser.add_argument('--serial', required=True, help='Número de série do emulador, conforme adb devices.')
    args = parser.parse_args()
    if not re.fullmatch(r'emulator-\d+', args.serial):
        parser.error('Use um emulador dedicado com a sessão já aberta.')

    document = json.loads(args.document.read_text(encoding='utf-8-sig'))
    for key in ('cell', 'project'):
        if not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', document[key]):
            parser.error(f'UUID inválido no campo {key}.')
    if not isinstance(document['title'], str) or not document['title'].strip():
        parser.error('Informe o título exato do documento no catálogo.')

    adb_path = Path(os.environ.get('ANDROID_HOME', Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk')) / 'platform-tools/adb.exe'
    scan_file = '/sdcard/em-workshop-document-test.xml'
    package = 'br.com.mielectric.rmconnect'
    cached = 'Disponível neste dispositivo, inclusive offline.'
    uncached = 'Ao abrir com conexão, uma cópia fica disponível offline.'

    def adb(*commands):
        return subprocess.run([str(adb_path), '-s', args.serial, *commands], check=True,
                              capture_output=True, timeout=25).stdout.decode('utf-8')

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
    initial = {radio: adb('shell', 'settings', 'get', 'global', key).strip() for radio, key in radios.items()}
    if set(initial.values()) - {'0', '1'} or '1' not in initial.values():
        raise RuntimeError('Inicie o teste com a rede do emulador conectada.')
    try:
        open_catalog()
        open_pdf(require_cache=False)
        wait_for(lambda: (pair := find_document()) and pair[1], 'O cache não foi confirmado após abrir o PDF.')
        for radio in radios:
            adb('shell', 'svc', radio, 'disable')
        wait_for(lambda: visible('Sem conexão'), 'O aplicativo não entrou em modo offline.')
        open_pdf(require_cache=True)
        open_catalog()
        open_pdf(require_cache=True)
    finally:
        for radio, state in initial.items():
            adb('shell', 'svc', radio, 'enable' if state == '1' else 'disable')
        adb('shell', 'rm', '-f', scan_file)
    print('PASS: PDF aberto online, offline e após reabrir o catálogo offline. Rede restaurada.')


if __name__ == '__main__':
    main()
