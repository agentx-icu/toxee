package com.toxee.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Keeps a file picked for a chat when Android reclaims toxee while the
 * system document picker is in front (checklist M9).
 *
 * file_picker cannot deliver such a result: its request code is derived from
 * an identity hash and its pick state lives in the process that died, so the
 * recreated activity receives the result and nobody takes it. Here:
 *
 * 1. Dart [arm]s with the chat right before it opens the picker; the next
 *    document-open intent started for a result is tagged with its request
 *    code and this process's random token. Dart disarms when the pick
 *    returns in the same process.
 * 2. A result for a tagged request from ANOTHER process (token differs) is a
 *    lost pick: the read grant is persisted, the "copying" state is written,
 *    and the file is copied into the cache — so another reclaim mid-copy
 *    resumes instead of losing it.
 * 3. Dart peeks at the result, records it in the account's storage, then
 *    acks; only the ack clears the state, so a reclaim in between just
 *    repeats a peek that staging recognises.
 *
 * Every write commits synchronously: the point is to survive a kill.
 */
class LostFilePickChannel(private val context: Context) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "arm" -> {
                    val account = call.argument<String>("account")
                    val peer = call.argument<String>("peer")
                    if (account.isNullOrEmpty() || peer.isNullOrEmpty()) {
                        result.error("bad_args", "account and peer required", null)
                    } else {
                        arm(context, account, peer)
                        result.success(null)
                    }
                }
                "disarm" -> {
                    disarm(context)
                    result.success(null)
                }
                "peek" -> peek(context) { state -> result.success(state) }
                "ack" -> {
                    ack(context, call.argument<String>("path"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val CHANNEL = "toxee/lost_file_pick"
        private const val PREFS = "toxee_lost_file_pick"
        private const val ARMED = "armed"
        private const val LAUNCH = "launch"
        private const val STATE_PREFIX = "state:"
        private val PICK_ACTIONS = setOf(Intent.ACTION_OPEN_DOCUMENT, Intent.ACTION_GET_CONTENT)

        /** Tells a request started by this process from one started by a dead one. */
        private val processToken: String = UUID.randomUUID().toString()

        private val main = Handler(Looper.getMainLooper())
        private var copying = false
        private val waiters = mutableListOf<(List<Map<String, Any?>>) -> Unit>()

        private fun prefs(context: Context): SharedPreferences =
            context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        private fun read(prefs: SharedPreferences, key: String): JSONObject? =
            prefs.getString(key, null)?.let { runCatching { JSONObject(it) }.getOrNull() }

        fun arm(context: Context, account: String, peer: String) {
            val armed = JSONObject()
                .put("account", account)
                .put("peer", peer)
                .put("at", System.currentTimeMillis())
            prefs(context).edit().putString(ARMED, armed.toString()).remove(LAUNCH).commit()
        }

        fun disarm(context: Context) {
            prefs(context).edit().remove(ARMED).remove(LAUNCH).commit()
        }

        /** MainActivity.startActivityForResult: tags the armed pick's request. */
        fun onStartForResult(context: Context, intent: Intent, requestCode: Int) {
            if (requestCode < 0 || intent.action !in PICK_ACTIONS) return
            val prefs = prefs(context)
            val armed = read(prefs, ARMED) ?: return
            armed.put("code", requestCode).put("token", processToken)
            prefs.edit().putString(LAUNCH, armed.toString()).remove(ARMED).commit()
        }

        /** MainActivity.onActivityResult, after the plugins have seen it. */
        fun onResult(activity: Activity, requestCode: Int, resultCode: Int, data: Intent?) {
            val prefs = prefs(activity)
            val launch = read(prefs, LAUNCH) ?: return
            if (launch.optInt("code", -1) != requestCode) return
            if (launch.optString("token") == processToken) return // file_picker has it
            val uri = data?.data ?: data?.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
            if (resultCode != Activity.RESULT_OK || uri == null) {
                prefs.edit().remove(LAUNCH).commit()
                return
            }
            runCatching {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            // The URI becomes durable in the same write that drops the tag;
            // its name and destination are resolved by the copy, which a
            // later process resumes if this one dies first.
            val id = "${System.currentTimeMillis()}_${UUID.randomUUID().toString().take(8)}"
            val state = JSONObject()
                .put("id", id)
                .put("status", "copying")
                .put("uri", uri.toString())
                .put("account", launch.optString("account"))
                .put("peer", launch.optString("peer"))
                .put("at", launch.optLong("at"))
            prefs.edit().putString(STATE_PREFIX + id, state.toString()).remove(LAUNCH).commit()
            startCopy(activity.applicationContext)
        }

        /**
         * Every lost pick, oldest first, once its copy is finished (resumed
         * if a reclaim cut it short). Each stays until [ack].
         */
        fun peek(context: Context, reply: (List<Map<String, Any?>>) -> Unit) {
            if (states(prefs(context)).none { it.optString("status") == "copying" }) {
                reply(states(prefs(context)).map(::toMap))
                return
            }
            waiters.add(reply)
            startCopy(context.applicationContext)
        }

        fun ack(context: Context, path: String?) {
            val prefs = prefs(context)
            val state = states(prefs).firstOrNull { path != null && it.optString("path") == path } ?: return
            prefs.edit().remove(STATE_PREFIX + state.optString("id")).commit()
            runCatching {
                context.contentResolver.releasePersistableUriPermission(
                    Uri.parse(state.optString("uri")),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            val file = File(path!!)
            if (state.optString("status") != "ready") file.delete()
            File("$path.part").delete()
            file.parentFile?.let { dir -> if (dir.list()?.isEmpty() == true) dir.delete() }
        }

        private fun states(prefs: SharedPreferences): List<JSONObject> =
            prefs.all.keys.filter { it.startsWith(STATE_PREFIX) }.sorted()
                .mapNotNull { read(prefs, it) }

        /** Copies every pick still marked copying, one after another. */
        private fun startCopy(context: Context) {
            if (copying) return
            copying = true
            Thread {
                val prefs = prefs(context)
                // Until none is left: a result can arrive while one is copied.
                while (true) {
                    val state = states(prefs).firstOrNull { it.optString("status") == "copying" } ?: break
                    copyOne(context, prefs, state)
                }
                main.post {
                    copying = false
                    // A result committed after the loop's last look (results,
                    // peeks and this callback all run on the main thread, so
                    // this check cannot miss one): copy it before replying.
                    if (states(prefs).any { it.optString("status") == "copying" }) {
                        startCopy(context)
                        return@post
                    }
                    val reply = states(prefs).map(::toMap)
                    val pending = waiters.toList()
                    waiters.clear()
                    pending.forEach { it(reply) }
                }
            }.start()
        }

        private fun copyOne(context: Context, prefs: SharedPreferences, state: JSONObject) {
            val key = STATE_PREFIX + state.optString("id")
            try {
                val uri = Uri.parse(state.optString("uri"))
                if (state.optString("path").isEmpty()) {
                    val name = sanitize(displayName(context, uri))
                    val dir = File(File(context.cacheDir, "lost_picks"), state.optString("id"))
                    state.put("name", name).put("path", File(dir, name).path)
                    prefs.edit().putString(key, state.toString()).commit()
                }
                val dest = File(state.optString("path"))
                val part = File("${dest.path}.part")
                // The rename is atomic: a destination that exists is a whole
                // copy whose "ready" a reclaim kept from being written.
                if (!dest.exists()) try {
                    dest.parentFile?.mkdirs()
                    val input = context.contentResolver.openInputStream(uri)
                        ?: throw IllegalStateException("provider returned no stream")
                    input.use { source -> part.outputStream().use { source.copyTo(it) } }
                    if (!part.renameTo(dest)) throw IllegalStateException("rename failed")
                } finally {
                    part.delete()
                }
                state.put("status", "ready")
            } catch (e: Exception) {
                state.put("status", "error").put("error", e.toString())
                if (state.optString("path").isEmpty()) {
                    // Nothing to name: still give Dart a path to ack by.
                    state.put("path", File(File(context.cacheDir, "lost_picks"), state.optString("id")).path)
                }
            }
            prefs.edit().putString(key, state.toString()).commit()
        }

        private fun toMap(state: JSONObject): Map<String, Any?> = mapOf(
            "status" to state.optString("status"),
            "path" to state.optString("path"),
            "name" to state.optString("name"),
            "account" to state.optString("account"),
            "peer" to state.optString("peer"),
            "at" to state.optLong("at"),
            "error" to state.optString("error").ifEmpty { null },
        )

        private fun displayName(context: Context, uri: Uri): String? = runCatching {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        }.getOrNull()

        /** A single path segment: no separators, no leading dots, bounded. */
        private fun sanitize(name: String?): String {
            val cleaned = (name ?: "").replace(Regex("[/\\\\\\u0000]"), "_").trimStart('.').trim()
            val bounded = if (cleaned.length > 120) cleaned.takeLast(120) else cleaned
            return bounded.ifEmpty { "file" }
        }
    }
}
