/*
 * libmpv 在 OpenHarmony 上的可加载性冒烟测试。
 *
 * 做的事：
 *   1. mpv_create / mpv_initialize —— 验证 .so 能被动态加载、符号齐全
 *   2. 指定 ao=ohaudio             —— 验证 OHOS OHAudio 音频输出驱动在库里
 *   3. loadfile 一个 wav，跑 3 秒  —— 验证 ffmpeg 解码 + AO 建流
 *   4. 打印 current-ao 与 time-pos —— 判断是否真的在播
 *
 * 用法： smoke_test <音频文件路径>
 */
#include <mpv/client.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const char *ev_name(int e) {
    switch (e) {
    case MPV_EVENT_NONE: return "NONE";
    case MPV_EVENT_START_FILE: return "START_FILE";
    case MPV_EVENT_END_FILE: return "END_FILE";
    case MPV_EVENT_FILE_LOADED: return "FILE_LOADED";
    case MPV_EVENT_AUDIO_RECONFIG: return "AUDIO_RECONFIG";
    case MPV_EVENT_VIDEO_RECONFIG: return "VIDEO_RECONFIG";
    case MPV_EVENT_PLAYBACK_RESTART: return "PLAYBACK_RESTART";
    case MPV_EVENT_SHUTDOWN: return "SHUTDOWN";
    case MPV_EVENT_LOG_MESSAGE: return "LOG_MESSAGE";
    default: return "OTHER";
    }
}

static void die(mpv_handle *mpv, int code, const char *what) {
    fprintf(stderr, "FAIL %s: %d (%s)\n", what, code, mpv_error_string(code));
    if (mpv)
        mpv_terminate_destroy(mpv);
    exit(1);
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : NULL;

    printf("libmpv client API version: %lu\n",
           (unsigned long)mpv_client_api_version());

    mpv_handle *mpv = mpv_create();
    if (!mpv)
        die(NULL, -1, "mpv_create");

    int r;
    if ((r = mpv_set_option_string(mpv, "ao", "ohaudio")) < 0)
        die(mpv, r, "set ao=ohaudio");
    if ((r = mpv_set_option_string(mpv, "vid", "no")) < 0)
        die(mpv, r, "set vid=no");
    if ((r = mpv_set_option_string(mpv, "audio-display", "no")) < 0)
        die(mpv, r, "set audio-display=no");
    if ((r = mpv_set_option_string(mpv, "terminal", "no")) < 0)
        die(mpv, r, "set terminal=no");
    if ((r = mpv_set_option_string(mpv, "idle", "yes")) < 0)
        die(mpv, r, "set idle=yes");
    if ((r = mpv_set_option_string(mpv, "audio-client-name", "bilimusic-smoke")) < 0)
        die(mpv, r, "set audio-client-name");

    if ((r = mpv_initialize(mpv)) < 0)
        die(mpv, r, "mpv_initialize");
    printf("OK   mpv_initialize\n");

    char *ver = mpv_get_property_string(mpv, "mpv-version");
    printf("     %s\n", ver ? ver : "(null)");
    mpv_free(ver);

    if (path) {
        const char *cmd[] = {"loadfile", path, NULL};
        if ((r = mpv_command(mpv, cmd)) < 0)
            die(mpv, r, "loadfile");
        printf("OK   loadfile %s\n", path);
    } else {
        printf("SKIP loadfile（没给音频文件）\n");
    }

    int got_reconfig = 0, got_loaded = 0;
    const double deadline = 3.0;
    for (int i = 0; i < 3000; i++) {
        mpv_event *ev = mpv_wait_event(mpv, 0.01);
        if (!ev)
            continue;
        if (ev->event_id != MPV_EVENT_NONE) {
            printf("EV   %s\n", ev_name(ev->event_id));
            if (ev->event_id == MPV_EVENT_AUDIO_RECONFIG)
                got_reconfig = 1;
            if (ev->event_id == MPV_EVENT_FILE_LOADED)
                got_loaded = 1;
            if (ev->event_id == MPV_EVENT_END_FILE)
                break;
        }
        char *pos = mpv_get_property_string(mpv, "time-pos");
        if (pos) {
            double p = atof(pos);
            mpv_free(pos);
            if (p >= deadline)
                break;
        }
    }

    char *ao = mpv_get_property_string(mpv, "current-ao");
    char *pos = mpv_get_property_string(mpv, "time-pos");
    char *fmt = mpv_get_property_string(mpv, "audio-codec-name");
    printf("RESULT current-ao=%s time-pos=%s codec=%s audio-reconfig=%d file-loaded=%d\n",
           ao ? ao : "(null)", pos ? pos : "(null)", fmt ? fmt : "(null)",
           got_reconfig, got_loaded);

    int ok = got_loaded && (got_reconfig || (ao && !strcmp(ao, "ohaudio")));
    mpv_free(ao);
    mpv_free(pos);
    mpv_free(fmt);
    mpv_terminate_destroy(mpv);

    printf(ok ? "SMOKE PASS\n" : "SMOKE FAIL\n");
    return ok ? 0 : 1;
}
