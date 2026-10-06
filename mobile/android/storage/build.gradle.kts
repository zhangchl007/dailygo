plugins {
    kotlin("jvm")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.devtools.ksp")
}

kotlin {
    jvmToolchain(17)
    sourceSets.main { kotlin.srcDir("src/shared/kotlin") }
}

dependencies {
    implementation(project(":domain"))
    implementation("androidx.room:room-runtime:2.7.2")
    implementation("androidx.sqlite:sqlite-bundled:2.5.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0")
    ksp("androidx.room:room-compiler:2.7.2")
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.4")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.11.4")
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencyLocking {
    lockAllConfigurations()
}

tasks.test {
    useJUnitPlatform()
    testLogging { events("passed", "failed", "skipped") }
}