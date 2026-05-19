object SettingsForm: TSettingsForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Glimpse Settings'
  ClientHeight = 520
  ClientWidth = 460
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  ShowHint = True
  TextHeight = 15
  object PageControl: TPageControl
    Left = 0
    Top = 0
    Width = 460
    Height = 480
    ActivePage = TshGeneral
    Align = alClient
    TabOrder = 0
    object TshGeneral: TTabSheet
      Caption = 'General'
      DesignSize = (
        452
        450)
      object LblMaxWorkers: TLabel
        Left = 12
        Top = 24
        Width = 69
        Height = 15
        Caption = 'Max workers:'
      end
      object LblMaxThreads: TLabel
        Left = 12
        Top = 53
        Width = 108
        Height = 15
        Caption = 'Limit workers count:'
      end
      object LblMaxThreadsAuto: TLabel
        Left = 198
        Top = 53
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
        Top = 198
        Width = 64
        Height = 15
        Caption = 'Scale target:'
      end
      object LblScaleSep: TLabel
        Left = 193
        Top = 198
        Width = 12
        Height = 15
        Caption = #8212
      end
      object LblScaleUnit: TLabel
        Left = 291
        Top = 198
        Width = 81
        Height = 15
        Caption = 'px (bigger side)'
      end
      object LblExtensions: TLabel
        Left = 12
        Top = 284
        Width = 58
        Height = 15
        Caption = 'Extensions:'
      end
      object LblFFmpegPath: TLabel
        Left = 12
        Top = 336
        Width = 73
        Height = 15
        Caption = 'FFmpeg path:'
      end
      object LblFFmpegInfo: TLabel
        Left = 12
        Top = 384
        Width = 94
        Height = 15
        AutoSize = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
      end
      object EdtFFmpegInfo: TEdit
        Left = 130
        Top = 382
        Width = 309
        Height = 21
        Hint = 
          'Resolved ffmpeg path or validation error. Click to select / copy' +
          '.'
        TabStop = False
        Anchors = [akLeft, akTop, akRight]
        AutoSize = False
        BevelInner = bvLowered
        BorderStyle = bsNone
        Color = clBtnFace
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
        ReadOnly = True
        TabOrder = 18
      end
      object EdtMaxWorkers: TEdit
        Left = 130
        Top = 20
        Width = 45
        Height = 23
        NumbersOnly = True
        TabOrder = 0
        Text = '1'
      end
      object UdMaxWorkers: TUpDown
        Left = 175
        Top = 20
        Width = 17
        Height = 23
        Associate = EdtMaxWorkers
        Min = 1
        Max = 16
        Position = 1
        TabOrder = 1
        Thousands = False
      end
      object ChkMaxWorkersAuto: TCheckBox
        Left = 198
        Top = 24
        Width = 130
        Height = 17
        Hint = 
          'Spawn one ffmpeg worker per requested frame, ignoring Max worker' +
          's above.'
        Caption = 'One per frame'
        TabOrder = 2
        OnClick = ChkMaxWorkersAutoClick
      end
      object EdtMaxThreads: TEdit
        Left = 130
        Top = 49
        Width = 45
        Height = 23
        Hint = 
          'Per-worker ffmpeg thread cap. 0 = let ffmpeg decide, -1 = single' +
          '-threaded.'
        NumbersOnly = True
        TabOrder = 3
        Text = '0'
        OnChange = EdtMaxThreadsChange
      end
      object UdMaxThreads: TUpDown
        Left = 175
        Top = 49
        Width = 17
        Height = 23
        Hint = 
          'Per-worker ffmpeg thread cap. 0 = let ffmpeg decide, -1 = single' +
          '-threaded.'
        Associate = EdtMaxThreads
        Min = -1
        Max = 64
        TabOrder = 4
        Thousands = False
      end
      object ChkUseBmpPipe: TCheckBox
        Left = 12
        Top = 82
        Width = 427
        Height = 17
        Hint = 
          'Stream raw BMP from ffmpeg in memory instead of going through te' +
          'mporary image files.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use BMP pipe (faster extraction, higher memory usage)'
        TabOrder = 5
      end
      object ChkHwAccel: TCheckBox
        Left = 12
        Top = 111
        Width = 427
        Height = 17
        Hint = 
          'Asks ffmpeg to use a GPU decoder when available. Falls back to C' +
          'PU if it cannot.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use hardware-accelerated decoding (GPU)'
        TabOrder = 6
      end
      object ChkUseKeyframes: TCheckBox
        Left = 12
        Top = 140
        Width = 427
        Height = 17
        Hint = 
          'Seeks only to the nearest keyframe. Much faster, but the actual ' +
          'frame may differ from the requested timecode.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Use keyframes (faster seeking, less precise timecodes)'
        TabOrder = 7
      end
      object ChkScaledExtraction: TCheckBox
        Left = 12
        Top = 169
        Width = 427
        Height = 17
        Hint = 
          'Asks ffmpeg to downscale during decode using the Scale target ra' +
          'nge below. Saves time on 4K+ video.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Extract frames at display size (faster for high-res video)'
        TabOrder = 8
        OnClick = ChkScaledExtractionClick
      end
      object EdtMinFrameSide: TEdit
        Left = 115
        Top = 194
        Width = 55
        Height = 23
        Hint = 
          'Lower bound (pixels, longer side) for the scaled extraction rang' +
          'e.'
        NumbersOnly = True
        TabOrder = 9
        Text = '32'
      end
      object UdMinFrameSide: TUpDown
        Left = 170
        Top = 194
        Width = 17
        Height = 23
        Hint = 
          'Lower bound (pixels, longer side) for the scaled extraction rang' +
          'e.'
        Associate = EdtMinFrameSide
        Min = 32
        Max = 7680
        Increment = 10
        Position = 32
        TabOrder = 10
        Thousands = False
      end
      object EdtMaxFrameSide: TEdit
        Left = 213
        Top = 194
        Width = 55
        Height = 23
        Hint = 
          'Upper bound (pixels, longer side) for the scaled extraction rang' +
          'e.'
        NumbersOnly = True
        TabOrder = 11
        Text = '32'
      end
      object UdMaxFrameSide: TUpDown
        Left = 268
        Top = 194
        Width = 17
        Height = 23
        Hint = 
          'Upper bound (pixels, longer side) for the scaled extraction rang' +
          'e.'
        Associate = EdtMaxFrameSide
        Min = 32
        Max = 7680
        Increment = 10
        Position = 32
        TabOrder = 12
        Thousands = False
      end
      object ChkAutoRefreshViewport: TCheckBox
        Left = 12
        Top = 224
        Width = 427
        Height = 17
        Hint = 
          'Re-runs extraction at the new size whenever you resize the viewe' +
          'r. Trades a moment of latency for sharper frames.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Re-extract automatically when the viewport changes'
        TabOrder = 13
      end
      object ChkRespectAnamorphic: TCheckBox
        Left = 12
        Top = 252
        Width = 427
        Height = 17
        Hint = 
          'Uses the video'#39's display aspect ratio when sizing frames, not th' +
          'e raw pixel grid.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Respect anamorphic dimensions'
        TabOrder = 14
      end
      object EdtExtensions: TEdit
        Left = 12
        Top = 301
        Width = 427
        Height = 23
        Hint = 'Space-separated list of file extensions the lister handles.'
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 15
      end
      object EdtFFmpegPath: TEdit
        Left = 12
        Top = 354
        Width = 396
        Height = 23
        Hint = 
          'Optional override for the ffmpeg executable path. Leave empty to' +
          ' auto-detect from PATH.'
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 16
        TextHint = 'Auto-detect'
        OnChange = EdtFFmpegPathChange
      end
      object BtnFFmpegPath: TButton
        Left = 414
        Top = 354
        Width = 25
        Height = 23
        Hint = 'Browse for the ffmpeg executable.'
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 17
        OnClick = BtnFFmpegPathClick
      end
    end
    object TshSampling: TTabSheet
      Caption = 'Sampling'
      ImageIndex = 7
      DesignSize = (
        452
        450)
      object LblSkipEdges: TLabel
        Left = 12
        Top = 24
        Width = 59
        Height = 15
        Caption = 'Skip edges:'
      end
      object LblSkipEdgesUnit: TLabel
        Left = 196
        Top = 24
        Width = 10
        Height = 15
        Caption = '%'
      end
      object LblRandomPercent: TLabel
        Left = 12
        Top = 74
        Width = 71
        Height = 15
        Caption = 'Randomness:'
      end
      object LblRandomPercentValue: TLabel
        Left = 417
        Top = 74
        Width = 22
        Height = 15
        Anchors = [akTop, akRight]
        Caption = '50%'
      end
      object EdtSkipEdges: TEdit
        Left = 130
        Top = 20
        Width = 45
        Height = 23
        Hint = 
          'Excludes the first and last N% of the video when picking frame p' +
          'ositions.'
        NumbersOnly = True
        TabOrder = 0
        Text = '0'
      end
      object UdSkipEdges: TUpDown
        Left = 175
        Top = 20
        Width = 16
        Height = 23
        Associate = EdtSkipEdges
        Max = 49
        TabOrder = 1
        Thousands = False
      end
      object ChkRandomExtraction: TCheckBox
        Left = 12
        Top = 49
        Width = 427
        Height = 17
        Hint = 
          'Picks frame positions randomly inside the allowed range instead ' +
          'of evenly spacing them.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Start from random positions'
        TabOrder = 2
      end
      object TrkRandomPercent: TTrackBar
        Left = 94
        Top = 70
        Width = 317
        Height = 25
        Hint = 
          'Width of the random window around each evenly-spaced position. H' +
          'igher = more variance.'
        Anchors = [akLeft, akTop, akRight]
        Max = 100
        Min = 1
        Frequency = 5
        Position = 50
        ShowSelRange = False
        TabOrder = 3
        TickMarks = tmBoth
        OnChange = TrkRandomPercentChange
      end
      object ChkCacheRandomFrames: TCheckBox
        Left = 12
        Top = 102
        Width = 427
        Height = 17
        Hint = 
          'Includes randomly-sampled frames in the disk cache. Off keeps th' +
          'e cache deterministic across reopens.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Cache random frames'
        TabOrder = 4
      end
    end
    object TshAppearance: TTabSheet
      Caption = 'Appearance'
      ImageIndex = 1
      DesignSize = (
        452
        450)
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
        OnClick = OnColorSwatchClick
      end
      object BtnBackground: TButton
        Left = 234
        Top = 20
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 1
        OnClick = OnColorSwatchClick
      end
      object EdtCellGap: TEdit
        Left = 150
        Top = 49
        Width = 45
        Height = 23
        Hint = 'Pixels of empty space between adjacent frames in the grid view.'
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
        Hint = 'Pixels of empty border around the entire viewer canvas.'
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
        Hint = 
          'Overlay each frame'#39's timecode in the viewer. F2 toggles at runti' +
          'me.'
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
        OnClick = OnColorSwatchClick
      end
      object BtnTCBack: TButton
        Left = 234
        Top = 107
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 9
        OnClick = OnColorSwatchClick
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
        OnClick = OnColorSwatchClick
      end
      object BtnTCTextColor: TButton
        Left = 234
        Top = 136
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 13
        OnClick = OnColorSwatchClick
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
        Hint = 'Initial visibility of the toolbar. F4 toggles it on the fly.'
        Caption = 'Show toolbar (F4 to toggle)'
        TabOrder = 19
      end
      object ChkShowStatusBar: TCheckBox
        Left = 230
        Top = 194
        Width = 200
        Height = 17
        Hint = 'Initial visibility of the status bar. F3 toggles it on the fly.'
        Caption = 'Show status bar (F3 to toggle)'
        TabOrder = 18
      end
      object LblStatusBarTemplate: TLabel
        Left = 12
        Top = 224
        Width = 108
        Height = 15
        Caption = 'Status bar template:'
      end
      object EdtStatusBarTemplate: TEdit
        Left = 12
        Top = 242
        Width = 427
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        Hint =
          'Tokens enclosed in %...% in the order they should appear. Each ' +
          'token becomes one panel. Optional attributes: width=auto|N, ' +
          'align=left|right|center. Empty resets to default.'
        TabOrder = 20
      end
      object MemStatusBarLegend: TMemo
        Left = 12
        Top = 268
        Width = 427
        Height = 48
        Anchors = [akLeft, akTop, akRight]
        Color = clBtnFace
        ReadOnly = True
        ScrollBars = ssVertical
        TabOrder = 21
        TabStop = False
      end
      object LblStatusBarFont: TLabel
        Left = 12
        Top = 326
        Width = 87
        Height = 15
        Caption = 'Status bar font:'
      end
      object EdtStatusBarFont: TEdit
        Left = 149
        Top = 322
        Width = 259
        Height = 23
        TabStop = False
        Anchors = [akLeft, akTop, akRight]
        ReadOnly = True
        TabOrder = 22
      end
      object BtnStatusBarFont: TButton
        Left = 414
        Top = 322
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 23
        OnClick = BtnStatusBarFontClick
      end
      object LblStatusBarHeight: TLabel
        Left = 12
        Top = 356
        Width = 130
        Height = 15
        Caption = 'Status bar height (px):'
      end
      object EdtStatusBarHeight: TEdit
        Left = 150
        Top = 352
        Width = 45
        Height = 23
        Hint =
          '0 = auto (derived from the configured font). Non-zero overrides' +
          ' to that pixel height; values below the font minimum are silently' +
          ' bumped so text never clips.'
        NumbersOnly = True
        TabOrder = 24
        Text = '0'
      end
      object UdStatusBarHeight: TUpDown
        Left = 195
        Top = 352
        Width = 17
        Height = 23
        Associate = EdtStatusBarHeight
        Max = 200
        TabOrder = 25
        Thousands = False
      end
      object LblStatusBarHeightApply: TLabel
        Left = 226
        Top = 356
        Width = 47
        Height = 15
        Caption = 'Apply in:'
      end
      object CbxStatusBarHeightApply: TComboBox
        Left = 280
        Top = 352
        Width = 159
        Height = 23
        Style = csDropDownList
        Anchors = [akLeft, akTop, akRight]
        Hint =
          'In which window mode the explicit height takes effect. The other ' +
          'mode falls back to the font-derived auto height regardless of ' +
          'the px value above.'
        TabOrder = 26
        Items.Strings = (
          'Lister only'
          'Quick View only'
          'Both')
      end
      object ChkStatusBarAutoWidthLive: TCheckBox
        Left = 12
        Top = 380
        Width = 350
        Height = 17
        Hint =
          'When OFF (default), each auto-width panel is sized once to its ' +
          'sample text and locked. When ON, widths re-measure on every ' +
          'refresh, tracking the live text but causing slight layout shift.'
        Caption = 'Recalculate auto-width panels on every update'
        TabOrder = 27
      end
      object ChkStatusBarStretchPanels: TCheckBox
        Left = 12
        Top = 402
        Width = 350
        Height = 17
        Hint =
          'Distribute remaining bar width across the auto-width panels ' +
          'proportionally to their natural size. Forces the progress bar ' +
          'into Over panels mode since no slack remains for docking.'
        Caption = 'Stretch auto-width panels to fill the bar'
        TabOrder = 28
        OnClick = ChkStatusBarStretchPanelsClick
      end
      object LblProgressBarLayout: TLabel
        Left = 12
        Top = 428
        Width = 116
        Height = 15
        Caption = 'Progress bar position:'
      end
      object CbxProgressBarLayout: TComboBox
        Left = 150
        Top = 424
        Width = 105
        Height = 23
        Style = csDropDownList
        Hint =
          'After panels: bar sits to the right of the info panels (clipped' +
          ' on narrow lister widths). Over panels: bar covers the panels f' +
          'ull-width while shown. Auto: picks based on lister width. ' +
          'Locked to Over panels while Stretch auto-width panels is on.'
        TabOrder = 29
        Items.Strings = (
          'After panels'
          'Over panels'
          'Auto')
      end
    end
    object TshSave: TTabSheet
      Caption = 'Save'
      ImageIndex = 2
      DesignSize = (
        452
        450)
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
      object LblBackgroundAlpha: TLabel
        Left = 12
        Top = 111
        Width = 109
        Height = 15
        Caption = 'Background opacity:'
      end
      object LblSaveFolder: TLabel
        Left = 12
        Top = 140
        Width = 75
        Height = 15
        Caption = 'Default folder:'
      end
      object LblBannerBackground: TLabel
        Left = 12
        Top = 202
        Width = 128
        Height = 15
        AutoSize = False
        Caption = 'Banner background:'
      end
      object LblBannerTextColor: TLabel
        Left = 12
        Top = 231
        Width = 128
        Height = 15
        AutoSize = False
        Caption = 'Banner text color:'
      end
      object LblBannerFont: TLabel
        Left = 12
        Top = 260
        Width = 65
        Height = 15
        Caption = 'Banner font:'
      end
      object LblBannerPosition: TLabel
        Left = 12
        Top = 318
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
      object EdtBackgroundAlpha: TEdit
        Left = 130
        Top = 107
        Width = 45
        Height = 23
        Hint = 
          'Background opacity for saved images (0 = transparent, 255 = opaq' +
          'ue). Only meaningful for PNG.'
        NumbersOnly = True
        TabOrder = 5
        Text = '255'
      end
      object UdBackgroundAlpha: TUpDown
        Left = 175
        Top = 107
        Width = 17
        Height = 23
        Associate = EdtBackgroundAlpha
        Max = 255
        Position = 255
        TabOrder = 6
        Thousands = False
      end
      object EdtSaveFolder: TEdit
        Left = 130
        Top = 136
        Width = 278
        Height = 23
        Hint = 
          'Default folder for save dialogs. Leave empty to remember the las' +
          't used folder per session.'
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 7
        TextHint = 'Leave empty for no default'
      end
      object BtnSaveFolder: TButton
        Left = 414
        Top = 136
        Width = 25
        Height = 23
        Hint = 'Browse for the default save folder.'
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 8
        OnClick = BtnSaveFolderClick
      end
      object ChkShowBanner: TCheckBox
        Left = 12
        Top = 169
        Width = 424
        Height = 17
        Hint = 
          'Adds a strip with the video filename and metadata to the saved c' +
          'ombined image.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Include file info banner in combined image export'
        TabOrder = 9
        OnClick = ChkShowBannerClick
      end
      object PnlBannerBackground: TPanel
        Left = 130
        Top = 198
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 10
        OnClick = OnColorSwatchClick
      end
      object BtnBannerBackground: TButton
        Left = 214
        Top = 198
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 11
        OnClick = OnColorSwatchClick
      end
      object PnlBannerTextColor: TPanel
        Left = 130
        Top = 227
        Width = 80
        Height = 23
        Cursor = crHandPoint
        BevelOuter = bvLowered
        ParentBackground = False
        TabOrder = 12
        OnClick = OnColorSwatchClick
      end
      object BtnBannerTextColor: TButton
        Left = 214
        Top = 227
        Width = 25
        Height = 23
        Caption = '...'
        TabOrder = 13
        OnClick = OnColorSwatchClick
      end
      object EdtBannerFont: TEdit
        Left = 130
        Top = 256
        Width = 278
        Height = 23
        TabStop = False
        Anchors = [akLeft, akTop, akRight]
        ReadOnly = True
        TabOrder = 14
      end
      object BtnBannerFont: TButton
        Left = 414
        Top = 256
        Width = 25
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 15
        OnClick = BtnBannerFontClick
      end
      object ChkBannerAutoSize: TCheckBox
        Left = 130
        Top = 287
        Width = 306
        Height = 17
        Hint = 'Scales the banner font so it stays readable at any output width.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Auto-size banner font to image width'
        TabOrder = 16
        OnClick = ChkBannerAutoSizeClick
      end
      object CbxBannerPosition: TComboBox
        Left = 130
        Top = 314
        Width = 105
        Height = 23
        Style = csDropDownList
        TabOrder = 17
        Items.Strings = (
          'Top'
          'Bottom')
      end
      object ChkSaveAtLiveResolution: TCheckBox
        Left = 12
        Top = 344
        Width = 424
        Height = 17
        Hint =
          'On: save at the size you see in the viewer. Off: re-extract at t' +
          'he video'#39's native frame size before saving.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Save at view resolution (uses native frame size when off)'
        TabOrder = 18
      end
      object ChkCopyAtLiveResolution: TCheckBox
        Left = 12
        Top = 365
        Width = 424
        Height = 17
        Hint =
          'On: copy to clipboard at the size you see in the viewer. Off: re' +
          '-extract at native frame size before copying. Independent of the' +
          ' save setting above.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Copy at view resolution (uses native frame size when off)'
        TabOrder = 19
      end
      object LblCombinedMaxSide: TLabel
        Left = 12
        Top = 393
        Width = 105
        Height = 15
        Caption = 'Max combined side:'
      end
      object EdtCombinedMaxSide: TEdit
        Left = 130
        Top = 389
        Width = 60
        Height = 23
        Hint =
          'Cap on the longer side of the rendered Save view / Copy view ima' +
          'ge in pixels. The image is shrunk proportionally if it exceeds t' +
          'his value. 0 disables the cap.'
        NumbersOnly = True
        TabOrder = 20
        Text = '0'
      end
      object UdCombinedMaxSide: TUpDown
        Left = 190
        Top = 389
        Width = 17
        Height = 23
        Associate = EdtCombinedMaxSide
        Max = 32768
        Increment = 256
        TabOrder = 21
        Thousands = False
      end
      object LblCombinedMaxSideUnit: TLabel
        Left = 213
        Top = 393
        Width = 14
        Height = 15
        Caption = 'px'
      end
    end
    object TshClipboard: TTabSheet
      Caption = 'Clipboard'
      ImageIndex = 8
      DesignSize = (
        452
        450)
      object LblClipboardFormatsHeader: TLabel
        Left = 12
        Top = 12
        Width = 280
        Height = 15
        Caption = 'Publish these formats when copying to clipboard:'
      end
      object ChkPublishAlphaAwareBitmap: TCheckBox
        Left = 12
        Top = 36
        Width = 424
        Height = 17
        Hint =
          'Preserves transparency. Used by modern image editors and web ' +
          'browsers. Costs roughly width*height*4 bytes per copy. (CF_DIBV5)'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Alpha-aware bitmap'
        TabOrder = 0
      end
      object ChkPublishCompressedPng: TCheckBox
        Left = 12
        Top = 62
        Width = 424
        Height = 17
        Hint =
          'Carries true alpha at a fraction of the raw-pixel memory ' +
          'cost. Used by many modern web and chat apps. ' +
          '(registered "PNG" format)'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Compressed PNG'
        TabOrder = 1
      end
      object ChkPublishFlattenedBitmap: TCheckBox
        Left = 12
        Top = 88
        Width = 424
        Height = 17
        Hint =
          'Opaque copy with transparency composited onto the background ' +
          'colour. Used as a fallback by paste targets that do not ' +
          'understand alpha. Costs roughly width*height*3 bytes per ' +
          'copy. (CF_DIB)'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Flattened bitmap for legacy apps'
        TabOrder = 2
      end
      object ChkPublishBitmapHandle: TCheckBox
        Left = 12
        Top = 114
        Width = 424
        Height = 17
        Hint =
          'Direct bitmap handle for paste targets that distrust DIB ' +
          'synthesis. Most modern apps do not need it. Costs roughly ' +
          'width*height*4 bytes per copy. (CF_BITMAP)'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'GDI bitmap handle'
        TabOrder = 3
      end
      object ChkClipboardAsFileReference: TCheckBox
        Left = 12
        Top = 154
        Width = 424
        Height = 17
        Hint =
          'Write the image to a temp PNG and publish the file path as ' +
          'CF_HDROP instead of a bitmap. When on, all format toggles ' +
          'above are ignored. Will not work with paste targets that ' +
          'accept only bitmap data.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Copy to clipboard as a file reference (overrides format toggles above)'
        TabOrder = 4
        OnClick = ChkClipboardAsFileReferenceClick
      end
    end
    object TshCache: TTabSheet
      Caption = 'Cache'
      ImageIndex = 3
      DesignSize = (
        452
        450)
      object LblCacheFolder: TLabel
        Left = 12
        Top = 53
        Width = 36
        Height = 15
        Caption = 'Folder:'
      end
      object LblCacheFolderInfo: TLabel
        Left = 12
        Top = 84
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
      object EdtCacheFolderInfo: TEdit
        Left = 130
        Top = 82
        Width = 309
        Height = 21
        Hint = 'Resolved cache folder path. Click to select / copy.'
        TabStop = False
        Anchors = [akLeft, akTop, akRight]
        AutoSize = False
        BorderStyle = bsNone
        Color = clBtnFace
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGray
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
        ReadOnly = True
        TabOrder = 6
      end
      object ChkCacheEnabled: TCheckBox
        Left = 12
        Top = 24
        Width = 140
        Height = 17
        Hint = 
          'Persists extracted frames between sessions so re-opening a video' +
          ' is instant. Off forces fresh extraction every time.'
        Caption = 'Enable disk cache'
        TabOrder = 0
        OnClick = ChkCacheEnabledClick
      end
      object BtnClearCache: TButton
        Left = 351
        Top = 20
        Width = 88
        Height = 23
        Hint = 'Delete all cached frames now.'
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
        Hint = 
          'Where cached frames live. Empty uses %LOCALAPPDATA%\Glimpse\cach' +
          'e.'
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
        Hint = 'Browse for the cache folder.'
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
        Hint = 
          'Cache size cap in megabytes. Oldest entries are evicted when thi' +
          's is exceeded.'
        NumbersOnly = True
        TabOrder = 4
        Text = '10'
      end
      object UdCacheMaxSize: TUpDown
        Left = 195
        Top = 107
        Width = 17
        Height = 23
        Hint = 
          'Cache size cap in megabytes. Oldest entries are evicted when thi' +
          's is exceeded.'
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
        Hint = 
          'Generate Total Commander panel thumbnails for handled video file' +
          's.'
        Caption = 'Enable thumbnails for TC panel'
        TabOrder = 0
        OnClick = ChkThumbnailsEnabledClick
      end
      object CbxThumbnailMode: TComboBox
        Left = 130
        Top = 49
        Width = 110
        Height = 23
        Hint = 
          'Single frame: one frame at the chosen position. Grid: a small co' +
          'ntact sheet inside the thumbnail.'
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
        Hint = 
          'Where in the video the single-frame thumbnail comes from (0 = st' +
          'art, 50 = middle, 100 = end).'
        NumbersOnly = True
        TabOrder = 2
        Text = '50'
      end
      object UdThumbnailPosition: TUpDown
        Left = 175
        Top = 78
        Width = 17
        Height = 23
        Hint = 
          'Where in the video the single-frame thumbnail comes from (0 = st' +
          'art, 50 = middle, 100 = end).'
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
        Hint = 'Number of frames sampled into the grid thumbnail.'
        NumbersOnly = True
        TabOrder = 4
        Text = '4'
      end
      object UdThumbnailGridFrames: TUpDown
        Left = 365
        Top = 78
        Width = 17
        Height = 23
        Hint = 'Number of frames sampled into the grid thumbnail.'
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
        450)
      object ChkQVDisableNavigation: TCheckBox
        Left = 12
        Top = 24
        Width = 427
        Height = 17
        Hint = 
          'In Quick View only: blocks the plugin'#39's prev/next-file shortcuts' +
          ' so TC keeps full control of selection.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Disable internal file navigation'
        TabOrder = 0
      end
      object ChkQVHideToolbar: TCheckBox
        Left = 12
        Top = 53
        Width = 427
        Height = 17
        Hint = 
          'Hide the toolbar when the plugin runs in Quick View, regardless ' +
          'of the General-tab Show toolbar setting.'
        Anchors = [akLeft, akTop, akRight]
        Caption = 'Hide toolbar'
        TabOrder = 1
      end
      object ChkQVHideStatusBar: TCheckBox
        Left = 12
        Top = 82
        Width = 427
        Height = 17
        Hint = 
          'Hide the status bar when the plugin runs in Quick View, regardle' +
          'ss of the General-tab Show status bar setting.'
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
        450)
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
        Hint = 'Remove the shortcut assigned to the selected action.'
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
        Hint = 'Open the shortcut capture dialog for the selected action.'
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
        Hint = 'Restore the default shortcut for every action.'
        Anchors = [akRight, akBottom]
        Caption = 'Reset all'
        TabOrder = 3
        OnClick = BtnHotkeyResetAllClick
      end
    end
  end
  object PnlButtons: TPanel
    Left = 0
    Top = 480
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
      Hint = 
        'Reset every setting on this dialog to its built-in default. Hotk' +
        'eys are preserved.'
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
    Left = 384
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
