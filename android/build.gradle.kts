plugins {
    // Put AGP on the root build script classpath so the hook below can use the
    // public Android Gradle Plugin API without reflection.
    id("com.android.application") apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// vasflow: ensure Android library modules compile against API 36 or newer.
// Flutter plugins such as file_picker declare their own compileSdk. finalizeDsl
// runs after the plugin's `android {}` block, which is too late for a plain
// plugins.withId configuration because the plugin would overwrite it.
subprojects {
    plugins.withId("com.android.library") {
        extensions.getByType(
            com.android.build.api.variant.LibraryAndroidComponentsExtension::class.java
        ).finalizeDsl { androidExtension ->
            androidExtension.compileSdk = maxOf(36, androidExtension.compileSdk ?: 0)
        }
    }
}
