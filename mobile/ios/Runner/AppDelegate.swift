import Flutter
import UIKit
import LibProofMode
import ZendeskCoreSDK
import SupportSDK
import SupportProvidersSDK

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Set up ProofMode platform channel
    setupProofModeChannel()

    // Set up Zendesk platform channel
    setupZendeskChannel()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Force portrait orientation for entire app (including camera preview)
  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return .portrait
  }

  private func setupProofModeChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("❌ ProofMode: Could not get FlutterViewController")
      return
    }

    let channel = FlutterMethodChannel(
      name: "org.openvine/proofmode",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "generateProof":
        guard let args = call.arguments as? [String: Any],
              let mediaPath = args["mediaPath"] as? String else {
          result(FlutterError(
            code: "INVALID_ARGUMENT",
            message: "Media path is required",
            details: nil
          ))
          return
        }

        NSLog("🔐 ProofMode: Generating proof for: \(mediaPath)")

        do {
          // Create MediaItem from file URL
          let fileURL = URL(fileURLWithPath: mediaPath)
          guard FileManager.default.fileExists(atPath: mediaPath) else {
            result(FlutterError(
              code: "FILE_NOT_FOUND",
              message: "Media file does not exist: \(mediaPath)",
              details: nil
            ))
            return
          }

          let mediaItem = MediaItem(mediaUrl: fileURL)

          // Configure proof generation options
          // Include device ID, location (if available), and network info
          let options = ProofGenerationOptions(
            showDeviceIds: true,
            showLocation: true,
            showMobileNetwork: true,
            notarizationProviders: []
          )

          // Generate proof using LibProofMode
          _ = Proof.shared.process(mediaItem: mediaItem, options: options)

          // Return the SHA256 hash (used as proof identifier)
          guard let proofHash = mediaItem.mediaItemHash, !proofHash.isEmpty else {
            NSLog("❌ ProofMode: Proof generation did not produce hash")
            result(FlutterError(
              code: "PROOF_HASH_MISSING",
              message: "LibProofMode did not generate video hash",
              details: nil
            ))
            return
          }

          NSLog("🔐 ProofMode: Proof generated successfully: \(proofHash)")
          result(proofHash)

        } catch {
          NSLog("❌ ProofMode: Proof generation failed: \(error.localizedDescription)")
          result(FlutterError(
            code: "PROOF_GENERATION_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }

      case "getProofDir":
        guard let args = call.arguments as? [String: Any],
              let proofHash = args["proofHash"] as? String else {
          result(FlutterError(
            code: "INVALID_ARGUMENT",
            message: "Proof hash is required",
            details: nil
          ))
          return
        }

        NSLog("🔐 ProofMode: Getting proof directory for hash: \(proofHash)")

        // ProofMode stores proof in documents directory under hash subfolder
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let proofDirPath = (documentsPath as NSString).appendingPathComponent(proofHash)

        if FileManager.default.fileExists(atPath: proofDirPath) {
          NSLog("🔐 ProofMode: Proof directory found: \(proofDirPath)")
          result(proofDirPath)
        } else {
          NSLog("⚠️ ProofMode: Proof directory not found for hash: \(proofHash)")
          result(nil)
        }

      case "isAvailable":
        // iOS ProofMode library is now available
        NSLog("🔐 ProofMode: isAvailable check - true (LibProofMode installed)")
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NSLog("✅ ProofMode: Platform channel registered with LibProofMode")
  }

  private func setupZendeskChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("❌ Zendesk: Could not get FlutterViewController")
      return
    }

    let channel = FlutterMethodChannel(
      name: "com.openvine/zendesk_support",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self,
            let controller = self.window?.rootViewController as? FlutterViewController else {
        result(FlutterError(code: "NO_CONTROLLER", message: "FlutterViewController not available", details: nil))
        return
      }

      switch call.method {
      case "initialize":
        guard let args = call.arguments as? [String: Any],
              let appId = args["appId"] as? String,
              let clientId = args["clientId"] as? String,
              let zendeskUrl = args["zendeskUrl"] as? String else {
          result(FlutterError(
            code: "INVALID_ARGUMENT",
            message: "appId, clientId, and zendeskUrl are required",
            details: nil
          ))
          return
        }

        NSLog("🎫 Zendesk: Initializing with URL: \(zendeskUrl)")

        // Initialize Zendesk Core SDK
        Zendesk.initialize(appId: appId, clientId: clientId, zendeskUrl: zendeskUrl)

        // Initialize Support SDK
        Support.initialize(withZendesk: Zendesk.instance)

        // Set anonymous identity by default
        let identity = Identity.createAnonymous()
        Zendesk.instance?.setIdentity(identity)

        NSLog("✅ Zendesk: Initialized successfully")
        result(true)

      case "showNewTicket":
        let args = call.arguments as? [String: Any]
        let subject = args?["subject"] as? String ?? ""
        let tags = args?["tags"] as? [String] ?? []
        // Note: description parameter not supported by Zendesk iOS SDK RequestUiConfiguration

        NSLog("🎫 Zendesk: Showing new ticket screen")

        // Configure request UI
        let config = RequestUiConfiguration()
        config.subject = subject
        config.tags = tags

        // Build request screen
        let requestScreen = RequestUi.buildRequestUi(with: [config])

        // Present modally
        controller.present(requestScreen, animated: true) {
          NSLog("✅ Zendesk: Ticket screen presented")
        }

        result(true)

      case "showTicketList":
        NSLog("🎫 Zendesk: Showing ticket list screen")

        // Build request list screen
        let requestListScreen = RequestUi.buildRequestList()

        // CRITICAL: Zendesk RequestUi requires UINavigationController for ticket navigation
        // Without this, tapping tickets won't open the conversation view
        let navigationController = UINavigationController(rootViewController: requestListScreen)

        // Present modally with navigation controller
        controller.present(navigationController, animated: true) {
          NSLog("✅ Zendesk: Ticket list presented in navigation controller")
        }

        result(true)

      case "createTicket":
        NSLog("🎫 Zendesk: Creating ticket programmatically (no UI)")

        // Extract parameters
        guard let args = call.arguments as? [String: Any],
              let subject = args["subject"] as? String,
              let description = args["description"] as? String else {
          NSLog("❌ Zendesk: Missing required parameters for createTicket")
          result(FlutterError(code: "INVALID_ARGS",
                            message: "Missing subject or description",
                            details: nil))
          return
        }

        let tags = args["tags"] as? [String] ?? []

        // Build create request object using ZDK API
        let createRequest = ZDKCreateRequest()
        createRequest.subject = subject
        createRequest.requestDescription = description
        createRequest.tags = tags

        NSLog("🎫 Zendesk: Submitting ticket - subject: '\(subject)', tags: \(tags)")

        // Submit ticket asynchronously using ZDKRequestProvider
        ZDKRequestProvider().createRequest(createRequest) { (request, error) in
          DispatchQueue.main.async {
            if let error = error {
              NSLog("❌ Zendesk: Failed to create ticket - \(error.localizedDescription)")
              result(false)
            } else if let request = request as? ZDKRequest {
              NSLog("✅ Zendesk: Ticket created successfully - ID: \(request.requestId)")
              result(true)
            } else {
              NSLog("⚠️ Zendesk: Unknown result when creating ticket")
              result(false)
            }
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NSLog("✅ Zendesk: Platform channel registered")
  }
}
