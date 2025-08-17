# saveman - Patch in a Save Manager screen to any Android app/game

## Features

- export - zips private app storage and shows file export dialog
- import - unzips and restores private app storage from a zip file

## Usage

You'll need to patch the APK file of the game you want to add the Save Manager to.

Once you have the APK file, run:

```bash
bash add-saveman.sh [[YOUR_APK_FILE]]
```

This will start the patching process. When prompted, type `password` (literally) to unlock the signing key and sign the patched APK.
