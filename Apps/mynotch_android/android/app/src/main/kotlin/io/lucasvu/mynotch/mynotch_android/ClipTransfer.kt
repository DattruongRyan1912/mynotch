package io.lucasvu.mynotch.mynotch_android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.util.Base64
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream

object ClipTransfer {
    private const val AUTHORITY = "io.lucasvu.mynotch.mynotch_android.syncfiles"

    fun sanitizeFileName(fileName: String): String {
        return fileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
    }

    fun sanitizeTransferId(transferId: String): String {
        return transferId.replace(Regex("[^a-zA-Z0-9_-]"), "_")
    }

    /**
     * Core filesystem saving logic with directory containment, symlink rejection,
     * and collision prevention without overwrite.
     */
    fun saveFileInternal(baseDir: File, transferId: String, fileName: String, bytes: ByteArray): File {
        val canonicalBase = baseDir.canonicalFile
        if (!canonicalBase.exists()) canonicalBase.mkdirs()

        val safeTransferId = sanitizeTransferId(transferId)
        val folder = File(canonicalBase, safeTransferId).canonicalFile
        if (!folder.toPath().startsWith(canonicalBase.toPath())) {
            throw SecurityException("Path traversal attempt in transferId: $transferId")
        }
        if (!folder.exists()) folder.mkdirs()

        val safeName = sanitizeFileName(fileName)
        val file = File(folder, safeName).canonicalFile
        if (!file.toPath().startsWith(folder.toPath())) {
            throw SecurityException("Path traversal attempt in fileName: $fileName")
        }
        if (file.exists() && java.nio.file.Files.isSymbolicLink(file.toPath())) {
            throw SecurityException("Symbolic links not permitted: ${file.path}")
        }

        var targetFile = file
        var counter = 1
        while (targetFile.exists()) {
            val nameWithoutExt = file.nameWithoutExtension
            val ext = file.extension
            val uniqueName = "$nameWithoutExt ($counter)${if (ext.isEmpty()) "" else ".$ext"}"
            targetFile = File(folder, uniqueName).canonicalFile
            if (!targetFile.toPath().startsWith(folder.toPath())) {
                throw SecurityException("Path traversal attempt in collision candidate: $uniqueName")
            }
            if (targetFile.exists() && java.nio.file.Files.isSymbolicLink(targetFile.toPath())) {
                throw SecurityException("Symbolic links not permitted in collision candidate: ${targetFile.path}")
            }
            counter++
        }

        FileOutputStream(targetFile).use { it.write(bytes) }
        return targetFile
    }

    /**
     * Saves received binary file bytes into internal `files/sync_files/<transferId>/<fileName>`
     * and copies the content URI to the Android clipboard.
     */
    fun saveAndCopyFile(
        context: Context,
        transferId: String,
        fileName: String,
        mimeType: String,
        base64Data: String
    ): String {
        val bytes = Base64.decode(base64Data, Base64.DEFAULT)
        val baseDir = File(context.filesDir, "sync_files")
        val targetFile = saveFileInternal(baseDir, transferId, fileName, bytes)

        val safeName = sanitizeFileName(fileName)
        val contentUri: Uri = FileProvider.getUriForFile(context, AUTHORITY, targetFile)

        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newUri(context.contentResolver, safeName, contentUri)
        clipboard.setPrimaryClip(clip)

        return targetFile.absolutePath
    }

    /**
     * Saves received image bytes into cache `sync_images/<fileName>` and copies URI to clipboard.
     */
    fun writeImageClipboard(
        context: Context,
        fileName: String,
        base64Data: String
    ): String {
        val baseDir = File(context.cacheDir, "sync_images").canonicalFile
        if (!baseDir.exists()) baseDir.mkdirs()

        val safeName = sanitizeFileName(fileName)
        val file = File(baseDir, safeName).canonicalFile
        if (!file.toPath().startsWith(baseDir.toPath())) {
            throw SecurityException("Path traversal attempt in fileName: $fileName")
        }
        if (file.exists() && java.nio.file.Files.isSymbolicLink(file.toPath())) {
            throw SecurityException("Symbolic links not permitted: ${file.path}")
        }

        var targetFile = file
        var counter = 1
        while (targetFile.exists()) {
            val nameWithoutExt = file.nameWithoutExtension
            val ext = file.extension
            val uniqueName = "$nameWithoutExt ($counter)${if (ext.isEmpty()) "" else ".$ext"}"
            targetFile = File(baseDir, uniqueName).canonicalFile
            counter++
        }

        val bytes = Base64.decode(base64Data, Base64.DEFAULT)
        FileOutputStream(targetFile).use { it.write(bytes) }

        val contentUri: Uri = FileProvider.getUriForFile(context, AUTHORITY, targetFile)

        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newUri(context.contentResolver, "Image", contentUri)
        clipboard.setPrimaryClip(clip)

        return targetFile.absolutePath
    }
}
