#!/bin/bash
set -e

APK="$1"
if [[ -z "$APK" ]]; then
  echo "Usage: $0 app.apk <package-name> (package-name example: org.hempuli.baba)"
  exit 1
fi

APKTOOL_JAR="./utils/apktool.jar"
APK_SIGNER_JAR="./utils/uber-apk-signer.jar"
KEYSTORE="./utils/signkey.jks"
KEY_ALIAS="signkey"
KEY_PASS="password"
STORE_PASS="password"
KEY_VALIDITY=100000  # days (~273 years)
WORKDIR="tmp"

# Download apktool if missing
if [ ! -f "$APKTOOL_JAR" ]; then
  echo "Downloading apktool..."
  curl -L https://github.com/iBotPeaches/Apktool/releases/download/v2.7.0/apktool_2.7.0.jar -o "$APKTOOL_JAR"
fi

# Download uber-apk-signer if missing
if [ ! -f "$APK_SIGNER_JAR" ]; then
  echo "Downloading uber-apk-signer..."
  curl -L https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar -o "$APK_SIGNER_JAR"
fi

# Generate keystore if missing
if [ ! -f "$KEYSTORE" ]; then
  echo "Generating keystore..."
  keytool -genkeypair -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity $KEY_VALIDITY \
    -keystore "$KEYSTORE" -storepass "$STORE_PASS" -keypass "$KEY_PASS" \
    -dname "CN=User, OU=Dev, O=Org, L=City, S=State, C=US" -noprompt
fi

rm -rf "$WORKDIR"

# echo "Decoding APK..."
java -jar "$APKTOOL_JAR" d -f "$APK" -o "$WORKDIR"

cd $WORKDIR

PKGNAME_DOT=$(grep -oP '(?<=package=")[^"]+' AndroidManifest.xml)
PKGNAME_SLASH="${PKGNAME_DOT//./\/}"

# 1. Copy smali files and replace package
mkdir -p "smali/$PKGNAME_SLASH"
for f in ../utils/saveman/SavemanActivity*.smali; do
    out="smali/$PKGNAME_SLASH/$(basename "$f")"
    if [ ! -f "$out" ] || ! grep -q "$PKGNAME_SLASH" "$out"; then
        sed "s|xyz/smt|$PKGNAME_SLASH|g" "$f" > "$out"
    fi
done

# 2. Add string to strings.xml
if ! grep -q 'shortcut_saveman' res/values/strings.xml; then
    sed -i '/<\/resources>/i\    <string name="shortcut_saveman">Save Manager</string>' res/values/strings.xml
fi

# 3. Update R$string.smali
RSTRING="smali/$PKGNAME_SLASH/R\$string.smali"
if [ -f "$RSTRING" ] && ! grep -q 'shortcut_saveman' "$RSTRING"; then
    MAXVAL=$(grep '\.field public static final' "$RSTRING" | \
             sed -E 's/.*0x([0-9a-f]+)$/\1/' | sort | tail -n1)
    
    if [ -z "$MAXVAL" ]; then
        NEWVAL="0x7f050000"
    else
        NEWVAL=$(printf "0x%08x" $((16#$MAXVAL + 1)))
    fi

    echo "    .field public static final shortcut_saveman:I = $NEWVAL" >> "$RSTRING"
fi

# 4. Create/update R$xml.smali
RXML="smali/$PKGNAME_SLASH/R\$xml.smali"
if [ ! -f "$RXML" ]; then
    cat > "$RXML" <<EOF
.class public final L$PKGNAME_SLASH/R\$xml;
.super Ljava/lang/Object;
.source "R.java"

.annotation system Ldalvik/annotation/EnclosingClass;
    value = L$PKGNAME_SLASH/R;
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x19
    name = "xml"
.end annotation

# static fields

.field public static final shortcuts:I = 0x7f070000

.method public constructor <init>()V
    .locals 0

    .line 42
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    return-void
.end method
EOF
else
    if ! grep -q 'shortcuts:I' "$RXML"; then
        MAXVAL=$(grep '\.field public static final' "$RXML" | \
                 sed -E 's/.*0x([0-9a-f]+)$/\1/' | sort | tail -n1)
        if [ -z "$MAXVAL" ]; then
            NEWVAL="0x7f070000"
        else
            NEWVAL=$(printf "0x%08x" $((16#$MAXVAL + 1)))
        fi
        echo "    .field public static final shortcuts:I = $NEWVAL" >> "$RXML"
    fi
fi

# 5. Update AndroidManifest.xml

# enable debug build
sed -i 's/\(<application[^>]*\)android:debuggable="[^"]*"/\1android:debuggable="true"/; t; s/\(<application[^>]*\)/\1 android:debuggable="true"/' AndroidManifest.xml

if ! grep -q 'android.app.shortcuts' AndroidManifest.xml; then
    LAUNCHER_LINE=$(grep -n 'android.intent.category.LAUNCHER' AndroidManifest.xml | head -n1 | cut -d: -f1)
    if [ -n "$LAUNCHER_LINE" ]; then
        ACTIVITY_START=$(head -n "$LAUNCHER_LINE" AndroidManifest.xml | grep -n '<activity' | tail -n1 | cut -d: -f1)
        sed -i "$((ACTIVITY_START+1))i\        <meta-data android:name=\"android.app.shortcuts\" android:resource=\"@xml/shortcuts\"/>" AndroidManifest.xml
    fi
fi

if ! grep -q "$PKGNAME_DOT.SavemanActivity" AndroidManifest.xml; then
    sed -i "/<\/application>/i\
        <activity android:name=\"$PKGNAME_DOT.SavemanActivity\" android:exported=\"true\">\n\
            <intent-filter>\n\
                <action android:name=\"android.intent.action.VIEW\"/>\n\
                <category android:name=\"android.intent.category.DEFAULT\"/>\n\
            </intent-filter>\n\
        </activity>\n\
        <provider\n\
            android:exported=\"true\"\n\
            android:grantUriPermissions=\"true\"\n\
            android:authorities=\"$PKGNAME_DOT.fileprovider\"\n\
            android:name=\"$PKGNAME_DOT.SavemanActivity\$FileProvider\"/>\n" AndroidManifest.xml
fi

# 6. Create/update shortcuts.xml
mkdir -p res/xml
if [ ! -f res/xml/shortcuts.xml ] || ! grep -q "$PKGNAME_DOT.SavemanActivity" res/xml/shortcuts.xml; then
    cat > res/xml/shortcuts.xml <<EOF
<shortcuts xmlns:android="http://schemas.android.com/apk/res/android">
    <shortcut
        android:enabled="true"
        android:icon="@android:drawable/ic_menu_save"
        android:shortcutId="saveman"
        android:shortcutShortLabel="@string/shortcut_saveman">
        <intent
            android:action="android.intent.action.VIEW"
            android:targetClass="$PKGNAME_DOT.SavemanActivity"
            android:targetPackage="$PKGNAME_DOT" />
    </shortcut>
</shortcuts>
EOF
fi

echo "Patched successfully."

cd ..

echo "Rebuilding APK..."
java -jar "$APKTOOL_JAR" b "$WORKDIR" -o "$WORKDIR/patched.apk"

echo "Signing APK..."
java -jar "$APK_SIGNER_JAR" -a "$WORKDIR/patched.apk" --ks "$KEYSTORE" --ksAlias "$KEY_ALIAS" --ksPass "$STORE_PASS" --keyPass "$KEY_PASS"

# cleanup
mv "$WORKDIR/patched-aligned-signed.apk" output.apk
rm -rf "$WORKDIR"

echo "Done. Result: output.apk"
