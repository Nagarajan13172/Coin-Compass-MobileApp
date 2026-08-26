package cloud.sathishkumar.coincompass

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * local_auth's BiometricPrompt is a Fragment, so the host must be a
 * FragmentActivity. With a plain FlutterActivity every authenticate() call
 * returns AuthResultCode.NOT_FRAGMENT_ACTIVITY, which local_auth 3.x surfaces
 * as LocalAuthException(uiUnavailable) — a silent failure, not a crash.
 */
class MainActivity : FlutterFragmentActivity() {
    private var privacyChannel: MethodChannel? = null
    private var upiChannel: MethodChannel? = null
    private var upi: UpiChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Fail closed: the recents thumbnail is captured when the activity
        // stops, and Dart has not read the lock preference yet. Start private
        // and let Dart relax it if the app lock is off.
        applyPrivacyScreen(true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // super registers GeneratedPluginRegistrant. Dropping it silently
        // unregisters every plugin, local_auth included.
        super.configureFlutterEngine(flutterEngine)
        privacyChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "cloud.sathishkumar.coincompass/privacy",
            ).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "setPrivacyScreen" -> {
                            applyPrivacyScreen(call.arguments as? Boolean ?: false)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }

        upi = UpiChannel(this)
        upiChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                UpiChannel.CHANNEL,
            ).apply {
                setMethodCallHandler { call, result ->
                    upi?.handle(call, result) ?: result.error(
                        "UNAVAILABLE",
                        "UPI is not available.",
                        null,
                    )
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        privacyChannel?.setMethodCallHandler(null)
        privacyChannel = null
        upiChannel?.setMethodCallHandler(null)
        upiChannel = null
        // Releases a Dart caller left awaiting a payment result.
        upi?.dispose()
        upi = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * 7.6 — a UPI app answers through onActivityResult, so the result has to be
     * caught by the activity and handed back to the waiting Dart call.
     */
    @Deprecated("Required: the payment apps answer through the legacy result API.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (upi?.onActivityResult(requestCode, data) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    /**
     * API 33+ can hide only the task-switcher snapshot. Below that the only
     * lever is FLAG_SECURE, which also blocks screenshots and casting.
     */
    private fun applyPrivacyScreen(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(!enabled)
        } else if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
