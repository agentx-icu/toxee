package com.toxee.app

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Keeps ONE Flutter engine per process in charge of the Tox session.
 *
 * tim2tox is a process-wide singleton (native callbacks, the default
 * instance, the profile file). A second MainActivity in the same process —
 * e.g. a launcher or another app starting it with FLAG_ACTIVITY_MULTIPLE_TASK
 * while the app is in the background — gets its own engine and
 * isolate, which would log in again on the same native instance, replace its
 * callbacks and save the profile concurrently. The Dart side claims ownership
 * before any Tox work (lib/bootstrap/single_session_guard.dart); the loser
 * brings the owner's task to the front and closes itself.
 *
 * Channel name: `toxee/session_owner`.
 *  - `claim()` → true when this activity owns (or takes over from a finishing
 *    or destroyed owner — a recreated activity can start before the old one
 *    is gone), false when another live activity owns the session.
 *  - `yieldToOwner()` → moves the owner's task to the front and finishes this
 *    activity's task.
 *
 * MainActivity claims natively in onCreate ([claimOrOwner]) so a losing
 * instance hands its launch intent (e.g. a lock-screen incoming call) to the
 * owner ([handOver]) instead of consuming it; the Dart `claim` then just
 * reads the same answer.
 */
class SessionOwnerChannel(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {

    fun register(binaryMessenger: BinaryMessenger) {
        MethodChannel(binaryMessenger, CHANNEL_NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "claim" -> result.success(claim(activity))
            "yieldToOwner" -> {
                yieldToOwner()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun yieldToOwner() {
        val owner = owner?.get()
        if (owner != null && owner !== activity) moveToFront(activity, owner)
        activity.finishAndRemoveTask()
    }

    companion object {
        const val CHANNEL_NAME = "toxee/session_owner"

        @Volatile
        private var owner: WeakReference<Activity>? = null

        @Synchronized
        fun claim(activity: Activity): Boolean {
            val current = owner?.get()
            if (current == null || current === activity ||
                current.isFinishing || current.isDestroyed
            ) {
                owner = WeakReference(activity)
                return true
            }
            return false
        }

        /** Claims for [activity]; returns the live owner when it loses. */
        @Synchronized
        fun claimOrOwner(activity: Activity): Activity? =
            if (claim(activity)) null else owner?.get()

        /**
         * Gives the losing [loser]'s launch [intent] to [owner], brings the
         * owner's task forward and closes the loser.
         */
        fun handOver(loser: Activity, owner: Activity, intent: Intent?) {
            if (intent != null && owner is MainActivity) {
                owner.receiveHandedOverIntent(Intent(intent))
            }
            moveToFront(loser, owner)
            loser.finishAndRemoveTask()
        }

        private fun moveToFront(from: Activity, owner: Activity) {
            val manager = from.getSystemService(ActivityManager::class.java)
            manager?.appTasks?.firstOrNull { taskIdOf(it) == owner.taskId }?.moveToFront()
        }

        private fun taskIdOf(task: ActivityManager.AppTask): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                task.taskInfo.taskId
            } else {
                @Suppress("DEPRECATION")
                task.taskInfo.persistentId
            }

        /** Called from the owner's onDestroy so a later launch can claim. */
        @Synchronized
        fun release(activity: Activity) {
            if (owner?.get() === activity) owner = null
        }
    }
}
