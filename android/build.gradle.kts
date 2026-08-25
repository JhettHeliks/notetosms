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

    val configureAndroidSubproject: () -> Unit = {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            try {
                // 1. Fallback namespace configuration
                val getNamespaceMethod = androidExt.javaClass.methods.firstOrNull { it.name == "getNamespace" && it.parameterCount == 0 }
                val setNamespaceMethod = androidExt.javaClass.methods.firstOrNull { it.name == "setNamespace" && it.parameterCount == 1 && it.parameterTypes[0] == String::class.java }

                val currentNamespace = getNamespaceMethod?.invoke(androidExt) as? String
                if (currentNamespace.isNullOrBlank() && setNamespaceMethod != null) {
                    val fallbackNamespace = when (project.name) {
                        "ota_update" -> "sk.fourq.otaupdate"
                        else -> {
                            val grp = project.group.toString()
                            if (grp.isNotBlank() && grp != "unspecified") {
                                grp
                            } else {
                                "com.app.plugin.${project.name.replace('-', '_')}"
                            }
                        }
                    }
                    setNamespaceMethod.invoke(androidExt, fallbackNamespace)
                }

                // 2. Ensure compileSdkVersion is at least 34 for modern resource linking
                val getCompileSdkVersionMethod = androidExt.javaClass.methods.firstOrNull { it.name == "getCompileSdkVersion" && it.parameterCount == 0 }
                val setCompileSdkVersionMethod = androidExt.javaClass.methods.firstOrNull { 
                    (it.name == "compileSdkVersion" || it.name == "setCompileSdkVersion") && it.parameterCount == 1 && (it.parameterTypes[0] == Int::class.javaPrimitiveType || it.parameterTypes[0] == Integer::class.java)
                }
                if (setCompileSdkVersionMethod != null) {
                    val currentSdk = getCompileSdkVersionMethod?.invoke(androidExt)
                    val sdkInt = when (currentSdk) {
                        is Int -> currentSdk
                        is String -> currentSdk.replace("android-", "").toIntOrNull() ?: 0
                        else -> 0
                    }
                    if (sdkInt < 34) {
                        setCompileSdkVersionMethod.invoke(androidExt, 34)
                    }
                }
            } catch (e: Exception) {
                // Ignore reflection error
            }
        }
    }

    if (project.state.executed) {
        configureAndroidSubproject()
    } else {
        project.afterEvaluate {
            configureAndroidSubproject()
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
