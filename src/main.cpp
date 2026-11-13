// main.cpp — process startup: EGA palette, shadows, application object.
//
// On terminals that support OSC 4 we overwrite the 16 ANSI colours with the
// canonical EGA/VGA values, so that "blue" really is #0000AA and "brown"
// really is #AA5500. The palette is restored when the program exits (and on
// SIGTERM/SIGHUP/SIGQUIT). Set TVEGA=0 to leave the terminal palette alone.

#include "app.h"

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include <unistd.h>

extern TPoint shadowSize;
extern TColorAttr shadowAttr;

// Indexed the way terminals do it, not the way the EGA datasheet does:
// 0 black, 1 red, 2 green, 3 yellow(brown), 4 blue, 5 magenta, 6 cyan,
// 7 light gray, then the bright versions.
static const char *const ansiRgb[16] =
{
    "#000000", "#AA0000", "#00AA00", "#AA5500",
    "#0000AA", "#AA00AA", "#00AAAA", "#AAAAAA",
    "#555555", "#FF5555", "#55FF55", "#FFFF55",
    "#5555FF", "#FF55FF", "#55FFFF", "#FFFFFF"
};

static const char resetPaletteSeq[] = "\033]104\033\\";
static bool paletteActive = false;

static void out(const char *s, size_t n)
{
    if (write(STDOUT_FILENO, s, n) < 0)
        return;
}

static void restoreTerminalPalette()
{
    if (paletteActive)
    {
        out(resetPaletteSeq, sizeof resetPaletteSeq - 1);
        paletteActive = false;
    }
}

static void restoreOnSignal(int sig)
{
    restoreTerminalPalette();
    signal(sig, SIG_DFL);
    raise(sig);
}

static void installEgaPalette()
{
    if (!isatty(STDOUT_FILENO))
        return;

    const char *opt = getenv("TVEGA");
    if (opt != 0 && opt[0] == '0' && opt[1] == EOS)
        return;

    std::string seq;
    for (int i = 0; i < 16; i++)
    {
        seq += "\033]4;";
        seq += std::to_string(i);
        seq += ";";
        seq += ansiRgb[i];
        seq += "\033\\";
    }
    out(seq.data(), seq.size());
    paletteActive = true;

    atexit(restoreTerminalPalette);
    signal(SIGTERM, restoreOnSignal);
    signal(SIGHUP, restoreOnSignal);
    signal(SIGQUIT, restoreOnSignal);
}

int main(int argc, char **argv)
{
    for (int i = 1; i < argc; i++)
    {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0)
        {
            printf("EGA EDIT — a Turbo Vision style text editor\n"
                   "Usage: %s [file...]\n\n"
                   "  F1 keyboard map   F2 save   F3 open   F4 new\n"
                   "  F10 menu          Ctrl-Q or Alt-X quits\n"
                   "  TVEGA=0           keep the terminal's own palette\n",
                   argv[0]);
            return 0;
        }
        if (strcmp(argv[i], "--version") == 0)
        {
            printf("EGA EDIT 1.0\n");
            return 0;
        }
    }

    installEgaPalette();

    // One-cell black shadow, exactly as the style guide asks for.
    shadowSize.x = 1;
    shadowSize.y = 1;
    shadowAttr = TColorAttr(0x00);

    TEditorApp app(argc, argv);
    app.run();
    app.shutDown();

    restoreTerminalPalette();
    return 0;
}
