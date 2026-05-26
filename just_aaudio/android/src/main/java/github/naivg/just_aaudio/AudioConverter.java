package github.naivg.just_aaudio;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.util.Log;

import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;

public class AudioConverter {
    private static final String TAG = "AudioConverter";
    
    /**
     * 使用Android原生API将音频文件转换为WAV格式
     * @param inputPath 输入文件路径
     * @param outputPath 输出WAV文件路径
     * @return 转换是否成功
     */
    public static boolean convertToWav(String inputPath, String outputPath) {
        Log.d(TAG, "Starting audio conversion from " + inputPath + " to " + outputPath);
        MediaExtractor extractor = null;
        MediaCodec decoder = null;
        
        try {
            // 创建MediaExtractor并设置数据源
            extractor = new MediaExtractor();
            Log.d(TAG, "Created MediaExtractor instance");
            extractor.setDataSource(inputPath);
            Log.d(TAG, "Set data source to: " + inputPath);
            
            // 查找音频轨道
            int audioTrackIndex = -1;
            MediaFormat audioFormat = null;
            
            int trackCount = extractor.getTrackCount();
            Log.d(TAG, "Found " + trackCount + " tracks in the media file");
            
            for (int i = 0; i < trackCount; i++) {
                MediaFormat format = extractor.getTrackFormat(i);
                String mime = format.getString(MediaFormat.KEY_MIME);
                Log.d(TAG, "Track " + i + " MIME type: " + mime);
                if (mime != null && mime.startsWith("audio/")) {
                    audioTrackIndex = i;
                    audioFormat = format;
                    Log.d(TAG, "Found audio track at index " + i + " with MIME: " + mime);
                    break;
                }
            }
            
            if (audioTrackIndex == -1) {
                Log.e(TAG, "No audio track found in file: " + inputPath);
                return false;
            }
            
            // 选择音频轨道
            extractor.selectTrack(audioTrackIndex);
            Log.d(TAG, "Selected audio track: " + audioTrackIndex);
            
            // 获取原始音频格式信息
            int sampleRate = audioFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE);
            int channelCount = audioFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
            Log.d(TAG, "Original audio format - Sample rate: " + sampleRate + ", Channels: " + channelCount);
            
            // 使用MediaCodec解码音频数据并保存为WAV文件
            boolean result = decodeAndConvertToWav(extractor, audioTrackIndex, audioFormat, outputPath, sampleRate, channelCount);
            Log.d(TAG, "Audio conversion result: " + result);
            return result;
            
        } catch (IOException e) {
            Log.e(TAG, "Error during audio conversion", e);
            return false;
        } catch (Exception e) {
            Log.e(TAG, "Unexpected error during audio conversion", e);
            return false;
        } finally {
            // 释放资源
            if (extractor != null) {
                extractor.release();
                Log.d(TAG, "Released MediaExtractor");
            }
        }
    }
    
    /**
     * 使用MediaCodec解码音频数据并保存为WAV文件
     */
    private static boolean decodeAndConvertToWav(MediaExtractor extractor, int audioTrackIndex,
                                               MediaFormat audioFormat, String outputPath, 
                                               int sampleRate, int channelCount) {
        MediaCodec decoder = null;
        FileOutputStream pcmOutputStream = null;
        FileChannel pcmChannel = null;
        
        try {
            Log.d(TAG, "Starting audio decoding. Output path: " + outputPath + 
                       ", Sample rate: " + sampleRate + ", Channels: " + channelCount);
            
            // 创建解码器
            String mime = audioFormat.getString(MediaFormat.KEY_MIME);
            decoder = MediaCodec.createDecoderByType(mime);
            decoder.configure(audioFormat, null, null, 0);
            decoder.start();
            Log.d(TAG, "Started MediaCodec decoder for MIME: " + mime);
            
            // 创建临时文件来存储PCM数据
            String tempPcmPath = outputPath + ".tmp";
            Log.d(TAG, "Creating temporary PCM file at: " + tempPcmPath);
            pcmOutputStream = new FileOutputStream(tempPcmPath);
            pcmChannel = pcmOutputStream.getChannel();
            
            // 解码循环
            ByteBuffer[] inputBuffers = decoder.getInputBuffers();
            ByteBuffer[] outputBuffers = decoder.getOutputBuffers();
            boolean isExtractorEOF = false;
            boolean isDecoderEOF = false;
            long totalBytes = 0;
            
            while (!isDecoderEOF) {
                if (!isExtractorEOF) {
                    // 将数据送入解码器
                    int inputBufferIndex = decoder.dequeueInputBuffer(1000);
                    if (inputBufferIndex >= 0) {
                        ByteBuffer inputBuffer = inputBuffers[inputBufferIndex];
                        int sampleSize = extractor.readSampleData(inputBuffer, 0);
                        if (sampleSize < 0) {
                            // 文件结束
                            decoder.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            isExtractorEOF = true;
                            Log.d(TAG, "Reached end of input file");
                        } else {
                            long presentationTimeUs = extractor.getSampleTime();
                            decoder.queueInputBuffer(inputBufferIndex, 0, sampleSize, presentationTimeUs, 0);
                            extractor.advance();
                        }
                    }
                }
                
                // 从解码器获取解码后的数据
                MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
                int outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, 1000);
                
                if (outputBufferIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED) {
                    // 输出缓冲区已更改
                    outputBuffers = decoder.getOutputBuffers();
                } else if (outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    // 输出格式已更改
                    MediaFormat newFormat = decoder.getOutputFormat();
                    Log.d(TAG, "Output format changed: " + newFormat);
                } else if (outputBufferIndex < 0) {
                    // 没有可用的输出缓冲区
                    continue;
                } else {
                    // 处理解码后的数据
                    ByteBuffer outputBuffer = outputBuffers[outputBufferIndex];
                    
                    // 写入PCM数据到临时文件
                    if ((bufferInfo.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && 
                        bufferInfo.size > 0) {
                        outputBuffer.position(bufferInfo.offset);
                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size);
                        pcmChannel.write(outputBuffer);
                        totalBytes += bufferInfo.size;
                        
                        // if (totalBytes % 100000 < bufferInfo.size) { // 每100KB左右记录一次
                        //     Log.d(TAG, "Written " + totalBytes + " bytes of PCM data");
                        // }
                    }
                    
                    decoder.releaseOutputBuffer(outputBufferIndex, false);
                    
                    // 检查是否结束
                    if ((bufferInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        isDecoderEOF = true;
                        Log.d(TAG, "Reached end of decoded stream. Total bytes: " + totalBytes);
                    }
                }
            }
            
            // 关闭PCM输出流
            if (pcmChannel != null) {
                pcmChannel.close();
            }
            if (pcmOutputStream != null) {
                pcmOutputStream.close();
            }
            
            // 停止并释放解码器
            if (decoder != null) {
                decoder.stop();
                decoder.release();
            }
            
            // 创建WAV文件
            Log.d(TAG, "Creating WAV file with " + totalBytes + " bytes of PCM data");
            createWavFile(tempPcmPath, outputPath, sampleRate, channelCount, totalBytes);
            Log.d(TAG, "Created WAV file at: " + outputPath);
            
            // 删除临时PCM文件
            java.io.File tempFile = new java.io.File(tempPcmPath);
            boolean deleted = tempFile.delete();
            Log.d(TAG, "Temporary PCM file deleted: " + deleted);
            
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Error decoding audio", e);
            return false;
        } finally {
            // 确保资源被释放
            try {
                if (pcmChannel != null) {
                    pcmChannel.close();
                }
                if (pcmOutputStream != null) {
                    pcmOutputStream.close();
                }
            } catch (IOException e) {
                Log.w(TAG, "Error closing output streams", e);
            }
            
            if (decoder != null) {
                try {
                    decoder.stop();
                    decoder.release();
                    Log.d(TAG, "Released MediaCodec decoder");
                } catch (Exception e) {
                    Log.w(TAG, "Error releasing decoder", e);
                }
            }
        }
    }
    
    /**
     * 创建WAV文件
     */
    private static void createWavFile(String pcmPath, String wavPath, int sampleRate, 
                                    int channelCount, long totalBytes) throws IOException {
        Log.d(TAG, "Creating WAV file. PCM path: " + pcmPath + ", WAV path: " + wavPath + 
                   ", Sample rate: " + sampleRate + ", Channels: " + channelCount + ", Bytes: " + totalBytes);
        try (FileOutputStream wavOutputStream = new FileOutputStream(wavPath);
             FileChannel wavChannel = wavOutputStream.getChannel();
             java.io.FileInputStream pcmInputStream = new java.io.FileInputStream(pcmPath)) {
            
            // 计算WAV文件头信息
            int bitsPerSample = 16; // 使用16位样本
            int byteRate = sampleRate * channelCount * bitsPerSample / 8;
            int blockAlign = channelCount * bitsPerSample / 8;
            
            Log.d(TAG, "WAV header info - Bits per sample: " + bitsPerSample + 
                       ", Byte rate: " + byteRate + ", Block align: " + blockAlign);
            
            // 写入RIFF头
            writeString(wavOutputStream, "RIFF");
            int fileSize = (int)(36 + totalBytes); // 文件大小 = 36 + 数据大小
            Log.d(TAG, "Writing RIFF header. File size: " + fileSize);
            writeInt(wavOutputStream, fileSize);
            writeString(wavOutputStream, "WAVE");
            
            // 写入fmt chunk
            writeString(wavOutputStream, "fmt ");
            writeInt(wavOutputStream, 16); // fmt chunk大小
            writeShort(wavOutputStream, (short) 1); // 音频格式 (1 = PCM)
            writeShort(wavOutputStream, (short) channelCount); // 声道数
            writeInt(wavOutputStream, sampleRate); // 采样率
            writeInt(wavOutputStream, byteRate); // 字节率
            writeShort(wavOutputStream, (short) blockAlign); // 块对齐
            writeShort(wavOutputStream, (short) bitsPerSample); // 位深度
            
            // 写入data chunk
            writeString(wavOutputStream, "data");
            writeInt(wavOutputStream, (int) totalBytes); // 数据大小
            Log.d(TAG, "Writing data chunk header. Data size: " + totalBytes);
            
            // 复制原始音频数据
            Log.d(TAG, "Starting to copy PCM data to WAV file");
            byte[] buffer = new byte[4096];
            long bytesCopied = 0;
            int bytesRead;
            while ((bytesRead = pcmInputStream.read(buffer)) != -1) {
                wavOutputStream.write(buffer, 0, bytesRead);
                bytesCopied += bytesRead;
                // if (bytesCopied % 100000 < bytesRead) { // 每100KB左右记录一次
                //     Log.d(TAG, "Copied " + bytesCopied + " bytes to WAV file");
                // }
            }
            Log.d(TAG, "Finished copying PCM data to WAV file. Total bytes copied: " + bytesCopied);
        }
    }
    
    private static void writeString(FileOutputStream out, String value) throws IOException {
        Log.v(TAG, "Writing string: " + value);
        out.write(value.getBytes());
    }
    
    private static void writeInt(FileOutputStream out, int value) throws IOException {
        Log.v(TAG, "Writing int: " + value);
        out.write(value & 0xFF);
        out.write((value >> 8) & 0xFF);
        out.write((value >> 16) & 0xFF);
        out.write((value >> 24) & 0xFF);
    }
    
    private static void writeShort(FileOutputStream out, short value) throws IOException {
        Log.v(TAG, "Writing short: " + value);
        out.write(value & 0xFF);
        out.write((value >> 8) & 0xFF);
    }
}