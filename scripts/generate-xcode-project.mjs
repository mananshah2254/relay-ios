// Reproducible project generator. No XcodeGen, Ruby gems, or npm install needed.
import { createHash } from 'node:crypto';
import { readdir, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ios = path.join(root, 'iOS');
const id = value => createHash('sha256').update(value).digest('hex').slice(0, 24).toUpperCase();
const q = value => JSON.stringify(value);
const objects = [];
const add = (key, body) => { objects.push(`\t\t${id(key)} = { ${body} };`); return id(key); };
const list = values => `(${values.join(', ')},)`;
async function swiftFiles(directory) {
  const entries = await readdir(path.join(ios, directory), { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const relative = `${directory}/${entry.name}`;
    if (entry.isDirectory()) files.push(...await swiftFiles(relative));
    else if (entry.name.endsWith('.swift')) files.push(relative);
  }
  return files.sort();
}

const appFiles = [...await swiftFiles('Relay'), 'Shared/AppEnvironment.swift', 'Shared/ShareUploadCoordinator.swift', 'Shared/RelayAppDelegate.swift'];
const shareFiles = [...await swiftFiles('ShareExtension'), 'Shared/AppEnvironment.swift', 'Shared/ShareUploadCoordinator.swift'];
const allFiles = [...new Set([...appFiles, ...shareFiles])].sort();
if (!appFiles.includes('Relay/RelayApp.swift')) throw new Error('RelayApp.swift must exist before generating the project.');
for (const file of allFiles) add(`file:${file}`, `isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${q(file)}; sourceTree = "<group>";`);
add('file:assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "Relay/Assets.xcassets"; sourceTree = "<group>";');
for (const file of ['Relay/Info.plist', 'ShareExtension/Info.plist', 'Relay/Relay.entitlements', 'ShareExtension/RelayShare.entitlements', 'Shared/PrivacyInfo.xcprivacy', 'Config/Base.xcconfig']) {
  const type = file.endsWith('.xcconfig') ? 'text.xcconfig' : 'text.plist.xml';
  add(`file:${file}`, `isa = PBXFileReference; lastKnownFileType = ${type}; path = ${q(file)}; sourceTree = "<group>";`);
}
add('product:app', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Relay.app; sourceTree = BUILT_PRODUCTS_DIR;');
add('product:share', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = RelayShare.appex; sourceTree = BUILT_PRODUCTS_DIR;');
add('group:products', `isa = PBXGroup; children = ${list([id('product:app'), id('product:share')])}; name = Products; sourceTree = "<group>";`);
add('group:root', `isa = PBXGroup; children = ${list([...allFiles.map(x => id(`file:${x}`)), ...['Relay/Info.plist', 'ShareExtension/Info.plist', 'Relay/Relay.entitlements', 'ShareExtension/RelayShare.entitlements', 'Shared/PrivacyInfo.xcprivacy', 'Config/Base.xcconfig'].map(x => id(`file:${x}`)), id('file:assets'), id('group:products')])}; sourceTree = "<group>";`);
// Xcode resolves local package references from the project source directory
// (iOS/), so the repository-root Package.swift is one level up.
add('package:core', 'isa = XCLocalSwiftPackageReference; relativePath = ..;');

for (const [target, files] of [['app', appFiles], ['share', shareFiles]]) {
  for (const file of files) add(`build:${target}:${file}`, `isa = PBXBuildFile; fileRef = ${id(`file:${file}`)};`);
  add(`build:${target}:privacy`, `isa = PBXBuildFile; fileRef = ${id('file:Shared/PrivacyInfo.xcprivacy')};`);
  if (target === 'app') add('build:app:assets', `isa = PBXBuildFile; fileRef = ${id('file:assets')};`);
  add(`core:${target}`, `isa = XCSwiftPackageProductDependency; package = ${id('package:core')}; productName = OutreachCore;`);
  add(`build:${target}:core`, `isa = PBXBuildFile; productRef = ${id(`core:${target}`)};`);
  add(`phase:${target}:sources`, `isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ${list(files.map(x => id(`build:${target}:${x}`)))}; runOnlyForDeploymentPostprocessing = 0;`);
  add(`phase:${target}:resources`, `isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ${list([id(`build:${target}:privacy`), ...(target === 'app' ? [id('build:app:assets')] : [])])}; runOnlyForDeploymentPostprocessing = 0;`);
  add(`phase:${target}:frameworks`, `isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ${list([id(`build:${target}:core`)])}; runOnlyForDeploymentPostprocessing = 0;`);
  for (const config of ['Debug', 'Release']) {
    const isApp = target === 'app';
    const settings = {
      PRODUCT_NAME: isApp ? 'Relay' : 'RelayShare',
      PRODUCT_BUNDLE_IDENTIFIER: isApp ? '$(RELAY_BUNDLE_ID)' : '$(RELAY_BUNDLE_ID).share',
      INFOPLIST_FILE: isApp ? 'Relay/Info.plist' : 'ShareExtension/Info.plist',
      CODE_SIGN_ENTITLEMENTS: isApp ? 'Relay/Relay.entitlements' : 'ShareExtension/RelayShare.entitlements',
      GENERATE_INFOPLIST_FILE: 'NO',
      SDKROOT: 'iphoneos',
      SUPPORTED_PLATFORMS: 'iphoneos iphonesimulator',
      SKIP_INSTALL: isApp ? 'NO' : 'YES',
      APPLICATION_EXTENSION_API_ONLY: isApp ? 'NO' : 'YES',
      LD_RUNPATH_SEARCH_PATHS: isApp ? '$(inherited) @executable_path/Frameworks' : '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
      SWIFT_EMIT_LOC_STRINGS: 'YES',
      SWIFT_OPTIMIZATION_LEVEL: config === 'Debug' ? '-Onone' : '-O',
      SWIFT_ACTIVE_COMPILATION_CONDITIONS: config === 'Debug' ? '$(inherited) DEBUG' : '$(inherited)',
      DEBUG_INFORMATION_FORMAT: config === 'Debug' ? 'dwarf' : 'dwarf-with-dsym'
    };
    if (isApp) settings.ASSETCATALOG_COMPILER_APPICON_NAME = 'AppIcon';
    add(`config:${target}:${config}`, `isa = XCBuildConfiguration; baseConfigurationReference = ${id('file:Config/Base.xcconfig')}; buildSettings = { ${Object.entries(settings).map(([k,v]) => `${k} = ${q(v)};`).join(' ')} }; name = ${config};`);
  }
  add(`configlist:${target}`, `isa = XCConfigurationList; buildConfigurations = ${list(['Debug','Release'].map(x => id(`config:${target}:${x}`)))}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`);
}
add('proxy:share', `isa = PBXContainerItemProxy; containerPortal = ${id('project')}; proxyType = 1; remoteGlobalIDString = ${id('target:share')}; remoteInfo = RelayShare;`);
add('dependency:share', `isa = PBXTargetDependency; target = ${id('target:share')}; targetProxy = ${id('proxy:share')};`);
add('build:embed', `isa = PBXBuildFile; fileRef = ${id('product:share')}; settings = { ATTRIBUTES = (RemoveHeadersOnCopy,); };`);
add('phase:embed', `isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ${list([id('build:embed')])}; name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;`);
for (const target of ['app','share']) {
  const name = target === 'app' ? 'Relay' : 'RelayShare';
  const phases = ['sources','frameworks','resources'].map(x => id(`phase:${target}:${x}`));
  if (target === 'app') phases.push(id('phase:embed'));
  add(`target:${target}`, `isa = PBXNativeTarget; buildConfigurationList = ${id(`configlist:${target}`)}; buildPhases = ${list(phases)}; buildRules = (); dependencies = ${target === 'app' ? list([id('dependency:share')]) : '()'}; name = ${name}; packageProductDependencies = ${list([id(`core:${target}`)])}; productName = ${name}; productReference = ${id(`product:${target}`)}; productType = ${q(target === 'app' ? 'com.apple.product-type.application' : 'com.apple.product-type.app-extension')};`);
}
for (const config of ['Debug','Release']) add(`config:project:${config}`, `isa = XCBuildConfiguration; buildSettings = { CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; ALWAYS_SEARCH_USER_PATHS = NO; ENABLE_STRICT_OBJC_MSGSEND = YES; GCC_C_LANGUAGE_STANDARD = gnu17; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 17.0; }; name = ${config};`);
add('configlist:project', `isa = XCConfigurationList; buildConfigurations = ${list(['Debug','Release'].map(x => id(`config:project:${x}`)))}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;`);
add('project', `isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = { ${id('target:app')} = { CreatedOnToolsVersion = 16.0; SystemCapabilities = { com.apple.ApplicationGroups.iOS = { enabled = 1; }; com.apple.Keychain = { enabled = 1; }; }; }; ${id('target:share')} = { CreatedOnToolsVersion = 16.0; SystemCapabilities = { com.apple.ApplicationGroups.iOS = { enabled = 1; }; com.apple.Keychain = { enabled = 1; }; }; }; }; }; buildConfigurationList = ${id('configlist:project')}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = ${id('group:root')}; packageReferences = ${list([id('package:core')])}; productRefGroup = ${id('group:products')}; projectDirPath = ""; projectRoot = ""; targets = ${list([id('target:app'),id('target:share')])};`);

const projectDirectory = path.join(ios, 'Relay.xcodeproj');
await mkdir(path.join(projectDirectory, 'xcshareddata/xcschemes'), { recursive: true });
await writeFile(path.join(projectDirectory, 'project.pbxproj'), `// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n${objects.join('\n')}\n\t};\n\trootObject = ${id('project')};\n}\n`);
const buildable = `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id('target:app')}" BuildableName="Relay.app" BlueprintName="Relay" ReferencedContainer="container:Relay.xcodeproj"/>`;
await writeFile(path.join(projectDirectory, 'xcshareddata/xcschemes/Relay.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${buildable}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">${buildable}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n`);
console.log(`Generated iOS/Relay.xcodeproj (${appFiles.length} app sources, ${shareFiles.length} extension sources).`);
