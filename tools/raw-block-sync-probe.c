// SPDX-License-Identifier: GPL-2.0-only
/*
 * Bounded durability probe for an explicitly disposable block partition.
 *
 * The caller is responsible for proving that the supplied device is the
 * dedicated MBPTEST partition. This program deliberately refuses regular
 * files and whole disks. It writes twelve non-overlapping 1 MiB regions,
 * issues fsync(2) after each direct write, and verifies every region by direct
 * readback.
 */

#define _GNU_SOURCE

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

#define SAMPLE_COUNT 12
#define IO_SIZE (1024U * 1024U)
#define IO_ALIGNMENT 4096U
#define BASE_OFFSET (1024ULL * 1024ULL * 1024ULL)
#define OFFSET_STRIDE (8ULL * 1024ULL * 1024ULL)
#define MIN_DEVICE_SIZE (4ULL * 1024ULL * 1024ULL * 1024ULL)
#define MAX_DEVICE_SIZE (16ULL * 1024ULL * 1024ULL * 1024ULL)

struct sample {
	uint64_t preflush_us;
	uint64_t write_us;
	uint64_t flush_us;
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
	printf("%s_p95_us=%" PRIu64 "\n", name, sorted[SAMPLE_COUNT - 1]);
	printf("%s_max_us=%" PRIu64 "\n", name, sorted[SAMPLE_COUNT - 1]);
}

static void fill_pattern(unsigned char *buffer, size_t sample_index)
{
	uint64_t state = 0x9e3779b97f4a7c15ULL ^
			 ((uint64_t)sample_index * 0xd1b54a32d192ed03ULL);
	size_t offset;

	for (offset = 0; offset < IO_SIZE; offset += sizeof(state)) {
		state ^= state >> 12;
		state ^= state << 25;
		state ^= state >> 27;
		state *= 0x2545f4914f6cdd1dULL;
		memcpy(buffer + offset, &state, sizeof(state));
	}
}

int main(int argc, char **argv)
{
	const char *device;
	struct stat status;
	struct sample samples[SAMPLE_COUNT] = { 0 };
	uint64_t preflush_values[SAMPLE_COUNT];
	uint64_t write_values[SAMPLE_COUNT];
	uint64_t flush_values[SAMPLE_COUNT];
	uint64_t read_values[SAMPLE_COUNT];
	uint64_t device_size;
	char partition_attribute[128];
	unsigned char *write_buffer;
	unsigned char *read_buffer;
	int fd;
	size_t i;

	if (argc != 2) {
		fprintf(stderr, "usage: %s /dev/DEDICATED-PARTITION\n", argv[0]);
		return EXIT_FAILURE;
	}
	device = argv[1];

	if (stat(device, &status) != 0)
		fail_errno("stat target");
	if (!S_ISBLK(status.st_mode))
		fail("target is not a block device");
	if (snprintf(partition_attribute, sizeof(partition_attribute),
		     "/sys/dev/block/%u:%u/partition",
		     major(status.st_rdev), minor(status.st_rdev)) < 0)
		fail("could not construct partition sysfs path");
	if (access(partition_attribute, R_OK) != 0)
		fail("target is a whole disk or lacks a partition attribute");

	fd = open(device, O_RDWR | O_DIRECT | O_EXCL | O_CLOEXEC);
	if (fd < 0)
		fail_errno("open target exclusively");
	if (ioctl(fd, BLKGETSIZE64, &device_size) != 0)
		fail_errno("BLKGETSIZE64");
	if (device_size < MIN_DEVICE_SIZE || device_size > MAX_DEVICE_SIZE)
		fail("target size is outside the 4-16 GiB safety window");
	if (BASE_OFFSET + (SAMPLE_COUNT - 1) * OFFSET_STRIDE + IO_SIZE >
	    device_size)
		fail("probe range does not fit inside target");

	if (posix_memalign((void **)&write_buffer, IO_ALIGNMENT, IO_SIZE) != 0 ||
	    posix_memalign((void **)&read_buffer, IO_ALIGNMENT, IO_SIZE) != 0)
		fail("could not allocate aligned I/O buffers");

	alarm(60);
	printf("probe_version=1\n");
	printf("target=%s\n", device);
	printf("target_size_bytes=%" PRIu64 "\n", device_size);
	printf("sample_count=%u\n", SAMPLE_COUNT);
	printf("write_size_bytes=%u\n", IO_SIZE);
	printf("base_offset_bytes=%" PRIu64 "\n", (uint64_t)BASE_OFFSET);
	printf("offset_stride_bytes=%" PRIu64 "\n", (uint64_t)OFFSET_STRIDE);

	for (i = 0; i < SAMPLE_COUNT; i++) {
		const off_t offset = (off_t)(BASE_OFFSET + i * OFFSET_STRIDE);
		uint64_t start;
		uint64_t end;
		ssize_t count;

		fill_pattern(write_buffer, i);
		memset(read_buffer, 0, IO_SIZE);

		start = monotonic_ns();
		if (fsync(fd) != 0)
			fail_errno("pre-write fsync");
		end = monotonic_ns();
		samples[i].preflush_us = elapsed_us(start, end);

		start = monotonic_ns();
		count = pwrite(fd, write_buffer, IO_SIZE, offset);
		end = monotonic_ns();
		if (count < 0)
			fail_errno("pwrite");
		if ((size_t)count != IO_SIZE)
			fail("short pwrite");
		samples[i].write_us = elapsed_us(start, end);

		start = monotonic_ns();
		if (fsync(fd) != 0)
			fail_errno("post-write fsync");
		end = monotonic_ns();
		samples[i].flush_us = elapsed_us(start, end);

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

		preflush_values[i] = samples[i].preflush_us;
		write_values[i] = samples[i].write_us;
		flush_values[i] = samples[i].flush_us;
		read_values[i] = samples[i].read_us;
		printf("sample=%zu offset=%jd preflush_us=%" PRIu64
		       " write_us=%" PRIu64 " flush_us=%" PRIu64
		       " read_us=%" PRIu64 "\n",
		       i + 1, (intmax_t)offset, samples[i].preflush_us,
		       samples[i].write_us, samples[i].flush_us,
		       samples[i].read_us);
		fflush(stdout);
	}

	if (fsync(fd) != 0)
		fail_errno("final fsync");
	if (close(fd) != 0)
		fail_errno("close target");

	print_summary("preflush", preflush_values);
	print_summary("write", write_values);
	print_summary("flush", flush_values);
	print_summary("read", read_values);
	printf("result=pass\n");

	free(read_buffer);
	free(write_buffer);
	return EXIT_SUCCESS;
}
