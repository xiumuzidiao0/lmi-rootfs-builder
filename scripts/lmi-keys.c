// SPDX-License-Identifier: MIT
// lmi-keys - hardware key / idle / screen / console font handling for LMI Linux Server.
//
// Behavior:
//  * power key (short press) -> toggle screen off/on (dim backlight)
//  * power key (held >= 8s)  -> clean poweroff / shutdown
//  * volume up key           -> step up console terminal font size
//  * volume down key         -> step down console terminal font size
//  * idle timeout (-t secs)  -> backlight off; touch/key wakes up
//
// Build:
//   gcc -static -O2 -Wall -o lmi-keys lmi-keys.c

#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/reboot.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAX_FDS 32
#define SCAN_MS 2000
#define ROLE_KEYS 1
#define ROLE_TOUCH 2

static int fds[MAX_FDS];
static char *paths[MAX_FDS];
static int roles[MAX_FDS];
static int nfds;

static char backlight_dir[256] = "/sys/class/backlight/panel0-backlight";
static int idle_secs = 300;
static int power_hold_secs = 8;
static double power_down_at;
static int power_down;
static int cur_brightness = 1024;
static int max_brightness = 2047;
static int min_brightness = 10;
static int dimmed;
static int restore_brightness = 1024;
static double last_input;
static int has_backlight;

static double
now_monotonic(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int
dev_has_key(int fd, unsigned int code)
{
	unsigned long bits[(KEY_MAX / (8 * sizeof(long))) + 1] = { 0 };

	if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) < 0)
		return 0;
	return (bits[code / (8 * sizeof(long))] >> (code % (8 * sizeof(long)))) & 1UL;
}

static void
init_backlight(void)
{
	char path[300];
	FILE *f;

	if (access(backlight_dir, F_OK) != 0) {
		glob_t g;
		if (glob("/sys/class/backlight/*", 0, NULL, &g) == 0 && g.gl_pathc > 0) {
			snprintf(backlight_dir, sizeof(backlight_dir), "%s", g.gl_pathv[0]);
		}
		globfree(&g);
	}

	snprintf(path, sizeof(path), "%s/max_brightness", backlight_dir);
	f = fopen(path, "r");
	if (!f) {
		fprintf(stderr, "lmi-keys: no backlight found at %s (screen dim disabled)\n", backlight_dir);
		has_backlight = 0;
		return;
	}
	has_backlight = 1;
	if (fscanf(f, "%d", &max_brightness) != 1)
		max_brightness = 2047;
	fclose(f);

	snprintf(path, sizeof(path), "%s/brightness", backlight_dir);
	f = fopen(path, "r");
	if (f) {
		if (fscanf(f, "%d", &cur_brightness) != 1)
			cur_brightness = max_brightness;
		fclose(f);
	}
	min_brightness = max_brightness / 100;
	if (min_brightness < 1)
		min_brightness = 1;
	restore_brightness = cur_brightness > min_brightness ? cur_brightness : max_brightness;

	fprintf(stderr, "lmi-keys: backlight at %s (cur=%d, max=%d)\n",
		backlight_dir, cur_brightness, max_brightness);
}

static void
write_brightness_raw(int value)
{
	char path[300];
	FILE *f;

	if (!has_backlight)
		return;

	snprintf(path, sizeof(path), "%s/brightness", backlight_dir);
	f = fopen(path, "w");
	if (!f) {
		fprintf(stderr, "lmi-keys: open %s: %s\n", path, strerror(errno));
		return;
	}
	fprintf(f, "%d\n", value);
	fclose(f);
}

static void
apply_brightness(int value)
{
	if (!has_backlight)
		return;
	if (value > max_brightness)
		value = max_brightness;
	if (value < min_brightness)
		value = min_brightness;
	if (value == cur_brightness)
		return;
	write_brightness_raw(value);
	cur_brightness = value;
	fprintf(stderr, "lmi-keys: brightness %d/%d\n", value, max_brightness);
}

static void
clean_poweroff(void)
{
	fprintf(stderr, "lmi-keys: power held >= %ds -> shutting down system\n", power_hold_secs);
	fflush(stderr);
	sync();

	pid_t pid = fork();
	if (pid == 0) {
		execl("/bin/systemctl", "systemctl", "poweroff", NULL);
		execl("/sbin/poweroff", "poweroff", "-f", NULL);
		execl("/usr/sbin/poweroff", "poweroff", "-f", NULL);
		execl("/sbin/init", "init", "0", NULL);
		_exit(1);
	}
	sleep(3);
	sync();
	reboot(RB_POWER_OFF);
}

static void
screen_dim(void)
{
	if (!has_backlight || dimmed)
		return;
	restore_brightness = cur_brightness > min_brightness ? cur_brightness : max_brightness;
	dimmed = 1;
	write_brightness_raw(0);
	cur_brightness = 0;
	fprintf(stderr, "lmi-keys: screen off (dimmed)\n");
}

static void
screen_restore(void)
{
	if (!has_backlight || !dimmed)
		return;
	dimmed = 0;
	apply_brightness(restore_brightness);
	fprintf(stderr, "lmi-keys: screen on (restored)\n");
}

static void
step_font(int dir)
{
	pid_t pid = fork();
	if (pid == 0) {
		if (dir > 0)
			execl("/usr/local/bin/lmi-font-step", "lmi-font-step", "up", NULL);
		else
			execl("/usr/local/bin/lmi-font-step", "lmi-font-step", "down", NULL);
		_exit(1);
	}
	if (pid > 0) {
		int status;
		waitpid(pid, &status, WNOHANG);
	}
}

static void
rescan(void)
{
	glob_t g;
	size_t i;

	if (glob("/dev/input/event*", 0, NULL, &g) != 0)
		return;
	for (i = 0; i < g.gl_pathc && nfds < MAX_FDS; i++) {
		int fd, j, known = 0, role = 0;

		for (j = 0; j < nfds; j++) {
			if (strcmp(paths[j], g.gl_pathv[i]) == 0) {
				known = 1;
				break;
			}
		}
		if (known)
			continue;
		fd = open(g.gl_pathv[i], O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		if (dev_has_key(fd, KEY_VOLUMEUP) || dev_has_key(fd, KEY_VOLUMEDOWN) ||
		    dev_has_key(fd, KEY_POWER))
			role |= ROLE_KEYS;
		if (dev_has_key(fd, BTN_TOUCH))
			role |= ROLE_TOUCH;
		if (!role) {
			close(fd);
			continue;
		}
		paths[nfds] = strdup(g.gl_pathv[i]);
		fds[nfds] = fd;
		roles[nfds] = role;
		nfds++;
		fprintf(stderr, "lmi-keys: watching %s (%s%s)\n", g.gl_pathv[i],
			(role & ROLE_KEYS) ? "keys" : "",
			(role & ROLE_TOUCH) ? ((role & ROLE_KEYS) ? ",touch" : "touch") : "");
	}
	globfree(&g);
}

int
main(int argc, char *argv[])
{
	int opt;

	while ((opt = getopt(argc, argv, "b:t:p:h")) != -1) {
		switch (opt) {
		case 'b':
			snprintf(backlight_dir, sizeof(backlight_dir), "%s", optarg);
			break;
		case 't':
			idle_secs = atoi(optarg);
			break;
		case 'p':
			power_hold_secs = atoi(optarg);
			if (power_hold_secs < 1)
				power_hold_secs = 8;
			break;
		default:
			fprintf(stderr,
				"usage: %s [-b backlight_dir] [-t idle_secs] [-p power_hold_secs]\n",
				argv[0]);
			return 1;
		}
	}

	init_backlight();
	last_input = now_monotonic();
	rescan();

	fprintf(stderr, "lmi-keys: started (idle=%ds, power_hold=%ds)\n",
		idle_secs, power_hold_secs);

	for (;;) {
		struct pollfd pfd[MAX_FDS];
		int i, ready;

		for (i = 0; i < nfds; i++) {
			pfd[i].fd = fds[i];
			pfd[i].events = POLLIN;
			pfd[i].revents = 0;
		}

		ready = poll(pfd, nfds, power_down ? 200 : SCAN_MS);
		if (ready < 0) {
			if (errno == EINTR)
				continue;
			perror("poll");
			return 1;
		}

		if (power_down && power_hold_secs > 0 &&
		    (now_monotonic() - power_down_at) >= power_hold_secs) {
			clean_poweroff();
			power_down = 0;
		}

		if (ready == 0) {
			rescan();
			if (idle_secs > 0 && !dimmed &&
			    (now_monotonic() - last_input) >= idle_secs)
				screen_dim();
			continue;
		}

		for (i = 0; i < nfds; i++) {
			struct input_event ev;
			ssize_t n;
			int drop = 0;

			if (!(pfd[i].revents & (POLLIN | POLLERR | POLLHUP)))
				continue;

			while ((n = read(pfd[i].fd, &ev, sizeof(ev))) == sizeof(ev)) {
				if (ev.type == EV_SYN)
					continue;
				if (ev.type != EV_KEY && ev.type != EV_ABS && ev.type != EV_REL)
					continue;

				last_input = now_monotonic();

				if (roles[i] & ROLE_TOUCH) {
					screen_restore();
					continue;
				}

				if (ev.type != EV_KEY)
					continue;

				if (ev.code == KEY_POWER) {
					if (ev.value == 1) {
						power_down = 1;
						power_down_at = now_monotonic();
					} else if (ev.value == 0 && power_down) {
						power_down = 0;
						double held = now_monotonic() - power_down_at;
						if (held < power_hold_secs) {
							// Short press: toggle screen off / on
							if (dimmed)
								screen_restore();
							else
								screen_dim();
						}
					}
					continue;
				}

				// Key press event only (ignore repeat and release for volume)
				if (ev.value != 1)
					continue;

				if (ev.code == KEY_VOLUMEUP) {
					screen_restore();
					fprintf(stderr, "lmi-keys: Volume Up -> step font up\n");
					step_font(1);
				} else if (ev.code == KEY_VOLUMEDOWN) {
					screen_restore();
					fprintf(stderr, "lmi-keys: Volume Down -> step font down\n");
					step_font(-1);
				}
			}

			if (n < 0 && errno == ENODEV)
				drop = 1;

			if (drop) {
				fprintf(stderr, "lmi-keys: device %s disconnected\n", paths[i]);
				close(fds[i]);
				free(paths[i]);
				nfds--;
				fds[i] = fds[nfds];
				paths[i] = paths[nfds];
				roles[i] = roles[nfds];
				break;
			}

			last_input = now_monotonic();
			if (idle_secs > 0 && !dimmed &&
			    (now_monotonic() - last_input) >= idle_secs)
				screen_dim();
		}
	}

	return 0;
}
