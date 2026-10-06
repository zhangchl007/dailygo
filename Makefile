.PHONY: all test build-ffi generate-bindings clean
.PHONY: native-test native-kotlin-test native-swift-test
.PHONY: native-storage-test
.PHONY: native-project-check native-android-dependencies native-android-build native-android-ui-test native-ios-test

.DEFAULT_GOAL := native-test

native-test: native-kotlin-test native-swift-test native-storage-test

native-kotlin-test:
	bash scripts/gradle.sh :domain:test

native-swift-test:
	bash scripts/swift.sh test --package-path mobile/ios/Packages/DailyGoDomain

native-storage-test:
	bash scripts/gradle.sh :storage:test --dependency-verification strict

native-project-check:
	bash scripts/swift.sh scripts/check-native-projects.swift

native-android-dependencies:
	bash scripts/gradle.sh -PandroidApp=true :app:verifyDependencyArtifacts --dependency-verification strict

native-android-build:
	bash scripts/gradle.sh -PandroidApp=true :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest :app:lintDebug --dependency-verification strict

native-android-ui-test:
	bash scripts/gradle.sh -PandroidApp=true :app:connectedDebugAndroidTest --dependency-verification strict

native-ios-test:
	bash scripts/ios-test.sh

all: test build-ffi generate-bindings

test:
	cargo test --workspace

build-ffi:
	cargo build -p dailygo-ffi

generate-bindings: build-ffi
	cargo run -p dailygo-ffi --bin uniffi-bindgen generate target/debug/libdailygo_ffi.so --library --language swift --out-dir mobile/ios/Generated
	cargo run -p dailygo-ffi --bin uniffi-bindgen generate target/debug/libdailygo_ffi.so --library --language kotlin --out-dir mobile/android/app/src/main/java/com/dailygo/generated

# Cross-compilation helpers for iOS & Android
build-ios-sim:
	cargo build -p dailygo-ffi --target aarch64-apple-ios-sim --release

build-ios-device:
	cargo build -p dailygo-ffi --target aarch64-apple-ios --release

build-android-arm64:
	cargo build -p dailygo-ffi --target aarch64-linux-android --release

clean:
	cargo clean
