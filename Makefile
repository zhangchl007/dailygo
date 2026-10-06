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
