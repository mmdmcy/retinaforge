// Compare ordinary macOS fsync() with Apple's strict F_FULLFSYNC operation.
// Build on macOS: clang -O2 -Wall -Wextra macos-fullfsync-probe.c -o macos-fullfsync-probe

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#ifndef F_FULLFSYNC
#error "This probe must be compiled on macOS, where F_FULLFSYNC is available."
#endif

struct sample {
    double write_ms;
    double sync_ms;
    double total_ms;
};

static double now_ms(void)
{
    struct timespec ts;

    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        perror("clock_gettime");
        exit(EXIT_FAILURE);
    }

    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1000000.0;
}

static void write_all(int fd, const unsigned char *buffer, size_t length)
{
    size_t offset = 0;

    while (offset < length) {
        ssize_t written = write(fd, buffer + offset, length - offset);

        if (written < 0) {
            if (errno == EINTR)
                continue;
            perror("write");
            exit(EXIT_FAILURE);
        }

        offset += (size_t)written;
    }
}

static int compare_doubles(const void *left, const void *right)
{
    double a = *(const double *)left;
    double b = *(const double *)right;

    return (a > b) - (a < b);
}

static void print_summary(const char *mode, const struct sample *samples,
                          size_t count)
{
    double *sync_values = calloc(count, sizeof(*sync_values));
    double sum = 0.0;
    size_t p95_index;

    if (!sync_values) {
        perror("calloc");
        exit(EXIT_FAILURE);
    }

    for (size_t i = 0; i < count; i++) {
        sync_values[i] = samples[i].sync_ms;
        sum += samples[i].sync_ms;
    }

    qsort(sync_values, count, sizeof(*sync_values), compare_doubles);
    p95_index = (count * 95 + 99) / 100;
    if (p95_index == 0)
        p95_index = 1;
    if (p95_index > count)
        p95_index = count;

    printf("summary,%s,count=%zu,mean_sync_ms=%.3f,median_sync_ms=%.3f,"
           "p95_sync_ms=%.3f,max_sync_ms=%.3f\n",
           mode, count, sum / (double)count, sync_values[count / 2],
           sync_values[p95_index - 1], sync_values[count - 1]);

    free(sync_values);
}

static void run_mode(const char *directory, const char *mode, int full_sync,
                     size_t iterations, size_t bytes, unsigned char *buffer)
{
    char path[PATH_MAX];
    struct sample *samples;
    int fd;

    if (snprintf(path, sizeof(path), "%s/.macos-sync-probe-XXXXXX", directory)
        >= (int)sizeof(path)) {
        fprintf(stderr, "directory path is too long\n");
        exit(EXIT_FAILURE);
    }

    fd = mkstemp(path);
    if (fd < 0) {
        perror("mkstemp");
        exit(EXIT_FAILURE);
    }

    samples = calloc(iterations, sizeof(*samples));
    if (!samples) {
        perror("calloc");
        close(fd);
        unlink(path);
        exit(EXIT_FAILURE);
    }

    for (size_t i = 0; i < iterations; i++) {
        double start_ms;
        double write_done_ms;
        double sync_done_ms;
        int rc;

        memcpy(buffer, &i, sizeof(i));
        start_ms = now_ms();
        write_all(fd, buffer, bytes);
        write_done_ms = now_ms();

        if (full_sync)
            rc = fcntl(fd, F_FULLFSYNC, 0);
        else
            rc = fsync(fd);

        sync_done_ms = now_ms();
        if (rc != 0) {
            fprintf(stderr, "%s failed on iteration %zu: %s\n", mode, i,
                    strerror(errno));
            free(samples);
            close(fd);
            unlink(path);
            exit(EXIT_FAILURE);
        }

        samples[i].write_ms = write_done_ms - start_ms;
        samples[i].sync_ms = sync_done_ms - write_done_ms;
        samples[i].total_ms = sync_done_ms - start_ms;
        printf("sample,%s,%zu,write_ms=%.3f,sync_ms=%.3f,total_ms=%.3f\n",
               mode, i + 1, samples[i].write_ms, samples[i].sync_ms,
               samples[i].total_ms);
    }

    print_summary(mode, samples, iterations);
    free(samples);
    close(fd);
    unlink(path);
}

static unsigned long parse_number(const char *text, const char *name)
{
    char *end = NULL;
    unsigned long value;

    errno = 0;
    value = strtoul(text, &end, 10);
    if (errno || !end || *end != '\0' || value == 0) {
        fprintf(stderr, "invalid %s: %s\n", name, text);
        exit(EXIT_FAILURE);
    }

    return value;
}

int main(int argc, char **argv)
{
    const char *directory = argc > 1 ? argv[1] : ".";
    size_t iterations = argc > 2 ? parse_number(argv[2], "iterations") : 12;
    size_t kib = argc > 3 ? parse_number(argv[3], "KiB per write") : 1024;
    size_t bytes;
    unsigned char *buffer;

    if (argc > 4) {
        fprintf(stderr, "usage: %s [directory [iterations [KiB-per-write]]]\n",
                argv[0]);
        return EXIT_FAILURE;
    }

    if (kib > SIZE_MAX / 1024) {
        fprintf(stderr, "write size is too large\n");
        return EXIT_FAILURE;
    }
    bytes = kib * 1024;

    buffer = malloc(bytes);
    if (!buffer) {
        perror("malloc");
        return EXIT_FAILURE;
    }
    memset(buffer, 0xa5, bytes);

    printf("config,directory=%s,iterations=%zu,bytes_per_write=%zu\n",
           directory, iterations, bytes);
    run_mode(directory, "fsync", 0, iterations, bytes, buffer);
    run_mode(directory, "F_FULLFSYNC", 1, iterations, bytes, buffer);

    free(buffer);
    return EXIT_SUCCESS;
}
