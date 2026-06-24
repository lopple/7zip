// CopyDialog.h

#ifndef ZIP7_INC_COPY_DIALOG_H
#define ZIP7_INC_COPY_DIALOG_H

#include "../../../Windows/Control/ComboBox.h"
#include "../../../Windows/Control/Dialog.h"
#include "../../../Windows/Control/Edit.h"

#include "CopyDialogRes.h"

#ifndef Z7_NO_REGISTRY
#include "../Common/ZipRegistry.h"
#endif

const int kCopyDialog_NumInfoLines = 11;

class CCopyDialog: public NWindows::NControl::CModalDialog
{
  NWindows::NControl::CComboBox _path;
  NWindows::NControl::CEdit _pathName;
  virtual void OnOK() Z7_override;
  virtual bool OnInit() Z7_override;
  virtual bool OnSize(WPARAM wParam, int xSize, int ySize) Z7_override;
  virtual bool OnButtonClicked(unsigned buttonID, HWND buttonHWND) Z7_override;
  void OnButtonSetPath();
  void UpdatePathNameVisibility();
  #ifndef Z7_NO_REGISTRY
  NExtract::CInfo _info;
  #endif
public:
  UString Title;
  UString Static;
  UString Value;
  UString Info;
  UStringVector Strings;
  bool OpenDestFolder;
  bool SplitDestEnabled;

  INT_PTR Create(HWND parentWindow = NULL) { return CModalDialog::Create(IDD_COPY, parentWindow); }
  CCopyDialog(): OpenDestFolder(false), SplitDestEnabled(false) {}
};

#endif
