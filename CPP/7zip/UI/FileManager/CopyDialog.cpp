// CopyDialog.cpp

#include "StdAfx.h"

#include "../../../Common/Wildcard.h"

#include "../../../Windows/FileName.h"

#include "../../../Windows/Control/Static.h"

#ifndef Z7_NO_REGISTRY
#include "../Common/ZipRegistry.h"
#endif

#include "BrowseDialog.h"
#include "CopyDialog.h"
#include "LangUtils.h"

using namespace NWindows;

#ifdef Z7_LANG
static const UInt32 kLangIDs[] =
{
  IDX_COPY_OPEN_DEST_FOLDER
};
#endif

bool CCopyDialog::OnInit()
{
  #ifdef Z7_LANG
  LangSetDlgItems(*this, kLangIDs, Z7_ARRAY_SIZE(kLangIDs));
  #endif
  #ifndef Z7_NO_REGISTRY
  _info.Load();
  OpenDestFolder = _info.OpenDestFolder.Val;
  #endif
  _path.Attach(GetItem(IDC_COPY));
  _pathName.Attach(GetItem(IDE_COPY_NAME));
  SetText(Title);

  NControl::CStatic staticContol;
  staticContol.Attach(GetItem(IDT_COPY));
  staticContol.SetText(Static);
  #ifdef UNDER_CE
  // we do it, since WinCE selects Value\something instead of Value !!!!
  _path.AddString(Value);
  #endif
  FOR_VECTOR (i, Strings)
    _path.AddString(Strings[i]);
  UString pathValue = Value;
  bool splitDest = false;
  #ifndef Z7_NO_REGISTRY
  splitDest = SplitDestEnabled && _info.SplitDest.Val;
  #else
  splitDest = SplitDestEnabled;
  #endif
  ShowItem_Bool(IDX_COPY_NAME_ENABLE, SplitDestEnabled);
  if (splitDest)
  {
    CheckButton(IDX_COPY_NAME_ENABLE, true);
    UString pathName;
    SplitPathToParts_Smart(Value, pathValue, pathName);
    if (pathValue.IsEmpty())
      pathValue = pathName;
    else
      _pathName.SetText(pathName);
  }
  UpdatePathNameVisibility();

  _path.SetText(pathValue);
  CheckButton(IDX_COPY_OPEN_DEST_FOLDER, OpenDestFolder);
  SetItemText(IDT_COPY_INFO, Info);
  NormalizeSize(true);
  return CModalDialog::OnInit();
}

bool CCopyDialog::OnSize(WPARAM /* wParam */, int xSize, int ySize)
{
  int mx, my;
  GetMargins(8, mx, my);
  int bx1, bx2, by;
  GetItemSizes(IDCANCEL, bx1, by);
  GetItemSizes(IDOK, bx2, by);
  const int y = ySize - my - by;
  const int x = xSize - mx - bx1;

  InvalidateRect(NULL);

  {
    RECT r;
    GetClientRectOfItem(IDB_COPY_SET_PATH, r);
    const int bx = RECT_SIZE_X(r);
    MoveItem(IDB_COPY_SET_PATH, xSize - mx - bx, r.top, bx, RECT_SIZE_Y(r));
    ChangeSubWindowSizeX(_path, xSize - mx - mx - bx - mx);
  }

  if (SplitDestEnabled)
    ChangeSubWindowSizeX(_pathName, xSize - mx * 2 - 14);

  {
    RECT r;
    GetClientRectOfItem(IDT_COPY_INFO, r);
    NControl::CStatic staticContol;
    staticContol.Attach(GetItem(IDT_COPY_INFO));
    const int yPos = SplitDestEnabled ? r.top : 40;
    const int checkY = y - my - 10;
    staticContol.Move(mx, yPos, xSize - mx * 2, checkY - 2 - yPos);
    MoveItem(IDX_COPY_OPEN_DEST_FOLDER, mx, checkY, xSize - mx * 2, 10);
  }

  MoveItem(IDCANCEL, x, y, bx1, by);
  MoveItem(IDOK, x - mx - bx2, y, bx2, by);

  return false;
}

bool CCopyDialog::OnButtonClicked(unsigned buttonID, HWND buttonHWND)
{
  switch (buttonID)
  {
    case IDB_COPY_SET_PATH:
      OnButtonSetPath();
      return true;
    case IDX_COPY_NAME_ENABLE:
      UpdatePathNameVisibility();
      return true;
  }
  return CModalDialog::OnButtonClicked(buttonID, buttonHWND);
}

void CCopyDialog::UpdatePathNameVisibility()
{
  ShowItem_Bool(IDE_COPY_NAME, SplitDestEnabled && IsButtonCheckedBool(IDX_COPY_NAME_ENABLE));
}

void CCopyDialog::OnButtonSetPath()
{
  UString currentPath;
  _path.GetText(currentPath);

  const UString title = LangString(IDS_SET_FOLDER);

  UString resultPath;
  if (!MyBrowseForFolder(*this, title, currentPath, resultPath))
    return;
  NFile::NName::NormalizeDirPathPrefix(resultPath);
  _path.SetCurSel(-1);
  _path.SetText(resultPath);
}

void CCopyDialog::OnOK()
{
  UString value;
  _path.GetText(value);

  const bool splitDest = SplitDestEnabled && IsButtonCheckedBool(IDX_COPY_NAME_ENABLE);
  if (splitDest)
  {
    value.Trim();
    NFile::NName::NormalizeDirPathPrefix(value);
    UString pathName;
    _pathName.GetText(pathName);
    pathName.Trim();
    value += pathName;
    NFile::NName::NormalizeDirPathPrefix(value);
  }
  Value = value;

  OpenDestFolder = IsButtonCheckedBool(IDX_COPY_OPEN_DEST_FOLDER);
  #ifndef Z7_NO_REGISTRY
  if (OpenDestFolder != _info.OpenDestFolder.Val)
  {
    _info.OpenDestFolder.Def = true;
    _info.OpenDestFolder.Val = OpenDestFolder;
  }
  if (SplitDestEnabled && splitDest != _info.SplitDest.Val)
  {
    _info.SplitDest.Def = true;
    _info.SplitDest.Val = splitDest;
  }
  _info.Save();
  #endif
  CModalDialog::OnOK();
}
