from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
project = root / 'シャドバ戦績研究.xcodeproj'
project.mkdir(exist_ok=True)
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
objects=[]
def obj(key,text): objects.append(f'{uid(key)} = {{ {text} }};'); return uid(key)
def ref(key): return uid(key)
for folder in ['Sources','Tests','UITests','Controls','Shared']:
    files = sorted((root/folder).glob('*.swift'))
    for p in files:
        key=str(p.relative_to(root)); obj(key,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{p.name}"; sourceTree = "<group>";')
        obj('build'+key,f'isa = PBXBuildFile; fileRef = {ref(key)};')
    obj(folder,f'isa = PBXGroup; path = {folder}; sourceTree = "<group>"; children = ({",".join(ref(str(p.relative_to(root))) for p in files)});')
obj('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;')
obj('assetsbuild',f'isa = PBXBuildFile; fileRef = {ref("assets")};')
for target,folder,ptype,ext in [('ShadowRecord','Sources','application','app'),('ShadowRecordTests','Tests','bundle.unit-test','xctest'),('ShadowRecordUITests','UITests','bundle.ui-testing','xctest'),('ShadowRecordControls','Controls','app-extension','appex')]:
    obj(target+'product',f'isa = PBXFileReference; explicitFileType = wrapper.{"application" if ext=="app" else "app-extension" if ext=="appex" else "cfbundle"}; path = {target}.{ext}; sourceTree = BUILT_PRODUCTS_DIR;')
    files=sorted((root/folder).glob('*.swift'))
    if folder in ['Sources','Controls']:
        for p in sorted((root/'Shared').glob('*.swift')):
            obj(target+str(p.relative_to(root)), f'isa = PBXBuildFile; fileRef = {ref(str(p.relative_to(root)))};')
    shared = [ref(target+str(p.relative_to(root))) for p in sorted((root/'Shared').glob('*.swift'))] if folder in ['Sources','Controls'] else []
    obj(target+'sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join([ref("build"+str(p.relative_to(root))) for p in files] + shared)}); runOnlyForDeploymentPostprocessing = 0;')
    obj(target+'frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    obj(target+'resources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ('+(ref('assetsbuild') if folder=='Sources' else '')+'); runOnlyForDeploymentPostprocessing = 0;')
    configs=[]
    for config in ['Debug','Release']:
        settings={'MARKETING_VERSION':'1.4.1','CURRENT_PROJECT_VERSION':'11','PRODUCT_NAME':target,'PRODUCT_BUNDLE_IDENTIFIER':'blog.epiclog.shadowrecord'+('' if folder=='Sources' else '.'+folder.lower()),'GENERATE_INFOPLIST_FILE':'YES','COPY_PHASE_STRIP':'NO','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'26.0','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_STYLE':'Automatic','SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"','SWIFT_STRICT_CONCURRENCY':'complete','SWIFT_OPTIMIZATION_LEVEL':'"-Onone"' if config=='Debug' else '"-O"','ENABLE_TESTABILITY':'YES' if config=='Debug' else 'NO'}
        if folder=='Sources': settings.update({'INFOPLIST_KEY_NSSupportsLiveActivities':'YES','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','INFOPLIST_KEY_CFBundleDisplayName':'"シャドバ戦績研究"','INFOPLIST_KEY_LSApplicationCategoryType':'"public.app-category.utilities"','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait','INFOPLIST_KEY_UIFileSharingEnabled':'YES','INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace':'YES'})
        if folder=='Controls': settings.update({'GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'Resources/Controls-Info.plist','APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'CONTROL_EXTENSION','LD_RUNPATH_SEARCH_PATHS':'"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"'})
        if folder=='Tests': settings.update({'TEST_HOST':'"$(BUILT_PRODUCTS_DIR)/ShadowRecord.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ShadowRecord"','BUNDLE_LOADER':'"$(TEST_HOST)"'})
        if folder=='UITests': settings.update({'TEST_TARGET_NAME':'ShadowRecord'})
        configs.append(obj(target+config,'isa = XCBuildConfiguration; name = '+config+'; buildSettings = {'+' '.join(k+' = '+v+';' for k,v in settings.items())+'};'))
    obj(target+'configs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    deps=''
    if folder in ['Tests','UITests']:
        obj(target+'proxy',f'isa = PBXContainerItemProxy; containerPortal = {ref("project")}; proxyType = 1; remoteGlobalIDString = {ref("ShadowRecord")}; remoteInfo = ShadowRecord;')
        deps=obj(target+'dep',f'isa = PBXTargetDependency; target = {ref("ShadowRecord")}; targetProxy = {ref(target+"proxy")};')
    extraPhase = ''
    if folder=='Sources':
        obj('embedControlFile', f'isa = PBXBuildFile; fileRef = {ref("ShadowRecordControlsproduct")}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy); }};')
        extraPhase = ',' + obj('embedControls', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({ref("embedControlFile")}); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
        deps = obj('appControlsDependency', f'isa = PBXTargetDependency; target = {ref("ShadowRecordControls")};')
    obj(target,f'isa = PBXNativeTarget; name = {target}; productName = {target}; productType = "com.apple.product-type.{ptype}"; productReference = {ref(target+"product")}; buildConfigurationList = {ref(target+"configs")}; buildPhases = ({ref(target+"sources")},{ref(target+"frameworks")},{ref(target+"resources")}{extraPhase}); buildRules = (); dependencies = ({deps});')
obj('products',f'isa = PBXGroup; name = Products; sourceTree = "<group>"; children = ({ref("ShadowRecordproduct")},{ref("ShadowRecordTestsproduct")},{ref("ShadowRecordUITestsproduct")},{ref("ShadowRecordControlsproduct")});')
obj('main',f'isa = PBXGroup; sourceTree = "<group>"; children = ({ref("Sources")},{ref("Tests")},{ref("UITests")},{ref("Controls")},{ref("Shared")},{ref("assets")},{ref("products")});')
for config in ['Debug','Release']: obj('project'+config,f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 26.0; DEBUG_INFORMATION_FORMAT = dwarf; }};')
obj('projectconfigs',f'isa = XCConfigurationList; buildConfigurations = ({ref("projectDebug")},{ref("projectRelease")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2650; }}; buildConfigurationList = {ref("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ja; knownRegions = (ja,en,Base); mainGroup = {ref("main")}; productRefGroup = {ref("products")}; projectDirPath = ""; projectRoot = ""; targets = ({ref("ShadowRecord")},{ref("ShadowRecordTests")},{ref("ShadowRecordUITests")},{ref("ShadowRecordControls")});')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+ref('project')+'; }\n')
scheme=project/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
def buildref(target): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref(target)}" BuildableName="{target}.{ "app" if target=="ShadowRecord" else "xctest"}" BlueprintName="{target}" ReferencedContainer="container:シャドバ戦績研究.xcodeproj"/>'
(scheme/'ShadowRecord.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2650" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildref('ShadowRecord')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildref('ShadowRecordTests')}</TestableReference><TestableReference skipped="NO">{buildref('ShadowRecordUITests')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref('ShadowRecord')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref('ShadowRecord')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
