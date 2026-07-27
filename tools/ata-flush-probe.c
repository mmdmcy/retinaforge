// SPDX-License-Identifier: GPL-2.0-only
/*
 * Issue one safe, non-data ATA command through SAT ATA PASS-THROUGH(16), and
 * report the command latency.
 *
 * This helper is intentionally limited to cache flush, read-verify, and power
 * mode query commands. It cannot issue an ATA write command.
 */

#include <errno.h>
#include <fcntl.h>
#include <scsi/sg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define ATA_CMD_FLUSH 0xe7
#define ATA_CMD_FLUSH_EXT 0xea
#define ATA_CMD_READ_VERIFY_EXT 0x42
#define ATA_CMD_CHECK_POWER 0xe5
#define ATA_CMD_SET_FEATURES 0xef
#define ATA_STATUS_ERR 0x01
#define ATA_STATUS_DF 0x20

static void usage(const char *program)
{
	fprintf(stderr,
		"Usage: %s DEVICE COMMAND\n"
		"Commands: --flush, --flush-ext, --read-verify-ext, "
		"--check-power, --disable-dipm\n"
		"Issues exactly one safe, non-data ATA command.\n",
		program);
}

static double elapsed_ms(const struct timespec *start,
			 const struct timespec *end)
{
	return (end->tv_sec - start->tv_sec) * 1000.0 +
	       (end->tv_nsec - start->tv_nsec) / 1000000.0;
}

static bool ata_return_status(const unsigned char *sense, size_t sense_len,
			      unsigned char *status,
			      unsigned char *error)
{
	size_t offset;

	if (sense_len < 8 || ((sense[0] & 0x7f) != 0x72 &&
			      (sense[0] & 0x7f) != 0x73))
		return false;

	for (offset = 8; offset + 2 <= sense_len;) {
		size_t descriptor_len = (size_t)sense[offset + 1] + 2;

		if (descriptor_len < 2 || offset + descriptor_len > sense_len)
			break;
		if (sense[offset] == 0x09 && descriptor_len >= 14) {
			*error = sense[offset + 3];
			*status = sense[offset + 13];
			return true;
		}
		offset += descriptor_len;
	}

	return false;
}

int main(int argc, char **argv)
{
	unsigned char cdb[16] = { 0 };
	unsigned char sense[64] = { 0 };
	unsigned char ata_status = 0;
	unsigned char ata_error = 0;
	struct timespec start, end;
	sg_io_hdr_t io = { 0 };
	unsigned char command;
	bool have_ata_status;
	int fd;

	if (argc != 3) {
		usage(argv[0]);
		return 2;
	}

	if (!strcmp(argv[2], "--flush"))
		command = ATA_CMD_FLUSH;
	else if (!strcmp(argv[2], "--flush-ext"))
		command = ATA_CMD_FLUSH_EXT;
	else if (!strcmp(argv[2], "--read-verify-ext"))
		command = ATA_CMD_READ_VERIFY_EXT;
	else if (!strcmp(argv[2], "--check-power"))
		command = ATA_CMD_CHECK_POWER;
	else if (!strcmp(argv[2], "--disable-dipm"))
		command = ATA_CMD_SET_FEATURES;
	else {
		usage(argv[0]);
		return 2;
	}

	fd = open(argv[1], O_RDONLY | O_NONBLOCK);
	if (fd < 0) {
		fprintf(stderr, "open %s: %s\n", argv[1], strerror(errno));
		return 1;
	}

	/* ATA PASS-THROUGH(16), non-data protocol, request ATA return sense. */
	cdb[0] = 0x85;
	cdb[1] = (3u << 1) |
		 ((command == ATA_CMD_FLUSH_EXT ||
		   command == ATA_CMD_READ_VERIFY_EXT) ? 1u : 0u);
	cdb[2] = 1u << 5; /* CK_COND */
	if (command == ATA_CMD_READ_VERIFY_EXT)
		cdb[6] = 8; /* Verify one physical 4 KiB sector range at LBA 0. */
	if (command == ATA_CMD_SET_FEATURES) {
		cdb[4] = 0x90; /* Disable use of a SATA feature. */
		cdb[6] = 0x03; /* Device-initiated power state transitions. */
		cdb[13] = 0xa0;
	} else {
		cdb[13] = 0x40; /* LBA device bit */
	}
	cdb[14] = command;

	io.interface_id = 'S';
	io.dxfer_direction = SG_DXFER_NONE;
	io.cmd_len = sizeof(cdb);
	io.mx_sb_len = sizeof(sense);
	io.cmdp = cdb;
	io.sbp = sense;
	io.timeout = 60000;

	if (clock_gettime(CLOCK_MONOTONIC, &start) != 0) {
		fprintf(stderr, "clock_gettime: %s\n", strerror(errno));
		close(fd);
		return 1;
	}

	if (ioctl(fd, SG_IO, &io) != 0) {
		fprintf(stderr, "SG_IO: %s\n", strerror(errno));
		close(fd);
		return 1;
	}

	if (clock_gettime(CLOCK_MONOTONIC, &end) != 0) {
		fprintf(stderr, "clock_gettime: %s\n", strerror(errno));
		close(fd);
		return 1;
	}
	close(fd);

	have_ata_status = ata_return_status(sense, io.sb_len_wr,
					    &ata_status, &ata_error);
	printf("command=0x%02x elapsed_ms=%.3f scsi_status=0x%02x "
	       "host_status=0x%04x driver_status=0x%04x",
	       command, elapsed_ms(&start, &end), io.status,
	       io.host_status, io.driver_status);
	if (have_ata_status)
		printf(" ata_status=0x%02x ata_error=0x%02x",
		       ata_status, ata_error);
	putchar('\n');

	if (io.host_status != 0)
		return 1;
	if (have_ata_status)
		return ata_status & (ATA_STATUS_ERR | ATA_STATUS_DF) ? 1 : 0;
	return io.status == 0 ? 0 : 1;
}
