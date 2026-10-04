// Headless GBA runner on libmgba, with a frame recorder.
//
// Usage: gba [--record DIR] <rom> <statefile> <script...>
//   If <statefile> exists it is loaded first; the state is saved back on exit.
//
// Script commands (space separated):
//   wait N            run N frames with no keys
//   press KEY [N]     hold KEY for N frames (default 4), then release for 4
//   hold KEY N        hold KEY for N frames, no release gap
//   shot FILE.png     write the current frame
//   reset             power cycle
// KEY: A B SELECT START RIGHT LEFT UP DOWN R L (combine with +, e.g. A+B)
//
// Recording (--record DIR): every emulated frame is compared with the previous
// one, and every frame whose pixels differ in any way is written to
// DIR/frames/<seq>.png. Nothing that reaches the screen is skipped; identical
// frames are only counted. Repeated runs append to the same DIR.
//   DIR/index.tsv   one row per stored frame:
//                   seq frame keys changed_px x0 y0 x1 y1 run
//                   (frame = game frame counter, bbox of changed pixels,
//                    run = which invocation wrote it)
//   DIR/inputs.tsv  one row per key change: run frame keys
//   DIR/runs.tsv    one row per invocation: run first_frame last_frame
//                   frames_emulated frames_stored script
#include <mgba/core/core.h>
#include <mgba/core/log.h>
#include <mgba/core/serialize.h>
#include <mgba-util/vfs.h>
#include <png.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

static void noLog(struct mLogger* l, int category, enum mLogLevel level, const char* format, va_list args) {
}

static struct mLogger nullLogger = { .log = noLog };

static const char* keyNames[] = { "A", "B", "SELECT", "START", "RIGHT", "LEFT", "UP", "DOWN", "R", "L" };

static struct mCore* core;
static color_t* buf;
static unsigned w, h;
static unsigned char* rgb;

static struct {
	const char* dir;
	FILE* index;
	FILE* inputs;
	color_t* prev;
	int havePrev;
	unsigned seq;
	unsigned run;
	uint32_t keys;
	int keysLogged;
	uint32_t firstFrame;
	unsigned emulated;
	unsigned stored;
} rec;

static void keysToString(uint32_t keys, char* out, size_t len) {
	out[0] = 0;
	if (!keys) {
		snprintf(out, len, "-");
		return;
	}
	for (int i = 0; i < 10; i++) {
		if (keys & (1u << i)) {
			if (out[0]) {
				strncat(out, "+", len - strlen(out) - 1);
			}
			strncat(out, keyNames[i], len - strlen(out) - 1);
		}
	}
}

static uint32_t parseKeys(const char* s) {
	uint32_t keys = 0;
	char tmp[64];
	strncpy(tmp, s, sizeof(tmp) - 1);
	tmp[sizeof(tmp) - 1] = 0;
	for (char* tok = strtok(tmp, "+"); tok; tok = strtok(NULL, "+")) {
		int found = 0;
		for (int i = 0; i < 10; i++) {
			if (!strcasecmp(tok, keyNames[i])) {
				keys |= 1u << i;
				found = 1;
			}
		}
		if (!found) {
			fprintf(stderr, "unknown key %s\n", tok);
			exit(2);
		}
	}
	return keys;
}

static void writePng(const char* path) {
	for (unsigned i = 0; i < w * h; i++) {
		uint32_t c = buf[i];
		rgb[i * 3] = c & 0xFF;
		rgb[i * 3 + 1] = (c >> 8) & 0xFF;
		rgb[i * 3 + 2] = (c >> 16) & 0xFF;
	}
	png_image img;
	memset(&img, 0, sizeof(img));
	img.version = PNG_IMAGE_VERSION;
	img.width = w;
	img.height = h;
	img.format = PNG_FORMAT_RGB;
	if (!png_image_write_to_file(&img, path, 0, rgb, w * 3, NULL)) {
		fprintf(stderr, "failed to write %s: %s\n", path, img.message);
		exit(1);
	}
}

static unsigned countLines(const char* path) {
	FILE* f = fopen(path, "r");
	if (!f) {
		return 0;
	}
	unsigned n = 0;
	int c;
	while ((c = fgetc(f)) != EOF) {
		if (c == '\n') {
			n++;
		}
	}
	fclose(f);
	return n;
}

static FILE* openTable(const char* name, const char* header, unsigned* rows) {
	char path[4096];
	snprintf(path, sizeof(path), "%s/%s", rec.dir, name);
	unsigned lines = countLines(path);
	FILE* f = fopen(path, "a");
	if (!f) {
		perror(path);
		exit(1);
	}
	if (!lines) {
		fprintf(f, "%s\n", header);
		lines = 1;
	}
	if (rows) {
		*rows = lines - 1;
	}
	return f;
}

static void recordStart(void) {
	char path[4096];
	mkdir(rec.dir, 0755);
	snprintf(path, sizeof(path), "%s/frames", rec.dir);
	if (mkdir(path, 0755) && errno != EEXIST) {
		perror(path);
		exit(1);
	}
	rec.index = openTable("index.tsv", "seq\tframe\tkeys\tchanged_px\tx0\ty0\tx1\ty1\trun", &rec.seq);
	rec.inputs = openTable("inputs.tsv", "run\tframe\tkeys", NULL);
	FILE* runs = openTable("runs.tsv", "run\tfirst_frame\tlast_frame\tframes_emulated\tframes_stored\tscript", &rec.run);
	fclose(runs);
	rec.prev = calloc(w * h, sizeof(color_t));
	rec.firstFrame = core->frameCounter(core);
}

static void recordFrame(void) {
	uint32_t frame = core->frameCounter(core);
	rec.emulated++;
	if (!rec.keysLogged || rec.keys != core->getKeys(core)) {
		char keys[64];
		rec.keys = core->getKeys(core);
		rec.keysLogged = 1;
		keysToString(rec.keys, keys, sizeof(keys));
		fprintf(rec.inputs, "%u\t%u\t%s\n", rec.run, frame, keys);
	}
	if (rec.havePrev && !memcmp(buf, rec.prev, w * h * sizeof(color_t))) {
		return;
	}
	unsigned changed = 0;
	unsigned x0 = w, y0 = h, x1 = 0, y1 = 0;
	for (unsigned y = 0; y < h; y++) {
		for (unsigned x = 0; x < w; x++) {
			unsigned i = y * w + x;
			if (!rec.havePrev || ((buf[i] ^ rec.prev[i]) & 0xFFFFFF)) {
				changed++;
				if (x < x0) x0 = x;
				if (y < y0) y0 = y;
				if (x > x1) x1 = x;
				if (y > y1) y1 = y;
			}
		}
	}
	if (!changed) {
		// Only the unused padding byte differed.
		memcpy(rec.prev, buf, w * h * sizeof(color_t));
		return;
	}
	char path[4096], keys[64];
	snprintf(path, sizeof(path), "%s/frames/%08u.png", rec.dir, rec.seq);
	writePng(path);
	keysToString(core->getKeys(core), keys, sizeof(keys));
	fprintf(rec.index, "%u\t%u\t%s\t%u\t%u\t%u\t%u\t%u\t%u\n", rec.seq, frame, keys, changed, x0, y0, x1, y1, rec.run);
	rec.seq++;
	rec.stored++;
	memcpy(rec.prev, buf, w * h * sizeof(color_t));
	rec.havePrev = 1;
}

static void recordFinish(int argc, char** argv, int scriptStart) {
	FILE* runs = openTable("runs.tsv", "", NULL);
	fprintf(runs, "%u\t%u\t%u\t%u\t%u\t", rec.run, rec.firstFrame, core->frameCounter(core), rec.emulated, rec.stored);
	for (int i = scriptStart; i < argc; i++) {
		fprintf(runs, "%s%s", i > scriptStart ? " " : "", argv[i]);
	}
	fprintf(runs, "\n");
	fclose(runs);
	fclose(rec.index);
	fclose(rec.inputs);
	printf("recorded run %u: %u frames emulated, %u stored (game frames %u-%u)\n", rec.run, rec.emulated, rec.stored,
	       rec.firstFrame, core->frameCounter(core));
}

static void run(uint32_t keys, int frames) {
	core->setKeys(core, keys);
	for (int i = 0; i < frames; i++) {
		core->runFrame(core);
		if (rec.dir) {
			recordFrame();
		}
	}
	core->setKeys(core, 0);
}

int main(int argc, char** argv) {
	int argi = 1;
	if (argc > 2 && !strcmp(argv[1], "--record")) {
		rec.dir = argv[2];
		argi = 3;
	}
	if (argc - argi < 2) {
		fprintf(stderr, "usage: %s [--record DIR] rom state [script...]\n", argv[0]);
		return 2;
	}
	const char* romPath = argv[argi];
	const char* statePath = argv[argi + 1];
	int scriptStart = argi + 2;

	mLogSetDefaultLogger(&nullLogger);
	core = mCoreFind(romPath);
	if (!core || !core->init(core)) {
		fprintf(stderr, "no core for %s\n", romPath);
		return 1;
	}
	mCoreInitConfig(core, NULL);
	core->desiredVideoDimensions(core, &w, &h);
	buf = calloc(w * h, sizeof(color_t));
	rgb = malloc(w * h * 3);
	core->setVideoBuffer(core, buf, w);
	if (!mCoreLoadFile(core, romPath)) {
		fprintf(stderr, "failed to load %s\n", romPath);
		return 1;
	}
	mCoreAutoloadSave(core);
	core->reset(core);

	struct VFile* vf = VFileOpen(statePath, O_RDONLY);
	if (vf) {
		if (!mCoreLoadStateNamed(core, vf, SAVESTATE_SAVEDATA | SAVESTATE_RTC)) {
			fprintf(stderr, "failed to load state %s\n", statePath);
		}
		vf->close(vf);
	}
	if (rec.dir) {
		recordStart();
	}

	for (int i = scriptStart; i < argc; i++) {
		const char* cmd = argv[i];
		if (!strcmp(cmd, "wait") && i + 1 < argc) {
			run(0, atoi(argv[++i]));
		} else if (!strcmp(cmd, "press") && i + 1 < argc) {
			uint32_t keys = parseKeys(argv[++i]);
			int n = 4;
			if (i + 1 < argc && argv[i + 1][0] >= '0' && argv[i + 1][0] <= '9') {
				n = atoi(argv[++i]);
			}
			run(keys, n);
			run(0, 4);
		} else if (!strcmp(cmd, "hold") && i + 2 < argc) {
			uint32_t keys = parseKeys(argv[++i]);
			run(keys, atoi(argv[++i]));
		} else if (!strcmp(cmd, "shot") && i + 1 < argc) {
			writePng(argv[++i]);
		} else if (!strcmp(cmd, "reset")) {
			core->reset(core);
		} else {
			fprintf(stderr, "bad command at %s\n", cmd);
			return 2;
		}
	}

	vf = VFileOpen(statePath, O_CREAT | O_TRUNC | O_RDWR);
	if (!vf || !mCoreSaveStateNamed(core, vf, SAVESTATE_SAVEDATA | SAVESTATE_RTC)) {
		fprintf(stderr, "failed to save state %s\n", statePath);
	}
	if (vf) {
		vf->close(vf);
	}
	if (rec.dir) {
		recordFinish(argc, argv, scriptStart);
	}
	core->deinit(core);
	return 0;
}
