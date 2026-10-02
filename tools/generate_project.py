"""Regenerate the checked-in Xcode project using only the Python standard library."""
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
objects = {}


def object_id(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def add(label, isa, **values):
    identifier = object_id(label)
    objects[identifier] = {"isa": isa, **values}
    return identifier


def serialize(value, depth=0):
    indent = "\t" * depth
    if isinstance(value, dict):
        lines = [f"{indent}\t{key} = {serialize(item, depth + 1)};" for key, item in value.items()]
        return "{\n" + "\n".join(lines) + f"\n{indent}}}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{indent}\t{serialize(item, depth + 1)},\n" for item in value) + f"{indent})"
    return json.dumps(str(value))


def file_ref(path, kind):
    return add(path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")


def phase(name, isa, files):
    builds = [add("build:" + name + path, "PBXBuildFile", fileRef=ref) for path, ref in files]
    return add(name, isa, buildActionMask="2147483647", files=builds, runOnlyForDeploymentPostprocessing="0")


def configs(name, settings):
    ids = []
    for config in ["Debug", "Release"]:
        values = dict(settings)
        if name == "project":
            values.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if config == "Debug" else "-O",
                          DEBUG_INFORMATION_FORMAT="dwarf" if config == "Debug" else "dwarf-with-dsym")
            if config == "Debug":
                values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
                values["ENABLE_TESTABILITY"] = "YES"
        ids.append(add(name + config, "XCBuildConfiguration", buildSettings=values, name=config))
    return add(name + " configs", "XCConfigurationList", buildConfigurations=ids,
               defaultConfigurationIsVisible="0", defaultConfigurationName="Release")


def main():
    sources = [(str(p.relative_to(ROOT)), file_ref(str(p.relative_to(ROOT)), "sourcecode.swift"))
               for p in sorted((ROOT / "VoltIQ").rglob("*.swift"))]
    tests = [(str(p.relative_to(ROOT)), file_ref(str(p.relative_to(ROOT)), "sourcecode.swift"))
             for p in sorted((ROOT / "VoltIQTests").glob("*.swift"))]
    resources = [("VoltIQ/Assets.xcassets", file_ref("VoltIQ/Assets.xcassets", "folder.assetcatalog")),
                 ("VoltIQ/PrivacyInfo.xcprivacy", file_ref("VoltIQ/PrivacyInfo.xcprivacy", "text.xml"))]
    info = file_ref("VoltIQ/Info.plist", "text.plist.xml")
    app_product = add("app product", "PBXFileReference", explicitFileType="wrapper.application", path="VoltIQ.app", sourceTree="BUILT_PRODUCTS_DIR")
    test_product = add("test product", "PBXFileReference", explicitFileType="wrapper.cfbundle", path="VoltIQTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    app_group = add("app group", "PBXGroup", children=[ref for _, ref in sources + resources] + [info], name="VoltIQ", sourceTree="<group>")
    test_group = add("test group", "PBXGroup", children=[ref for _, ref in tests], name="VoltIQTests", sourceTree="<group>")
    products = add("products", "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
    main_group = add("main group", "PBXGroup", children=[app_group, test_group, products], sourceTree="<group>")
    project_config = configs("project", {"IPHONEOS_DEPLOYMENT_TARGET": "16.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES", "GCC_WARN_UNUSED_VARIABLE": "YES", "GCC_WARN_UNUSED_FUNCTION": "YES"})
    app_config = configs("app", {"PRODUCT_BUNDLE_IDENTIFIER": "com.voltiq.ios", "PRODUCT_NAME": "$(TARGET_NAME)",
        "INFOPLIST_FILE": "VoltIQ/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "CODE_SIGN_STYLE": "Automatic",
        "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
        "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"]})
    app_target = add("app target", "PBXNativeTarget", buildConfigurationList=app_config,
        buildPhases=[phase("app sources", "PBXSourcesBuildPhase", sources), phase("app frameworks", "PBXFrameworksBuildPhase", []),
                     phase("app resources", "PBXResourcesBuildPhase", resources)], buildRules=[], dependencies=[], name="VoltIQ",
        productName="VoltIQ", productReference=app_product, productType="com.apple.product-type.application")
    proxy = add("test proxy", "PBXContainerItemProxy", containerPortal=object_id("project"), proxyType="1", remoteGlobalIDString=app_target, remoteInfo="VoltIQ")
    dependency = add("test dependency", "PBXTargetDependency", target=app_target, targetProxy=proxy)
    test_config = configs("test", {"PRODUCT_BUNDLE_IDENTIFIER": "com.voltiq.ios.tests", "PRODUCT_NAME": "$(TARGET_NAME)",
        "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1,2",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/VoltIQ.app/VoltIQ", "BUNDLE_LOADER": "$(TEST_HOST)",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]})
    test_target = add("test target", "PBXNativeTarget", buildConfigurationList=test_config,
        buildPhases=[phase("test sources", "PBXSourcesBuildPhase", tests), phase("test frameworks", "PBXFrameworksBuildPhase", [])],
        buildRules=[], dependencies=[dependency], name="VoltIQTests", productName="VoltIQTests", productReference=test_product,
        productType="com.apple.product-type.bundle.unit-test")
    project = add("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "16.0"},
        test_target: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app_target}}}, buildConfigurationList=project_config,
        compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings="0", knownRegions=["en", "Base"],
        mainGroup=main_group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[app_target, test_target])
    document = {"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project}
    (ROOT / "VoltIQ.xcodeproj/project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(document) + "\n")
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="VoltIQ.app" BlueprintName="VoltIQ" ReferencedContainer="container:VoltIQ.xcodeproj"/></BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
    <TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="VoltIQTests.xctest" BlueprintName="VoltIQTests" ReferencedContainer="container:VoltIQ.xcodeproj"/></TestableReference>
  </Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="VoltIQ.app" BlueprintName="VoltIQ" ReferencedContainer="container:VoltIQ.xcodeproj"/></BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="VoltIQ.app" BlueprintName="VoltIQ" ReferencedContainer="container:VoltIQ.xcodeproj"/></BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (ROOT / "VoltIQ.xcodeproj/xcshareddata/xcschemes/VoltIQ.xcscheme").write_text(scheme)
    print(f"Generated project: app target {app_target}, test target {test_target}")


if __name__ == "__main__":
    main()
