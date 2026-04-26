object SettingsForm: TSettingsForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Glimpse Settings'
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
      object LblSkipEdges: TLabel
        Left = 12
        Top = 24
        Width = 59
        Height = 15
        Caption = 'Skip edges:'
      end
      object LblSkipEdgesUnit: TLabel
        Left = 198
        Top = 24
        Width = 10
        Height = 15
        Caption = '%'
      end
      object LblMaxWorkers: TLabel
        Left = 12
        Top = 53
        Width = 69
        Height = 15
        Caption = 'Max workers:'
      end
      object LblMaxThreads: TLabel
        Left = 12
        Top = 82
        Width = 108
        Height = 15
        Caption = 'Limit workers count:'
      end
      object LblMaxThreadsAuto: TLabel
        Left = 198
        Top = 82
        Width = 3
        Height = 15
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object LblScaleTarget: TLabel
        Left = 32
        Top = 227
        Width = 64
        Height = 15
        Caption = 'Scale target:'
      end
      object LblScaleSep: TLabel
        Left = 193
        Top = 227
        Width = 12
        Height = 15
        Caption = #8212
      end
      object LblScaleUnit: TLabel
        Left = 291
        Top = 227
        Width = 81
        Height = 15
        Caption = 'px (bigger side)'
      end
      object LblExtensions: TLabel
        Left = 12
        Top = 313
        Width = 58
        Height = 15
        Caption = 'Extensions:'
      end
      object LblFFmpegPath: TLabel
        Left = 12
        Top = 343
        Width = 73
        Height = 15
        Caption = 'FFmpeg path:'
      end
      object LblFFmpegInfo: TLabel
        Left = 12
        Top = 364
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
        Text = '0'
      end
      object UdSkipEdges: TUpDown
        Left = 175
        Top = 20
        Width = 17
        Height = 23
        Associate = EdtSkipEdges
        Max = 49
        TabOrder = 1
        Thousands = False
      end
      object EdtMaxWorkers: TEdit
        Left = 130
        Top = 49
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 2
        Text = '1'
      end
      object UdMaxWorkers: TUpDown
        Left = 175
        Top = 49
        Width = 17
        Height = 23
        Associate = EdtMaxWorkers
        Min = 1
        Max = 16
        Position = 1
        TabOrder = 3
        Thousands = False
      end
      object ChkMaxWorkersAuto: TCheckBox
        Left = 198
        Top = 53
        Width = 130
        Height = 17
        Caption = 'One per frame'
        TabOrder = 4
        OnClick = ChkMaxWorkersAutoClick
      end
      object EdtMaxThreads: TEdit
        Left = 130
        Top = 78
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 5
        Text = '0'
        OnChange = EdtMaxThreadsChange
      end
      object UdMaxThreads: TUpDown
        Left = 175
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtMaxThreads
        Min = -1
        Max = 64
        TabOrder = 6
        Thousands = False
      end
      object ChkUseBmpPipe: TCheckBox
        Left = 12
        Top = 111
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use BMP pipe (faster extraction, higher memory usage)'
        TabOrder = 7
      end
      object ChkHwAccel: TCheckBox
        Left = 12
        Top = 140
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use hardware-accelerated decoding (GPU)'
        TabOrder = 8
      end
      object ChkUseKeyframes: TCheckBox
        Left = 12
        Top = 169
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use keyframes (faster seeking, less precise timecodes)'
        TabOrder = 9
      end
      object ChkScaledExtraction: TCheckBox
        Left = 12
        Top = 198
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Extract frames at display size (faster for high-res video)'
        TabOrder = 10
        OnClick = ChkScaledExtractionClick
      end
      object EdtMinFrameSide: TEdit
        Left = 115
        Top = 223
        Width = 55
        Height = 23
        NumbersOnly = True
        TabOrder = 11
        Text = '32'
      end
      object UdMinFrameSide: TUpDown
        Left = 170
        Top = 223
        Width = 17
        Height = 23
        Associate = EdtMinFrameSide
        Min = 32
        Max = 7680
        Increment = 10
        Position = 32
        TabOrder = 12
        Thousands = False
      end
      object EdtMaxFrameSide: TEdit
        Left = 213
        Top = 223
        Width = 55
        Height = 23
        NumbersOnly = True
        TabOrder = 13
        Text = '32'
      end
      object UdMaxFrameSide: TUpDown
        Left = 268
        Top = 223
        Width = 17
        Height = 23
        Associate = EdtMaxFrameSide
        Min = 32
        Max = 7680
        Increment = 10
        Position = 32
        TabOrder = 14
        Thousands = False
      end
      object ChkRespectAnamorphic: TCheckBox
        Left = 12
        Top = 252
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Respect anamorphic dimensions'
        TabOrder = 15
      end
      object ChkAutoRefreshViewport: TCheckBox
        Left = 12
        Top = 281
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Re-extract automatically when the viewport changes'
        TabOrder = 16
      end
      object EdtExtensions: TEdit
        Left = 115
        Top = 310
        Width = 324
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 17
      end
      object EdtFFmpegPath: TEdit
        Left = 115
        Top = 339
        Width = 293
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 18
        TextHint = 'Auto-detect'
        OnChange = EdtFFmpegPathChange
      end
      object BtnFFmpegPath: TButton
        Left = 414
        Top = 339
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 19
        OnClick = BtnFFmpegPathClick
      end
    end
    object TshAppearance: TTabSheet
      Caption = 'Appearance'
      ImageIndex = 1
      DesignSize = (
        452
        400)
      object LblBackground: TLabel
        Left = 12
        Top = 24
        Width = 97
        Height = 15
        Caption = 'Background color:'
      end
      object LblCellGap: TLabel
        Left = 12
        Top = 53
        Width = 69
        Height = 15
        Caption = 'Cell gap (px):'
      end
      object LblBorder: TLabel
        Left = 292
        Top = 53
        Width = 73
        Height = 15
        AutoSize = False
        Caption = 'Border (px):'
      end
      object LblTCBack: TLabel
        Left = 12
        Top = 111
        Width = 135
        Height = 15
        AutoSize = False
        Caption = 'Timecode background:'
      end
      object LblTCAlpha: TLabel
        Left = 292
        Top = 111
        Width = 44
        Height = 15
        Caption = 'Opacity:'
      end
      object LblTCTextColor: TLabel
        Left = 12
        Top = 140
        Width = 128
        Height = 15
        AutoSize = False
        Caption = 'Timecode text color:'
      end
      object LblTCTextAlpha: TLabel
        Left = 292
        Top = 140
        Width = 44
        Height = 15
        Caption = 'Opacity:'
      end
      object LblTimestampFont: TLabel
        Left = 12
        Top = 169
        Width = 88
        Height = 15
        Caption = 'Timestamp font:'
      end
      object PnlBackground: TPanel
        Left = 150
        Top = 20
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 0
        OnClick = PnlBackgroundClick
      end
      object BtnBackground: TButton
        Left = 234
        Top = 20
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 1
        OnClick = PnlBackgroundClick
      end
      object EdtCellGap: TEdit
        Left = 150
        Top = 49
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 2
        Text = '0'
      end
      object UdCellGap: TUpDown
        Left = 195
        Top = 49
        Width = 17
        Height = 23
        Associate = EdtCellGap
        Max = 32767
        TabOrder = 3
        Thousands = False
      end
      object EdtBorder: TEdit
        Left = 377
        Top = 49
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 4
        Text = '0'
      end
      object UdBorder: TUpDown
        Left = 422
        Top = 49
        Width = 17
        Height = 23
        Associate = EdtBorder
        Max = 200
        TabOrder = 5
        Thousands = False
      end
      object ChkShowTimecode: TCheckBox
        Left = 12
        Top = 82
        Width = 130
        Height = 17
        Caption = 'Show timestamp'
        TabOrder = 6
      end
      object CbxTimestampCorner: TComboBox
        Left = 150
        Top = 78
        Width = 105
        Height = 23
        Style = csDropDownList
        TabOrder = 7
        Items.Strings = (
          'Top left'
          'Top right'
          'Bottom left'
          'Bottom right')
      end
      object PnlTCBack: TPanel
        Left = 150
        Top = 107
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 8
        OnClick = PnlTCBackClick
      end
      object BtnTCBack: TButton
        Left = 234
        Top = 107
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 9
        OnClick = PnlTCBackClick
      end
      object EdtTCAlpha: TEdit
        Left = 377
        Top = 107
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 10
        Text = '0'
      end
      object UdTCAlpha: TUpDown
        Left = 422
        Top = 107
        Width = 17
        Height = 23
        Associate = EdtTCAlpha
        Max = 255
        TabOrder = 11
        Thousands = False
      end
      object PnlTCTextColor: TPanel
        Left = 150
        Top = 136
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 12
        OnClick = PnlTCTextColorClick
      end
      object BtnTCTextColor: TButton
        Left = 234
        Top = 136
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 13
        OnClick = PnlTCTextColorClick
      end
      object EdtTCTextAlpha: TEdit
        Left = 377
        Top = 136
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 14
        Text = '255'
      end
      object UdTCTextAlpha: TUpDown
        Left = 422
        Top = 136
        Width = 17
        Height = 23
        Associate = EdtTCTextAlpha
        Max = 255
        Position = 255
        TabOrder = 15
        Thousands = False
      end
      object EdtTimestampFont: TEdit
        Left = 149
        Top = 165
        Width = 259
        Height = 23
        TabStop = False
        Anchors = [akLeft, akTop, akRight]
        ReadOnly = True
        TabOrder = 16
      end
      object BtnTimestampFont: TButton
        Left = 414
        Top = 165
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 17
        OnClick = BtnTimestampFontClick
      end
      object ChkShowToolbar: TCheckBox
        Left = 12
        Top = 194
        Width = 200
        Height = 17
        Caption = 'Show toolbar (F4 to toggle)'
        TabOrder = 19
      end
      object ChkShowStatusBar: TCheckBox
        Left = 230
        Top = 194
        Width = 200
        Height = 17
        Caption = 'Show status bar (F3 to toggle)'
        TabOrder = 18
      end
    end
    object TshSave: TTabSheet
      Caption = 'Save'
      ImageIndex = 2
      DesignSize = (
        452
        400)
      object LblSaveFormat: TLabel
        Left = 12
        Top = 24
        Width = 41
        Height = 15
        Caption = 'Format:'
      end
      object LblJpegQuality: TLabel
        Left = 12
        Top = 53
        Width = 67
        Height = 15
        Caption = 'JPEG quality:'
      end
      object LblPngCompression: TLabel
        Left = 12
        Top = 82
        Width = 98
        Height = 15
        Caption = 'PNG compression:'
      end
      object LblSaveFolder: TLabel
        Left = 12
        Top = 111
        Width = 75
        Height = 15
        Caption = 'Default folder:'
      end
      object LblBannerBackground: TLabel
        Left = 12
        Top = 173
        Width = 128
        Height = 15
        AutoSize = False
        Caption = 'Banner background:'
      end
      object LblBannerTextColor: TLabel
        Left = 12
        Top = 202
        Width = 128
        Height = 15
        AutoSize = False
        Caption = 'Banner text color:'
      end
      object LblBannerFont: TLabel
        Left = 12
        Top = 231
        Width = 65
        Height = 15
        Caption = 'Banner font:'
      end
      object LblBannerPosition: TLabel
        Left = 12
        Top = 289
        Width = 86
        Height = 15
        Caption = 'Banner position:'
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
        Text = '1'
      end
      object UdJpegQuality: TUpDown
        Left = 175
        Top = 49
        Width = 17
        Height = 23
        Associate = EdtJpegQuality
        Min = 1
        Position = 1
        TabOrder = 2
        Thousands = False
      end
      object EdtPngCompression: TEdit
        Left = 130
        Top = 78
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 3
        Text = '0'
      end
      object UdPngCompression: TUpDown
        Left = 175
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtPngCompression
        Max = 9
        TabOrder = 4
        Thousands = False
      end
      object EdtSaveFolder: TEdit
        Left = 130
        Top = 107
        Width = 278
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 5
        TextHint = 'Leave empty for no default'
      end
      object BtnSaveFolder: TButton
        Left = 414
        Top = 107
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 6
        OnClick = BtnSaveFolderClick
      end
      object ChkShowBanner: TCheckBox
        Left = 12
        Top = 140
        Width = 424
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Include file info banner in combined image export'
        TabOrder = 7
        OnClick = ChkShowBannerClick
      end
      object PnlBannerBackground: TPanel
        Left = 130
        Top = 169
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 8
        OnClick = PnlBannerBackgroundClick
      end
      object BtnBannerBackground: TButton
        Left = 214
        Top = 169
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 9
        OnClick = PnlBannerBackgroundClick
      end
      object PnlBannerTextColor: TPanel
        Left = 130
        Top = 198
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 10
        OnClick = PnlBannerTextColorClick
      end
      object BtnBannerTextColor: TButton
        Left = 214
        Top = 198
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 11
        OnClick = PnlBannerTextColorClick
      end
      object EdtBannerFont: TEdit
        Left = 130
        Top = 227
        Width = 278
        Height = 23
        TabStop = False
        Anchors = [akLeft, akTop, akRight]
        ReadOnly = True
        TabOrder = 12
      end
      object BtnBannerFont: TButton
        Left = 414
        Top = 227
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 13
        OnClick = BtnBannerFontClick
      end
      object ChkBannerAutoSize: TCheckBox
        Left = 130
        Top = 258
        Width = 306
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Auto-size banner font to image width'
        TabOrder = 14
        OnClick = ChkBannerAutoSizeClick
      end
      object CbxBannerPosition: TComboBox
        Left = 130
        Top = 285
        Width = 105
        Height = 23
        Style = csDropDownList
        TabOrder = 15
        Items.Strings = (
          'Top'
          'Bottom')
      end
    end
    object TshCache: TTabSheet
      Caption = 'Cache'
      ImageIndex = 3
      DesignSize = (
        452
        400)
      object LblCacheFolder: TLabel
        Left = 12
        Top = 53
        Width = 36
        Height = 15
        Caption = 'Folder:'
      end
      object LblCacheFolderInfo: TLabel
        Left = 12
        Top = 82
        Width = 427
        Height = 15
        AutoSize = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object LblCacheMaxSize: TLabel
        Left = 12
        Top = 111
        Width = 47
        Height = 15
        Caption = 'Max size:'
      end
      object LblCacheMaxSizeUnit: TLabel
        Left = 218
        Top = 111
        Width = 18
        Height = 15
        Caption = 'MB'
      end
      object LblCacheSizeInfo: TLabel
        Left = 244
        Top = 111
        Width = 195
        Height = 15
        AutoSize = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object ChkCacheEnabled: TCheckBox
        Left = 12
        Top = 24
        Width = 140
        Height = 17
        Caption = 'Enable disk cache'
        TabOrder = 0
        OnClick = ChkCacheEnabledClick
      end
      object BtnClearCache: TButton
        Left = 351
        Top = 20
        Width = 88
        Height = 23
        Anchors = [akTop, akRight]
        Caption = 'Clear Cache'
        TabOrder = 1
        OnClick = BtnClearCacheClick
      end
      object EdtCacheFolder: TEdit
        Left = 130
        Top = 49
        Width = 278
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 2
        TextHint = 'Leave empty for default'
        OnChange = EdtCacheFolderChange
      end
      object BtnCacheFolder: TButton
        Left = 414
        Top = 49
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 3
        OnClick = BtnCacheFolderClick
      end
      object EdtCacheMaxSize: TEdit
        Left = 130
        Top = 107
        Width = 65
        Height = 23
        NumbersOnly = True
        TabOrder = 4
        Text = '10'
      end
      object UdCacheMaxSize: TUpDown
        Left = 195
        Top = 107
        Width = 17
        Height = 23
        Associate = EdtCacheMaxSize
        Min = 10
        Max = 10000
        Position = 10
        TabOrder = 5
        Thousands = False
      end
    end
    object TshThumbnails: TTabSheet
      Caption = 'Thumbnails'
      ImageIndex = 4
      object LblThumbnailMode: TLabel
        Left = 12
        Top = 53
        Width = 34
        Height = 15
        Caption = 'Mode:'
      end
      object LblThumbnailPosition: TLabel
        Left = 12
        Top = 82
        Width = 46
        Height = 15
        Caption = 'Position:'
      end
      object LblThumbnailPositionUnit: TLabel
        Left = 198
        Top = 82
        Width = 10
        Height = 15
        Caption = '%'
      end
      object LblThumbnailGridFrames: TLabel
        Left = 240
        Top = 82
        Width = 64
        Height = 15
        Caption = 'Grid frames:'
      end
      object ChkThumbnailsEnabled: TCheckBox
        Left = 12
        Top = 24
        Width = 412
        Height = 17
        Caption = 'Enable thumbnails for TC panel'
        TabOrder = 0
        OnClick = ChkThumbnailsEnabledClick
      end
      object CbxThumbnailMode: TComboBox
        Left = 130
        Top = 49
        Width = 110
        Height = 23
        Style = csDropDownList
        TabOrder = 1
        OnChange = CbxThumbnailModeChange
        Items.Strings = (
          'Single frame'
          'Grid')
      end
      object EdtThumbnailPosition: TEdit
        Left = 130
        Top = 78
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 2
        Text = '50'
      end
      object UdThumbnailPosition: TUpDown
        Left = 175
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtThumbnailPosition
        Position = 50
        TabOrder = 3
        Thousands = False
      end
      object EdtThumbnailGridFrames: TEdit
        Left = 320
        Top = 78
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 4
        Text = '4'
      end
      object UdThumbnailGridFrames: TUpDown
        Left = 365
        Top = 78
        Width = 17
        Height = 23
        Associate = EdtThumbnailGridFrames
        Min = 2
        Max = 16
        Position = 4
        TabOrder = 5
        Thousands = False
      end
    end
    object TshQuickView: TTabSheet
      Caption = 'Quick View'
      ImageIndex = 5
      DesignSize = (
        452
        400)
      object ChkQVDisableNavigation: TCheckBox
        Left = 12
        Top = 24
        Width = 427
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Disable internal file navigation'
        TabOrder = 0
      end
      object ChkQVHideToolbar: TCheckBox
        Left = 12
        Top = 53
        Width = 427
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Hide toolbar'
        TabOrder = 1
      end
      object ChkQVHideStatusBar: TCheckBox
        Left = 12
        Top = 82
        Width = 427
        Height = 17
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Hide status bar'
        TabOrder = 2
      end
    end
    object TshHotkeys: TTabSheet
      Caption = 'Hotkeys'
      ImageIndex = 6
      DesignSize = (
        452
        400)
      object LvwHotkeys: TListView
        Left = 12
        Top = 12
        Width = 427
        Height = 318
        Anchors = [akLeft, akTop, akRight, akBottom]
        Columns = <
          item
            Caption = 'Action'
            Width = 240
          end
          item
            Caption = 'Shortcut'
            Width = 160
          end>
        HideSelection = False
        ReadOnly = True
        RowSelect = True
        TabOrder = 0
        ViewStyle = vsReport
        OnDblClick = LvwHotkeysDblClick
      end
      object BtnHotkeyClear: TButton
        Left = 12
        Top = 338
        Width = 75
        Height = 25
        Anchors = [akLeft, akBottom]
        Caption = 'Clear'
        TabOrder = 1
        OnClick = BtnHotkeyClearClick
      end
      object BtnHotkeyAssign: TButton
        Left = 93
        Top = 338
        Width = 85
        Height = 25
        Anchors = [akLeft, akBottom]
        Caption = 'Assign...'
        TabOrder = 2
        OnClick = BtnHotkeyAssignClick
      end
      object BtnHotkeyResetAll: TButton
        Left = 364
        Top = 338
        Width = 75
        Height = 25
        Anchors = [akRight, akBottom]
        Caption = 'Reset all'
        TabOrder = 3
        OnClick = BtnHotkeyResetAllClick
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
    Left = 352
    Top = 8
  end
end
