#!/usr/bin/env python3
"""Run shared production code in an iOS simulator, without adding Xcode schemes/targets.
First build the app, then run: python3 Tests/run-integration.py DERIVED_DATA SIMULATOR_UDID
Optional third arg: simulator app data container to seed a visible test document (never a real device).
"""
import os, pathlib, plistlib, shutil, subprocess, sys, tempfile, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
derived = pathlib.Path(sys.argv[1]); device = sys.argv[2]
work = pathlib.Path(tempfile.mkdtemp(prefix='ReaderIntegration-'))
products = derived / 'Build/Products/Debug-iphonesimulator'

def epub(name, toc=True):
    with zipfile.ZipFile(work / name, 'w') as z:
        z.writestr('mimetype', 'application/epub+zip')
        z.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        nav = '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' if toc else ''
        z.writestr('OEBPS/book.opf', f'''<package version="3.0" unique-identifier="id" xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">reader-tests</dc:identifier><dc:title>Fixture EPUB</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-09-24T00:00:00Z</meta></metadata><manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>{nav}</manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>''')
        z.writestr('OEBPS/a.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>A</title></head><body><h1 id="one">One</h1><p>FIRST chapter teaches anatomy.</p><h1 id="two">Two</h1><p>SECOND chapter teaches physiology.</p></body></html>')
        z.writestr('OEBPS/b.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>B</title></head><body><h1 id="three">Three</h1><p>THIRD chapter teaches movement.</p></body></html>')
        if toc: z.writestr('OEBPS/nav.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="a.xhtml#one">One</a></li><li><a href="a.xhtml#two">Two</a></li><li><a href="b.xhtml#three">Three</a></li></ol></nav></body></html>')
epub('chapters.epub'); epub('no-toc.epub', False)
app = work / 'Checks.app'; app.mkdir()
(app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.karloss.ReaderIntegrationChecks','CFBundleExecutable':'Checks','CFBundlePackageType':'APPL'}))
for bundle in products.glob('*.bundle'): shutil.copytree(bundle, app / bundle.name)
files = ['DocumentModel','LibraryStorage','DocumentExtractor','EPUBService','SpeechEngine','SpeechTypes','ReaderSettings']
sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'], text=True).strip()
arch = os.uname().machine
cmd = ['xcrun','--sdk','iphonesimulator','swiftc','-swift-version','6','-parse-as-library','-module-name','NativeTTSBenchmark','-sdk',sdk,'-target',f'{arch}-apple-ios26.0-simulator','-I',str(products),'-F',str(products / 'PackageFrameworks'),'-module-cache-path',str(work / 'modules'),'-Xcc',f'-fmodule-map-file={derived}/Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator/Minizip.modulemap','-Xcc',f'-I{derived}/SourcePackages/checkouts/Zip/Zip/minizip/include','-lz','-lxml2', '-o',str(app / 'Checks')]
cmd += [str(root / 'NativeTTSBenchmark' / (f + '.swift')) for f in files]
cmd += [str(root / 'Tests/IntegrationChecks.swift')]
cmd += [str(p) for p in products.glob('*.o')]
subprocess.run(cmd, check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)], check=True)
run = ['xcrun','simctl','spawn',device,str(app / 'Checks'),str(work)]
if len(sys.argv) > 3: run.append(sys.argv[3])
print('Validation artifacts:', work, flush=True)
subprocess.run(run, check=True)
