// SPDX-License-Identifier: GPL-2.0-only
/*
 * Installer-like plain ext4 durable-write probe.
 *
 * Mimics package-unpack traffic: many small files, each created, written,
 * and fdatasync'd, with periodic directory fsync. Long syncs are reported,
 * not treated as hard failure, so a physical capture can decide whether
 * unencrypted Linux stays usable under installer-shaped load.
 */
#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/magic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <time.h>
#include <unistd.h>

#define FILE_COUNT 512U
#define IO_SIZE 4096U
#define DIR_SYNC_EVERY 32U
#define LONG_SYNC_US (100U * 1000U)
#define PROBE_DIR ".mbp-ahci-installer-sync-probe"

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

static void print_summary(const char *name, const uint64_t *values, size_t count)
{
	uint64_t *sorted;
	uint64_t total = 0;
	size_t i;

	sorted = malloc(count * sizeof(*sorted));
	if (sorted == NULL)
		fail_errno("malloc summary");
	memcpy(sorted, values, count * sizeof(*sorted));
	qsort(sorted, count, sizeof(*sorted), compare_u64);
	for (i = 0; i < count; i++)
		total += values[i];

	printf("%s_mean_us=%" PRIu64 "\n", name, total / count);
	printf("%s_median_us=%" PRIu64 "\n", name,
	       (sorted[count / 2 - 1] + sorted[count / 2]) / 2);
	printf("%s_p95_us=%" PRIu64 "\n", name,
	       sorted[((count * 95) + 99) / 100 - 1]);
	printf("%s_max_us=%" PRIu64 "\n", name, sorted[count - 1]);
	free(sorted);
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

int main(int argc, char **argv)
{
	const char *mountpoint;
	const char *profile;
	struct stat status;
	struct statfs filesystem;
	uint64_t *sync_values;
	unsigned char buffer[IO_SIZE];
	char path[256];
	int mount_fd;
	int dir_fd;
	size_t i;
	size_t long_sync_count = 0;
	size_t first_long_index = 0;
	int saw_long = 0;
	uint64_t wall_start_ns;
	uint64_t wall_end_ns;
	uint64_t dir_sync_total_us = 0;
	size_t dir_sync_count = 0;

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

	sync_values = calloc(FILE_COUNT, sizeof(*sync_values));
	if (sync_values == NULL)
		fail_errno("calloc sync_values");

	mount_fd = open(mountpoint,
			O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (mount_fd < 0)
		fail_errno("open mountpoint directory");
	if (mkdirat(mount_fd, PROBE_DIR, 0700) != 0 && errno != EEXIST)
		fail_errno("mkdirat probe directory");
	dir_fd = openat(mount_fd, PROBE_DIR,
			O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (dir_fd < 0)
		fail_errno("open probe directory");

	printf("profile=%s\n", profile);
	printf("pattern=installer-smallfile-durable\n");
	printf("file_count=%u\n", FILE_COUNT);
	printf("io_size_bytes=%u\n", IO_SIZE);
	printf("dir_sync_every=%u\n", DIR_SYNC_EVERY);
	printf("long_sync_threshold_us=%u\n", LONG_SYNC_US);

	wall_start_ns = monotonic_ns();
	for (i = 0; i < FILE_COUNT; i++) {
		int fd;
		uint64_t start_ns;
		uint64_t end_ns;
		uint64_t sync_us;

		if (snprintf(path, sizeof(path), "f-%04zu", i) >= (int)sizeof(path))
			fail("probe path truncated");
		fill_pattern(buffer, i);
		fd = openat(dir_fd, path,
			    O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
			    0600);
		if (fd < 0)
			fail_errno("openat probe file");
		if (write(fd, buffer, IO_SIZE) != (ssize_t)IO_SIZE)
			fail_errno("write probe file");
		start_ns = monotonic_ns();
		if (fdatasync(fd) != 0)
			fail_errno("fdatasync probe file");
		end_ns = monotonic_ns();
		if (close(fd) != 0)
			fail_errno("close probe file");

		sync_us = elapsed_us(start_ns, end_ns);
		sync_values[i] = sync_us;
		if (sync_us >= LONG_SYNC_US) {
			long_sync_count++;
			if (!saw_long) {
				first_long_index = i;
				saw_long = 1;
			}
		}

		if (((i + 1) % DIR_SYNC_EVERY) == 0) {
			start_ns = monotonic_ns();
			if (fsync(dir_fd) != 0)
				fail_errno("fsync probe directory");
			end_ns = monotonic_ns();
			dir_sync_total_us += elapsed_us(start_ns, end_ns);
			dir_sync_count++;
		}
	}
	wall_end_ns = monotonic_ns();

	print_summary("fdatasync", sync_values, FILE_COUNT);
	printf("long_sync_count=%zu\n", long_sync_count);
	if (saw_long)
		printf("first_long_index=%zu\n", first_long_index);
	else
		printf("first_long_index=none\n");
	printf("dir_sync_count=%zu\n", dir_sync_count);
	printf("dir_sync_total_us=%" PRIu64 "\n", dir_sync_total_us);
	if (dir_sync_count > 0)
		printf("dir_sync_mean_us=%" PRIu64 "\n",
		       dir_sync_total_us / dir_sync_count);
	printf("wall_elapsed_us=%" PRIu64 "\n",
	       elapsed_us(wall_start_ns, wall_end_ns));
	printf("result=pass\n");

	for (i = 0; i < FILE_COUNT; i++) {
		if (snprintf(path, sizeof(path), "f-%04zu", i) >= (int)sizeof(path))
			fail("cleanup path truncated");
		if (unlinkat(dir_fd, path, 0) != 0)
			fail_errno("unlinkat probe file");
	}
	if (close(dir_fd) != 0)
		fail_errno("close probe directory");
	if (unlinkat(mount_fd, PROBE_DIR, AT_REMOVEDIR) != 0)
		fail_errno("rmdir probe directory");
	if (fsync(mount_fd) != 0)
		fail_errno("fsync mountpoint directory");
	if (close(mount_fd) != 0)
		fail_errno("close mountpoint directory");
	free(sync_values);
	return EXIT_SUCCESS;
}
