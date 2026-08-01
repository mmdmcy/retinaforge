// SPDX-License-Identifier: GPL-2.0-only
/*
 * Durable sync probe for an ephemeral dm-crypt mapper over the disposable
 * scratch partition. Refuses non-mapper block devices and whole disks.
 *
 * Pattern matches the filesystem stack samples: twelve sequential 1 MiB
 * O_DIRECT writes each followed by fdatasync(2), then direct readback.
 */
#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/fs.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <time.h>
#include <unistd.h>

#define SAMPLE_COUNT 12U
#define IO_SIZE (1024U * 1024U)
#define IO_ALIGNMENT 4096U
#define LONG_SYNC_US (100U * 1000U)
#define MIN_DEVICE_SIZE (4ULL * 1024ULL * 1024ULL * 1024ULL)
#define MAX_DEVICE_SIZE (16ULL * 1024ULL * 1024ULL * 1024ULL)

struct sample {
	uint64_t write_us;
	uint64_t sync_us;
	uint64_t read_us;
};

static void fail_errno(const char *operation)
{
	fprintf(stderr, "error: %s: %s\n", operation, strerror(errno));
	exit(EXIT_FAILURE);
}

static void fail(const char *message)
{
	fprintf(stderr, "error: %s\n", message);
	exit(EXIT_FAILURE);
}

static uint64_t monotonic_ns(void)
{
	struct timespec value;

	if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
		fail_errno("clock_gettime");
	return (uint64_t)value.tv_sec * 1000000000ULL +
	       (uint64_t)value.tv_nsec;
}

static uint64_t elapsed_us(uint64_t start_ns, uint64_t end_ns)
{
	return (end_ns - start_ns + 500ULL) / 1000ULL;
}

static int compare_u64(const void *left, const void *right)
{
	const uint64_t a = *(const uint64_t *)left;
	const uint64_t b = *(const uint64_t *)right;

	return (a > b) - (a < b);
}

static void print_summary(const char *name, const uint64_t values[SAMPLE_COUNT])
{
	uint64_t sorted[SAMPLE_COUNT];
	uint64_t total = 0;
	size_t i;

	memcpy(sorted, values, sizeof(sorted));
	qsort(sorted, SAMPLE_COUNT, sizeof(sorted[0]), compare_u64);
	for (i = 0; i < SAMPLE_COUNT; i++)
		total += values[i];

	printf("%s_mean_us=%" PRIu64 "\n", name, total / SAMPLE_COUNT);
	printf("%s_median_us=%" PRIu64 "\n", name,
	       (sorted[SAMPLE_COUNT / 2 - 1] + sorted[SAMPLE_COUNT / 2]) / 2);
	printf("%s_p95_us=%" PRIu64 "\n", name,
	       sorted[((SAMPLE_COUNT * 95) + 99) / 100 - 1]);
	printf("%s_max_us=%" PRIu64 "\n", name, sorted[SAMPLE_COUNT - 1]);
}

static void fill_pattern(unsigned char *buffer, size_t sample_index)
{
	uint64_t state = 0xbb67ae8584caa73bULL ^
			 ((uint64_t)sample_index * 0x9e3779b97f4a7c15ULL);
	size_t offset;

	for (offset = 0; offset < IO_SIZE; offset += sizeof(state)) {
		state ^= state >> 12;
		state ^= state << 25;
		state ^= state >> 27;
		state *= 0x2545f4914f6cdd1dULL;
		memcpy(buffer + offset, &state, sizeof(state));
	}
}

static void validate_profile(const char *profile)
{
	const unsigned char *cursor = (const unsigned char *)profile;

	if (*cursor == '\0' || strlen(profile) > 48)
		fail("profile label is empty or too long");
	for (; *cursor != '\0'; cursor++) {
		if (!isalnum(*cursor) && *cursor != '-' && *cursor != '_')
			fail("profile label contains an unsupported character");
	}
}

static void require_device_mapper(const struct stat *status)
{
	char path[128];

	if (snprintf(path, sizeof(path), "/sys/dev/block/%u:%u/dm",
		     major(status->st_rdev), minor(status->st_rdev)) < 0)
		fail("could not construct dm sysfs path");
	if (access(path, R_OK) != 0)
		fail("target is not a device-mapper node");
}

int main(int argc, char **argv)
{
	const char *device;
	const char *profile;
	struct stat status;
	struct sample samples[SAMPLE_COUNT] = { 0 };
	uint64_t write_values[SAMPLE_COUNT];
	uint64_t sync_values[SAMPLE_COUNT];
	uint64_t read_values[SAMPLE_COUNT];
	uint64_t device_size;
	unsigned char *write_buffer;
	unsigned char *read_buffer;
	int fd;
	size_t i;
	size_t long_sync_count = 0;
	size_t first_long_index = 0;
	bool saw_long = false;

	if (argc != 3) {
		fprintf(stderr, "usage: %s MAPPER-DEVICE PROFILE\n", argv[0]);
		return EXIT_FAILURE;
	}
	device = argv[1];
	profile = argv[2];
	validate_profile(profile);

	if (stat(device, &status) != 0)
		fail_errno("stat mapper");
	if (!S_ISBLK(status.st_mode))
		fail("target is not a block device");
	require_device_mapper(&status);

	fd = open(device, O_RDWR | O_DIRECT | O_CLOEXEC);
	if (fd < 0)
		fail_errno("open mapper");
	if (ioctl(fd, BLKGETSIZE64, &device_size) != 0)
		fail_errno("BLKGETSIZE64");
	if (device_size < MIN_DEVICE_SIZE || device_size > MAX_DEVICE_SIZE)
		fail("mapper size is outside the 4-16 GiB safety window");
	if ((uint64_t)SAMPLE_COUNT * IO_SIZE > device_size)
		fail("probe range does not fit inside mapper");

	if (posix_memalign((void **)&write_buffer, IO_ALIGNMENT, IO_SIZE) != 0 ||
	    posix_memalign((void **)&read_buffer, IO_ALIGNMENT, IO_SIZE) != 0)
		fail("could not allocate aligned I/O buffers");

	alarm(120);
	if (fsync(fd) != 0)
		fail_errno("initial fsync");

	printf("probe_version=1\n");
	printf("profile=%s\n", profile);
	printf("pattern=dmcrypt-raw-durable-sync\n");
	printf("target=%s\n", device);
	printf("target_size_bytes=%" PRIu64 "\n", device_size);
	printf("sample_count=%u\n", SAMPLE_COUNT);
	printf("write_size_bytes=%u\n", IO_SIZE);
	printf("long_sync_threshold_us=%u\n", LONG_SYNC_US);

	for (i = 0; i < SAMPLE_COUNT; i++) {
		const off_t offset = (off_t)(i * IO_SIZE);
		uint64_t start;
		uint64_t end;
		ssize_t count;

		fill_pattern(write_buffer, i);
		memset(read_buffer, 0, IO_SIZE);

		start = monotonic_ns();
		count = pwrite(fd, write_buffer, IO_SIZE, offset);
		end = monotonic_ns();
		if (count < 0)
			fail_errno("pwrite");
		if ((size_t)count != IO_SIZE)
			fail("short pwrite");
		samples[i].write_us = elapsed_us(start, end);

		start = monotonic_ns();
		if (fdatasync(fd) != 0)
			fail_errno("fdatasync");
		end = monotonic_ns();
		samples[i].sync_us = elapsed_us(start, end);

		start = monotonic_ns();
		count = pread(fd, read_buffer, IO_SIZE, offset);
		end = monotonic_ns();
		if (count < 0)
			fail_errno("pread verification");
		if ((size_t)count != IO_SIZE)
			fail("short pread");
		if (memcmp(write_buffer, read_buffer, IO_SIZE) != 0)
			fail("readback verification mismatch");
		samples[i].read_us = elapsed_us(start, end);

		write_values[i] = samples[i].write_us;
		sync_values[i] = samples[i].sync_us;
		read_values[i] = samples[i].read_us;
		if (samples[i].sync_us >= LONG_SYNC_US) {
			long_sync_count++;
			if (!saw_long) {
				saw_long = true;
				first_long_index = i + 1;
			}
		}
		printf("sample=%zu offset=%jd write_us=%" PRIu64
		       " fdatasync_us=%" PRIu64 " read_us=%" PRIu64 "\n",
		       i + 1, (intmax_t)offset, samples[i].write_us,
		       samples[i].sync_us, samples[i].read_us);
		fflush(stdout);
	}

	if (fsync(fd) != 0)
		fail_errno("final fsync");
	if (close(fd) != 0)
		fail_errno("close mapper");

	print_summary("write", write_values);
	print_summary("fdatasync", sync_values);
	print_summary("read", read_values);
	printf("long_sync_count=%zu\n", long_sync_count);
	if (saw_long)
		printf("first_long_index=%zu\n", first_long_index);
	else
		printf("first_long_index=none\n");
	printf("readback=pass\n");
	printf("result=pass\n");

	free(read_buffer);
	free(write_buffer);
	return EXIT_SUCCESS;
}
