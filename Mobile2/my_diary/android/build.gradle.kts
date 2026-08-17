allprojects {
    // 关键修复：插件工程（如 geolocator_android）在自身 buildscript 里硬编码
    // google()/mavenCentral()，其 classpath 不继承 pluginManagement。
    // 在此向所有工程的 buildscript 注入国内镜像，确保 kotlin-reflect:2.2.10 等可解析。
    buildscript {
        repositories {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/central") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
            maven { url = uri("https://repo.huaweicloud.com/repository/maven/") }
            maven { url = uri("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/") }
        }
    }
    repositories {
        // 国内镜像（首选，加速依赖解析；华为/腾讯补齐 kotlin-reflect 等）
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://repo.huaweicloud.com/repository/maven/") }
        maven { url = uri("https://repo.huaweicloud.com/repository/google/") }
        maven { url = uri("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/") }
        maven { url = uri("https://maven.pkg.jetbrains.space/public/p/kotlinx-html/maven") }
        // 原仓库兜底
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
