# Cloud sync setup (Firebase / Cloud Firestore)

Your data lives in a local database on each device. Cloud sync copies it through **Cloud
Firestore** in a Firebase project that you own, so your iPhone, iPad and Mac stay in step.
Nothing is shared with anyone else; security rules limit every account to its own data.

## One-time setup (about 10 minutes)

1. Go to <https://console.firebase.google.com> and **Add project** (any name, e.g. "CPA
   Manager"). Turn Google Analytics off.
2. **Build → Firestore Database → Create database.** Choose a location near you and start
   in **production mode**.
3. **Build → Authentication → Get started → Email/Password → Enable** (leave "Email link"
   off). This is the login you'll use on every device.
4. **Firestore Database → Rules:** replace the contents with the file `firestore.rules` from
   this repository and **Publish**.
5. **Project settings (gear) → Your apps → Add app → Apple (iOS)**. Bundle ID:
   `com.gottfriedcpa.ProjectManager`. Skip the "add SDK" steps. **Download
   `GoogleService-Info.plist`.**
6. Put that file at `CPAManager/Resources/GoogleService-Info.plist` in your local checkout.
   It is git-ignored, so it is never committed. Run `xcodegen generate` and build. The same
   file is used by the iPhone/iPad and Mac apps.

## Xcode Cloud (TestFlight builds)

The plist isn't in git, so give Xcode Cloud a secret copy:

1. On your Mac: `base64 -i CPAManager/Resources/GoogleService-Info.plist | pbcopy`
2. App Store Connect → your app → Xcode Cloud → Manage Workflows → edit the workflow →
   **Environment → Environment Variables → +**: name `GOOGLE_SERVICE_INFO_PLIST_BASE64`,
   paste the value, tick **Secret**.
3. `ci_scripts/ci_post_clone.sh` decodes it into place before the project is generated.

Without the file the app still builds and runs; Settings → Cloud Sync just says it isn't set up.

## Using it

- **Settings → Cloud Sync → Create account** (email + password of your choice, 6+ characters),
  then **Sign in** with the same account on every device.
- The first device uploads everything. Other devices download it and merge with whatever they
  already have (records are matched by id; duplicates of the sample data can be deleted).
- After that, edits sync automatically within a couple of seconds and on every launch.

## Good to know

- **Conflicts:** if the same record is edited on two devices, the edit made on the device that
  hadn't synced yet wins on that device (nothing typed is silently replaced), then propagates.
- **Deleting:** deletions sync. If a device suddenly looks like it lost a large share of its
  records, sync pauses and asks whether to restore them from the cloud or delete them everywhere.
- **Files:** documents/receipts up to about 0.8 MB sync. Bigger ones stay on the device that
  added them (the record itself still syncs). Storing large files needs Firebase Storage,
  which requires Firebase's pay-as-you-go plan.
- **Cost:** a solo practice fits comfortably inside Firestore's free daily quota.
- **Back up anyway:** Settings → Backup exports a file independent of any cloud.
- **iCloud:** the old CloudKit database is no longer used for your data. Settings and your
  Google/QuickBooks connections still sync through iCloud key-value storage and Keychain.
