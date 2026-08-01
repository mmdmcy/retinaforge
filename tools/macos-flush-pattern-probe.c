// Compare ordinary fsync, F_FULLFSYNC, and sustained FULLFSYNC patterns on macOS.
// Build on macOS:
//   clang -O2 -Wall -Wextra macos-flush-pattern-probe.c -o macos-flush-pattern-probe
//
// Emits machine-readable lines for scripts/compare-flush-patterns.py.

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

static void print_summary(const char *mode, const struct sample *samples,
			  size_t count, double wall_ms)
{
	double *sync_values;
	double sum = 0.0;
	size_t long_count = 0;
	size_t p95_index;
	size_t first_long = SIZE_MAX;
	char first_long_text[32];

	sync_values = calloc(count, sizeof(*sync_values));
	if (!sync_values) {
		perror("calloc");
		exit(EXIT_FAILURE);
	}

	for (size_t i = 0; i < count; i++) {
		sync_values[i] = samples[i].sync_ms;
		sum += samples[i].sync_ms;
		if (samples[i].sync_ms >= 100.0) {
			long_count++;
			if (first_long == SIZE_MAX)
				first_long = i;
		}
	}

	qsort(sync_values, count, sizeof(*sync_values), compare_doubles);
	p95_index = (count * 95 + 99) / 100;
	if (p95_index == 0)
		p95_index = 1;
	if (p95_index > count)
		p95_index = count;

	if (first_long == SIZE_MAX)
		snprintf(first_long_text, sizeof(first_long_text), "none");
	else
		snprintf(first_long_text, sizeof(first_long_text), "%zu",
			 first_long + 1);

	printf("summary,os=darwin,mode=%s,count=%zu,mean_sync_ms=%.3f,"
	       "median_sync_ms=%.3f,p95_sync_ms=%.3f,max_sync_ms=%.3f,"
	       "long_sync_count=%zu,first_long_index=%s,wall_ms=%.3f,"
	       "syncs_per_s=%.3f\n",
	       mode, count, sum / (double)count, sync_values[count / 2],
	       sync_values[p95_index - 1], sync_values[count - 1], long_count,
	       first_long_text, wall_ms,
	       wall_ms > 0.0 ? (count * 1000.0) / wall_ms : 0.0);

	free(sync_values);
}

static int do_sync(int fd, int full_sync)
{
	if (full_sync)
		return fcntl(fd, F_FULLFSYNC, 0);
	return fsync(fd);
}

/*
 * isolated: create a fresh temp file, N times (write + sync), unlink.
 * sustained: one file, N times (write + sync) appending.
 * flush-only: write total_bytes once, then N syncs with no further writes.
 */
static void run_pattern(const char *directory, const char *mode, int full_sync,
			size_t iterations, size_t bytes, size_t flush_only_bytes,
			unsigned char *buffer)
{
	char path[PATH_MAX];
	struct sample *samples;
	double wall_start;
	double wall_end;
	int fd;

	if (snprintf(path, sizeof(path), "%s/.macos-flush-pattern-XXXXXX",
		     directory) >= (int)sizeof(path)) {
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

	wall_start = now_ms();

	if (strcmp(mode, "flush-only-F_FULLFSYNC") == 0 ||
	    strcmp(mode, "flush-only-fsync") == 0) {
		size_t remaining = flush_only_bytes;
		size_t chunk = bytes;

		while (remaining > 0) {
			size_t this_chunk = remaining < chunk ? remaining : chunk;

			write_all(fd, buffer, this_chunk);
			remaining -= this_chunk;
		}
		for (size_t i = 0; i < iterations; i++) {
			double sync_start = now_ms();
			int rc = do_sync(fd, full_sync);
			double sync_end = now_ms();

			if (rc != 0) {
				fprintf(stderr, "%s failed on iteration %zu: %s\n",
					mode, i, strerror(errno));
				free(samples);
				close(fd);
				unlink(path);
				exit(EXIT_FAILURE);
			}
			samples[i].write_ms = 0.0;
			samples[i].sync_ms = sync_end - sync_start;
			samples[i].total_ms = samples[i].sync_ms;
			printf("sample,os=darwin,mode=%s,%zu,write_ms=%.3f,"
			       "sync_ms=%.3f,total_ms=%.3f\n",
			       mode, i + 1, samples[i].write_ms, samples[i].sync_ms,
			       samples[i].total_ms);
		}
	} else if (strcmp(mode, "sustained-F_FULLFSYNC") == 0 ||
		   strcmp(mode, "sustained-fsync") == 0) {
		for (size_t i = 0; i < iterations; i++) {
			double start_ms;
			double write_done_ms;
			double sync_done_ms;
			int rc;

			memcpy(buffer, &i, sizeof(i));
			start_ms = now_ms();
			write_all(fd, buffer, bytes);
			write_done_ms = now_ms();
			rc = do_sync(fd, full_sync);
			sync_done_ms = now_ms();
			if (rc != 0) {
				fprintf(stderr, "%s failed on iteration %zu: %s\n",
					mode, i, strerror(errno));
				free(samples);
				close(fd);
				unlink(path);
				exit(EXIT_FAILURE);
			}
			samples[i].write_ms = write_done_ms - start_ms;
			samples[i].sync_ms = sync_done_ms - write_done_ms;
			samples[i].total_ms = sync_done_ms - start_ms;
			printf("sample,os=darwin,mode=%s,%zu,write_ms=%.3f,"
			       "sync_ms=%.3f,total_ms=%.3f\n",
			       mode, i + 1, samples[i].write_ms, samples[i].sync_ms,
			       samples[i].total_ms);
		}
	} else {
		/* isolated: recreate semantics of the original probe per sample */
		for (size_t i = 0; i < iterations; i++) {
			char isolated_path[PATH_MAX];
			int isolated_fd;
			double start_ms;
			double write_done_ms;
			double sync_done_ms;
			int rc;

			if (snprintf(isolated_path, sizeof(isolated_path),
				     "%s/.macos-flush-pattern-iso-XXXXXX",
				     directory) >= (int)sizeof(isolated_path)) {
				fprintf(stderr, "directory path is too long\n");
				exit(EXIT_FAILURE);
			}
			isolated_fd = mkstemp(isolated_path);
			if (isolated_fd < 0) {
				perror("mkstemp");
				exit(EXIT_FAILURE);
			}
			memcpy(buffer, &i, sizeof(i));
			start_ms = now_ms();
			write_all(isolated_fd, buffer, bytes);
			write_done_ms = now_ms();
			rc = do_sync(isolated_fd, full_sync);
			sync_done_ms = now_ms();
			if (rc != 0) {
				fprintf(stderr, "%s failed on iteration %zu: %s\n",
					mode, i, strerror(errno));
				close(isolated_fd);
				unlink(isolated_path);
				free(samples);
				close(fd);
				unlink(path);
				exit(EXIT_FAILURE);
			}
			samples[i].write_ms = write_done_ms - start_ms;
			samples[i].sync_ms = sync_done_ms - write_done_ms;
			samples[i].total_ms = sync_done_ms - start_ms;
			printf("sample,os=darwin,mode=%s,%zu,write_ms=%.3f,"
			       "sync_ms=%.3f,total_ms=%.3f\n",
			       mode, i + 1, samples[i].write_ms, samples[i].sync_ms,
			       samples[i].total_ms);
			close(isolated_fd);
			unlink(isolated_path);
		}
	}

	wall_end = now_ms();
	print_summary(mode, samples, iterations, wall_end - wall_start);
	free(samples);
	close(fd);
	unlink(path);
}

static void usage(const char *argv0)
{
	fprintf(stderr,
		"usage: %s [directory [iterations [KiB-per-write [flush-only-MiB]]]]\n"
		"Runs isolated, sustained, and flush-only F_FULLFSYNC patterns\n"
		"plus isolated/sustained ordinary fsync for comparison.\n",
		argv0);
}

int main(int argc, char **argv)
{
	const char *directory = argc > 1 ? argv[1] : ".";
	size_t iterations = argc > 2 ? parse_number(argv[2], "iterations") : 64;
	size_t kib = argc > 3 ? parse_number(argv[3], "KiB per write") : 1024;
	size_t flush_only_mib =
		argc > 4 ? parse_number(argv[4], "flush-only MiB") : 64;
	size_t bytes;
	size_t flush_only_bytes;
	unsigned char *buffer;

	if (argc > 5) {
		usage(argv[0]);
		return EXIT_FAILURE;
	}
	if (kib > SIZE_MAX / 1024 || flush_only_mib > SIZE_MAX / (1024 * 1024)) {
		fprintf(stderr, "requested size is too large\n");
		return EXIT_FAILURE;
	}
	bytes = kib * 1024;
	flush_only_bytes = flush_only_mib * 1024 * 1024;

	buffer = malloc(bytes);
	if (!buffer) {
		perror("malloc");
		return EXIT_FAILURE;
	}
	memset(buffer, 0xa5, bytes);

	printf("config,os=darwin,directory=%s,iterations=%zu,bytes_per_write=%zu,"
	       "flush_only_bytes=%zu\n",
	       directory, iterations, bytes, flush_only_bytes);

	run_pattern(directory, "isolated-fsync", 0, iterations < 12 ? iterations : 12,
		    bytes, flush_only_bytes, buffer);
	run_pattern(directory, "isolated-F_FULLFSYNC", 1,
		    iterations < 12 ? iterations : 12, bytes, flush_only_bytes,
		    buffer);
	run_pattern(directory, "sustained-fsync", 0, iterations, bytes,
		    flush_only_bytes, buffer);
	run_pattern(directory, "sustained-F_FULLFSYNC", 1, iterations, bytes,
		    flush_only_bytes, buffer);
	run_pattern(directory, "flush-only-F_FULLFSYNC", 1, iterations, bytes,
		    flush_only_bytes, buffer);

	free(buffer);
	return EXIT_SUCCESS;
}
