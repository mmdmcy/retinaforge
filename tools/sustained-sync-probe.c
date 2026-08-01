// SPDX-License-Identifier: GPL-2.0-only
/*
 * Sustained ext4 write + fdatasync probe mirroring the Darwin
 * sustained-F_FULLFSYNC pattern: one file, N times (1 MiB write + durable sync).
 *
 * Does not treat long syncs as failure; it reports them so Linux can be compared
 * against Darwin's millisecond-class sustained FULLFSYNC result.
 */
#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/magic.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <time.h>
#include <unistd.h>

#define SAMPLE_COUNT 64U
#define IO_SIZE (1024U * 1024U)
#define IO_ALIGNMENT 4096U
#define LONG_SYNC_US (100U * 1000U)
#define PROBE_FILE ".mbp-ahci-sustained-sync-probe"

struct sample {
	uint64_t write_us;
	uint64_t sync_us;
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
	uint64_t state = 0x9e3779b97f4a7c15ULL ^
			 ((uint64_t)sample_index * 0x6a09e667f3bcc909ULL);
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

static void full_pwrite(int fd, const unsigned char *buffer, size_t count,
			off_t offset)
{
	size_t completed = 0;

	while (completed < count) {
		ssize_t rc = pwrite(fd, buffer + completed, count - completed,
				    offset + (off_t)completed);

		if (rc < 0) {
			if (errno == EINTR)
				continue;
			fail_errno("pwrite");
		}
		if (rc == 0)
			fail("zero-length pwrite");
		completed += (size_t)rc;
	}
}

static void full_pread(int fd, unsigned char *buffer, size_t count,
		       off_t offset)
{
	size_t completed = 0;

	while (completed < count) {
		ssize_t rc = pread(fd, buffer + completed, count - completed,
				   offset + (off_t)completed);

		if (rc < 0) {
			if (errno == EINTR)
				continue;
			fail_errno("pread verification");
		}
		if (rc == 0)
			fail("unexpected EOF during verification");
		completed += (size_t)rc;
	}
}

int main(int argc, char **argv)
{
	const char *mountpoint;
	const char *profile;
	struct stat status;
	struct statfs filesystem;
	struct sample samples[SAMPLE_COUNT] = { 0 };
	uint64_t write_values[SAMPLE_COUNT];
	uint64_t sync_values[SAMPLE_COUNT];
	unsigned char *write_buffer;
	unsigned char *read_buffer;
	int directory_fd;
	int fd;
	size_t i;
	size_t long_sync_count = 0;
	size_t first_long_index = 0;
	bool saw_long = false;
	uint64_t wall_start_ns;
	uint64_t wall_end_ns;

	if (argc != 3) {
		fprintf(stderr, "usage: %s MOUNTPOINT PROFILE\n", argv[0]);
		return EXIT_FAILURE;
	}
	mountpoint = argv[1];
	profile = argv[2];
	validate_profile(profile);

	if (stat(mountpoint, &status) != 0)
		fail_errno("stat mountpoint");
	if (!S_ISDIR(status.st_mode))
		fail("mountpoint is not a directory");
	if (statfs(mountpoint, &filesystem) != 0)
		fail_errno("statfs mountpoint");
	if ((unsigned long)filesystem.f_type != EXT4_SUPER_MAGIC)
		fail("mounted filesystem is not ext4");

	directory_fd = open(mountpoint,
			    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (directory_fd < 0)
		fail_errno("open mountpoint directory");
	fd = openat(directory_fd, PROBE_FILE,
		    O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
	if (fd < 0)
		fail_errno("create probe file exclusively");

	if (posix_memalign((void **)&write_buffer, IO_ALIGNMENT, IO_SIZE) != 0 ||
	    posix_memalign((void **)&read_buffer, IO_ALIGNMENT, IO_SIZE) != 0)
		fail("could not allocate aligned I/O buffers");

	alarm(300);
	if (syncfs(fd) != 0)
		fail_errno("initial syncfs");

	printf("probe_version=1\n");
	printf("profile=%s\n", profile);
	printf("pattern=darwin-sustained-fullfsync-mirror\n");
	printf("filesystem_type=ext4\n");
	printf("sample_count=%u\n", SAMPLE_COUNT);
	printf("write_size_bytes=%u\n", IO_SIZE);
	printf("long_sync_threshold_us=%u\n", LONG_SYNC_US);

	wall_start_ns = monotonic_ns();
	for (i = 0; i < SAMPLE_COUNT; i++) {
		const off_t offset = (off_t)(i * IO_SIZE);
		uint64_t start;
		uint64_t end;

		fill_pattern(write_buffer, i);
		start = monotonic_ns();
		full_pwrite(fd, write_buffer, IO_SIZE, offset);
		end = monotonic_ns();
		samples[i].write_us = elapsed_us(start, end);

		start = monotonic_ns();
		if (fdatasync(fd) != 0)
			fail_errno("fdatasync");
		end = monotonic_ns();
		samples[i].sync_us = elapsed_us(start, end);

		write_values[i] = samples[i].write_us;
		sync_values[i] = samples[i].sync_us;
		if (samples[i].sync_us >= LONG_SYNC_US) {
			long_sync_count++;
			if (!saw_long) {
				saw_long = true;
				first_long_index = i + 1;
			}
		}
		printf("sample=%zu offset=%jd write_us=%" PRIu64
		       " fdatasync_us=%" PRIu64 "\n",
		       i + 1, (intmax_t)offset, samples[i].write_us,
		       samples[i].sync_us);
		fflush(stdout);
	}
	wall_end_ns = monotonic_ns();

	if (fdatasync(fd) != 0)
		fail_errno("final fdatasync");
	if (posix_fadvise(fd, 0, 0, POSIX_FADV_DONTNEED) != 0)
		fail("posix_fadvise DONTNEED failed");
	if (close(fd) != 0)
		fail_errno("close probe file after writes");

	fd = openat(directory_fd, PROBE_FILE,
		    O_RDONLY | O_DIRECT | O_CLOEXEC | O_NOFOLLOW);
	if (fd < 0)
		fail_errno("open probe file for direct verification");
	for (i = 0; i < SAMPLE_COUNT; i++) {
		fill_pattern(write_buffer, i);
		memset(read_buffer, 0, IO_SIZE);
		full_pread(fd, read_buffer, IO_SIZE, (off_t)(i * IO_SIZE));
		if (memcmp(write_buffer, read_buffer, IO_SIZE) != 0)
			fail("direct readback verification mismatch");
	}
	if (close(fd) != 0)
		fail_errno("close direct verification file");
	if (unlinkat(directory_fd, PROBE_FILE, 0) != 0)
		fail_errno("unlink probe file");
	if (fsync(directory_fd) != 0)
		fail_errno("fsync probe directory");
	if (close(directory_fd) != 0)
		fail_errno("close mountpoint directory");

	print_summary("write", write_values);
	print_summary("fdatasync", sync_values);
	printf("long_sync_count=%zu\n", long_sync_count);
	if (saw_long)
		printf("first_long_index=%zu\n", first_long_index);
	else
		printf("first_long_index=none\n");
	printf("wall_us=%" PRIu64 "\n", elapsed_us(wall_start_ns, wall_end_ns));
	printf("readback=pass\n");
	printf("result=pass\n");

	free(read_buffer);
	free(write_buffer);
	return EXIT_SUCCESS;
}
