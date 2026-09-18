#!/usr/bin/env python3
"""Deterministic Xcode project generator, requires only Python's standard library."""
import hashlib
import json
import pathlib

root = pathlib.Path(__file__).resolve().parents[1]
objects = {}
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(object_key, isa, **attributes):
    key = ident(object_key); objects[key] = dict(isa=isa, **attributes); return key
def encode(value, indent=0):
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (indent + 1) + json.dumps(k) + " = " + encode(v, indent + 1) + ";\n" for k, v in value.items()) + "\t" * indent + "}"
    if isinstance(value, list): return "(" + ", ".join(encode(v, indent) for v in value) + ")"
    return json.dumps(str(value))
def file(path, filetype): return add("file:" + path, "PBXFileReference", path=path, sourceTree="SOURCE_ROOT", lastKnownFileType=filetype)
def build(name, reference): return add("build:" + name, "PBXBuildFile", fileRef=reference)

assets = root / "iOS/Resources/Assets.xcassets"
icon = assets / "AppIcon.appiconset"; icon.mkdir(parents=True, exist_ok=True)
(assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
(icon / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2))
completion = assets / "CompletionArtwork.imageset"; completion.mkdir(parents=True, exist_ok=True)
(completion / "Contents.json").write_text(json.dumps({"images": [{"filename": "CompletionArtwork.png", "idiom": "universal", "scale": "1x"}], "info": {"author": "xcode", "version": 1}}, indent=2))
closing_photo = assets / "ClosingPhoto.imageset/ClosingPhoto.jpg"
for required_artwork in [icon / "AppIcon.png", completion / "CompletionArtwork.png", closing_photo]:
    if not required_artwork.exists():
        raise SystemExit(f"Missing visual asset: {required_artwork}. Restore it from Design/ or add an authorized replacement.")

projectID = ident("project")
appID = ident("target:app")
localAppID = ident("target:local-app")
coreID = ident("target:core")
testsID = ident("target:tests")
uiTestsID = ident("target:ui-tests")
appSources = [str(path.relative_to(root)) for path in sorted((root / "iOS").rglob("*.swift"))]
coreSources = ["Core/Session.swift"]
testSources = [str(path.relative_to(root)) for folder in [root / "Tests/CoreTests", root / "Tests/iOSTests"] for path in sorted(folder.rglob("*.swift"))]
uiTestSources = [str(path.relative_to(root)) for path in sorted((root / "Tests/UITests").rglob("*.swift"))]
allSourceRefs = []
sourceFileRefs = {}
def sourcePhase(name, paths):
    builds = []
    for path in paths:
        reference = sourceFileRefs.get(path)
        if reference is None:
            reference = file(path, "sourcecode.swift")
            sourceFileRefs[path] = reference
            allSourceRefs.append(reference)
        builds.append(build(name + path, reference))
    return add("sources:" + name, "PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
appPhase = sourcePhase("app", appSources); localAppPhase = sourcePhase("local-app", appSources); corePhase = sourcePhase("core", coreSources); testPhase = sourcePhase("tests", testSources); uiTestPhase = sourcePhase("ui-tests", uiTestSources)
resources = []
resourceRefs = []
resourceEntries = []
for path in sorted((root / "iOS/Resources").iterdir()):
    if path.is_file() or path.suffix == ".xcassets":
        relative = str(path.relative_to(root))
        kind = {".wav": "audio.wav", ".m4a": "audio.m4a", ".xcassets": "folder.assetcatalog", ".plist": "text.plist.xml", ".xcprivacy": "text.xml"}.get(path.suffix, "text.json")
        reference = file(relative, kind); resourceRefs.append(reference); resourceEntries.append((relative, reference)); resources.append(build("resource:" + relative, reference))
resourcesPhase = add("resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)
localResources = [build("local-resource:" + relative, reference) for relative, reference in resourceEntries]
localResourcesPhase = add("local-resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=localResources, runOnlyForDeploymentPostprocessing=0)
appProduct = add("product:app", "PBXFileReference", explicitFileType="wrapper.application", path="Meditacion.app", sourceTree="BUILT_PRODUCTS_DIR")
localAppProduct = add("product:local-app", "PBXFileReference", explicitFileType="wrapper.application", path="EvamorLocal.app", sourceTree="BUILT_PRODUCTS_DIR")
coreProduct = add("product:core", "PBXFileReference", explicitFileType="wrapper.framework", path="MeditationCore.framework", sourceTree="BUILT_PRODUCTS_DIR")
testProduct = add("product:tests", "PBXFileReference", explicitFileType="wrapper.cfbundle", path="MeditacionTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
uiTestProduct = add("product:ui-tests", "PBXFileReference", explicitFileType="wrapper.cfbundle", path="DhammaUITests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
def frameworks(name, refs): return add("frameworks:" + name, "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=refs, runOnlyForDeploymentPostprocessing=0)
appFrameworks = frameworks("app", [build("app:core", coreProduct)])
localAppFrameworks = frameworks("local-app", [build("local-app:core", coreProduct)])
testFrameworks = frameworks("tests", [build("tests:core", coreProduct)])
uiTestFrameworks = frameworks("ui-tests", [])
coreFrameworks = frameworks("core", [])
def dependency(name, target):
    proxy = add("proxy:" + name, "PBXContainerItemProxy", containerPortal=projectID, proxyType=1, remoteGlobalIDString=target, remoteInfo=name)
    return add("dependency:" + name, "PBXTargetDependency", target=target, targetProxy=proxy)
appCoreDependency = dependency("app:core", coreID)
localAppCoreDependency = dependency("local-app:core", coreID)
testCoreDependency = dependency("tests:core", coreID)
testAppDependency = dependency("tests:app", appID)
uiTestAppDependency = dependency("ui-tests:app", appID)
common = {"IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0", "CLANG_ENABLE_MODULES": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES", "TARGETED_DEVICE_FAMILY": "1"}
def configurations(name, extra):
    refs = []
    for mode in ["Debug", "Release"]:
        settings = dict(common, **extra)
        settings.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym"})
        if mode == "Debug": settings.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "ENABLE_TESTABILITY": "YES"})
        if name == "local-app": settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG EVAMOR_LOCAL" if mode == "Debug" else "EVAMOR_LOCAL"
        if name == "app": settings["APS_ENVIRONMENT"] = "development" if mode == "Debug" else "production"
        refs.append(add("config:" + name + mode, "XCBuildConfiguration", name=mode, buildSettings=settings))
    return add("configlist:" + name, "XCConfigurationList", buildConfigurations=refs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
projectConfigs = configurations("project", {"CODE_SIGN_STYLE": "Automatic", "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES"})
appConfigs = configurations("app", {"PRODUCT_NAME": "Meditacion", "PRODUCT_BUNDLE_IDENTIFIER": "com.manuelbecerril.evamor", "INFOPLIST_FILE": "iOS/Info.plist", "CODE_SIGN_ENTITLEMENTS": "iOS/Meditacion.entitlements", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
localAppConfigs = configurations("local-app", {"PRODUCT_NAME": "EvamorLocal", "PRODUCT_BUNDLE_IDENTIFIER": "com.manuelbecerril.evamor.local", "DEVELOPMENT_TEAM": "X5MB743UFG", "INFOPLIST_FILE": "iOS/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
coreConfigs = configurations("core", {"PRODUCT_NAME": "MeditationCore", "PRODUCT_BUNDLE_IDENTIFIER": "com.example.meditacion.core", "DEFINES_MODULE": "YES", "GENERATE_INFOPLIST_FILE": "YES", "MACH_O_TYPE": "staticlib", "SKIP_INSTALL": "YES", "CODE_SIGNING_ALLOWED": "NO"})
testConfigs = configurations("tests", {"PRODUCT_NAME": "MeditacionTests", "PRODUCT_BUNDLE_IDENTIFIER": "com.example.meditacion.tests", "GENERATE_INFOPLIST_FILE": "YES", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Meditacion.app/Meditacion", "BUNDLE_LOADER": "$(TEST_HOST)"})
uiTestConfigs = configurations("ui-tests", {"PRODUCT_NAME": "DhammaUITests", "PRODUCT_BUNDLE_IDENTIFIER": "com.example.meditacion.uitests", "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "Meditacion"})
add("target:app", "PBXNativeTarget", name="Meditacion", productName="Meditacion", productReference=appProduct, productType="com.apple.product-type.application", buildConfigurationList=appConfigs, buildPhases=[appPhase, appFrameworks, resourcesPhase], buildRules=[], dependencies=[appCoreDependency], packageProductDependencies=[])
add("target:local-app", "PBXNativeTarget", name="Evamor Local", productName="EvamorLocal", productReference=localAppProduct, productType="com.apple.product-type.application", buildConfigurationList=localAppConfigs, buildPhases=[localAppPhase, localAppFrameworks, localResourcesPhase], buildRules=[], dependencies=[localAppCoreDependency], packageProductDependencies=[])
add("target:core", "PBXNativeTarget", name="MeditationCore", productName="MeditationCore", productReference=coreProduct, productType="com.apple.product-type.framework", buildConfigurationList=coreConfigs, buildPhases=[corePhase, coreFrameworks], buildRules=[], dependencies=[])
add("target:tests", "PBXNativeTarget", name="MeditacionTests", productName="MeditacionTests", productReference=testProduct, productType="com.apple.product-type.bundle.unit-test", buildConfigurationList=testConfigs, buildPhases=[testPhase, testFrameworks], buildRules=[], dependencies=[testCoreDependency, testAppDependency])
add("target:ui-tests", "PBXNativeTarget", name="DhammaUITests", productName="DhammaUITests", productReference=uiTestProduct, productType="com.apple.product-type.bundle.ui-testing", buildConfigurationList=uiTestConfigs, buildPhases=[uiTestPhase, uiTestFrameworks], buildRules=[], dependencies=[uiTestAppDependency])
productsGroup = add("products", "PBXGroup", name="Products", sourceTree="<group>", children=[appProduct, localAppProduct, coreProduct, testProduct, uiTestProduct])
configRefs = [file("iOS/Info.plist", "text.plist.xml"), file("iOS/Meditacion.entitlements", "text.plist.entitlements")]
mainGroup = add("mainGroup", "PBXGroup", sourceTree="<group>", children=allSourceRefs + resourceRefs + configRefs + [productsGroup])
add("project", "PBXProject", attributes={"LastUpgradeCheck": "1620", "TargetAttributes": {appID: {"SystemCapabilities": {"com.apple.Push": {"enabled": 1}, "com.apple.iCloud": {"enabled": 1}, "com.apple.BackgroundModes": {"enabled": 1}}}, testsID: {"TestTargetID": appID}, uiTestsID: {"TestTargetID": appID}}}, buildConfigurationList=projectConfigs, compatibilityVersion="Xcode 14.0", developmentRegion="es", hasScannedForEncodings=0, knownRegions=["es", "en", "Base"], mainGroup=mainGroup, productRefGroup=productsGroup, projectDirPath="", projectRoot="", targets=[appID, localAppID, coreID, testsID, uiTestsID], packageReferences=[])
projectFolder = root / "Meditacion.xcodeproj"; projectFolder.mkdir(exist_ok=True)
(projectFolder / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": projectID}) + "\n")
schemes = projectFolder / "xcshareddata/xcschemes"; schemes.mkdir(parents=True, exist_ok=True)
def buildable(target, name, blueprint=None): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{blueprint or name.split(".")[0]}" ReferencedContainer="container:Meditacion.xcodeproj"/>'
(schemes / "Meditacion.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1620" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable(appID, "Meditacion.app")}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildable(testsID, "MeditacionTests.xctest")}</TestableReference><TestableReference skipped="NO">{buildable(uiTestsID, "DhammaUITests.xctest")}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable(appID, "Meditacion.app")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable(appID, "Meditacion.app")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
(schemes / "Evamor Local.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1620" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="NO" buildForAnalyzing="YES">{buildable(localAppID, "EvamorLocal.app", "Evamor Local")}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable(localAppID, "EvamorLocal.app", "Evamor Local")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable(localAppID, "EvamorLocal.app", "Evamor Local")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
</Scheme>''')
print("Generated Meditacion.xcodeproj while preserving the visual assets")
