import com.android.build.gradle.BaseExtension

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
    
    // Ensure AAR metadata directories exist for Gradle 9 validation
    val subBuild = newSubprojectBuildDir.asFile
    File(subBuild, "intermediates/aar_metadata_check/debug/checkDebugAarMetadata").mkdirs()
    File(subBuild, "intermediates/aar_metadata_check/release/checkReleaseAarMetadata").mkdirs()

    afterEvaluate {
        val android = project.extensions.findByName("android") as? BaseExtension
        android?.compileSdkVersion(36)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

