/* Copyright (c) 2026 Manuel Hilgert <hilman2@gmail.com>
 *
 * A librtlsdr without a dongle. It plays a Davis ISS on channel 1 in the EU
 * band in real time, so a whole station can run on a Raspberry Pi with no SDR.
 *
 * The samples are paced by the clock and queued like USB transfers. When the
 * reader falls behind, blocks are dropped and counted, as a real dongle would
 * lose them. Every ten seconds, and at the end, the counters go to the file
 * named by STANDIN_STATS.
 *
 * Build: gcc -O2 -shared -fPIC -o librtlsdr.so.0 standin_rtlsdr.c -lm -lpthread
 */
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define SAMPLE_RATE 268800
#define SYMBOL_LENGTH 14
#define FRAME_BYTES 10              /* Sync word, six data bytes, CRC. */
#define BURST_SAMPLES (FRAME_BYTES * 8 * SYMBOL_LENGTH)
#define PERIOD 2.5625               /* Seconds between bursts of channel 1. */
#define DEVIATION 4800.0
#define AMPLITUDE 60.0
#define NOISE 6.0
#define MAX_TRANSFERS 32

static const double channels[5] = {868077250, 868197250, 868317250, 868437250, 868557250};
static const int pattern[5] = {0, 2, 4, 1, 3};

typedef void (*rtlsdr_read_async_cb_t)(unsigned char *buffer, uint32_t length, void *context);

static double dongle_error = 25000.0;  /* Stands for a dongle reading about 29 ppm off. */
static volatile uint32_t tuned;
static volatile int cancelled;
static uint64_t produced, dropped, bursts_heard, bursts_total;

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t ready = PTHREAD_COND_INITIALIZER;
static unsigned char *transfers[MAX_TRANSFERS];
static uint32_t transfer_count, transfer_length, head, used;

static uint16_t crc16(const uint8_t *data, int length)
{
    uint16_t crc = 0;
    for (int i = 0; i < length; i++) {
        crc ^= (uint16_t)data[i] << 8;
        for (int bit = 0; bit < 8; bit++)
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
    }
    return crc;
}

/* Fill one frame of the ISS. The message types take turns the way an ISS mixes
 * them: temperature, humidity and rain count, each with wind. */
static void build_frame(uint64_t index, uint8_t *frame)
{
    uint8_t data[8] = {0x80, 2, 128, 0x2B, 0xC8, 0x00, 0, 0};  /* 70.0 F, digital */
    switch (index % 3) {
    case 1:
        data[0] = 0xA0;                                        /* 55.0 %, digital */
        data[3] = 0x26;
        data[4] = 0x28;
        break;
    case 2:
        data[0] = 0xE0;                                        /* Rain counter */
        data[3] = (uint8_t)(index / 300 % 128);
        data[4] = 0x01;
        break;
    default:
        break;
    }
    uint16_t crc = crc16(data, 6);
    data[6] = crc >> 8;
    data[7] = crc & 0xFF;
    frame[0] = 0xCB;
    frame[1] = 0x89;
    for (int i = 0; i < 8; i++) {
        uint8_t value = data[i], reversed = 0;
        for (int bit = 0; bit < 8; bit++)
            reversed |= ((value >> bit) & 1) << (7 - bit);
        frame[2 + i] = reversed;
    }
}

static uint32_t noise_state = 2463534242u;

static inline double noise(void)
{
    /* The sum of four uniform values is close enough to a Gaussian here. */
    double sum = 0;
    for (int i = 0; i < 4; i++) {
        noise_state ^= noise_state << 13;
        noise_state ^= noise_state >> 17;
        noise_state ^= noise_state << 5;
        sum += (double)(noise_state & 0xFFFF) / 65536.0 - 0.5;
    }
    return sum * 3.46;
}

static void fill(unsigned char *buffer, uint32_t samples, uint64_t start)
{
    static uint64_t burst_index;
    static double phase;
    for (uint32_t i = 0; i < samples; i++) {
        uint64_t sample = start + i;
        double re = NOISE * noise(), im = NOISE * noise();
        uint64_t first = (uint64_t)((0.7 + burst_index * PERIOD) * SAMPLE_RATE);
        if (sample >= first) {
            uint64_t position = sample - first;
            if (position < BURST_SAMPLES) {
                static uint8_t frame[FRAME_BYTES];
                static double offset;
                static int audible;
                if (position == 0) {
                    int channel = pattern[burst_index % 5];
                    build_frame(burst_index, frame);
                    /* A quarter of the sample rate below the tuned frequency,
                     * where the receiver expects the carrier. */
                    offset = channels[channel] + dongle_error - (double)tuned - SAMPLE_RATE / 4.0;
                    audible = fabs(offset) < 0.45 * SAMPLE_RATE;
                    phase = 0;
                    bursts_total++;
                    bursts_heard += audible;
                }
                if (audible) {
                    int bit_index = (int)(position / SYMBOL_LENGTH);
                    int bit = (frame[bit_index / 8] >> (7 - bit_index % 8)) & 1;
                    phase += 2 * M_PI * ((bit ? DEVIATION : -DEVIATION) + offset) / SAMPLE_RATE;
                    re += AMPLITUDE * cos(phase);
                    im += AMPLITUDE * sin(phase);
                }
            } else {
                burst_index++;
            }
        }
        double i_value = round(127.4 + re), q_value = round(127.4 + im);
        buffer[2 * i] = (unsigned char)(i_value < 0 ? 0 : i_value > 255 ? 255 : i_value);
        buffer[2 * i + 1] = (unsigned char)(q_value < 0 ? 0 : q_value > 255 ? 255 : q_value);
    }
}

static void write_stats(void)
{
    const char *path = getenv("STANDIN_STATS");
    if (!path)
        return;
    FILE *stream = fopen(path, "w");
    if (!stream)
        return;
    fprintf(stream, "produced=%llu dropped=%llu bursts=%llu heard=%llu\n",
            (unsigned long long)produced, (unsigned long long)dropped,
            (unsigned long long)bursts_total, (unsigned long long)bursts_heard);
    fclose(stream);
}

static void *producer(void *unused)
{
    (void)unused;
    uint32_t samples = transfer_length / 2;
    uint64_t start = 0;
    struct timespec next;
    clock_gettime(CLOCK_MONOTONIC, &next);
    unsigned char *scratch = malloc(transfer_length);
    while (!cancelled) {
        fill(scratch, samples, start);
        start += samples;
        uint64_t nanoseconds = next.tv_nsec + samples * 1000000000ULL / SAMPLE_RATE;
        next.tv_sec += nanoseconds / 1000000000ULL;
        next.tv_nsec = nanoseconds % 1000000000ULL;
        clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &next, NULL);
        pthread_mutex_lock(&lock);
        produced++;
        if (used < transfer_count) {
            memcpy(transfers[(head + used) % transfer_count], scratch, transfer_length);
            used++;
            pthread_cond_signal(&ready);
        } else {
            dropped++;
        }
        pthread_mutex_unlock(&lock);
        if (produced % 333 == 0)
            write_stats();
    }
    free(scratch);
    return NULL;
}

uint32_t rtlsdr_get_device_count(void) { return 1; }
const char *rtlsdr_get_device_name(uint32_t index) { (void)index; return "Stand-in dongle"; }
int rtlsdr_get_index_by_serial(const char *serial) { (void)serial; return -1; }

int rtlsdr_open(void **device, uint32_t index)
{
    (void)index;
    *device = &dropped;
    cancelled = 0;
    return 0;
}

int rtlsdr_close(void *device) { (void)device; write_stats(); return 0; }
int rtlsdr_set_center_freq(void *device, uint32_t frequency) { (void)device; tuned = frequency; return 0; }
int rtlsdr_set_sample_rate(void *device, uint32_t rate) { (void)device; (void)rate; return 0; }
int rtlsdr_set_tuner_gain_mode(void *device, int manual) { (void)device; (void)manual; return 0; }
int rtlsdr_set_tuner_gain(void *device, int gain) { (void)device; (void)gain; return 0; }
int rtlsdr_get_tuner_gains(void *device, int *gains) { (void)device; (void)gains; return 0; }
int rtlsdr_reset_buffer(void *device) { (void)device; return 0; }

int rtlsdr_read_async(void *device, rtlsdr_read_async_cb_t callback, void *context,
                      uint32_t buffer_count, uint32_t buffer_length)
{
    (void)device;
    pthread_t thread;
    transfer_count = buffer_count > MAX_TRANSFERS ? MAX_TRANSFERS : buffer_count;
    transfer_length = buffer_length;
    head = used = 0;
    for (uint32_t i = 0; i < transfer_count; i++)
        transfers[i] = malloc(buffer_length);
    pthread_create(&thread, NULL, producer, NULL);
    unsigned char *block = malloc(buffer_length);
    while (!cancelled) {
        pthread_mutex_lock(&lock);
        while (!used && !cancelled)
            pthread_cond_wait(&ready, &lock);
        if (cancelled) {
            pthread_mutex_unlock(&lock);
            break;
        }
        memcpy(block, transfers[head], buffer_length);
        head = (head + 1) % transfer_count;
        used--;
        pthread_mutex_unlock(&lock);
        callback(block, buffer_length, context);
    }
    pthread_join(thread, NULL);
    free(block);
    write_stats();
    return 0;
}

int rtlsdr_cancel_async(void *device)
{
    (void)device;
    pthread_mutex_lock(&lock);
    cancelled = 1;
    pthread_cond_broadcast(&ready);
    pthread_mutex_unlock(&lock);
    return 0;
}

int rtlsdr_read_sync(void *device, void *buffer, int length, int *read)
{
    (void)device; (void)buffer; (void)length; (void)read;
    return -1;
}
