// dialogs.cpp — About, keyboard map, palette table, find/replace, edit dialogs.

#include "app.h"

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ushort execDialog(TDialog *d, void *data)
{
    TView *p = TProgram::application->validView(d);

    if (p == 0)
        return cmCancel;

    if (data != 0)
        p->setData(data);

    ushort result = TProgram::deskTop->execView(p);

    if (result != cmCancel && data != 0)
        p->getData(data);

    TObject::destroy(p);
    return result;
}

// ---------------------------------------------------------------------------
// EGA colour artwork
// ---------------------------------------------------------------------------

void TColorStrip::draw()
{
    TDrawBuffer b;

    for (short i = 0; i < 16; i++)
        b.moveStr(i, "\u2588", TColorAttr(int(i | (i << 4))), 1);

    writeLine(0, 0, 16, 1, b);
}

void TColorTable::draw()
{
    static const char *names[16] =
    {
        "black",     "blue",      "green",      "cyan",
        "red",       "magenta",   "brown",      "light gray",
        "dark gray", "light blue","light green","light cyan",
        "light red", "light magenta", "yellow", "white"
    };
    static const char *hex[16] =
    {
        "#000000", "#0000AA", "#00AA00", "#00AAAA",
        "#AA0000", "#AA00AA", "#AA5500", "#AAAAAA",
        "#555555", "#5555FF", "#55FF55", "#55FFFF",
        "#FF5555", "#FF55FF", "#FFFF55", "#FFFFFF"
    };

    TDrawBuffer b;
    TColorAttr text = TColorAttr(0x70);

    for (short row = 0; row < 8; row++)
    {
        b.moveChar(0, ' ', text, size.x);

        for (short col = 0; col < 2; col++)
        {
            int idx = row + col * 8;
            short x = col * 28;

            b.moveStr(x, "\u2588\u2588", TColorAttr(int(idx | (idx << 4))), 2);

            char line[48];
            snprintf(line, sizeof line, "%2d %-13s %s", idx, names[idx], hex[idx]);
            b.moveStr(x + 3, line, text, 25);
        }

        writeLine(0, row, size.x, 1, b);
    }
}

// ---------------------------------------------------------------------------
// A one-line cyan banner, the kind that used to head every DOS dialog.
// ---------------------------------------------------------------------------

class TBannerView : public TView
{
public:
    TBannerView(const TRect &r, TStringView aText) noexcept :
        TView(r),
        text(aText)
    {
    }

    virtual void draw()
    {
        TDrawBuffer b;
        TColorAttr c = TColorAttr(0x30); // black on cyan

        b.moveChar(0, ' ', c, size.x);
        int x = (size.x - (int)text.size()) / 2;
        if (x < 0)
            x = 0;
        b.moveStr(x, text, c, size.x - x);
        writeLine(0, 0, size.x, 1, b);
    }

private:
    TStringView text;
};

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

TDialog *createAboutDialog()
{
    TDialog *d = new TDialog(TRect(0, 0, 60, 18), "About");
    d->options |= ofCentered;

    d->insert(new TBannerView(TRect(1, 1, 59, 2), "E G A   E D I T   1.0"));
    d->insert(new TStaticText(TRect(3, 3, 57, 4), "A Turbo Vision style text editor."));

    d->insert(new TStaticText(TRect(3, 5, 57, 6), "Every pixel is a character cell."));
    d->insert(new TStaticText(TRect(3, 6, 57, 7), "EGA colours, double-line frames, no anti-aliasing."));

    d->insert(new TColorStrip(TRect(3, 8, 21, 9)));
    d->insert(new TStaticText(TRect(23, 8, 57, 9), "EGA 16-colour palette"));

    d->insert(new TStaticText(TRect(3, 10, 57, 11), "Built with magiblot/tvision and C++17."));
    d->insert(new TStaticText(TRect(3, 11, 57, 12), "Font: the bitmap glyphs your terminal ships."));

    d->insert(new TStaticText(TRect(3, 13, 57, 14), "Press F1 for the keyboard map."));

    d->insert(new TButton(TRect(25, 15, 35, 17), "OK", cmOK, bfDefault));

    d->selectNext(False);
    return d;
}

// ---------------------------------------------------------------------------
// Keyboard map
// ---------------------------------------------------------------------------

TDialog *createKeysDialog()
{
    static const char *lines[] =
    {
        "F1  Keyboard   F2  Save     F3  Open    F4  New",
        "F5  Zoom       F6  Next     F10 Menu    Alt-X  Exit",
        "",
        "Ctrl-N  New            Ctrl-O  Open        Ctrl-S  Save",
        "Ctrl-Z  Undo           Ctrl-X  Cut         Ctrl-C  Copy",
        "Ctrl-V  Paste          Ctrl-A  Select all  Ctrl-W  Close",
        "Ctrl-F  Find           Ctrl-H  Replace     Ctrl-L  Again",
        "",
        "Tab / Shift-Tab  Move focus       Enter  Default button",
        "Esc  Cancel dialog or close menu  Alt+letter  Jump to menu",
        "",
        "Mouse: click a title to focus it, drag a border, use the corner."
    };

    TDialog *d = new TDialog(TRect(0, 0, 70, 20), "Keyboard");
    d->options |= ofCentered;

    for (int i = 0; i < (int)(sizeof lines / sizeof lines[0]); i++)
        d->insert(new TStaticText(TRect(3, 2 + i, 67, 3 + i), lines[i]));

    d->insert(new TButton(TRect(30, 16, 40, 18), "OK", cmOK, bfDefault));

    d->selectNext(False);
    return d;
}

// ---------------------------------------------------------------------------
// EGA palette reference
// ---------------------------------------------------------------------------

TDialog *createColorsDialog()
{
    TDialog *d = new TDialog(TRect(0, 0, 62, 17), "EGA Palette");
    d->options |= ofCentered;

    d->insert(new TStaticText(TRect(3, 2, 59, 3), "EGA 16-COLOUR PALETTE"));
    d->insert(new TColorTable(TRect(3, 4, 59, 12)));

    d->insert(new TButton(TRect(26, 13, 36, 15), "OK", cmOK, bfDefault));

    d->selectNext(False);
    return d;
}

// ---------------------------------------------------------------------------
// Find / replace
// ---------------------------------------------------------------------------

TDialog *createFindDialog()
{
    TDialog *d = new TDialog(TRect(0, 0, 38, 12), "Find");

    d->options |= ofCentered;

    TInputLine *control = new TInputLine(TRect(3, 3, 32, 4), 80);
    d->insert(control);
    d->insert(new TLabel(TRect(2, 2, 15, 3), "~T~ext to find", control));
    d->insert(new THistory(TRect(32, 3, 35, 4), control, 10));

    d->insert(new TCheckBoxes(TRect(3, 5, 35, 7),
        new TSItem("~C~ase sensitive",
        new TSItem("~W~hole words only", 0))));

    d->insert(new TButton(TRect(14, 9, 24, 11), "O~K~", cmOK, bfDefault));
    d->insert(new TButton(TRect(26, 9, 36, 11), "Cancel", cmCancel, bfNormal));

    d->selectNext(False);
    return d;
}

TDialog *createReplaceDialog()
{
    TDialog *d = new TDialog(TRect(0, 0, 40, 16), "Replace");

    d->options |= ofCentered;

    TInputLine *control = new TInputLine(TRect(3, 3, 34, 4), 80);
    d->insert(control);
    d->insert(new TLabel(TRect(2, 2, 15, 3), "~T~ext to find", control));
    d->insert(new THistory(TRect(34, 3, 37, 4), control, 10));

    control = new TInputLine(TRect(3, 6, 34, 7), 80);
    d->insert(control);
    d->insert(new TLabel(TRect(2, 5, 12, 6), "~N~ew text", control));
    d->insert(new THistory(TRect(34, 6, 37, 7), control, 11));

    d->insert(new TCheckBoxes(TRect(3, 8, 37, 12),
        new TSItem("~C~ase sensitive",
        new TSItem("~W~hole words only",
        new TSItem("~P~rompt on replace",
        new TSItem("~R~eplace all", 0))))));

    d->insert(new TButton(TRect(17, 13, 27, 15), "O~K~", cmOK, bfDefault));
    d->insert(new TButton(TRect(28, 13, 38, 15), "Cancel", cmCancel, bfNormal));

    d->selectNext(False);
    return d;
}

// ---------------------------------------------------------------------------
// Editor error / prompt dialogs
// ---------------------------------------------------------------------------

ushort doEditDialog(int dialog, ...)
{
    va_list arg;
    char buf[512];

    switch (dialog)
    {
        case edOutOfMemory:
            return messageBox("Not enough memory for this operation.",
                              mfError | mfOKButton);

        case edReadError:
        {
            va_start(arg, dialog);
            const char *name = va_arg(arg, const char *);
            va_end(arg);
            snprintf(buf, sizeof buf, "Error reading file %s.", name);
            return messageBox(buf, mfError | mfOKButton);
        }

        case edWriteError:
        {
            va_start(arg, dialog);
            const char *name = va_arg(arg, const char *);
            va_end(arg);
            snprintf(buf, sizeof buf, "Error writing file %s.", name);
            return messageBox(buf, mfError | mfOKButton);
        }

        case edCreateError:
        {
            va_start(arg, dialog);
            const char *name = va_arg(arg, const char *);
            va_end(arg);
            snprintf(buf, sizeof buf, "Error creating file %s.", name);
            return messageBox(buf, mfError | mfOKButton);
        }

        case edSaveModify:
        {
            va_start(arg, dialog);
            const char *name = va_arg(arg, const char *);
            va_end(arg);
            const char *base = strrchr(name, '/');
            if (base != 0)
                name = base + 1;
            snprintf(buf, sizeof buf, "%s has been modified. Save?", name);
            return messageBox(buf, mfInformation | mfYesNoCancel);
        }

        case edSaveUntitled:
            return messageBox("Save untitled file?", mfInformation | mfYesNoCancel);

        case edSaveAs:
        {
            va_start(arg, dialog);
            char *name = va_arg(arg, char *);
            va_end(arg);
            return execDialog(new TFileDialog("*.*", "Save File As",
                                              "~N~ame", fdOKButton, 101), name);
        }

        case edFind:
        {
            va_start(arg, dialog);
            char *name = va_arg(arg, char *);
            va_end(arg);
            return execDialog(createFindDialog(), name);
        }

        case edSearchFailed:
            return messageBox("Search string not found.", mfError | mfOKButton);

        case edReplace:
        {
            va_start(arg, dialog);
            char *name = va_arg(arg, char *);
            va_end(arg);
            return execDialog(createReplaceDialog(), name);
        }

        case edReplacePrompt:
        {
            // Avoid placing the dialog on the same line as the cursor.
            TRect r(0, 1, 40, 8);
            r.move((TProgram::deskTop->size.x - r.b.x) / 2, 0);
            TPoint t = TProgram::deskTop->makeGlobal(r.b);
            t.y++;
            va_start(arg, dialog);
            TPoint *pt = va_arg(arg, TPoint *);
            if (pt->y <= t.y)
                r.move(0, TProgram::deskTop->size.y - r.b.y - 2);
            va_end(arg);
            return messageBoxRect(r, "Replace this occurrence?",
                                  mfYesNoCancel | mfInformation);
        }
    }
    return cmCancel;
}
