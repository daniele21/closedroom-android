package com.closedroom.probe;

import android.content.AttributionSource;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.pm.ApplicationInfo;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Process;

import java.io.Closeable;
import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Minimal shell-UID carrier-call audio feasibility probe.
 *
 * <p>This is deliberately not product code. It is launched by app_process as the Android shell user
 * and writes a short WAV file on the device so G1 can be evaluated before the Android app is built.
 *
 * <p>The shell-context approach is independently implemented from the Android framework behavior and
 * informed by scrcpy's Apache-2.0 server architecture (AudioDirectCapture/FakeContext).
 */
public final class CallAudioProbe {
    private static final String VERSION = "0.1.0";
    private static final String SHELL_PACKAGE = "com.android.shell";
    private static final int DEFAULT_SAMPLE_RATE = 48_000;
    private static final int DEFAULT_SECONDS = 30;
    private static final int MAX_SECONDS = 180;
    private static final int MIN_API = 31; // Android 12. Keep the first spike small and explicit.

    private CallAudioProbe() {}

    public static void main(String[] args) {
        try {
            if (args.length == 0 || "help".equals(args[0]) || "--help".equals(args[0])) {
                printUsage();
                return;
            }

            if ("info".equals(args[0])) {
                printInfo();
                return;
            }

            if ("record".equals(args[0])) {
                record(parseOptions(args));
                return;
            }

            fail("unknown_command", "Unknown command: " + args[0], null);
        } catch (Throwable t) {
            fail("uncaught", t.getClass().getSimpleName() + ": " + safeMessage(t), t);
        }
    }

    private static void printInfo() {
        System.out.println("CRPROBE result=info"
                + " version=" + VERSION
                + " uid=" + Process.myUid()
                + " shell_uid=" + Process.SHELL_UID
                + " api=" + Build.VERSION.SDK_INT
                + " release=" + sanitize(Build.VERSION.RELEASE)
                + " manufacturer=" + sanitize(Build.MANUFACTURER)
                + " brand=" + sanitize(Build.BRAND)
                + " model=" + sanitize(Build.MODEL)
                + " device=" + sanitize(Build.DEVICE)
                + " abi=" + sanitize(primaryAbi()));
    }

    private static void record(Map<String, String> options) throws Exception {
        requireShell();
        requireSupportedApi();

        String sourceName = options.getOrDefault("source", "voice-call");
        int source = resolveSource(sourceName);
        int seconds = parseInt(options.getOrDefault("seconds", Integer.toString(DEFAULT_SECONDS)), "seconds");
        if (seconds < 1 || seconds > MAX_SECONDS) {
            throw new IllegalArgumentException("seconds must be 1.." + MAX_SECONDS);
        }

        int sampleRate = parseInt(options.getOrDefault("sample-rate", Integer.toString(DEFAULT_SAMPLE_RATE)), "sample-rate");
        String channelName = options.getOrDefault("channels", "stereo");
        int channelConfig = resolveChannelConfig(channelName);
        int channelCount = "mono".equals(channelName) ? 1 : 2;
        String outputPath = required(options, "output");

        File output = new File(outputPath);
        File parent = output.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Cannot create output directory: " + parent);
        }

        Context context = ShellRuntime.createShellContext();
        AudioFormat format = new AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(channelConfig)
                .build();

        int minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelConfig, AudioFormat.ENCODING_PCM_16BIT);
        if (minBuffer <= 0) {
            throw new IllegalStateException("AudioRecord.getMinBufferSize failed: " + minBuffer);
        }

        AudioRecord recorder = new AudioRecord.Builder()
                .setContext(context)
                .setAudioSource(source)
                .setAudioFormat(format)
                .setBufferSizeInBytes(minBuffer * 8)
                .build();

        if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
            recorder.release();
            throw new IllegalStateException("AudioRecord not initialized");
        }

        long byteCount = 0;
        long nonZeroSamples = 0;
        int peakAbs = 0;
        long deadlineNanos = System.nanoTime() + seconds * 1_000_000_000L;
        byte[] buffer = new byte[Math.max(minBuffer * 2, 8192)];

        try (WavWriter wav = new WavWriter(output, sampleRate, channelCount, 16)) {
            recorder.startRecording();
            if (recorder.getRecordingState() != AudioRecord.RECORDSTATE_RECORDING) {
                throw new IllegalStateException("AudioRecord did not enter RECORDSTATE_RECORDING");
            }

            System.out.println("CRPROBE result=recording"
                    + " source=" + sourceName
                    + " source_id=" + source
                    + " sample_rate=" + sampleRate
                    + " channels=" + channelName
                    + " seconds=" + seconds
                    + " output=" + outputPath);

            while (System.nanoTime() < deadlineNanos) {
                int read = recorder.read(buffer, 0, buffer.length, AudioRecord.READ_BLOCKING);
                if (read < 0) {
                    throw new IllegalStateException("AudioRecord.read failed: " + read);
                }
                if (read == 0) {
                    continue;
                }

                wav.write(buffer, 0, read);
                byteCount += read;

                for (int i = 0; i + 1 < read; i += 2) {
                    int sample = (short) ((buffer[i] & 0xff) | (buffer[i + 1] << 8));
                    int abs = Math.abs(sample);
                    if (abs != 0) {
                        nonZeroSamples++;
                    }
                    if (abs > peakAbs) {
                        peakAbs = abs;
                    }
                }
            }
        } finally {
            try {
                recorder.stop();
            } catch (IllegalStateException ignored) {
                // release() below still owns cleanup.
            }
            recorder.release();
        }

        System.out.println("CRPROBE result=ok"
                + " source=" + sourceName
                + " bytes=" + byteCount
                + " non_zero_samples=" + nonZeroSamples
                + " peak_abs=" + peakAbs
                + " output=" + outputPath);
    }

    private static Map<String, String> parseOptions(String[] args) {
        Map<String, String> options = new HashMap<>();
        for (int i = 1; i < args.length; i++) {
            String key = args[i];
            if (!key.startsWith("--") || i + 1 >= args.length) {
                throw new IllegalArgumentException("Expected --key value, got: " + key);
            }
            options.put(key.substring(2), args[++i]);
        }
        return options;
    }

    private static int resolveSource(String source) {
        switch (source) {
            case "voice-call":
                return MediaRecorder.AudioSource.VOICE_CALL;
            case "voice-uplink":
                return MediaRecorder.AudioSource.VOICE_UPLINK;
            case "voice-downlink":
                return MediaRecorder.AudioSource.VOICE_DOWNLINK;
            case "voice-communication":
                return MediaRecorder.AudioSource.VOICE_COMMUNICATION;
            case "mic":
                return MediaRecorder.AudioSource.MIC;
            case "remote-submix":
                return MediaRecorder.AudioSource.REMOTE_SUBMIX;
            default:
                throw new IllegalArgumentException("Unsupported source: " + source);
        }
    }

    private static int resolveChannelConfig(String channels) {
        if ("mono".equals(channels)) {
            return AudioFormat.CHANNEL_IN_MONO;
        }
        if ("stereo".equals(channels)) {
            return AudioFormat.CHANNEL_IN_STEREO;
        }
        throw new IllegalArgumentException("channels must be mono or stereo");
    }

    private static void requireShell() {
        if (Process.myUid() != Process.SHELL_UID) {
            throw new IllegalStateException("Probe must run as shell UID 2000; actual uid=" + Process.myUid());
        }
    }

    private static void requireSupportedApi() {
        if (Build.VERSION.SDK_INT < MIN_API) {
            throw new IllegalStateException("Initial probe supports Android 12/API 31+; actual api=" + Build.VERSION.SDK_INT);
        }
    }

    private static int parseInt(String value, String name) {
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(name + " must be an integer", e);
        }
    }

    private static String required(Map<String, String> options, String name) {
        String value = options.get(name);
        if (value == null || value.isEmpty()) {
            throw new IllegalArgumentException("--" + name + " is required");
        }
        return value;
    }

    private static String primaryAbi() {
        if (Build.SUPPORTED_ABIS == null || Build.SUPPORTED_ABIS.length == 0) {
            return "unknown";
        }
        return Build.SUPPORTED_ABIS[0];
    }

    private static String sanitize(String value) {
        if (value == null) {
            return "unknown";
        }
        return value.replace(' ', '_').replace('\n', '_').replace('\r', '_');
    }

    private static String safeMessage(Throwable t) {
        return t.getMessage() == null ? "no_message" : t.getMessage().replace('\n', ' ').replace('\r', ' ');
    }

    private static void fail(String type, String message, Throwable t) {
        System.err.println("CRPROBE result=error type=" + type + " message=" + sanitize(message));
        if (t != null) {
            t.printStackTrace(System.err);
        }
        System.exit(2);
    }

    private static void printUsage() {
        System.out.println("ClosedRoom call-audio feasibility probe " + VERSION);
        System.out.println("  info");
        System.out.println("  record --output <device.wav> [--source voice-call|voice-uplink|voice-downlink|voice-communication|mic|remote-submix]");
        System.out.println("         [--seconds 30] [--sample-rate 48000] [--channels stereo|mono]");
    }

    private static final class ShellRuntime {
        private static Context createShellContext() throws Exception {
            Class<?> activityThreadClass = Class.forName("android.app.ActivityThread");
            Constructor<?> constructor = activityThreadClass.getDeclaredConstructor();
            constructor.setAccessible(true);
            Object activityThread = constructor.newInstance();

            Field current = activityThreadClass.getDeclaredField("sCurrentActivityThread");
            current.setAccessible(true);
            current.set(null, activityThread);

            Field systemThread = activityThreadClass.getDeclaredField("mSystemThread");
            systemThread.setAccessible(true);
            systemThread.setBoolean(activityThread, true);

            fillAppInfo(activityThreadClass, activityThread);

            Method getSystemContext = activityThreadClass.getDeclaredMethod("getSystemContext");
            getSystemContext.setAccessible(true);
            Context base = (Context) getSystemContext.invoke(activityThread);
            if (base == null) {
                throw new IllegalStateException("ActivityThread returned null system context");
            }
            return new ShellContext(base);
        }

        private static void fillAppInfo(Class<?> activityThreadClass, Object activityThread) {
            try {
                Class<?> bindDataClass = Class.forName("android.app.ActivityThread$AppBindData");
                Constructor<?> bindDataConstructor = bindDataClass.getDeclaredConstructor();
                bindDataConstructor.setAccessible(true);
                Object bindData = bindDataConstructor.newInstance();

                ApplicationInfo appInfo = new ApplicationInfo();
                appInfo.packageName = SHELL_PACKAGE;

                Field appInfoField = bindDataClass.getDeclaredField("appInfo");
                appInfoField.setAccessible(true);
                appInfoField.set(bindData, appInfo);

                Field boundApplication = activityThreadClass.getDeclaredField("mBoundApplication");
                boundApplication.setAccessible(true);
                boundApplication.set(activityThread, bindData);
            } catch (Throwable t) {
                System.err.println("CRPROBE warning=fill_app_info_failed detail=" + sanitize(safeMessage(t)));
            }
        }
    }

    private static final class ShellContext extends ContextWrapper {
        private ShellContext(Context base) {
            super(base);
        }

        @Override
        public String getPackageName() {
            return SHELL_PACKAGE;
        }

        @Override
        public String getOpPackageName() {
            return SHELL_PACKAGE;
        }

        @Override
        public Context getApplicationContext() {
            return this;
        }

        @Override
        public AttributionSource getAttributionSource() {
            return new AttributionSource.Builder(Process.SHELL_UID)
                    .setPackageName(SHELL_PACKAGE)
                    .build();
        }
    }

    private static final class WavWriter implements Closeable {
        private final RandomAccessFile file;
        private final int sampleRate;
        private final int channels;
        private final int bitsPerSample;
        private long dataBytes;

        private WavWriter(File output, int sampleRate, int channels, int bitsPerSample) throws IOException {
            this.file = new RandomAccessFile(output, "rw");
            this.sampleRate = sampleRate;
            this.channels = channels;
            this.bitsPerSample = bitsPerSample;
            file.setLength(0);
            writeHeader(0);
        }

        private void write(byte[] data, int offset, int length) throws IOException {
            file.write(data, offset, length);
            dataBytes += length;
        }

        @Override
        public void close() throws IOException {
            file.seek(0);
            writeHeader(dataBytes);
            file.close();
        }

        private void writeHeader(long bytes) throws IOException {
            if (bytes > 0xffff_ffffL - 36) {
                throw new IOException("WAV data exceeds RIFF 32-bit size");
            }

            int byteRate = sampleRate * channels * bitsPerSample / 8;
            int blockAlign = channels * bitsPerSample / 8;

            file.writeBytes("RIFF");
            writeLe32(36 + bytes);
            file.writeBytes("WAVE");
            file.writeBytes("fmt ");
            writeLe32(16);
            writeLe16(1);
            writeLe16(channels);
            writeLe32(sampleRate);
            writeLe32(byteRate);
            writeLe16(blockAlign);
            writeLe16(bitsPerSample);
            file.writeBytes("data");
            writeLe32(bytes);
        }

        private void writeLe16(long value) throws IOException {
            file.write((int) (value & 0xff));
            file.write((int) ((value >>> 8) & 0xff));
        }

        private void writeLe32(long value) throws IOException {
            file.write((int) (value & 0xff));
            file.write((int) ((value >>> 8) & 0xff));
            file.write((int) ((value >>> 16) & 0xff));
            file.write((int) ((value >>> 24) & 0xff));
        }
    }
}
