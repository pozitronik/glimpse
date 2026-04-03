object SettingsForm: TSettingsForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'VideoThumb Settings'
  ClientHeight = 628
  ClientWidth = 460
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  TextHeight = 15
  object GbxGeneral: TGroupBox
    Left = 8
    Top = 8
    Width = 444
    Height = 155
    Caption = ' General '
    TabOrder = 0
    object LblSkipEdges: TLabel
      Left = 12
      Top = 24
      Width = 62
      Height = 15
      Caption = 'Skip edges:'
    end
    object LblSkipEdgesUnit: TLabel
      Left = 198
      Top = 24
      Width = 11
      Height = 15
      Caption = '%'
    end
    object LblMaxWorkers: TLabel
      Left = 12
      Top = 53
      Width = 74
      Height = 15
      Caption = 'Max workers:'
    end
    object ChkMaxWorkersAuto: TCheckBox
      Left = 198
      Top = 53
      Width = 130
      Height = 17
      Caption = 'One per frame'
      TabOrder = 7
      OnClick = ChkMaxWorkersAutoClick
    end
    object LblExtensions: TLabel
      Left = 12
      Top = 82
      Width = 63
      Height = 15
      Caption = 'Extensions:'
    end
    object LblFFmpegPath: TLabel
      Left = 12
      Top = 111
      Width = 76
      Height = 15
      Caption = 'FFmpeg path:'
    end
    object LblFFmpegInfo: TLabel
      Left = 12
      Top = 132
      Width = 3
      Height = 15
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object EdtSkipEdges: TEdit
      Left = 130
      Top = 20
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 0
    end
    object UdSkipEdges: TUpDown
      Left = 175
      Top = 20
      Width = 17
      Height = 23
      Associate = EdtSkipEdges
      Max = 49
      Thousands = False
      TabOrder = 1
    end
    object EdtMaxWorkers: TEdit
      Left = 130
      Top = 49
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 2
    end
    object UdMaxWorkers: TUpDown
      Left = 175
      Top = 49
      Width = 17
      Height = 23
      Associate = EdtMaxWorkers
      Min = 1
      Max = 16
      Thousands = False
      TabOrder = 3
    end
    object EdtExtensions: TEdit
      Left = 130
      Top = 78
      Width = 306
      Height = 23
      TabOrder = 4
    end
    object EdtFFmpegPath: TEdit
      Left = 130
      Top = 107
      Width = 274
      Height = 23
      TabOrder = 5
      TextHint = 'Auto-detect'
      OnChange = EdtFFmpegPathChange
    end
    object BtnFFmpegPath: TButton
      Left = 408
      Top = 107
      Width = 28
      Height = 23
      Caption = '...'
      TabOrder = 6
      OnClick = BtnFFmpegPathClick
    end
  end
  object GbxAppearance: TGroupBox
    Left = 8
    Top = 169
    Width = 444
    Height = 138
    Caption = ' Appearance '
    TabOrder = 1
    object LblBackground: TLabel
      Left = 12
      Top = 24
      Width = 71
      Height = 15
      Caption = 'Background:'
    end
    object LblTCBack: TLabel
      Left = 12
      Top = 53
      Width = 78
      Height = 15
      Caption = 'Timecode bg:'
    end
    object LblTCAlpha: TLabel
      Left = 12
      Top = 82
      Width = 65
      Height = 15
      Caption = 'Timecode opacity:'
    end
    object LblTCAlphaHint: TLabel
      Left = 198
      Top = 82
      Width = 196
      Height = 15
      Caption = '(0 = transparent, 255 = opaque)'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object PnlBackground: TPanel
      Left = 130
      Top = 20
      Width = 80
      Height = 23
      BevelOuter = bvLowered
      Caption = ''
      Cursor = crHandPoint
      ParentBackground = False
      TabOrder = 0
      OnClick = PnlBackgroundClick
    end
    object BtnBackground: TButton
      Left = 214
      Top = 20
      Width = 25
      Height = 23
      Caption = '...'
      TabOrder = 1
      OnClick = PnlBackgroundClick
    end
    object PnlTCBack: TPanel
      Left = 130
      Top = 49
      Width = 80
      Height = 23
      BevelOuter = bvLowered
      Caption = ''
      Cursor = crHandPoint
      ParentBackground = False
      TabOrder = 2
      OnClick = PnlTCBackClick
    end
    object BtnTCBack: TButton
      Left = 214
      Top = 49
      Width = 25
      Height = 23
      Caption = '...'
      TabOrder = 3
      OnClick = PnlTCBackClick
    end
    object EdtTCAlpha: TEdit
      Left = 130
      Top = 78
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 4
    end
    object UdTCAlpha: TUpDown
      Left = 175
      Top = 78
      Width = 17
      Height = 23
      Associate = EdtTCAlpha
      Max = 255
      Thousands = False
      TabOrder = 5
    end
    object ChkShowToolbar: TCheckBox
      Left = 12
      Top = 111
      Width = 200
      Height = 17
      Caption = 'Show toolbar (F4 to toggle)'
      TabOrder = 6
    end
  end
  object GbxSave: TGroupBox
    Left = 8
    Top = 313
    Width = 444
    Height = 138
    Caption = ' Save '
    TabOrder = 2
    object LblSaveFormat: TLabel
      Left = 12
      Top = 24
      Width = 44
      Height = 15
      Caption = 'Format:'
    end
    object LblJpegQuality: TLabel
      Left = 12
      Top = 53
      Width = 76
      Height = 15
      Caption = 'JPEG quality:'
    end
    object LblPngCompression: TLabel
      Left = 12
      Top = 82
      Width = 104
      Height = 15
      Caption = 'PNG compression:'
    end
    object LblSaveFolder: TLabel
      Left = 12
      Top = 111
      Width = 82
      Height = 15
      Caption = 'Default folder:'
    end
    object CbxSaveFormat: TComboBox
      Left = 130
      Top = 20
      Width = 80
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      OnChange = CbxSaveFormatChange
      Items.Strings = (
        'PNG'
        'JPEG')
    end
    object EdtJpegQuality: TEdit
      Left = 130
      Top = 49
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 1
    end
    object UdJpegQuality: TUpDown
      Left = 175
      Top = 49
      Width = 17
      Height = 23
      Associate = EdtJpegQuality
      Min = 1
      Max = 100
      Thousands = False
      TabOrder = 2
    end
    object EdtPngCompression: TEdit
      Left = 130
      Top = 78
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 3
    end
    object UdPngCompression: TUpDown
      Left = 175
      Top = 78
      Width = 17
      Height = 23
      Associate = EdtPngCompression
      Max = 9
      Thousands = False
      TabOrder = 4
    end
    object EdtSaveFolder: TEdit
      Left = 130
      Top = 107
      Width = 274
      Height = 23
      TabOrder = 5
      TextHint = 'Leave empty for no default'
    end
    object BtnSaveFolder: TButton
      Left = 408
      Top = 107
      Width = 28
      Height = 23
      Caption = '...'
      TabOrder = 6
      OnClick = BtnSaveFolderClick
    end
  end
  object GbxCache: TGroupBox
    Left = 8
    Top = 457
    Width = 444
    Height = 123
    Caption = ' Cache '
    TabOrder = 3
    object LblCacheFolder: TLabel
      Left = 12
      Top = 53
      Width = 38
      Height = 15
      Caption = 'Folder:'
    end
    object LblCacheFolderInfo: TLabel
      Left = 12
      Top = 73
      Width = 3
      Height = 15
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object LblCacheMaxSize: TLabel
      Left = 12
      Top = 96
      Width = 52
      Height = 15
      Caption = 'Max size:'
    end
    object LblCacheMaxSizeUnit: TLabel
      Left = 218
      Top = 96
      Width = 18
      Height = 15
      Caption = 'MB'
    end
    object LblCacheSizeInfo: TLabel
      Left = 244
      Top = 96
      Width = 3
      Height = 15
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object ChkCacheEnabled: TCheckBox
      Left = 12
      Top = 22
      Width = 140
      Height = 17
      Caption = 'Enable disk cache'
      TabOrder = 0
      OnClick = ChkCacheEnabledClick
    end
    object BtnClearCache: TButton
      Left = 348
      Top = 18
      Width = 88
      Height = 25
      Caption = 'Clear Cache'
      TabOrder = 5
      OnClick = BtnClearCacheClick
    end
    object EdtCacheFolder: TEdit
      Left = 130
      Top = 49
      Width = 274
      Height = 23
      TabOrder = 1
      TextHint = 'Leave empty for default'
      OnChange = EdtCacheFolderChange
    end
    object BtnCacheFolder: TButton
      Left = 408
      Top = 49
      Width = 28
      Height = 23
      Caption = '...'
      TabOrder = 2
      OnClick = BtnCacheFolderClick
    end
    object EdtCacheMaxSize: TEdit
      Left = 130
      Top = 92
      Width = 65
      Height = 23
      NumbersOnly = True
      TabOrder = 3
    end
    object UdCacheMaxSize: TUpDown
      Left = 195
      Top = 92
      Width = 17
      Height = 23
      Associate = EdtCacheMaxSize
      Min = 10
      Max = 10000
      Thousands = False
      TabOrder = 4
    end
  end
  object BtnDefaults: TButton
    Left = 8
    Top = 592
    Width = 100
    Height = 28
    Caption = 'Reset Defaults'
    TabOrder = 4
    OnClick = BtnDefaultsClick
  end
  object BtnOK: TButton
    Left = 296
    Top = 592
    Width = 75
    Height = 28
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 5
  end
  object BtnCancel: TButton
    Left = 377
    Top = 592
    Width = 75
    Height = 28
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 6
  end
  object ColorDlg: TColorDialog
    Options = [cdFullOpen]
    Left = 408
    Top = 8
  end
end
