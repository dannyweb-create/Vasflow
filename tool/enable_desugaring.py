from pathlib import Path

path = Path("android/app/build.gradle.kts")

if not path.exists():
    raise SystemExit("Gradle file not found")

text = path.read_text()

if "isCoreLibraryDesugaringEnabled = true" not in text:
    text = text.replace(
        "compileOptions {",
        "compileOptions {\n        isCoreLibraryDesugaringEnabled = true",
        1,
    )

if "coreLibraryDesugaring(" not in text:
    text = text.replace(
        "kotlin {",
        'dependencies {\n'
        '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
        '}\n\n'
        "kotlin {",
        1,
    )

path.write_text(text)
print("Core library desugaring configured.")
