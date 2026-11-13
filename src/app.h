// app.h — the editor application and its dialogs.

#if !defined(EDITOR_APP_H)
#define EDITOR_APP_H

#include "tvcommon.h"

// Commands that are ours (Turbo Vision commands live below 1000).
const int
    cmAbout      = 1100,
    cmKeys       = 1101,
    cmShowColors = 1102,
    cmQuitApp    = 1103;

class TClockView;

class TEditorApp : public TApplication
{
public:
    TEditorApp(int argc, char **argv);
    virtual ~TEditorApp();

    static TMenuBar *initMenuBar(TRect r);
    static TStatusLine *initStatusLine(TRect r);
    static TDeskTop *initDeskTop(TRect r);

    virtual void handleEvent(TEvent &event);
    virtual void idle();

private:
    TEditWindow *openEditor(const char *fileName, Boolean visible);
    void fileOpen();
    void fileNew();
    void changeDir();
    void showAbout();
    void showKeys();
    void showColors();

    TClockView *clock;
    int windowCount;
};

// A 16-cell strip of solid EGA colours, used in the About and Palette dialogs.
class TColorStrip : public TView
{
public:
    TColorStrip(const TRect &bounds) noexcept : TView(bounds) {}
    virtual void draw();
};

// The 16-colour EGA table, drawn as swatch / index / name / hex.
class TColorTable : public TView
{
public:
    TColorTable(const TRect &bounds) noexcept : TView(bounds) {}
    virtual void draw();
};

TDialog *createAboutDialog();
TDialog *createKeysDialog();
TDialog *createColorsDialog();

ushort execDialog(TDialog *d, void *data);
TDialog *createFindDialog();
TDialog *createReplaceDialog();
ushort doEditDialog(int dialog, ...);

#endif // EDITOR_APP_H
