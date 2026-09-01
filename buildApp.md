# 1. Boot a simulator and open the Simulator app
xcrun simctl boot "iPhone 13"
open -a Simulator

# 2. Build for that simulator
xcodebuild -project Ember.xcodeproj -scheme Ember \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build

# 3. Install and launch
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Ember.app
xcrun simctl launch booted com.ember.app