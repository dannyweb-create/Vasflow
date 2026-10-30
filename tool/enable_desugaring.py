#!/usr/bin/env python3
"""Apply the Android build settings that Flutter's generator does not add.

Run from the repository root after `flutter create` has generated android/.
The script is idempotent: running it again makes no changes.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

MIN_COMPILE_SDK = 36
DESUGAR_DEPENDENCY = "com.android.tools:desugar_jdk_libs:2.1.4"

APP_GRADLE = Path("android/app/build.gradle.kts")
ROOT_GRADLE = Path("android/build.gradle.kts")

ROOT_PLUGINS = """plugins {
    // Put AGP on the root build script classpath so the hook below can use the
    // public Android Gradle Plugin API without reflection.
    id("com.android.application") apply false
}
"""

ROOT_HOOK_MARKER = "// vasflow: ensure Android library modules compile against API 36"

ROOT_HOOK = f"""
{ROOT_HOOK_MARKER} or newer.
// Flutter plugins such as file_picker declare their own compileSdk. finalizeDsl
// runs after the plugin's `android {{}}` block, which is too late for a plain
// plugins.withId configuration because the plugin would overwrite it.
subprojects {{
    plugins.withId("com.android.library") {{
        extensions.getByType(
            com.android.build.api.variant.LibraryAndroidComponentsExtension::class.java
        ).finalizeDsl {{ androidExtension ->
            androidExtension.compileSdk = maxOf({MIN_COMPILE_SDK}, androidExtension.compileSdk ?: 0)
        }}
    }}
}}
"""

DESUGAR_PATTERN = re.compile(
    r"^[ \t]*coreLibraryDesugaring\(\s*\"[^\"]*desugar_jdk_libs[^\"]*\"\s*\)[ \t]*\n",
    re.M,
)


class PatchError(Exception):
    pass


def _read(path: Path) -> str:
    if not path.exists():
        raise PatchError(f"{path} not found; run this after `flutter create` generated android/.")
    return path.read_text()


def _write_if_changed(path: Path, old: str, new: str) -> bool:
    if old == new:
        return False
    path.write_text(new)
    return True


def patch_app_gradle(text: str) -> str:
    compile_sdk = re.compile(
        r"^([ \t]*)compileSdk(?:Version)?\s*=\s*(.+?)\s*$",
        re.M,
    )
    match = compile_sdk.search(text)
    if not match:
        raise PatchError(f"No compileSdk assignment found in {APP_GRADLE}.")
    if not re.search(r"compileSdk\s*=\s*maxOf\(\s*36\s*,", text):
        indent, expression = match.group(1), match.group(2)
        text = (
            text[: match.start()]
            + f"{indent}compileSdk = maxOf({MIN_COMPILE_SDK}, {expression})"
            + text[match.end() :]
        )

    if not re.search(r"isCoreLibraryDesugaringEnabled\s*=\s*true", text):
        if re.search(r"isCoreLibraryDesugaringEnabled\s*=\s*false", text):
            text = re.sub(
                r"isCoreLibraryDesugaringEnabled\s*=\s*false",
                "isCoreLibraryDesugaringEnabled = true",
                text,
                count=1,
            )
        else:
            compile_options = re.search(r"^([ \t]*)compileOptions\s*\{\s*\n", text, re.M)
            if not compile_options:
                raise PatchError(f"No compileOptions block found in {APP_GRADLE}.")
            indent = compile_options.group(1) + "    "
            text = (
                text[: compile_options.end()]
                + f"{indent}isCoreLibraryDesugaringEnabled = true\n"
                + text[compile_options.end() :]
            )

    text = DESUGAR_PATTERN.sub("", text)
    dependencies = re.search(r"^dependencies\s*\{\s*\n", text, re.M)
    dependency_line = f'    coreLibraryDesugaring("{DESUGAR_DEPENDENCY}")\n'
    if dependencies:
        text = (
            text[: dependencies.end()]
            + dependency_line
            + text[dependencies.end() :]
        )
    else:
        text = text.rstrip("\n") + "\n\ndependencies {\n" + dependency_line + "}\n"
    return text


def patch_root_gradle(text: str) -> str:
    app_plugin = 'id("com.android.application") apply false'
    if app_plugin not in text:
        plugins = re.search(r"^plugins\s*\{\s*\n", text, re.M)
        if plugins:
            text = (
                text[: plugins.end()]
                + f"    {app_plugin}\n"
                + text[plugins.end() :]
            )
        else:
            text = ROOT_PLUGINS + "\n" + text

    if ROOT_HOOK_MARKER not in text:
        if not text.endswith("\n"):
            text += "\n"
        text += ROOT_HOOK
    return text


def main() -> int:
    app_old = _read(APP_GRADLE)
    root_old = _read(ROOT_GRADLE)

    app_new = patch_app_gradle(app_old)
    root_new = patch_root_gradle(root_old)

    if len(re.findall(r"coreLibraryDesugaring\(", app_new)) != 1:
        raise PatchError("Expected exactly one coreLibraryDesugaring dependency.")
    if not re.search(r"isCoreLibraryDesugaringEnabled\s*=\s*true", app_new):
        raise PatchError("Core library desugaring is not enabled.")
    if ROOT_HOOK_MARKER not in root_new:
        raise PatchError("The Android library compileSdk hook was not written.")

    app_changed = _write_if_changed(APP_GRADLE, app_old, app_new)
    root_changed = _write_if_changed(ROOT_GRADLE, root_old, root_new)

    print(f"{APP_GRADLE}: {'updated' if app_changed else 'already correct'}")
    print(f"{ROOT_GRADLE}: {'updated' if root_changed else 'already correct'}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except PatchError as error:
        sys.exit(f"ERROR (tool/enable_desugaring.py): {error}")
