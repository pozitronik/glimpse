object WcxSettingsForm: TWcxSettingsForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Glimpse WCX Settings'
  ClientHeight = 410
  ClientWidth = 460
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  TextHeight = 15
  object PageControl: TPageControl
    Left = 0
    Top = 0
    Width = 460
    Height = 370
    ActivePage = TshGeneral
    Align = alClient
    TabOrder = 0
    object TshGeneral: TTabSheet
      Caption = 'General'
      object LblFrameCount: TLabel
        Left = 12
        Top = 24
        Width = 70
        Height = 15
        Caption = 'Frame count:'
      end
      object LblSkipEdges: TLabel
        Left = 12
        Top = 53
        Width = 59
        Height = 15
        Caption = 'Skip edges:'
      end
      object LblSkipEdgesUnit: TLabel
        Left = 198
        Top = 53
        Width = 10
        Height = 15
        Caption = '%'
      end
      object LblMaxWorkers: TLabel
        Left = 12
        Top = 82
        Width = 69
        Height = 15
        Caption = 'Max workers:'
      end
      object LblMaxThreads: TLabel
        Left = 12
        Top = 111
        Width = 108
        Height = 15
        Caption = 'Limit workers count:'
      end
      object LblMaxThreadsAuto: TLabel
        Left = 198
        Top = 111
        Width = 3
        Height = 15
        Font.Color = clGray
        ParentFont = False
      end
      object LblFFmpegPath: TLabel
        Left = 12
        Top = 231
        Width = 73
        Height = 15
        Caption = 'FFmpeg path:'
      end
      object LblFFmpegInfo: TLabel
        Left = 12
        Top = 254
        Width = 3
        Height = 15
        Font.Color = clGray
        ParentFont = False
      end
      object EdtFrameCount: TEdit
        Left = 130
        Top = 20
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 0
        Text = '1'
      end
      object UdFrameCount: TUpDown
        Left = 175
        Top = 20
        Width = 17
        Height = 23
        Associate = EdtFrameCount
        Min = 1
        Max = 99
        Position = 1
        TabOrder = 1
        Thousands = False
      end
      object EdtSkipEdges: TEdit
        Left = 130
        Top = 49
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 2
        Text = '0'
      end
      object UdSkipEdges: TUpDown
        Left = 175
        Top = 49
        Width = 17
        Height = 23
        Associate = EdtSkipEdges
        Max = 49
        TabOrder = 3
        Thousands = False
      end
      object EdtMaxWorkers: TEdit
        Left = 130
        Top = 78
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 4
        Text = '1'
      end
      object UdMaxWorkers: TUpDown
        Left = 175
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtMaxWorkers
        Min = 1
        Max = 16
        Position = 1
        TabOrder = 5
        Thousands = False
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
        Text = '0'
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
        TabOrder = 8
        Thousands = False
      end
      object ChkUseBmpPipe: TCheckBox
        Left = 12
        Top = 140
        Width = 424
        Height = 17
        Caption = 'Use BMP pipe (faster extraction, higher memory usage)'
        TabOrder = 9
      end
      object ChkHwAccel: TCheckBox
        Left = 12
        Top = 169
        Width = 424
        Height = 17
        Caption = 'Use hardware-accelerated decoding (GPU)'
        TabOrder = 10
      end
      object ChkUseKeyframes: TCheckBox
        Left = 12
        Top = 198
        Width = 424
        Height = 17
        Caption = 'Use keyframes (faster seeking, less precise timecodes)'
        TabOrder = 11
      end
      object EdtFFmpegPath: TEdit
        Left = 130
        Top = 227
        Width = 288
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 12
        TextHint = 'Auto-detect'
        OnChange = EdtFFmpegPathChange
      end
      object BtnFFmpegPath: TButton
        Left = 424
        Top = 227
        Width = 28
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 13
        OnClick = BtnFFmpegPathClick
      end
    end
    object TshOutput: TTabSheet
      Caption = 'Output'
      ImageIndex = 1
      object LblOutputMode: TLabel
        Left = 12
        Top = 24
        Width = 75
        Height = 15
        Caption = 'Output mode:'
      end
      object LblFormat: TLabel
        Left = 12
        Top = 53
        Width = 75
        Height = 15
        Caption = 'Image format:'
      end
      object LblJpegQuality: TLabel
        Left = 12
        Top = 82
        Width = 67
        Height = 15
        Caption = 'JPEG quality:'
      end
      object LblPngCompression: TLabel
        Left = 12
        Top = 111
        Width = 98
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
        Text = '1'
      end
      object UdJpegQuality: TUpDown
        Left = 175
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtJpegQuality
        Min = 1
        Position = 1
        TabOrder = 3
        Thousands = False
      end
      object EdtPngCompression: TEdit
        Left = 130
        Top = 107
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 4
        Text = '0'
      end
      object UdPngCompression: TUpDown
        Left = 175
        Top = 107
        Width = 17
        Height = 23
        Associate = EdtPngCompression
        Max = 9
        TabOrder = 5
        Thousands = False
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
    object TshCombined: TTabSheet
      Caption = 'Combined'
      ImageIndex = 2
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
        Width = 69
        Height = 15
        Caption = 'Cell gap (px):'
      end
      object LblBackground: TLabel
        Left = 12
        Top = 82
        Width = 67
        Height = 15
        Caption = 'Background:'
      end
      object LblTimestampFont: TLabel
        Left = 12
        Top = 140
        Width = 88
        Height = 15
        Caption = 'Timestamp font:'
      end
      object LblTimestampFontSize: TLabel
        Left = 320
        Top = 140
        Width = 23
        Height = 15
        Caption = 'Size:'
      end
      object EdtColumns: TEdit
        Left = 130
        Top = 20
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 0
        Text = '0'
      end
      object UdColumns: TUpDown
        Left = 175
        Top = 20
        Width = 17
        Height = 23
        Associate = EdtColumns
        Max = 20
        TabOrder = 1
        Thousands = False
      end
      object EdtCellGap: TEdit
        Left = 130
        Top = 49
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 2
        Text = '0'
      end
      object UdCellGap: TUpDown
        Left = 175
        Top = 49
        Width = 17
        Height = 23
        Associate = EdtCellGap
        Max = 20
        TabOrder = 3
        Thousands = False
      end
      object PnlBackground: TPanel
        Left = 130
        Top = 78
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
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
      object EdtTimestampFont: TEdit
        Left = 130
        Top = 136
        Width = 180
        Height = 23
        TabOrder = 7
      end
      object EdtTimestampFontSize: TEdit
        Left = 350
        Top = 136
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 8
        Text = '6'
      end
      object UdTimestampFontSize: TUpDown
        Left = 395
        Top = 136
        Width = 17
        Height = 23
        Associate = EdtTimestampFontSize
        Min = 6
        Max = 72
        Position = 6
        TabOrder = 9
        Thousands = False
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
    object TshLimits: TTabSheet
      Caption = 'Size limit'
      ImageIndex = 3
      object LblLimitsHint: TLabel
        Left = 12
        Top = 24
        Width = 240
        Height = 15
        Caption = 'Maximum longer side in pixels (0 = no limit)'
        Font.Color = clGray
        ParentFont = False
      end
      object LblFrameMax: TLabel
        Left = 12
        Top = 53
        Width = 148
        Height = 15
        Caption = 'Separate frames longer side:'
      end
      object LblCombinedMax: TLabel
        Left = 12
        Top = 82
        Width = 156
        Height = 15
        Caption = 'Combined image longer side:'
      end
      object EdtFrameMax: TEdit
        Left = 170
        Top = 49
        Width = 60
        Height = 23
        NumbersOnly = True
        TabOrder = 0
        Text = '0'
      end
      object UdFrameMax: TUpDown
        Left = 230
        Top = 49
        Width = 17
        Height = 23
        Associate = EdtFrameMax
        Max = 7680
        Increment = 16
        TabOrder = 1
        Thousands = False
      end
      object EdtCombinedMax: TEdit
        Left = 170
        Top = 78
        Width = 60
        Height = 23
        NumbersOnly = True
        TabOrder = 2
        Text = '0'
      end
      object UdCombinedMax: TUpDown
        Left = 230
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtCombinedMax
        Max = 7680
        Increment = 16
        TabOrder = 3
        Thousands = False
      end
    end
  end
  object PnlButtons: TPanel
    Left = 0
    Top = 370
    Width = 460
    Height = 40
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object BtnDefaults: TButton
      Left = 8
      Top = 6
      Width = 100
      Height = 28
      Caption = 'Reset Defaults'
      TabOrder = 0
      OnClick = BtnDefaultsClick
    end
    object BtnOK: TButton
      Left = 296
      Top = 6
      Width = 75
      Height = 28
      Anchors = [akTop, akRight]
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 1
    end
    object BtnCancel: TButton
      Left = 377
      Top = 6
      Width = 75
      Height = 28
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 2
    end
  end
  object ColorDlg: TColorDialog
    Options = [cdFullOpen]
    Left = 408
    Top = 8
  end
end
