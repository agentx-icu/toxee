fun inferAndroidNamespace(manifestFile: File): String? {
    if (!manifestFile.exists()) {
        return null
    }

    val match = Regex("""package\s*=\s*"([^"]+)"""").find(manifestFile.readText())
    return match?.groupValues?.getOrNull(1)
}

fun configureMissingNamespace(project: Project) {
    val androidExtension = project.extensions.findByName("android") ?: return
    val namespaceGetter = androidExtension.javaClass.methods.find {
        it.name == "getNamespace" && it.parameterCount == 0
    } ?: return

    val currentNamespace = namespaceGetter.invoke(androidExtension) as? String
    if (!currentNamespace.isNullOrBlank()) {
        return
    }

    val inferredNamespace = inferAndroidNamespace(project.file("src/main/AndroidManifest.xml")) ?: return
    val namespaceSetter = androidExtension.javaClass.methods.find {
        it.name == "setNamespace" && it.parameterCount == 1
    } ?: return

    namespaceSetter.invoke(androidExtension, inferredNamespace)
}

val flutterIntegrationTestAndroidxPins = mapOf(
    "androidx.test:runner:1.2+" to "1.2.0",
    "androidx.test:rules:1.2+" to "1.2.0",
    "androidx.test.espresso:espresso-core:3.2+" to "3.2.0",
)

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    pluginManager.withPlugin("com.android.library") {
        configureMissingNamespace(project)
    }
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            val pin = flutterIntegrationTestAndroidxPins[
                "${requested.group}:${requested.name}:${requested.version}"
            ]
            if (pin != null) {
                useVersion(pin)
                because("Pin Flutter 3.41.9 integration_test AndroidX versions")
            }
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
