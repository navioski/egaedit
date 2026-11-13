// app.cpp — application object, menus, status line, desktop and the clock.

#include "app.h"

#include <cstdio>
#include <cstring>
#include <ctime>

// Window palette indices: frame passive, frame active, icon, scrollbar page,
// scrollbar controls, scroller normal, scroller selected, reserved.
static const char cpBlueWindowAlt[] = "\x08\x09\x0A\x0B\x0C\x0F\x0E\x0F";

// ---------------------------------------------------------------------------
// A small clock, pinned to the right end of the menu bar (DOS style).
// ---------------------------------------------------------------------------

class TClockView : public TView
{
public:
    TClockView(const TRect &r) noexcept : TView(r)
    {
        lastTime[0] = EOS;
        curTime[0] = EOS;
    }

    virtual void draw()
    {
        TDrawBuffer b;
        TColorAttr c = TColorAttr(0x70); // black on light gray, like the menu bar

        b.moveChar(0, ' ', c, size.x);
        b.moveStr(size.x - 8, curTime, c, 8);
        writeLine(0, 0, size.x, 1, b);
    }

    void update()
    {
        time_t t = time(0);
        struct tm *tm = localtime(&t);
        char buf[9];

        strftime(buf, sizeof buf, "%H:%M:%S", tm);
        if (strcmp(lastTime, buf) != 0)
        {
            strcpy(curTime, buf);
            drawView();
            strcpy(lastTime, buf);
        }
    }

private:
    char lastTime[9];
    char curTime[9];
};

// ---------------------------------------------------------------------------
// An edit window whose title is the file name, not the whole path.
// ---------------------------------------------------------------------------

class TEditorWindow : public TEditWindow
{
public:
    TEditorWindow(const TRect &r, TStringView fileName, int number) noexcept :
        TWindowInit(&TEditWindow::initFrame),
        TEditWindow(r, fileName, number)
    {
    }

    // Same blue window scheme as stock Turbo Vision, except the editor text is
    // white (15) instead of yellow (14). Entry 7 stays the selection colour.
    virtual TPalette &getPalette() const
    {
        static TPalette palette(cpBlueWindowAlt, sizeof(cpBlueWindowAlt) - 1);
        return palette;
    }

    virtual const char *getTitle(short maxSize)
    {
        const char *full = TEditWindow::getTitle(maxSize);
        if (full == 0)
            return 0;
        const char *slash = strrchr(full, '/');
        return slash != 0 ? slash + 1 : full;
    }
};

// ---------------------------------------------------------------------------
// The desktop: a 25% dither of light gray on EGA blue.
// ---------------------------------------------------------------------------

class TStyleBackground : public TBackground
{
public:
    TStyleBackground(const TRect &r) noexcept : TBackground(r, '\xB0') {}

    virtual void draw()
    {
        TDrawBuffer b;
        TColorAttr c = TColorAttr(0x17); // light gray dots on blue

        b.moveChar(0, '\xB0', c, size.x);
        writeLine(0, 0, size.x, size.y, b);
    }
};

class TStyleDeskTop : public TDeskTop
{
public:
    TStyleDeskTop(const TRect &r) noexcept :
        TDeskInit(&TStyleDeskTop::initBackground),
        TDeskTop(r)
    {
    }

    static TBackground *initBackground(TRect r)
    {
        return new TStyleBackground(r);
    }
};

// ---------------------------------------------------------------------------
// Application
// ---------------------------------------------------------------------------

TEditorApp::TEditorApp(int argc, char **argv) :
    TProgInit(&TEditorApp::initStatusLine,
              &TEditorApp::initMenuBar,
              &TEditorApp::initDeskTop),
    clock(0),
    windowCount(0)
{
    TCommandSet ts;
    ts.enableCmd(cmSave);
    ts.enableCmd(cmSaveAs);
    ts.enableCmd(cmCut);
    ts.enableCmd(cmCopy);
    ts.enableCmd(cmPaste);
    ts.enableCmd(cmClear);
    ts.enableCmd(cmUndo);
    ts.enableCmd(cmFind);
    ts.enableCmd(cmReplace);
    ts.enableCmd(cmSearchAgain);
    disableCommands(ts);

    enableCommand(cmQuitApp);
    enableCommand(cmSelectAll);
    enableCommand(cmInsMode);
    enableCommand(cmIndentMode);

    TEditor::editorDialog = doEditDialog;

    // Clock in the top-right corner, over the empty end of the menu bar.
    TRect r = getExtent();
    r.a.x = r.b.x - 10;
    r.b.y = r.a.y + 1;
    clock = new TClockView(r);
    clock->growMode = gfGrowLoX | gfGrowHiX;
    insert(clock);

    int opened = 0;
    for (int i = 1; i < argc; i++)
    {
        if (argv[i][0] != '-')
        {
            openEditor(argv[i], True);
            opened++;
        }
    }

    if (opened == 0)
    {
        FILE *f = fopen("WELCOME.TXT", "r");
        if (f != 0)
        {
            fclose(f);
            openEditor("WELCOME.TXT", True);
        }
        else
            openEditor(0, True);
    }

}

TEditorApp::~TEditorApp()
{
}

TEditWindow *TEditorApp::openEditor(const char *fileName, Boolean visible)
{
    TRect r = deskTop->getExtent();
    int step = windowCount < 3 ? windowCount : 0;
    windowCount++;

    r.a.x += 2 + 2 * step;
    r.a.y += 1 + step;
    r.b.x -= 2;
    r.b.y -= 1;

    if (r.b.x - r.a.x < 24 || r.b.y - r.a.y < 6)
        r = deskTop->getExtent().grow(-2, -1);

    TEditWindow *p = (TEditWindow *)validView(new TEditorWindow(r, fileName, wnNoNumber));

    if (p != 0)
    {
        if (!visible)
            p->hide();
        deskTop->insert(p);
    }
    return p;
}

void TEditorApp::fileOpen()
{
    char fileName[512];
    strcpy(fileName, "*.*");

    if (execDialog(new TFileDialog("*.*", "Open File", "~N~ame",
                                   fdOpenButton, 100), fileName) != cmCancel)
        openEditor(fileName, True);
}

void TEditorApp::fileNew()
{
    openEditor(0, True);
}

void TEditorApp::changeDir()
{
    execDialog(new TChDirDialog(cdNormal, 0), 0);
}

void TEditorApp::showAbout()
{
    execDialog(createAboutDialog(), 0);
}

void TEditorApp::showKeys()
{
    execDialog(createKeysDialog(), 0);
}

void TEditorApp::showColors()
{
    execDialog(createColorsDialog(), 0);
}

void TEditorApp::handleEvent(TEvent &event)
{
    TApplication::handleEvent(event);

    if (event.what != evCommand)
        return;

    switch (event.message.command)
    {
        case cmQuitApp:
            if (deskTop->valid(cmClose))
                endModal(cmQuit);
            break;
        case cmOpen:       fileOpen();  break;
        case cmNew:        fileNew();   break;
        case cmChangeDir: changeDir(); break;
        case cmAbout:      showAbout(); break;
        case cmKeys:       showKeys();  break;
        case cmShowColors: showColors();break;
        default:
            return;
    }
    clearEvent(event);
}

void TEditorApp::idle()
{
    TApplication::idle();
    if (clock != 0)
        clock->update();
}

// ---------------------------------------------------------------------------
// Menus
// ---------------------------------------------------------------------------

TMenuBar *TEditorApp::initMenuBar(TRect r)
{
    TSubMenu &file =
        *new TSubMenu("~F~ile", kbAltF) +
            *new TMenuItem("~N~ew", cmNew, kbCtrlN, hcNoContext, "Ctrl-N") +
            *new TMenuItem("~O~pen...", cmOpen, kbF3, hcNoContext, "F3") +
            *new TMenuItem("~S~ave", cmSave, kbF2, hcNoContext, "F2") +
            *new TMenuItem("Save ~a~s...", cmSaveAs, kbNoKey) +
            newLine() +
            *new TMenuItem("Change ~d~ir...", cmChangeDir, kbNoKey) +
            newLine() +
            *new TMenuItem("E~x~it", cmQuitApp, kbAltX, hcNoContext, "Alt-X");

    TSubMenu &edit =
        *new TSubMenu("~E~dit", kbAltE) +
            *new TMenuItem("~U~ndo", cmUndo, kbCtrlZ, hcNoContext, "Ctrl-Z") +
            newLine() +
            *new TMenuItem("Cu~t~", cmCut, kbCtrlX, hcNoContext, "Ctrl-X") +
            *new TMenuItem("~C~opy", cmCopy, kbCtrlC, hcNoContext, "Ctrl-C") +
            *new TMenuItem("~P~aste", cmPaste, kbCtrlV, hcNoContext, "Ctrl-V") +
            *new TMenuItem("~D~elete", cmClear, kbCtrlDel, hcNoContext, "Ctrl-Del") +
            newLine() +
            *new TMenuItem("Select ~A~ll", cmSelectAll, kbCtrlA, hcNoContext, "Ctrl-A");

    TSubMenu &search =
        *new TSubMenu("~S~earch", kbAltS) +
            *new TMenuItem("~F~ind...", cmFind, kbCtrlF, hcNoContext, "Ctrl-F") +
            *new TMenuItem("~R~eplace...", cmReplace, kbCtrlH, hcNoContext, "Ctrl-H") +
            *new TMenuItem("Search ~a~gain", cmSearchAgain, kbCtrlL, hcNoContext, "Ctrl-L");

    TSubMenu &options =
        *new TSubMenu("~O~ptions", kbAltO) +
            *new TMenuItem("~I~nsert mode", cmInsMode, kbNoKey) +
            *new TMenuItem("~A~uto indent", cmIndentMode, kbNoKey) +
            newLine() +
            *new TMenuItem("~E~GA palette...", cmShowColors, kbNoKey);

    TSubMenu &window =
        *new TSubMenu("~W~indow", kbAltW) +
            *new TMenuItem("Casc~a~de", cmCascade, kbNoKey) +
            *new TMenuItem("~T~ile", cmTile, kbNoKey) +
            *new TMenuItem("~N~ext", cmNext, kbF6, hcNoContext, "F6") +
            *new TMenuItem("~P~revious", cmPrev, kbShiftF6, hcNoContext, "Shift-F6") +
            *new TMenuItem("~Z~oom", cmZoom, kbF5, hcNoContext, "F5") +
            newLine() +
            *new TMenuItem("Close ~a~ll", cmCloseAll, kbNoKey) +
            *new TMenuItem("~C~lose", cmClose, kbCtrlW, hcNoContext, "Ctrl-W");

    TSubMenu &help =
        *new TSubMenu("~H~elp", kbAltH) +
            *new TMenuItem("~K~eyboard...", cmKeys, kbF1, hcNoContext, "F1") +
            *new TMenuItem("~A~bout...", cmAbout, kbNoKey);

    r.b.y = r.a.y + 1;
    return new TMenuBar(r, file + edit + search + options + window + help);
}

TStatusLine *TEditorApp::initStatusLine(TRect r)
{
    r.a.y = r.b.y - 1;
    return new TStatusLine(r,
        *new TStatusDef(0, 0xFFFF) +
            *new TStatusItem("~F1~ Help", kbF1, cmKeys) +
            *new TStatusItem("~F2~ Save", kbF2, cmSave) +
            *new TStatusItem("~F3~ Open", kbF3, cmOpen) +
            *new TStatusItem("~F4~ New", kbF4, cmNew) +
            *new TStatusItem("~F5~ Zoom", kbF5, cmZoom) +
            *new TStatusItem("~F6~ Next", kbF6, cmNext) +
            *new TStatusItem("~F10~ Menu", kbF10, cmMenu) +
            *new TStatusItem("~Alt-X~ Exit", kbAltX, cmQuitApp) +
            *new TStatusItem(0, kbCtrlQ, cmQuitApp) +
            *new TStatusItem(0, kbCtrlS, cmSave) +
            *new TStatusItem(0, kbCtrlO, cmOpen) +
            *new TStatusItem(0, kbCtrlN, cmNew) +
            *new TStatusItem(0, kbCtrlZ, cmUndo) +
            *new TStatusItem(0, kbCtrlX, cmCut) +
            *new TStatusItem(0, kbCtrlC, cmCopy) +
            *new TStatusItem(0, kbCtrlV, cmPaste) +
            *new TStatusItem(0, kbCtrlA, cmSelectAll) +
            *new TStatusItem(0, kbCtrlF, cmFind) +
            *new TStatusItem(0, kbCtrlH, cmReplace) +
            *new TStatusItem(0, kbCtrlL, cmSearchAgain) +
            *new TStatusItem(0, kbCtrlW, cmClose));
}

TDeskTop *TEditorApp::initDeskTop(TRect r)
{
    r.a.y++;
    r.b.y--;
    return new TStyleDeskTop(r);
}
