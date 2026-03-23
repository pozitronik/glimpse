/// Total Commander WLX (Lister) plugin API types and constants.
/// Reference: TC Lister Plugin Interface documentation.
unit uWlxAPI;

interface

uses
  Winapi.Windows;

const
  { ListSendCommand command identifiers }
  lc_Copy       = 1;
  lc_NewParams  = 2;
  lc_SelectAll  = 3;
  lc_SetPercent = 4;

  { ListLoad ShowFlags bitmask }
  lcp_WrapText       = 1;
  lcp_FitToWindow    = 2;
  lcp_Ansi           = 4;
  lcp_Ascii          = 8;
  lcp_Variable       = 12;
  lcp_ForceShow      = 16;
  lcp_FitLargerOnly  = 32;
  lcp_Center         = 64;
  lcp_DarkMode       = 128;
  lcp_DarkModeNative = 256;

  { ListSearchText search parameter flags }
  lcs_FindFirst  = 1;
  lcs_MatchCase  = 2;
  lcs_WholeWords = 4;
  lcs_Backwards  = 8;

  { Special menu item IDs sent via WM_COMMAND }
  itm_Percent   = $FFFE;
  itm_FontStyle = $FFFD;
  itm_Wrap      = $FFFC;
  itm_Fit       = $FFFB;
  itm_Next      = $FFFA;
  itm_Center    = $FFF9;

  { Return codes }
  LISTPLUGIN_OK    = 0;
  LISTPLUGIN_ERROR = 1;

type
  PListDefaultParamStruct = ^TListDefaultParamStruct;
  TListDefaultParamStruct = record
    Size: Integer;
    PluginInterfaceVersionLow: DWORD;
    PluginInterfaceVersionHi: DWORD;
    DefaultIniName: array[0..MAX_PATH - 1] of AnsiChar;
  end;

implementation

end.
