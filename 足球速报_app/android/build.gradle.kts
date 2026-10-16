allprojects {
    repositories {
        // 本地 maven 仓库：io.flutter 引擎产物（download.flutter.io 无任何可达镜像，
        // 已用 curl 从 storage.flutter-io.cn 预先下载到本地，必须放在最前）
        maven(url = uri("file:///X:/maven-local"))
        google()
        // 本网络 repo.maven.apache.org 与 repo1.maven.org 均不通，
        // 走 JetBrains 官方 cache-redirector 对 Maven Central 的代理
        maven(url = "https://cache-redirector.jetbrains.com/repo1.maven.org/maven2")
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
