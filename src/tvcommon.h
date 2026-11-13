// tvcommon.h — one place to pull in the Turbo Vision classes we use.
//
// The library still follows Borland's "Uses_XXX" convention: tv.h only
// includes the headers for the classes whose Uses_ macro is defined.

#if !defined(TVCOMMON_H)
#define TVCOMMON_H

#define Uses_TApplication
#define Uses_TBackground
#define Uses_TButton
#define Uses_TChDirDialog
#define Uses_TCheckBoxes
#define Uses_TClipboard
#define Uses_TCommandSet
#define Uses_TDeskTop
#define Uses_TDialog
#define Uses_TDrawBuffer
#define Uses_TEditWindow
#define Uses_TEditor
#define Uses_TEvent
#define Uses_TFileDialog
#define Uses_TFileEditor
#define Uses_TFrame
#define Uses_TGroup
#define Uses_THistory
#define Uses_TIndicator
#define Uses_TInputLine
#define Uses_TKeys
#define Uses_TLabel
#define Uses_TMenu
#define Uses_TMenuBar
#define Uses_TMenuItem
#define Uses_MsgBox
#define Uses_TObject
#define Uses_TPalette
#define Uses_TPoint
#define Uses_TProgram
#define Uses_TRect
#define Uses_TScrollBar
#define Uses_TSItem
#define Uses_TStaticText
#define Uses_TStatusDef
#define Uses_TStatusItem
#define Uses_TStatusLine
#define Uses_TSubMenu
#define Uses_TView
#define Uses_TWindow
#define Uses_TColorAttr

#include <tvision/tv.h>

#endif // TVCOMMON_H
