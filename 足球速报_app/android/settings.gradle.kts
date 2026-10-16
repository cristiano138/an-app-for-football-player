pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            // 注意：Properties.load(InputStream) 固定按 ISO-8859-1 解码，
            // 中文路径（定时球报）必须是 UTF-8 读取，否则 includeBuild 路径会乱码。
            file("local.properties").reader(Charsets.UTF_8).use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        // 本网络 plugins.gradle.org 不通，走 JetBrains 官方 cache-redirector 镜像
        maven(url = "https://cache-redirector.jetbrains.com/plugins.gradle.org/m2")
        // repo.maven.apache.org / repo1.maven.org 均不通，用 redirector 代理 Maven Central 兜底
        maven(url = "https://cache-redirector.jetbrains.com/repo1.maven.org/maven2")
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
