#!/usr/bin/env python3
"""XCTest UI host generated in a temporary copy. Never adds schemes/targets to the app project.
Usage: python3 Tests/run-ui.py SIMULATOR_UDID [DERIVED_DATA]
"""
import pathlib, shutil, subprocess, sys, tempfile, plistlib, platform, os, sqlite3, zipfile
root = pathlib.Path(__file__).resolve().parents[1]
# Default smoke flow; other system-picker flows are selected explicitly.
os.environ.setdefault('READER_UI_TEST', 'testTextReaderAndSettings')
derived = sys.argv[2] if len(sys.argv)>2 else '/private/tmp/NativeReaderUIBuild'
# A stable temporary source path permits incremental builds across UI checks.
work = pathlib.Path(derived) / 'ValidationSource'
work.mkdir(parents=True, exist_ok=True)
for name in ['NativeTTSBenchmark', 'NativeTTSBenchmark.xcodeproj', 'Tests']:
    if (work / name).exists(): shutil.rmtree(work / name)
    shutil.copytree(root / name, work / name)
# Test-only file sharing exposes fixtures to the real system file picker.
info_path = work / 'NativeTTSBenchmark/Info.plist'
info = plistlib.loads(info_path.read_bytes())
info.update(UIFileSharingEnabled=True, LSSupportsOpeningDocumentsInPlace=True)
info_path.write_bytes(plistlib.dumps(info))
p = work / 'NativeTTSBenchmark.xcodeproj/project.pbxproj'
s = p.read_text()
s = s.replace('objects = {', '''objects = {
    BB0000000000000000000001 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/ReaderUITests.swift; sourceTree = SOURCE_ROOT; };
    BB0000000000000000000002 = {isa = PBXBuildFile; fileRef = BB0000000000000000000001; };
    BB0000000000000000000003 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = ReaderUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
    BB0000000000000000000004 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (BB0000000000000000000002); runOnlyForDeploymentPostprocessing = 0; };
    BB0000000000000000000005 = {isa = PBXNativeTarget; name = ReaderUITests; productName = ReaderUITests; productType = "com.apple.product-type.bundle.ui-testing"; productReference = BB0000000000000000000003; buildConfigurationList = BB0000000000000000000006; buildPhases = (BB0000000000000000000004); dependencies = (BB0000000000000000000009); };
    BB0000000000000000000006 = {isa = XCConfigurationList; buildConfigurations = (BB0000000000000000000007); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
    BB0000000000000000000007 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.karloss.ReaderUITests; PRODUCT_NAME = ReaderUITests; SWIFT_VERSION = 6.0; IPHONEOS_DEPLOYMENT_TARGET = 26.0; TARGETED_DEVICE_FAMILY = "1,2"; SDKROOT = iphoneos; TEST_TARGET_NAME = NativeTTSBenchmark; }; };
    BB0000000000000000000008 = {isa = PBXContainerItemProxy; containerPortal = 000000000000000000000001; proxyType = 1; remoteGlobalIDString = 000000000000000000000005; remoteInfo = NativeTTSBenchmark; };
    BB0000000000000000000009 = {isa = PBXTargetDependency; target = 000000000000000000000005; targetProxy = BB0000000000000000000008; };
''',1)
s = s.replace('targets = (','targets = (BB0000000000000000000005,',1)
p.write_text(s)
def ref(id, name, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:NativeTTSBenchmark.xcodeproj"/>'
app = ref('000000000000000000000005','NativeTTSBenchmark','NativeTTSBenchmark.app')
test = ref('BB0000000000000000000005','ReaderUITests','ReaderUITests.xctest')
schemes=work/'NativeTTSBenchmark.xcodeproj/xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
(schemes/'ReaderValidation.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{app}</BuildActionEntry><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{test}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test}</TestableReference></Testables><MacroExpansion>{app}</MacroExpansion></TestAction></Scheme>''')
print('UI validation copy:', work, flush=True)
command = ['xcodebuild','-project',str(work/'NativeTTSBenchmark.xcodeproj'),'-scheme','ReaderValidation','-destination',f'platform=iOS Simulator,id={sys.argv[1]}','-derivedDataPath',derived,'-clonedSourcePackagesDirPath','/private/tmp/NativeReaderBuild/SourcePackages','-parallel-testing-enabled','NO','-collect-test-diagnostics','never','CODE_SIGNING_ALLOWED=NO','ONLY_ACTIVE_ARCH=YES','ARCHS='+platform.machine()]
subprocess.run(command + ['build-for-testing'], check=True)
subprocess.run(['xcrun','simctl','install',sys.argv[1],str(pathlib.Path(derived)/'Build/Products/Debug-iphonesimulator/NativeTTSBenchmark.app')], check=True)
container = pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',sys.argv[1],'com.karloss.NativeTTSBenchmark','data'], text=True).strip())
fixtures = sorted((p for p in pathlib.Path(tempfile.gettempdir()).glob('ReaderIntegration-*') if (p/'mixed.pdf').exists() and (p/'mixed.pdf').stat().st_size > 0), key=lambda p:p.stat().st_mtime)
if fixtures:
    target = container/'Documents/Validation fixtures'; target.mkdir(parents=True, exist_ok=True)
    for name in ['embedded.pdf','mixed.pdf','chapters.epub','no-toc.epub','corrupt.pdf','ocr.png']:
        source = fixtures[-1]/name
        if source.exists(): shutil.copyfile(source,target/name)
    # Give the no-TOC fixture a distinct title so Library assertions are unambiguous.
    no_toc = target/'no-toc.epub'
    with zipfile.ZipFile(no_toc) as archive:
        entries = [(item, archive.read(item.filename)) for item in archive.infolist()]
    with zipfile.ZipFile(no_toc, 'w') as archive:
        for item, data in entries:
            if item.filename.endswith('.opf'): data = data.replace(b'Fixture EPUB', b'No TOC Fixture')
            archive.writestr(item, data)
    with zipfile.ZipFile(target/'chapters.epub') as archive:
        entries = [(item, archive.read(item.filename)) for item in archive.infolist()]
    with zipfile.ZipFile(target/'selection.epub', 'w') as archive:
        for item, data in entries:
            if item.filename.endswith('.opf'): data = data.replace(b'Fixture EPUB', b'All Chapters Fixture')
            archive.writestr(item, data)
    if os.environ.get('READER_UI_TEST') in ('testCancellation', 'testPhotoImport'):
        subprocess.run(['xcrun', 'swift', str(root/'Tests/MakeUIFixtures.swift'), str(target)], check=True)
    if os.environ.get('READER_UI_TEST') == 'testPhotoImport':
        for name in ['photo-first.png', 'photo-second.png']:
            subprocess.run(['xcrun','simctl','addmedia',sys.argv[1],str(target/name)],check=True)

def library_snapshot():
    support = container / 'Library/Application Support'
    if not (support/'default.store').exists(): return [], []
    connection = sqlite3.connect('file:' + str(support/'default.store') + '?mode=ro', uri=True)
    rows = sorted(connection.execute('select hex(ZID), ZTITLE from ZLIBRARYDOCUMENT').fetchall())
    connection.close()
    folders = sorted(p.name for p in (support/'ReaderLibrary').iterdir()) if (support/'ReaderLibrary').exists() else []
    return rows, folders

actions = os.environ.get('READER_UI_TEST') == 'testDocumentActions'
cancellation = os.environ.get('READER_UI_TEST') == 'testCancellation'
before = library_snapshot() if actions or cancellation else None
staged_before = {p.name for p in (container/'tmp').glob('ReaderImport-*')}
exports_before = {p.name for p in (container/'Documents').glob('*.txt')}
if os.environ.get('READER_UI_TEST'):
    command += ['-only-testing:ReaderUITests/ReaderUITests/'+name for name in os.environ['READER_UI_TEST'].split(',')]
subprocess.run(command + ['test-without-building'], check=True)

if actions:
    # XCTest may reinstall the app and relocate its preserved data container.
    container = pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',sys.argv[1],'com.karloss.NativeTTSBenchmark','data'], text=True).strip())
    assert library_snapshot() == before, 'Delete changed another document or left managed files/metadata'
    exports = {p for p in (container/'Documents').glob('*.txt') if p.name not in exports_before}
    assert len(exports) == 1, 'Expected one actual text export in app Documents'
    expected = 'La fisioterapia estudia el movimiento.\n\nEl sistema muscular sostiene el cuerpo.'
    assert next(iter(exports)).read_text() == expected, 'Export differs from normalized Reader/TTS text'
    print('PASS: actual exported UTF-8 text equals Reader/TTS paragraphs; Delete removes only its new metadata/files', flush=True)

if os.environ.get('READER_UI_TEST') in ('testPDFImport', 'testEPUBImport'):
    container = pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',sys.argv[1],'com.karloss.NativeTTSBenchmark','data'], text=True).strip())
    is_pdf = os.environ['READER_UI_TEST'] == 'testPDFImport'
    files = list((container/'Documents').rglob('embedded*.txt' if is_pdf else 'Fixture EPUB*.txt'))
    assert files, 'No actual export found'
    text = max(files, key=lambda p:p.stat().st_mtime).read_text()
    if is_pdf:
        assert all(marker in text for marker in ['[Page 2]', '[Page 3]', 'Embedded page 2', 'Embedded page 3'])
        assert 'Embedded page 1' not in text and '[Page 1]' not in text
    else:
        assert 'FIRST' in text and 'THIRD' in text and 'SECOND' not in text
    print('PASS: actual export contains selected original pages/chapters only', flush=True)

if cancellation:
    container = pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',sys.argv[1],'com.karloss.NativeTTSBenchmark','data'], text=True).strip())
    assert library_snapshot() == before, 'Cancelled import altered library metadata/files'
    assert {p.name for p in (container/'tmp').glob('ReaderImport-*')} == staged_before, 'Cancelled import left new staged files'
    print('PASS: cancellation leaves library unchanged and no staged import files', flush=True)

if os.environ.get('READER_UI_TEST') == 'testPhotoImport':
    container = pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',sys.argv[1],'com.karloss.NativeTTSBenchmark','data'], text=True).strip())
    files = list((container/'Documents').rglob('Photos*.txt'))
    assert files, 'No actual photo text export found'
    text = max(files, key=lambda p:p.stat().st_mtime).read_text()
    assert '[Page 1]' in text and '[Page 2]' in text
    assert text.index('FIRST PHOTO') < text.index('[Page 2]') < text.index('SECOND PHOTO'), text
    print('PASS: two distinct PhotosPicker selections retain their requested order through OCR, Reader and export', flush=True)

if os.environ.get('READER_UI_TEST') == 'testEPUBSelectAll':
    container = pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',sys.argv[1],'com.karloss.NativeTTSBenchmark','data'], text=True).strip())
    files = list((container/'Documents').rglob('All Chapters Fixture*.txt'))
    assert files, 'No selected-chapter export found'
    text = max(files, key=lambda p:p.stat().st_mtime).read_text()
    assert 'SECOND' in text and 'FIRST' not in text and 'THIRD' not in text, text
    print('PASS: All chapters toggle and individual selection export only chapter Two', flush=True)
