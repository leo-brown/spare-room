#!/usr/bin/env python3
"""Generate the dependency-free Xcode project; safe to run after adding Swift files."""
import hashlib
from pathlib import Path
import json
root=Path(__file__).resolve().parent
objects={}
def ident(s): return hashlib.sha256(s.encode()).hexdigest()[:24].upper()
def add(name,body): objects[ident(name)]=body; return ident(name)
def q(s): return json.dumps(str(s))
sources=sorted((root/'Crashpad').glob('*.swift'))
refs=[]; builds=[]
for p in sources:
    ref=add('file:'+p.name,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(p.name)}; sourceTree = "<group>";')
    refs.append(ref)
    builds.append(add('build:'+p.name,f'isa = PBXBuildFile; fileRef = {ref};'))
asset=add('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
privacy=add('privacy','isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>";')
info=add('info','isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
resources=[add('resource:'+r,f'isa = PBXBuildFile; fileRef = {r};') for r in (asset,privacy)]
product=add('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = Crashpad.app; sourceTree = BUILT_PRODUCTS_DIR;')
group=add('appgroup',f'isa = PBXGroup; children = ({",".join(refs+[asset,privacy,info])},); path = Crashpad; sourceTree = "<group>";')
products=add('products',f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
main=add('main',f'isa = PBXGroup; children = ({group},{products},); sourceTree = "<group>";')
srcphase=add('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
resphase=add('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resources)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks=add('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
projectconfigs=[]; targetconfigs=[]
for mode in ['Debug','Release']:
    projectconfigs.append(add('project'+mode,f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; }};'))
    opts='SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if mode=='Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O";'
    targetconfigs.append(add('target'+mode,f'''isa = XCBuildConfiguration; name = {mode}; buildSettings = {{
        PRODUCT_BUNDLE_IDENTIFIER = uk.co.leobrown.crashpad; PRODUCT_NAME = "$(TARGET_NAME)";
        INFOPLIST_FILE = Crashpad/Info.plist; GENERATE_INFOPLIST_FILE = NO;
        ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_STYLE = Automatic;
        CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0.0;
        TARGETED_DEVICE_FAMILY = "1,2"; SUPPORTS_MACCATALYST = NO;
        SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
        SWIFT_EMIT_LOC_STRINGS = YES; ENABLE_USER_SCRIPT_SANDBOXING = YES; {opts}
    }};'''))
pc=add('projectconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(projectconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc=add('targetconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(targetconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=add('target',f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({srcphase},{frameworks},{resphase},); buildRules = (); dependencies = (); name = Crashpad; productName = Crashpad; productReference = {product}; productType = "com.apple.product-type.application";')

uitestfile=add('uitestfile','isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CrashpadUITests.swift; sourceTree = "<group>";')
uitestgroup=add('uitestgroup',f'isa = PBXGroup; children = ({uitestfile},); path = CrashpadUITests; sourceTree = "<group>";')
objects[main]=objects[main].replace(f'{group},{products}',f'{group},{uitestgroup},{products}')
uitestproduct=add('uitestproduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = CrashpadUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
objects[products]=objects[products].replace(f'({product},)',f'({product},{uitestproduct},)')
uitestbuild=add('uitestbuild',f'isa = PBXBuildFile; fileRef = {uitestfile};')
uitestphase=add('uitestphase',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({uitestbuild},); runOnlyForDeploymentPostprocessing = 0;')
uiconfigs=[]
for mode in ['Debug','Release']:
    uiconfigs.append(add('uitest'+mode,f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ PRODUCT_BUNDLE_IDENTIFIER = uk.co.leobrown.crashpad.uitests; PRODUCT_NAME = "$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES; TARGETED_DEVICE_FAMILY = "1,2"; TEST_TARGET_NAME = Crashpad; CODE_SIGN_STYLE = Automatic; }};'))
uicl=add('uiconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(uiconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
proxy=add('proxy',f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Crashpad;')
dependency=add('dependency',f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
uitarget=add('uitarget',f'isa = PBXNativeTarget; buildConfigurationList = {uicl}; buildPhases = ({uitestphase},); buildRules = (); dependencies = ({dependency},); name = CrashpadUITests; productName = CrashpadUITests; productReference = {uitestproduct}; productType = "com.apple.product-type.bundle.ui-testing";')

project=add('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},{uitarget},);')
proj=root/'Crashpad.xcodeproj'; proj.mkdir(exist_ok=True)
(proj/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(k+' = { '+v+' };' for k,v in objects.items())+'\n}; rootObject = '+project+'; }\n')
schemes=proj/'xcshareddata'/'xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
(schemes/'Crashpad.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Crashpad.app" BlueprintName="Crashpad" ReferencedContainer="container:Crashpad.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uitarget}" BuildableName="CrashpadUITests.xctest" BlueprintName="CrashpadUITests" ReferencedContainer="container:Crashpad.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Crashpad.app" BlueprintName="Crashpad" ReferencedContainer="container:Crashpad.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(proj)
