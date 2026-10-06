.PHONY: all test build-ffi generate-bindings clean
.PHONY: native-test native-kotlin-test native-swift-test

.DEFAULT_GOAL := native-test

native-test: native-kotlin-test native-swift-test

native-kotlin-test:
	bash scripts/gradle.sh :domain:test

native-swift-test:
	bash scripts/swift.sh test --package-path mobile/ios/Packages/DailyGoDomain

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
