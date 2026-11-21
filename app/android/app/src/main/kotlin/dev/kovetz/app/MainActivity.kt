package dev.kovetz.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.Locale
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private data class Export(
        val source: File,
        val report: File?,
        val reply: MethodChannel.Result,
    )

    private data class Document(val id: String, val name: String)

    private var pendingExport: Export? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.kovetz/export")
            .setMethodCallHandler { call, reply ->
                if (call.method != "save" && call.method != "savePair") {
                    reply.notImplemented()
                    return@setMethodCallHandler
                }
                val source = (call.argument<String>("path")
                    ?: call.argument<String>("archivePath"))?.let(::File)
                val pair = call.method == "savePair"
                val report = if (pair) call.argument<String>("reportPath")?.let(::File) else null
                if (source == null || !source.isFile || !source.canRead() ||
                    (pair && (report == null || !report.isFile || !report.canRead())) ||
                    pendingExport != null
                ) {
                    reply.error("exportFailed", null, null)
                } else {
                    pickOutput(Export(source, report, reply))
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun pickOutput(export: Export) {
        val intent = if (export.report != null) {
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
        } else {
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, export.source.name)
            }
        }
        pendingExport = export
        try {
            startActivityForResult(intent, SAVE_BACKUP)
        } catch (_: ActivityNotFoundException) {
            pendingExport = null
            export.reply.error("exportFailed", null, null)
        } catch (_: SecurityException) {
            pendingExport = null
            export.reply.error("exportFailed", null, null)
        }
    }

    @Deprecated("Used by FlutterActivity's Activity-based document integration")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_BACKUP) return
        val export = pendingExport ?: return
        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null) {
            pendingExport = null
            export.reply.success(if (export.report != null) mapOf("saved" to false) else false)
            return
        }
        thread(name = "backup-export") {
            try {
                val saved: Any = if (export.report != null) {
                    savePair(export, destination)
                } else {
                    copy(export.source, destination)
                    true
                }
                runOnUiThread {
                    pendingExport = null
                    export.reply.success(saved)
                }
            } catch (failure: Exception) {
                runOnUiThread {
                    pendingExport = null
                    export.reply.error(
                        "exportFailed",
                        null,
                        mapOf("cleanupIncomplete" to failure.suppressed.isNotEmpty()),
                    )
                }
            }
        }
    }

    private fun savePair(export: Export, tree: Uri): Map<String, Any> {
        val parent = DocumentsContract.buildDocumentUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree),
        )
        val folderName = document(parent).name
        val existing = children(tree)
        val names = existing.map { it.name.lowercase(Locale.ROOT) }.toSet()
        val ids = existing.map { it.id }.toMutableSet()
        val base = export.source.name.removeSuffixIgnoreCase(".jwlibrary")
        var candidate = base
        var suffix = 0
        while (names.contains("$candidate.jwlibrary".lowercase(Locale.ROOT)) ||
            names.contains("$candidate.report.txt".lowercase(Locale.ROOT))
        ) {
            candidate = "$base (${++suffix})"
        }

        val created = mutableListOf<Uri>()
        try {
            fun create(name: String, mimeType: String): Uri {
                val uri = DocumentsContract.createDocument(contentResolver, parent, mimeType, name)
                    ?: throw IOException("Document provider could not create a file")
                // Only documents created by this export may be written or rolled back.
                val id = DocumentsContract.getDocumentId(uri)
                if (!ids.add(id)) throw IOException("Document provider returned an existing file")
                created.add(uri)
                if (document(uri).name != name) {
                    throw IOException("Document provider changed the paired file name")
                }
                return uri
            }

            val archive = create("$candidate.jwlibrary", "application/octet-stream")
            val report = create("$candidate.report.txt", "text/plain")
            copy(export.source, archive)
            copy(requireNotNull(export.report), report)
            return mapOf("saved" to true, "folderName" to folderName)
        } catch (failure: Exception) {
            for (uri in created.asReversed()) {
                try {
                    if (!DocumentsContract.deleteDocument(contentResolver, uri)) {
                        failure.addSuppressed(IOException("Document provider could not remove partial export"))
                    }
                } catch (cleanupFailure: Exception) {
                    failure.addSuppressed(cleanupFailure)
                }
            }
            throw failure
        }
    }

    private fun copy(source: File, destination: Uri) {
        val output = contentResolver.openOutputStream(destination, "w")
            ?: throw IOException("Document provider returned no output stream")
        output.use { target ->
            source.inputStream().use { it.copyTo(target) }
        }
    }

    private fun children(tree: Uri): List<Document> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree),
        )
        val documents = mutableListOf<Document>()
        val cursor = contentResolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null,
        ) ?: throw IOException("Document provider could not list the folder")
        cursor.use {
            while (it.moveToNext()) {
                documents.add(Document(it.getString(0), it.getString(1)))
            }
        }
        return documents
    }

    private fun document(uri: Uri): Document {
        val cursor = contentResolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null,
        ) ?: throw IOException("Document provider could not read the file name")
        cursor.use {
            if (!it.moveToFirst()) throw IOException("Document provider returned no file")
            return Document(it.getString(0), it.getString(1))
        }
    }

    private fun String.removeSuffixIgnoreCase(suffix: String): String =
        if (endsWith(suffix, ignoreCase = true)) dropLast(suffix.length) else this

    private companion object {
        const val SAVE_BACKUP = 2014
    }
}
