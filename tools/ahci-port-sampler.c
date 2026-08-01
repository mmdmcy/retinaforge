// SPDX-License-Identifier: GPL-2.0-only
/*
 * Sample AHCI host/port registers for the unique Samsung 144d:1600 controller.
 *
 * While ENABLE_PATH exists, append monotonic-timestamped MMIO samples to
 * OUTPUT_PATH. Used by the legacy-stack appliance to discriminate whether long
 * FLUSH CACHE EXT intervals keep PxCI set (command still active) or clear
 * early (completion observed late).
 *
 * Usage: ahci-port-sampler OUTPUT_PATH ENABLE_PATH [period_us]
 */

#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define PCI_VENDOR "0x144d"
#define PCI_DEVICE "0x1600"
#define AHCI_BAR_MAP_SIZE 4096U
#define HOST_IS_OFF 0x08U
#define PORT0_BASE 0x100U
#define PXIS_OFF (PORT0_BASE + 0x10U)
#define PXTFD_OFF (PORT0_BASE + 0x20U)
#define PXSERR_OFF (PORT0_BASE + 0x30U)
#define PXSACT_OFF (PORT0_BASE + 0x34U)
#define PXCI_OFF (PORT0_BASE + 0x38U)
#define DEFAULT_PERIOD_US 1000U

static volatile sig_atomic_t stop_requested;

static void on_signal(int signo)
{
	(void)signo;
	stop_requested = 1;
}

static void fail(const char *message)
{
	fprintf(stderr, "error: %s\n", message);
	exit(EXIT_FAILURE);
}

static void fail_errno(const char *operation)
{
	fprintf(stderr, "error: %s: %s\n", operation, strerror(errno));
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

static bool read_sysfs_string(const char *path, char *buffer, size_t size)
{
	int fd;
	ssize_t n;

	fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return false;
	n = read(fd, buffer, size - 1);
	close(fd);
	if (n <= 0)
		return false;
	while (n > 0 && (buffer[n - 1] == '\n' || buffer[n - 1] == '\r'))
		n--;
	buffer[n] = '\0';
	return true;
}

static bool strings_equal(const char *left, const char *right)
{
	return strcmp(left, right) == 0;
}

static void find_unique_controller(char *bdf, size_t bdf_size)
{
	DIR *dir;
	struct dirent *entry;
	unsigned matches = 0;
	char vendor[32];
	char device[32];
	char path[512];

	dir = opendir("/sys/bus/pci/devices");
	if (!dir)
		fail_errno("opendir /sys/bus/pci/devices");

	while ((entry = readdir(dir)) != NULL) {
		if (entry->d_name[0] == '.')
			continue;
		if (snprintf(path, sizeof(path),
			     "/sys/bus/pci/devices/%s/vendor",
			     entry->d_name) >= (int)sizeof(path))
			continue;
		if (!read_sysfs_string(path, vendor, sizeof(vendor)))
			continue;
		if (snprintf(path, sizeof(path),
			     "/sys/bus/pci/devices/%s/device",
			     entry->d_name) >= (int)sizeof(path))
			continue;
		if (!read_sysfs_string(path, device, sizeof(device)))
			continue;
		if (!strings_equal(vendor, PCI_VENDOR) ||
		    !strings_equal(device, PCI_DEVICE))
			continue;
		matches++;
		if (matches == 1) {
			if (strlen(entry->d_name) + 1 > bdf_size) {
				closedir(dir);
				fail("PCI BDF path is unexpectedly long");
			}
			memcpy(bdf, entry->d_name, strlen(entry->d_name) + 1);
		}
	}
	closedir(dir);

	if (matches == 0)
		fail("Apple Samsung 144d:1600 controller not found");
	if (matches > 1)
		fail("multiple 144d:1600 controllers found");
}

static uint32_t read_reg(volatile uint32_t *regs, unsigned offset)
{
	return regs[offset / 4U];
}

int main(int argc, char **argv)
{
	const char *output_path;
	const char *enable_path;
	unsigned period_us = DEFAULT_PERIOD_US;
	char bdf[64];
	char resource_path[128];
	int resource_fd;
	int output_fd;
	void *map;
	volatile uint32_t *regs;
	FILE *output;
	struct sigaction action;
	uint64_t samples = 0;

	if (argc < 3 || argc > 4)
		fail("usage: ahci-port-sampler OUTPUT_PATH ENABLE_PATH [period_us]");

	output_path = argv[1];
	enable_path = argv[2];
	if (argc == 4) {
		char *end = NULL;
		unsigned long value = strtoul(argv[3], &end, 10);

		if (end == argv[3] || *end != '\0' || value < 100UL ||
		    value > 100000UL)
			fail("period_us must be 100..100000");
		period_us = (unsigned)value;
	}

	memset(&action, 0, sizeof(action));
	action.sa_handler = on_signal;
	sigemptyset(&action.sa_mask);
	if (sigaction(SIGTERM, &action, NULL) != 0 ||
	    sigaction(SIGINT, &action, NULL) != 0)
		fail_errno("sigaction");

	find_unique_controller(bdf, sizeof(bdf));
	if (snprintf(resource_path, sizeof(resource_path),
		     "/sys/bus/pci/devices/%s/resource0", bdf) >=
	    (int)sizeof(resource_path))
		fail("AHCI resource path is unexpectedly long");

	resource_fd = open(resource_path, O_RDONLY | O_CLOEXEC);
	if (resource_fd < 0)
		fail_errno("open AHCI resource0");

	map = mmap(NULL, AHCI_BAR_MAP_SIZE, PROT_READ, MAP_SHARED, resource_fd,
		   0);
	if (map == MAP_FAILED)
		fail_errno("mmap AHCI resource0");
	regs = map;

	output_fd = open(output_path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC,
			 0600);
	if (output_fd < 0)
		fail_errno("open sample output");
	output = fdopen(output_fd, "w");
	if (!output)
		fail_errno("fdopen sample output");

	fprintf(output,
		"# ahci-port-sampler bdf=%s period_us=%u\n"
		"# t_ns HOST_IS PxIS PxCI PxSACT PxTFD PxSERR\n",
		bdf, period_us);
	fflush(output);

	while (!stop_requested) {
		struct stat enable_stat;
		uint32_t host_is;
		uint32_t pxis;
		uint32_t pxci;
		uint32_t pxsact;
		uint32_t pxtfd;
		uint32_t pxserr;

		if (stat(enable_path, &enable_stat) != 0)
			break;

		host_is = read_reg(regs, HOST_IS_OFF);
		pxis = read_reg(regs, PXIS_OFF);
		pxci = read_reg(regs, PXCI_OFF);
		pxsact = read_reg(regs, PXSACT_OFF);
		pxtfd = read_reg(regs, PXTFD_OFF);
		pxserr = read_reg(regs, PXSERR_OFF);

		fprintf(output,
			"%" PRIu64 " 0x%08" PRIx32 " 0x%08" PRIx32
			" 0x%08" PRIx32 " 0x%08" PRIx32 " 0x%08" PRIx32
			" 0x%08" PRIx32 "\n",
			monotonic_ns(), host_is, pxis, pxci, pxsact, pxtfd,
			pxserr);
		if (fflush(output) != 0)
			fail_errno("fflush sample output");
		samples++;
		usleep(period_us);
	}

	fprintf(output, "# samples=%" PRIu64 "\n", samples);
	fflush(output);
	fclose(output);
	munmap(map, AHCI_BAR_MAP_SIZE);
	close(resource_fd);

	if (samples == 0)
		fail("no AHCI samples collected");
	return 0;
}
