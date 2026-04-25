object WcxSettingsForm: TWcxSettingsForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Glimpse WCX Settings'
  ClientHeight = 470
  ClientWidth = 460
  Color = clBtnFace
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
    Height = 430
    ActivePage = TshGeneral
    Align = alClient
    TabOrder = 0
    object TshGeneral: TTabSheet
      Caption = 'General'
      DesignSize = (
        452
        400)
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
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
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
        Width = 424
        Height = 15
        Anchors = [akLeft, akTop, akRight]
        AutoSize = False
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
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use BMP pipe (faster extraction, higher memory usage)'
        TabOrder = 9
      end
      object ChkHwAccel: TCheckBox
        Left = 12
        Top = 169
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use hardware-accelerated decoding (GPU)'
        TabOrder = 10
      end
      object ChkUseKeyframes: TCheckBox
        Left = 12
        Top = 198
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use keyframes (faster seeking, less precise timecodes)'
        TabOrder = 11
      end
      object EdtFFmpegPath: TEdit
        Left = 130
        Top = 227
        Width = 278
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 12
        TextHint = 'Auto-detect'
        OnChange = EdtFFmpegPathChange
      end
      object BtnFFmpegPath: TButton
        Left = 414
        Top = 227
        Width = 25
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
      DesignSize = (
        452
        400)
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
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Show file sizes (extracts all frames when entering archive)'
        TabOrder = 6
      end
    end
    object TshCombined: TTabSheet
      Caption = 'Combined'
      ImageIndex = 2
      DesignSize = (
        452
        400)
      object LblColumns: TLabel
        Left = 12
        Top = 24
        Width = 100
        Height = 15
        Caption = 'Columns (0=auto):'
      end
      object LblBackground: TLabel
        Left = 12
        Top = 53
        Width = 97
        Height = 15
        Caption = 'Background color:'
      end
      object LblCellGap: TLabel
        Left = 12
        Top = 82
        Width = 69
        Height = 15
        Caption = 'Cell gap (px):'
      end
      object LblBorder: TLabel
        Left = 292
        Top = 82
        Width = 73
        Height = 15
        AutoSize = False
        Caption = 'Border (px):'
      end
      object LblTCBack: TLabel
        Left = 12
        Top = 140
        Width = 135
        Height = 15
        AutoSize = False
        Caption = 'Timecode background:'
      end
      object LblTCAlpha: TLabel
        Left = 292
        Top = 140
        Width = 44
        Height = 15
        Caption = 'Opacity:'
      end
      object LblTCTextColor: TLabel
        Left = 12
        Top = 169
        Width = 128
        Height = 15
        AutoSize = False
        Caption = 'Timecode text color:'
      end
      object LblTCTextAlpha: TLabel
        Left = 292
        Top = 169
        Width = 44
        Height = 15
        Caption = 'Opacity:'
      end
      object LblTimestampFont: TLabel
        Left = 12
        Top = 198
        Width = 88
        Height = 15
        Caption = 'Timestamp font:'
      end
      object LblBannerBackground: TLabel
        Left = 12
        Top = 256
        Width = 135
        Height = 15
        AutoSize = False
        Caption = 'Banner background:'
      end
      object LblBannerTextColor: TLabel
        Left = 12
        Top = 285
        Width = 135
        Height = 15
        AutoSize = False
        Caption = 'Banner text color:'
      end
      object LblBannerFont: TLabel
        Left = 12
        Top = 314
        Width = 65
        Height = 15
        Caption = 'Banner font:'
      end
      object LblBannerPosition: TLabel
        Left = 12
        Top = 372
        Width = 86
        Height = 15
        Caption = 'Banner position:'
      end
      object EdtColumns: TEdit
        Left = 150
        Top = 20
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 0
        Text = '0'
      end
      object UdColumns: TUpDown
        Left = 195
        Top = 20
        Width = 17
        Height = 23
        Associate = EdtColumns
        Max = 20
        TabOrder = 1
        Thousands = False
      end
      object PnlBackground: TPanel
        Left = 150
        Top = 49
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 2
        OnClick = PnlBackgroundClick
      end
      object BtnBackground: TButton
        Left = 234
        Top = 49
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 3
        OnClick = PnlBackgroundClick
      end
      object EdtCellGap: TEdit
        Left = 150
        Top = 78
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 4
        Text = '0'
      end
      object UdCellGap: TUpDown
        Left = 195
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtCellGap
        Max = 32767
        TabOrder = 5
        Thousands = False
      end
      object EdtBorder: TEdit
        Left = 377
        Top = 78
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 6
        Text = '0'
      end
      object UdBorder: TUpDown
        Left = 422
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtBorder
        Max = 32767
        TabOrder = 7
        Thousands = False
      end
      object ChkTimestamp: TCheckBox
        Left = 12
        Top = 111
        Width = 130
        Height = 17
        Caption = 'Show timestamp'
        TabOrder = 8
      end
      object CbxTimestampCorner: TComboBox
        Left = 150
        Top = 107
        Width = 105
        Height = 23
        Style = csDropDownList
        TabOrder = 9
        Items.Strings = (
          'Top left'
          'Top right'
          'Bottom left'
          'Bottom right')
      end
      object PnlTCBack: TPanel
        Left = 150
        Top = 136
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 10
        OnClick = PnlTCBackClick
      end
      object BtnTCBack: TButton
        Left = 234
        Top = 136
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 11
        OnClick = PnlTCBackClick
      end
      object EdtTCAlpha: TEdit
        Left = 377
        Top = 136
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 12
        Text = '0'
      end
      object UdTCAlpha: TUpDown
        Left = 422
        Top = 136
        Width = 17
        Height = 23
        Associate = EdtTCAlpha
        Max = 255
        TabOrder = 13
        Thousands = False
      end
      object PnlTCTextColor: TPanel
        Left = 150
        Top = 165
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 14
        OnClick = PnlTCTextColorClick
      end
      object BtnTCTextColor: TButton
        Left = 234
        Top = 165
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 15
        OnClick = PnlTCTextColorClick
      end
      object EdtTCTextAlpha: TEdit
        Left = 377
        Top = 165
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 16
        Text = '255'
      end
      object UdTCTextAlpha: TUpDown
        Left = 422
        Top = 165
        Width = 17
        Height = 23
        Associate = EdtTCTextAlpha
        Max = 255
        Position = 255
        TabOrder = 17
        Thousands = False
      end
      object EdtTimestampFont: TEdit
        Left = 149
        Top = 194
        Width = 259
        Height = 23
        TabStop = False
        Anchors = [akLeft, akTop, akRight]
        ReadOnly = True
        TabOrder = 18
      end
      object BtnTimestampFont: TButton
        Left = 414
        Top = 194
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 19
        OnClick = BtnTimestampFontClick
      end
      object ChkShowBanner: TCheckBox
        Left = 12
        Top = 227
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Include file info banner'
        TabOrder = 20
        OnClick = ChkShowBannerClick
      end
      object PnlBannerBackground: TPanel
        Left = 150
        Top = 252
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 21
        OnClick = PnlBannerBackgroundClick
      end
      object BtnBannerBackground: TButton
        Left = 234
        Top = 252
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 22
        OnClick = PnlBannerBackgroundClick
      end
      object PnlBannerTextColor: TPanel
        Left = 150
        Top = 281
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 23
        OnClick = PnlBannerTextColorClick
      end
      object BtnBannerTextColor: TButton
        Left = 234
        Top = 281
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 24
        OnClick = PnlBannerTextColorClick
      end
      object EdtBannerFont: TEdit
        Left = 149
        Top = 310
        Width = 259
        Height = 23
        TabStop = False
        Anchors = [akLeft, akTop, akRight]
        ReadOnly = True
        TabOrder = 25
      end
      object BtnBannerFont: TButton
        Left = 414
        Top = 310
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 26
        OnClick = BtnBannerFontClick
      end
      object ChkBannerAutoSize: TCheckBox
        Left = 150
        Top = 343
        Width = 289
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Auto-size banner font to image width'
        TabOrder = 28
        OnClick = ChkBannerAutoSizeClick
      end
      object CbxBannerPosition: TComboBox
        Left = 150
        Top = 368
        Width = 105
        Height = 23
        Style = csDropDownList
        TabOrder = 27
        Items.Strings = (
          'Top'
          'Bottom')
      end
    end
    object TshLimits: TTabSheet
      Caption = 'Size limit'
      ImageIndex = 3
      DesignSize = (
        452
        400)
      object LblLimitsHint: TLabel
        Left = 12
        Top = 24
        Width = 424
        Height = 15
        Anchors = [akLeft, akTop, akRight]
        AutoSize = False
        Caption = 'Maximum longer side in pixels (0 = no limit)'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
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
    Top = 430
    Width = 460
    Height = 40
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    DesignSize = (
      460
      40)
    object BtnDefaults: TButton
      Left = 8
      Top = 6
      Width = 100
      Height = 28
      Anchors = [akLeft, akBottom]
      Caption = 'Reset Defaults'
      TabOrder = 0
      OnClick = BtnDefaultsClick
    end
    object BtnApply: TButton
      Left = 215
      Top = 6
      Width = 75
      Height = 28
      Anchors = [akRight, akBottom]
      Caption = 'Apply'
      TabOrder = 1
      OnClick = BtnApplyClick
    end
    object BtnOK: TButton
      Left = 296
      Top = 6
      Width = 75
      Height = 28
      Anchors = [akRight, akBottom]
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 2
    end
    object BtnCancel: TButton
      Left = 377
      Top = 6
      Width = 75
      Height = 28
      Anchors = [akRight, akBottom]
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 3
    end
  end
  object ColorDlg: TColorDialog
    Options = [cdFullOpen]
    Left = 408
    Top = 8
  end
  object FontDlg: TFontDialog
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    Options = [fdEffects, fdForceFontExist]
    Left = 344
    Top = 8
  end
end
