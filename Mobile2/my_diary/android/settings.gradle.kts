pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 国内镜像（首选，加速 AGP/Kotlin/Gradle 插件下载；华为/腾讯补齐 kotlin-reflect 等）
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://repo.huaweicloud.com/repository/maven/") }
        maven { url = uri("https://repo.huaweicloud.com/repository/google/") }
        maven { url = uri("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/") }
        maven { url = uri("https://maven.pkg.jetbrains.space/public/p/kotlinx-html/maven") }
        // 原仓库兜底
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

// 关键修复：部分插件（如 geolocator_android）在自身 buildscript 里硬编码
// google()/mavenCentral()，其 buildscript classpath 不经过 pluginManagement，
// 导致 kotlin-reflect:2.2.10 等传递依赖在部分网络下 TLS 握手失败。
// 在每个工程求值前向 buildscript 注入国内镜像，确保先从镜像解析。
gradle.beforeProject { project ->
    project.buildscript.repositories.maven { setUrl("https://maven.aliyun.com/repository/google") }
    project.buildscript.repositories.maven { setUrl("https://maven.aliyun.com/repository/central") }
    project.buildscript.repositories.maven { setUrl("https://maven.aliyun.com/repository/public") }
    project.buildscript.repositories.maven { setUrl("https://repo.huaweicloud.com/repository/maven/") }
    project.buildscript.repositories.maven { setUrl("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/") }
}

include(":app")
