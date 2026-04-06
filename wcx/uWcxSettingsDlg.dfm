object WcxSettingsForm: TWcxSettingsForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Glimpse WCX Settings'
  ClientHeight = 676
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
    Height = 242
    Caption = ' General '
    TabOrder = 0
    object LblFrameCount: TLabel
      Left = 12
      Top = 24
      Width = 75
      Height = 15
      Caption = 'Frame count:'
    end
    object LblSkipEdges: TLabel
      Left = 12
      Top = 53
      Width = 62
      Height = 15
      Caption = 'Skip edges:'
    end
    object LblSkipEdgesUnit: TLabel
      Left = 198
      Top = 53
      Width = 11
      Height = 15
      Caption = '%'
    end
    object LblMaxWorkers: TLabel
      Left = 12
      Top = 82
      Width = 74
      Height = 15
      Caption = 'Max workers:'
    end
    object LblMaxThreads: TLabel
      Left = 12
      Top = 111
      Width = 112
      Height = 15
      Caption = 'Limit workers count:'
    end
    object LblMaxThreadsAuto: TLabel
      Left = 198
      Top = 111
      Width = 3
      Height = 15
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object LblFFmpegPath: TLabel
      Left = 12
      Top = 198
      Width = 76
      Height = 15
      Caption = 'FFmpeg path:'
    end
    object LblFFmpegInfo: TLabel
      Left = 12
      Top = 221
      Width = 3
      Height = 15
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clGray
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object EdtFrameCount: TEdit
      Left = 130
      Top = 20
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 0
    end
    object UdFrameCount: TUpDown
      Left = 175
      Top = 20
      Width = 17
      Height = 23
      Associate = EdtFrameCount
      Min = 1
      Max = 99
      Thousands = False
      TabOrder = 1
    end
    object EdtSkipEdges: TEdit
      Left = 130
      Top = 49
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 2
    end
    object UdSkipEdges: TUpDown
      Left = 175
      Top = 49
      Width = 17
      Height = 23
      Associate = EdtSkipEdges
      Max = 49
      Thousands = False
      TabOrder = 3
    end
    object EdtMaxWorkers: TEdit
      Left = 130
      Top = 78
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 4
    end
    object UdMaxWorkers: TUpDown
      Left = 175
      Top = 78
      Width = 17
      Height = 23
      Associate = EdtMaxWorkers
      Min = 1
      Max = 16
      Thousands = False
      TabOrder = 5
    end
    object ChkMaxWorkersAuto: TCheckBox
      Left = 198
      Top = 82
      Width = 130
      Height = 17
      Caption = 'One per frame'
      TabOrder = 6
      OnClick = ChkMaxWorkersAutoClick
    end
    object EdtMaxThreads: TEdit
      Left = 130
      Top = 107
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 7
      OnChange = EdtMaxThreadsChange
    end
    object UdMaxThreads: TUpDown
      Left = 175
      Top = 107
      Width = 17
      Height = 23
      Associate = EdtMaxThreads
      Min = -1
      Max = 64
      Thousands = False
      TabOrder = 8
    end
    object ChkUseBmpPipe: TCheckBox
      Left = 12
      Top = 140
      Width = 424
      Height = 17
      Caption = 'Use BMP pipe (faster extraction, higher memory usage)'
      TabOrder = 9
    end
    object EdtFFmpegPath: TEdit
      Left = 130
      Top = 194
      Width = 274
      Height = 23
      TabOrder = 11
      TextHint = 'Auto-detect'
      OnChange = EdtFFmpegPathChange
    end
    object BtnFFmpegPath: TButton
      Left = 408
      Top = 194
      Width = 28
      Height = 23
      Caption = '...'
      TabOrder = 12
      OnClick = BtnFFmpegPathClick
    end
  end
  object GbxOutput: TGroupBox
    Left = 8
    Top = 258
    Width = 444
    Height = 168
    Caption = ' Output '
    TabOrder = 1
    object LblOutputMode: TLabel
      Left = 12
      Top = 24
      Width = 78
      Height = 15
      Caption = 'Output mode:'
    end
    object LblFormat: TLabel
      Left = 12
      Top = 53
      Width = 78
      Height = 15
      Caption = 'Image format:'
    end
    object LblJpegQuality: TLabel
      Left = 12
      Top = 82
      Width = 76
      Height = 15
      Caption = 'JPEG quality:'
    end
    object LblPngCompression: TLabel
      Left = 12
      Top = 111
      Width = 104
      Height = 15
      Caption = 'PNG compression:'
    end
    object CbxOutputMode: TComboBox
      Left = 130
      Top = 20
      Width = 150
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      OnChange = CbxOutputModeChange
      Items.Strings = (
        'Separate frames'
        'Combined image')
    end
    object CbxFormat: TComboBox
      Left = 130
      Top = 49
      Width = 80
      Height = 23
      Style = csDropDownList
      TabOrder = 1
      Items.Strings = (
        'PNG'
        'JPEG')
    end
    object EdtJpegQuality: TEdit
      Left = 130
      Top = 78
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 2
    end
    object UdJpegQuality: TUpDown
      Left = 175
      Top = 78
      Width = 17
      Height = 23
      Associate = EdtJpegQuality
      Min = 1
      Max = 100
      Thousands = False
      TabOrder = 3
    end
    object EdtPngCompression: TEdit
      Left = 130
      Top = 107
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 4
    end
    object UdPngCompression: TUpDown
      Left = 175
      Top = 107
      Width = 17
      Height = 23
      Associate = EdtPngCompression
      Max = 9
      Thousands = False
      TabOrder = 5
    end
    object ChkShowFileSizes: TCheckBox
      Left = 12
      Top = 140
      Width = 424
      Height = 17
      Caption = 'Show file sizes (extracts all frames when entering archive)'
      TabOrder = 6
    end
  end
  object GbxCombined: TGroupBox
    Left = 8
    Top = 434
    Width = 444
    Height = 190
    Caption = ' Combined image '
    TabOrder = 2
    object LblColumns: TLabel
      Left = 12
      Top = 24
      Width = 100
      Height = 15
      Caption = 'Columns (0=auto):'
    end
    object LblCellGap: TLabel
      Left = 12
      Top = 53
      Width = 72
      Height = 15
      Caption = 'Cell gap (px):'
    end
    object LblBackground: TLabel
      Left = 12
      Top = 82
      Width = 71
      Height = 15
      Caption = 'Background:'
    end
    object EdtColumns: TEdit
      Left = 130
      Top = 20
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 0
    end
    object UdColumns: TUpDown
      Left = 175
      Top = 20
      Width = 17
      Height = 23
      Associate = EdtColumns
      Max = 20
      Thousands = False
      TabOrder = 1
    end
    object EdtCellGap: TEdit
      Left = 130
      Top = 49
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 2
    end
    object UdCellGap: TUpDown
      Left = 175
      Top = 49
      Width = 17
      Height = 23
      Associate = EdtCellGap
      Max = 20
      Thousands = False
      TabOrder = 3
    end
    object PnlBackground: TPanel
      Left = 130
      Top = 78
      Width = 80
      Height = 23
      BevelOuter = bvLowered
      Caption = ''
      Cursor = crHandPoint
      ParentBackground = False
      TabOrder = 4
      OnClick = PnlBackgroundClick
    end
    object BtnBackground: TButton
      Left = 214
      Top = 78
      Width = 25
      Height = 23
      Caption = '...'
      TabOrder = 5
      OnClick = PnlBackgroundClick
    end
    object ChkTimestamp: TCheckBox
      Left = 12
      Top = 111
      Width = 200
      Height = 17
      Caption = 'Show timestamps on frames'
      TabOrder = 6
    end
    object LblTimestampFont: TLabel
      Left = 12
      Top = 140
      Width = 90
      Height = 15
      Caption = 'Timestamp font:'
    end
    object EdtTimestampFont: TEdit
      Left = 130
      Top = 136
      Width = 180
      Height = 23
      TabOrder = 7
    end
    object LblTimestampFontSize: TLabel
      Left = 320
      Top = 140
      Width = 25
      Height = 15
      Caption = 'Size:'
    end
    object EdtTimestampFontSize: TEdit
      Left = 350
      Top = 136
      Width = 45
      Height = 23
      NumbersOnly = True
      TabOrder = 8
    end
    object UdTimestampFontSize: TUpDown
      Left = 395
      Top = 136
      Width = 17
      Height = 23
      Associate = EdtTimestampFontSize
      Min = 6
      Max = 72
      Thousands = False
      TabOrder = 9
    end
    object ChkShowBanner: TCheckBox
      Left = 12
      Top = 165
      Width = 424
      Height = 17
      Caption = 'Include file info banner'
      TabOrder = 10
    end
  end
  object BtnDefaults: TButton
    Left = 8
    Top = 636
    Width = 100
    Height = 28
    Caption = 'Reset Defaults'
    TabOrder = 3
    OnClick = BtnDefaultsClick
  end
  object BtnOK: TButton
    Left = 296
    Top = 636
    Width = 75
    Height = 28
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 4
  end
  object BtnCancel: TButton
    Left = 377
    Top = 636
    Width = 75
    Height = 28
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 5
  end
  object ColorDlg: TColorDialog
    Options = [cdFullOpen]
    Left = 408
    Top = 636
  end
end
