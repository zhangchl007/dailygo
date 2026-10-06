plugins {
    kotlin("jvm")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.4")
    testImplementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.11.4")
}

dependencyLocking {
    lockAllConfigurations()
}

tasks.test {
    useJUnitPlatform()
    systemProperty("dailygo.fixtures", rootProject.file("../../tests/fixtures").absolutePath)
    inputs.dir(rootProject.file("../../tests/fixtures"))
    testLogging {
        events("passed", "failed", "skipped")
    }
}