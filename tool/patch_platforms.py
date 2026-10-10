"""Adds Bluetooth permissions and the display name to the folders `flutter create` generates.

Run from the repository root after `flutter create --platforms android,ios .`.
Safe to run more than once.
"""

from pathlib import Path

ANDROID_MANIFEST = Path("android/app/src/main/AndroidManifest.xml")
IOS_PLIST = Path("ios/Runner/Info.plist")

ANDROID_PERMISSIONS = """
    <!-- Bluetooth LE. Android 12+ uses the BLUETOOTH_SCAN/CONNECT runtime permissions; scanning
         never derives location, so location is only requested on Android 11 and older. -->
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
"""

IOS_KEYS = """	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>BLE Kit uses Bluetooth to find and talk to nearby devices such as heart-rate monitors and receipt printers.</string>
"""


def patch_android() -> None:
    text = ANDROID_MANIFEST.read_text()
    if "BLUETOOTH_SCAN" not in text:
        index = text.index("<application")
        text = text[:index] + ANDROID_PERMISSIONS.lstrip("\n") + "\n    " + text[index:]
    text = text.replace('android:label="ble_kit"', 'android:label="BLE Kit"')
    ANDROID_MANIFEST.write_text(text)


def patch_ios() -> None:
    text = IOS_PLIST.read_text()
    if "NSBluetoothAlwaysUsageDescription" not in text:
        index = text.rindex("</dict>")
        text = text[:index] + IOS_KEYS + text[index:]
    text = text.replace("<string>Ble Kit</string>", "<string>BLE Kit</string>")
    IOS_PLIST.write_text(text)


if __name__ == "__main__":
    patch_android()
    patch_ios()
    print("patched", ANDROID_MANIFEST, IOS_PLIST)
