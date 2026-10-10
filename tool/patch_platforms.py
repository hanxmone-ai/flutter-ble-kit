"""Adds Bluetooth permissions and the app name to the generated platform
projects. Run once after `flutter create`; safe to run again."""

import re
from pathlib import Path

APP_NAME = "BLE Kit"

ANDROID_PERMISSIONS = """
    <!-- Bluetooth LE: Android 12+ -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <!-- Bluetooth LE: Android 11 and older -->
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
"""

IOS_KEYS = """	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>BLE Kit uses Bluetooth to find and talk to nearby devices such as sensors and receipt printers.</string>
"""


def patch_android() -> None:
    path = Path("android/app/src/main/AndroidManifest.xml")
    text = path.read_text()
    if "BLUETOOTH_SCAN" not in text:
        text = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + "\n" + ANDROID_PERMISSIONS, text, count=1)
    text = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', text, count=1)
    path.write_text(text)


def patch_ios() -> None:
    path = Path("ios/Runner/Info.plist")
    text = path.read_text()
    if "NSBluetoothAlwaysUsageDescription" not in text:
        index = text.rindex("</dict>")
        text = text[:index] + IOS_KEYS + text[index:]
    text = re.sub(
        r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)",
        lambda m: m.group(1) + APP_NAME + m.group(2),
        text,
    )
    path.write_text(text)


def patch_web() -> None:
    index = Path("web/index.html")
    text = index.read_text()
    text = re.sub(r"<title>[^<]*</title>", f"<title>{APP_NAME} · Flutter Bluetooth LE demo</title>", text)
    text = re.sub(r'(<meta name="description" content=")[^"]*(")',
                  lambda m: m.group(1) + "Scan, connect, inspect GATT and print receipts over Bluetooth LE. "
                  "Runs with simulated devices in the browser." + m.group(2), text)
    text = re.sub(r'(apple-mobile-web-app-title" content=")[^"]*(")', lambda m: m.group(1) + APP_NAME + m.group(2), text)
    index.write_text(text)
    manifest = Path("web/manifest.json")
    if manifest.exists():
        m = manifest.read_text()
        m = re.sub(r'"name": "[^"]*"', f'"name": "{APP_NAME}"', m)
        m = re.sub(r'"short_name": "[^"]*"', f'"short_name": "{APP_NAME}"', m)
        m = re.sub(r'"theme_color": "[^"]*"', '"theme_color": "#0F766E"', m)
        m = re.sub(r'"background_color": "[^"]*"', '"background_color": "#12171A"', m)
        manifest.write_text(m)


if __name__ == "__main__":
    patch_android()
    patch_ios()
    patch_web()
    print("patched android, ios and web")
