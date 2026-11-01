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
sources=sorted((root/'SpareRoom').glob('*.swift'))
refs=[]; builds=[]
for p in sources:
    ref=add('file:'+p.name,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(p.name)}; sourceTree = "<group>";')
    refs.append(ref)
    builds.append(add('build:'+p.name,f'isa = PBXBuildFile; fileRef = {ref};'))
asset=add('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
privacy=add('privacy','isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>";')
info=add('info','isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
resources=[add('resource:'+r,f'isa = PBXBuildFile; fileRef = {r};') for r in (asset,privacy)]
product=add('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = SpareRoom.app; sourceTree = BUILT_PRODUCTS_DIR;')
group=add('appgroup',f'isa = PBXGroup; children = ({",".join(refs+[asset,privacy,info])},); path = SpareRoom; sourceTree = "<group>";')
products=add('products',f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
main=add('main',f'isa = PBXGroup; children = ({group},{products},); sourceTree = "<group>";')
srcphase=add('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
resphase=add('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resources)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks=add('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
projectconfigs=[]; targetconfigs=[]
for mode in ['Debug','Release']:
    projectconfigs.append(add('project'+mode,f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; }};'))
    opts='SWIFT_OPTIMIZATION_LEVEL = "-Onone";' if mode=='Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O";'
    targetconfigs.append(add('target'+mode,f'''isa = XCBuildConfiguration; name = {mode}; buildSettings = {{
        PRODUCT_BUNDLE_IDENTIFIER = uk.co.leobrown.spareroom; PRODUCT_NAME = "$(TARGET_NAME)";
        INFOPLIST_FILE = SpareRoom/Info.plist; GENERATE_INFOPLIST_FILE = NO;
        ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_STYLE = Automatic;
        CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0.0;
        TARGETED_DEVICE_FAMILY = "1,2"; SUPPORTS_MACCATALYST = NO;
        SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
        SWIFT_EMIT_LOC_STRINGS = YES; ENABLE_USER_SCRIPT_SANDBOXING = YES; {opts}
    }};'''))
pc=add('projectconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(projectconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc=add('targetconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(targetconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=add('target',f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({srcphase},{frameworks},{resphase},); buildRules = (); dependencies = (); name = SpareRoom; productName = SpareRoom; productReference = {product}; productType = "com.apple.product-type.application";')
project=add('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
proj=root/'SpareRoom.xcodeproj'; proj.mkdir(exist_ok=True)
(proj/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+ '\n'.join(k+' = { '+v+' };' for k,v in objects.items())+'\n}; rootObject = '+project+'; }\n')
schemes=proj/'xcshareddata'/'xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
(schemes/'SpareRoom.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SpareRoom.app" BlueprintName="SpareRoom" ReferencedContainer="container:SpareRoom.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SpareRoom.app" BlueprintName="SpareRoom" ReferencedContainer="container:SpareRoom.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(proj)
