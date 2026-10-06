plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.devtools.ksp")
}

android {
    namespace = "com.dailygo"
    compileSdk = 36
    buildToolsVersion = "35.0.0"

    defaultConfig {
        applicationId = "com.dailygo"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    sourceSets {
        getByName("main") {
            java.setSrcDirs(listOf("src/main/kotlin", "../storage/src/shared/kotlin"))
            jniLibs.setSrcDirs(emptyList<String>())
        }
        getByName("androidTest").assets.srcDir("../storage/schemas")
        getByName("androidTest").assets.srcDir("../../../tests/fixtures/legacy")
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

kotlin {
    jvmToolchain(17)
    sourceSets.getByName("main").kotlin.setSrcDirs(listOf("src/main/kotlin", "../storage/src/shared/kotlin"))
    sourceSets.getByName("androidTest").kotlin.srcDir("../storage/src/sharedTest/kotlin")
}

val verificationBuildTools by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
}

dependencies {
    verificationBuildTools("com.android.tools.build:aapt2:8.10.1-12782657:linux")
    verificationBuildTools("com.android.tools.lint:lint-gradle:31.10.1")
    implementation(project(":domain"))
    implementation("androidx.room:room-runtime:2.7.2")
    implementation("androidx.sqlite:sqlite-bundled:2.5.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0")
    ksp("androidx.room:room-compiler:2.7.2")
    implementation(platform("androidx.compose:compose-bom:2025.04.01"))
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling:1.8.0")
    debugImplementation("androidx.compose.ui:ui-test-manifest:1.8.0")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation(platform("androidx.compose:compose-bom:2025.04.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}

dependencyLocking {
    lockAllConfigurations()
}

ksp {
    arg("room.schemaLocation", "${rootProject.projectDir}/storage/schemas")
}

tasks.register("verifyDependencyArtifacts") {
    group = "verification"
    description = "Resolve app/test runtime and AAPT2/Lint tool artifacts for checksum verification without an Android SDK."
    doLast {
        configurations.filter { it.isCanBeResolved && it.name.endsWith("RuntimeClasspath") }
            .forEach { it.resolve() }
        verificationBuildTools.resolve()
    }
}