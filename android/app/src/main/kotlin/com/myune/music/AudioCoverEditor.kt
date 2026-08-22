package com.myune.music

import android.os.Build
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.images.AndroidArtwork
import java.io.File
import java.io.IOException

object AudioCoverEditor {
    fun replaceEmbeddedCover(path: String, imageBytes: ByteArray) {
        require(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            "替换音频文件封面需要 Android 8.0 或更高版本"
        }
        require(imageBytes.isNotEmpty()) { "封面图片为空" }

        val source = File(path)
        require(source.isFile) { "音频文件不存在" }
        require(source.canWrite()) { "音频文件不可写，请检查存储权限或文件位置" }

        val parent = source.parentFile ?: throw IOException("无法访问音频文件目录")
        val extension = source.extension.let { if (it.isEmpty()) "audio" else it }
        val stamp = System.nanoTime()
        val temporary = File(parent, ".${source.nameWithoutExtension}.myune-edit-$stamp.$extension")
        val backup = File(parent, ".${source.name}.myune-backup-$stamp")
        var originalMoved = false

        try {
            source.copyTo(temporary, overwrite = false)
            val audioFile = AudioFileIO.read(temporary)
            val tag = audioFile.tagOrCreateAndSetDefault
            val artwork = AndroidArtwork().apply {
                binaryData = imageBytes
                mimeType = detectMimeType(imageBytes)
                description = "Front cover"
                pictureType = 3
            }
            tag.deleteArtworkField()
            tag.setField(artwork)
            audioFile.commit()

            if (!source.renameTo(backup)) throw IOException("无法创建原文件备份")
            originalMoved = true
            if (!temporary.renameTo(source)) {
                if (backup.renameTo(source)) {
                    originalMoved = false
                }
                throw IOException("无法写回新的音频文件")
            }
            originalMoved = false
            if (!backup.delete()) backup.deleteOnExit()
        } finally {
            if (temporary.exists()) temporary.delete()
            if (originalMoved && !source.exists() && backup.exists()) {
                backup.renameTo(source)
            }
        }
    }

    private fun detectMimeType(bytes: ByteArray): String {
        if (bytes.size >= 8 && bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte()) {
            return "image/png"
        }
        if (bytes.size >= 3 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte()) {
            return "image/jpeg"
        }
        if (bytes.size >= 6 && bytes[0] == 0x47.toByte() && bytes[1] == 0x49.toByte()) {
            return "image/gif"
        }
        if (bytes.size >= 12 && String(bytes, 0, 4) == "RIFF" && String(bytes, 8, 4) == "WEBP") {
            return "image/webp"
        }
        return "image/png"
    }
}
