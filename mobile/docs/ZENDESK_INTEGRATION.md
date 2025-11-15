# Zendesk Support SDK Integration

## Overview

OpenVine now integrates with Zendesk Support SDK for professional bug reporting and customer support. The integration provides native iOS/Android support ticket submission with graceful fallback to email when Zendesk is not configured.

## Features

- **Native Support UI**: Users tap "Contact Support" in Settings to open Zendesk's native ticket creation screen
- **Graceful Degradation**: App works fully without Zendesk credentials, falling back to email bug reports
- **Platform Channels**: Custom Flutter platform channels bridge to official Zendesk iOS/Android SDKs
- **Zero Impact**: Non-configured builds continue working normally with email fallback

## Architecture

```
Settings Screen
    ↓
ZendeskSupportService (Flutter)
    ↓
MethodChannel ("com.openvine/zendesk_support")
    ↓
    ├── iOS: AppDelegate.swift → Zendesk Support SDK
    └── Android: MainActivity.kt → Zendesk Support SDK
```

## Configuration

### Step 1: Get Zendesk Credentials

From your Zendesk account dashboard:
- **App ID**: Zendesk application identifier
- **Client ID**: OAuth client ID for API access
- **Zendesk URL**: Your Zendesk instance URL (e.g., `https://openvine.zendesk.com`)

### Step 2: Create .env File

Copy the example file and fill in your credentials:

```bash
cd mobile
cp .env.example .env
```

Edit `.env`:

```bash
ZENDESK_APP_ID=your_app_id_here
ZENDESK_CLIENT_ID=your_client_id_here
ZENDESK_URL=https://openvine.zendesk.com
```

**Important**: `.env` is gitignored to protect credentials. Never commit real credentials.

### Step 3: Build with Credentials

Credentials are injected at build time via `--dart-define`:

```bash
# Development builds (loads from .env automatically)
flutter run

# Production builds
flutter build ios --dart-define=ZENDESK_APP_ID=xxx --dart-define=ZENDESK_CLIENT_ID=yyy
flutter build apk --dart-define=ZENDESK_APP_ID=xxx --dart-define=ZENDESK_CLIENT_ID=yyy
```

## Usage

### For Users

1. Open Settings screen
2. Scroll to Support section
3. Tap "Contact Support"
4. Fill out ticket in native Zendesk UI
5. Submit ticket

If Zendesk is not configured, users will see the email bug report dialog as before.

### For Developers

**Check availability:**
```dart
if (ZendeskSupportService.isAvailable) {
  // Zendesk initialized and ready
}
```

**Show new ticket screen:**
```dart
final success = await ZendeskSupportService.showNewTicketScreen(
  subject: 'Support Request',
  tags: ['mobile', 'bug'],
);
```

**Show ticket list:**
```dart
final success = await ZendeskSupportService.showTicketListScreen();
```

## Implementation Details

### Files Modified

**Configuration:**
- `lib/config/zendesk_config.dart` - Credential configuration
- `.env.example` - Credential template

**Flutter Service:**
- `lib/services/zendesk_support_service.dart` - Platform channel wrapper

**iOS Platform:**
- `ios/Podfile` - Add ZendeskSupportSDK dependency
- `ios/Runner/AppDelegate.swift` - Implement platform channel handlers

**Android Platform:**
- `android/build.gradle.kts` - Add Zendesk Maven repository
- `android/app/build.gradle.kts` - Add Zendesk SDK + AndroidX AppCompat dependencies
- `android/app/src/main/kotlin/co/openvine/app/MainActivity.kt` - Implement platform channel handlers

**App Integration:**
- `lib/main.dart` - Initialize Zendesk at app startup
- `lib/screens/settings_screen.dart` - Replace bug report with Contact Support

### Platform Channel Methods

**Method**: `initialize`
- Configures Zendesk SDK with credentials
- Sets anonymous user identity
- Returns `true` on success, `false` if credentials missing

**Method**: `showNewTicket`
- Launches native ticket creation UI
- Optional subject and tags parameters
- Returns `true` on success

**Method**: `showTicketList`
- Launches native ticket list UI (user's past tickets)
- Returns `true` on success

## Testing

### Without Credentials

1. Build without `.env` file or credentials
2. App should start normally
3. Settings → Contact Support should show email dialog
4. Verify no crashes or errors

### With Credentials

1. Configure `.env` with valid Zendesk credentials
2. Build and run app
3. Settings → Contact Support should show Zendesk native UI
4. Submit test ticket
5. Verify ticket appears in Zendesk dashboard

## Troubleshooting

### iOS Build Fails

```bash
cd ios
pod install
cd ..
flutter clean
flutter build ios
```

### Android Build Fails

```bash
flutter clean
flutter pub get
flutter build apk
```

### Zendesk Not Initializing

Check logs for initialization status:
```
[STARTUP] Zendesk Support SDK initialized successfully
```

Or if skipped:
```
[STARTUP] Zendesk Support SDK not initialized (credentials not configured)
```

### Support Button Shows Email Dialog

This means Zendesk is not available. Reasons:
1. `.env` file missing or empty
2. Credentials not passed to build via `--dart-define`
3. Platform channel initialization failed (check native logs)

## Migration from Old Bug Reporting

The old Cloudflare Worker bug report endpoint is still available as a fallback. When Zendesk is not configured, the app automatically uses the email dialog.

No user action required - the transition is transparent.

## Future Enhancements

- User identity sync (once authenticated, set Zendesk identity)
- Attachment support (screenshots, logs)
- In-app chat (requires Zendesk Messaging SDK instead of Support SDK)
- Custom ticket fields

## References

- [Zendesk Support SDK for iOS](https://developer.zendesk.com/documentation/zendesk-web-widget-sdks/sdks/ios/getting_started/)
- [Zendesk Support SDK for Android](https://developer.zendesk.com/documentation/zendesk-web-widget-sdks/sdks/android/getting_started/)
- Design Doc: `mobile/docs/plans/2025-11-15-zendesk-support-integration-design.md`
- Implementation Plan: `mobile/docs/plans/2025-11-15-zendesk-support-integration.md`
