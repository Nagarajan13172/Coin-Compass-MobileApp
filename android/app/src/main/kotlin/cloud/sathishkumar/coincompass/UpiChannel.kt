package cloud.sathishkumar.coincompass

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Phase 7.6 — listing the UPI apps on this phone and handing one a payment.
 *
 * Written here rather than pulled from a package: every maintained option
 * wraps the same twenty lines of PackageManager plus startActivityForResult,
 * and a payment path is a poor place to inherit an unmaintained dependency.
 *
 * Nothing here decides anything about money. It reports which apps exist,
 * launches the one that was chosen, and returns the response string verbatim
 * for Dart to interpret — see UpiResult, which is explicit that the response
 * is advisory and not proof of payment.
 */
class UpiChannel(private val activity: Activity) {

    companion object {
        const val CHANNEL = "cloud.sathishkumar.coincompass/upi"

        /** Arbitrary, only has to be unique within this activity. */
        private const val REQUEST_CODE = 7601

        /** The intent every UPI app registers for. */
        private val PAY_URI: Uri = Uri.parse("upi://pay")

        /**
         * Apps disagree about where they put the result. `response` is the
         * NPCI-documented extra; the others are what real apps have shipped.
         */
        private val RESPONSE_KEYS = listOf("response", "Status", "status", "result")
    }

    private var pending: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listApps" -> result.success(listApps())
            "pay" -> pay(call, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Every activity that can handle `upi://pay`.
     *
     * On Android 11+ this returns nothing at all unless the manifest declares a
     * matching <queries> element — package visibility is opt-in, and the
     * failure mode is an empty list rather than an error, so the sheet simply
     * reports that no UPI app is installed.
     *
     * That declaration must name the HOST as well as the scheme:
     *
     *     <data android:scheme="upi" android:host="pay"/>
     *
     * A scheme-only query is matched as the bare URI `upi:`, which does not
     * match the payment apps' own `upi://pay` filters. On the device this cost
     * an hour: the manifest looked right, the query returned 0, and
     * getPackageInfo("com.phonepe.app") threw NameNotFound while `adb shell pm
     * query-activities` happily listed all five apps. Adding the host took it
     * from 0 to 5.
     */
    private fun listApps(): List<Map<String, Any?>> {
        val pm = activity.packageManager
        val intent = Intent(Intent.ACTION_VIEW, PAY_URI)
        val matches: List<ResolveInfo> = pm.queryIntentActivities(intent, 0)

        return matches
            .mapNotNull { info ->
                val pkg = info.activityInfo?.packageName ?: return@mapNotNull null
                mapOf(
                    "packageName" to pkg,
                    "label" to info.loadLabel(pm).toString(),
                    "icon" to iconOf(pkg),
                )
            }
            // The same package can register more than one matching activity.
            .distinctBy { it["packageName"] }
            .sortedBy { (it["label"] as String).lowercase() }
    }

    /**
     * The launcher icon as base64 PNG.
     *
     * Adaptive icons are not BitmapDrawables, so they have to be drawn onto a
     * canvas — reading `.bitmap` directly returns null for most modern apps and
     * would leave the sheet iconless for exactly the apps people use.
     */
    private fun iconOf(packageName: String): String? = try {
        val drawable: Drawable = activity.packageManager.getApplicationIcon(packageName)
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            drawable.bitmap
        } else {
            val width = drawable.intrinsicWidth.coerceAtLeast(1)
            val height = drawable.intrinsicHeight.coerceAtLeast(1)
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                val canvas = Canvas(it)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
            }
        }
        ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
        }
    } catch (_: PackageManager.NameNotFoundException) {
        // Uninstalled between listing and drawing. A missing icon is a cosmetic
        // problem; failing the whole list over it is not.
        null
    } catch (_: Throwable) {
        null
    }

    private fun pay(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("BUSY", "A payment is already in progress.", null)
            return
        }

        val uri = call.argument<String>("uri")
        val packageName = call.argument<String>("packageName")
        if (uri.isNullOrBlank() || packageName.isNullOrBlank()) {
            result.error("BAD_ARGS", "uri and packageName are required.", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).setPackage(packageName)
        if (intent.resolveActivity(activity.packageManager) == null) {
            result.error("NO_APP", "That app can no longer handle payments.", null)
            return
        }

        pending = result
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (error: Throwable) {
            pending = null
            result.error("LAUNCH_FAILED", error.message, null)
        }
    }

    /** @return true when this consumed the result. */
    fun onActivityResult(requestCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null

        // RESULT_CANCELED with no extras is a back press, which Dart reads as
        // cancelled. It is deliberately NOT reported as an error: backing out
        // of a payment is a normal thing to do.
        result.success(responseOf(data))
        return true
    }

    private fun responseOf(data: Intent?): String? {
        if (data == null) return null
        for (key in RESPONSE_KEYS) {
            val value = data.getStringExtra(key)
            if (!value.isNullOrBlank()) return value
        }
        // Some apps answer on the data URI instead of an extra.
        return data.dataString
    }

    /** Releases a caller left waiting if the activity goes away mid-payment. */
    fun dispose() {
        pending?.success(null)
        pending = null
    }
}
