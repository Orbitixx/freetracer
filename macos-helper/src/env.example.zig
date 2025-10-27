pub const BUNDLE_ID = "com.example.myapp-helper";
pub const MAIN_APP_BUNDLE_ID = "com.example.myapp";
pub const MAIN_APP_TEAM_ID = "XXXXXXXXXX";
// User home path to be used for tests
pub const USER_HOME_PATH = "/Users/USER_NAME";
// Path to a valid, bootable ISO file to be used for tests
pub const TEST_ISO_FILE_PATH = "/Path/to/known/bootable/iso";

pub const HELPER_VERSION: [:0]const u8 = "1.0";

pub const INFO_PLIST =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    \\<plist version="1.0">
    \\<dict>
    \\  <key>CFBundleIdentifier</key>
    \\      <string>com.example.myapp-helper</string>
    \\  <key>CFBundleInfoDictionaryVersion</key>
    \\      <string>6.0</string>
    \\  <key>CFBundleName</key>
    \\      <string>Freetracer Helper</string>
    \\  <key>CFBundleVersion</key>
    \\      <string>3</string>
    \\  <key>MachServices</key>
    \\  <dict>
    \\    <key>com.example.myapp-helper</key>
    \\      <true/>
    \\  </dict>
    \\  <key>SMAuthorizedClients</key>
    \\      <array>
    \\          <string>identifier "com.example.myapp" and anchor apple generic and certificate leaf[subject.OU] = "XXXXXXXXX" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */</string>
    \\      </array>
    \\</dict>
    \\</plist> 
;

pub const LAUNCHD_PLIST =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    \\<plist version="1.0">
    \\<dict>
    \\<key>Label</key>
    \\<string>com.example.myapp-helper</string>
    \\<key>ProgramArguments</key>
    \\<array>
    \\<string>/Library/PrivilegedHelperTools/com.example.myapp-helper</string>
    \\</array>
    \\<key>MachServices</key>
    \\<dict>
    \\<key>com.example.myapp-helper</key>
    \\<true/>
    \\</dict>
    \\<key>StandardOutPath</key>
    \\<string>/var/log/obx.stdout</string>
    \\<key>StandardErrorPath</key>
    \\<string>/var/log/obx.stderr</string>
    \\<key>Program</key>
    \\<string>/Library/PrivilegedHelperTools/com.example.myapp-helper</string>
    \\<key>ProgramArguments</key>
    \\<array>
    \\    <string>/Library/PrivilegedHelperTools/com.example.myapp-helper</string>
    \\</array>
    \\</dict>
    \\</plist>
;
